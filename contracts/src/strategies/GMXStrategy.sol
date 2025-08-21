// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IStrategy.sol";

// GMX Protocol interfaces
interface IGMXRewardTracker {
    function stake(address depositToken, uint256 amount) external;
    function unstake(address depositToken, uint256 amount) external;
    function claim(address receiver) external returns (uint256);
    function claimable(address account) external view returns (uint256);
    function stakedAmounts(address account) external view returns (uint256);
    function depositBalances(address account, address depositToken) external view returns (uint256);
}

interface IGMXRewardRouter {
    function stakeGmx(uint256 amount) external;
    function unstakeGmx(uint256 amount) external;
    function stakeEsGmx(uint256 amount) external;
    function unstakeEsGmx(uint256 amount) external;
    function mintAndStakeGlp(address token, uint256 amount, uint256 minUsdg, uint256 minGlp) 
        external returns (uint256);
    function unstakeAndRedeemGlp(address tokenOut, uint256 glpAmount, uint256 minOut, address receiver)
        external returns (uint256);
    function claim() external;
    function claimEsGmx() external;
    function claimFees() external;
    function compound() external;
    function handleRewards(
        bool shouldClaimGmx,
        bool shouldStakeGmx,
        bool shouldClaimEsGmx,
        bool shouldStakeEsGmx,
        bool shouldStakeMultiplierPoints,
        bool shouldClaimWeth,
        bool shouldConvertWethToEth
    ) external;
}

interface IGMXGlpManager {
    function getPrice(bool maximize) external view returns (uint256);
    function getAum(bool maximise) external view returns (uint256);
    function cooldownDuration() external view returns (uint256);
    function lastAddedAt(address account) external view returns (uint256);
}

interface IGMXVault {
    function getMaxPrice(address token) external view returns (uint256);
    function getMinPrice(address token) external view returns (uint256);
    function usdgAmounts(address token) external view returns (uint256);
    function poolAmounts(address token) external view returns (uint256);
}

/**
 * @title GMXStrategy
 * @dev Strategy for staking GLP tokens on GMX protocol
 */
contract GMXStrategy is IStrategy, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant STRATEGY_MANAGER_ROLE = keccak256("STRATEGY_MANAGER_ROLE");
    
    uint256 public constant MAX_BPS = 10_000;
    uint256 public constant PRECISION = 1e30;
    
    IERC20 public immutable override asset; // The underlying asset (USDC, USDT, etc.)
    IERC20 public immutable glpToken;
    IERC20 public immutable esGmxToken;
    IERC20 public immutable gmxToken;
    IERC20 public immutable wethToken;
    
    IGMXRewardRouter public immutable rewardRouter;
    IGMXRewardTracker public immutable feeGlpTracker;
    IGMXRewardTracker public immutable stakedGlpTracker;
    IGMXGlpManager public immutable glpManager;
    IGMXVault public immutable vault;
    
    uint8 public constant override riskLevel = 3; // Medium-low risk
    
    uint256 public totalGLP;
    uint256 public totalEsGMX;
    uint256 public lastHarvest;
    uint256 public totalHarvestedWeth;
    uint256 public totalHarvestedEsGmx;
    bool public active = true;
    
    // Strategy parameters
    uint256 public maxSlippage = 100; // 1%
    uint256 public minMintAmount = 10 * 1e18; // 10 USD minimum
    uint256 public autoCompoundThreshold = 1e18; // 1 WETH
    bool public autoCompoundEnabled = true;
    uint256 public cooldownPeriod = 15 minutes; // GLP cooldown
    
    // Performance tracking
    uint256 public totalDeposited;
    uint256 public totalWithdrawn;
    uint256 public lastAPYUpdate;
    uint256 public currentAPY;
    
    event GLPMinted(uint256 assetAmount, uint256 glpAmount);
    event GLPRedeemed(uint256 glpAmount, uint256 assetAmount);
    event RewardsHarvested(uint256 wethAmount, uint256 esGmxAmount);
    event RewardsCompounded(uint256 wethAmount);
    event APYUpdated(uint256 oldAPY, uint256 newAPY);

    modifier onlyStrategyManager() {
        require(hasRole(STRATEGY_MANAGER_ROLE, msg.sender), "Not strategy manager");
        _;
    }

    constructor(
        address _asset,
        address _glpToken,
        address _esGmxToken,
        address _gmxToken,
        address _wethToken,
        address _rewardRouter,
        address _feeGlpTracker,
        address _stakedGlpTracker,
        address _glpManager,
        address _vault,
        address _admin
    ) {
        require(_asset != address(0), "Invalid asset");
        require(_rewardRouter != address(0), "Invalid reward router");
        
        asset = IERC20(_asset);
        glpToken = IERC20(_glpToken);
        esGmxToken = IERC20(_esGmxToken);
        gmxToken = IERC20(_gmxToken);
        wethToken = IERC20(_wethToken);
        
        rewardRouter = IGMXRewardRouter(_rewardRouter);
        feeGlpTracker = IGMXRewardTracker(_feeGlpTracker);
        stakedGlpTracker = IGMXRewardTracker(_stakedGlpTracker);
        glpManager = IGMXGlpManager(_glpManager);
        vault = IGMXVault(_vault);
        
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(STRATEGY_MANAGER_ROLE, _admin);
        
        // Approve tokens
        asset.safeApprove(_rewardRouter, type(uint256).max);
        glpToken.safeApprove(_rewardRouter, type(uint256).max);
        esGmxToken.safeApprove(_rewardRouter, type(uint256).max);
        
        lastHarvest = block.timestamp;
        lastAPYUpdate = block.timestamp;
    }

    /*//////////////////////////////////////////////////////////////
                        STRATEGY IMPLEMENTATION
    //////////////////////////////////////////////////////////////*/

    function getAPY() external view override returns (uint256 apy) {
        if (totalGLP == 0) return 0;
        
        // GLP APY = (WETH rewards + esGMX rewards) / GLP value
        uint256 wethRewards = feeGlpTracker.claimable(address(this));
        uint256 esGmxRewards = stakedGlpTracker.claimable(address(this));
        
        uint256 timeSinceLastHarvest = block.timestamp - lastHarvest;
        
        if (timeSinceLastHarvest > 0 && totalDeposited > 0) {
            // Annualize rewards
            uint256 annualWethRewards = (wethRewards * 365 days) / timeSinceLastHarvest;
            uint256 annualEsGmxRewards = (esGmxRewards * 365 days) / timeSinceLastHarvest;
            
            // Convert to asset value (simplified - in production use oracle)
            uint256 wethValue = _getWethValueInAsset(annualWethRewards);
            uint256 esGmxValue = _getEsGmxValueInAsset(annualEsGmxRewards);
            
            // Calculate APY
            apy = ((wethValue + esGmxValue) * MAX_BPS) / totalDeposited;
            
            // Add base GLP yield (typically 20-40% APR)
            apy += 2500; // Approximate base APY of 25%
        }
        
        return apy;
    }

    function totalAssets() external view override returns (uint256) {
        if (totalGLP == 0) {
            return asset.balanceOf(address(this));
        }
        
        // Convert GLP to asset value
        uint256 glpPrice = glpManager.getPrice(false); // Get sell price
        uint256 glpValue = (totalGLP * glpPrice) / PRECISION;
        
        // Convert USD value to asset amount based on asset price
        uint256 assetPrice = vault.getMinPrice(address(asset));
        uint256 assetValue = (glpValue * PRECISION) / assetPrice;
        
        return assetValue + asset.balanceOf(address(this));
    }

    function invest(uint256 amount) external override nonReentrant returns (uint256 invested) {
        require(hasRole(STRATEGY_MANAGER_ROLE, msg.sender), "Not authorized");
        require(active, "Strategy not active");
        require(amount >= minMintAmount, "Amount too small");
        
        uint256 assetBalance = asset.balanceOf(address(this));
        amount = amount > assetBalance ? assetBalance : amount;
        
        if (amount == 0) return 0;
        
        // Calculate minimum GLP to receive (with slippage protection)
        uint256 assetPrice = vault.getMaxPrice(address(asset));
        uint256 expectedUsdValue = (amount * assetPrice) / PRECISION;
        uint256 glpPrice = glpManager.getPrice(true); // Get buy price
        uint256 expectedGlp = (expectedUsdValue * PRECISION) / glpPrice;
        uint256 minGlp = (expectedGlp * (MAX_BPS - maxSlippage)) / MAX_BPS;
        
        // Mint and stake GLP
        uint256 glpReceived = rewardRouter.mintAndStakeGlp(
            address(asset),
            amount,
            expectedUsdValue * (MAX_BPS - maxSlippage) / MAX_BPS, // minUsdg
            minGlp
        );
        
        totalGLP += glpReceived;
        invested = amount;
        totalDeposited += invested;
        
        emit GLPMinted(amount, glpReceived);
        
        return invested;
    }

    function withdraw(uint256 amount) external override nonReentrant returns (uint256 withdrawn) {
        require(hasRole(STRATEGY_MANAGER_ROLE, msg.sender), "Not authorized");
        require(amount > 0, "Invalid amount");
        
        uint256 availableAssets = this.totalAssets();
        amount = amount > availableAssets ? availableAssets : amount;
        
        uint256 directBalance = asset.balanceOf(address(this));
        
        if (amount <= directBalance) {
            // Can withdraw directly
            withdrawn = amount;
            asset.safeTransfer(msg.sender, withdrawn);
        } else {
            // Need to redeem GLP
            uint256 neededFromGLP = amount - directBalance;
            
            // Check cooldown period
            require(
                block.timestamp >= glpManager.lastAddedAt(address(this)) + glpManager.cooldownDuration(),
                "GLP cooldown active"
            );
            
            // Calculate GLP amount to redeem
            uint256 assetPrice = vault.getMinPrice(address(asset));
            uint256 neededUsdValue = (neededFromGLP * assetPrice) / PRECISION;
            uint256 glpPrice = glpManager.getPrice(false); // Get sell price
            uint256 glpToRedeem = (neededUsdValue * PRECISION) / glpPrice;
            
            // Add slippage buffer
            glpToRedeem = (glpToRedeem * (MAX_BPS + maxSlippage)) / MAX_BPS;
            glpToRedeem = glpToRedeem > totalGLP ? totalGLP : glpToRedeem;
            
            if (glpToRedeem > 0) {
                uint256 minOut = (neededFromGLP * (MAX_BPS - maxSlippage)) / MAX_BPS;
                
                uint256 redeemed = rewardRouter.unstakeAndRedeemGlp(
                    address(asset),
                    glpToRedeem,
                    minOut,
                    address(this)
                );
                
                totalGLP -= glpToRedeem;
                withdrawn = directBalance + redeemed;
                
                emit GLPRedeemed(glpToRedeem, redeemed);
            } else {
                withdrawn = directBalance;
            }
            
            // Transfer total withdrawn amount
            asset.safeTransfer(msg.sender, withdrawn);
        }
        
        totalWithdrawn += withdrawn;
        return withdrawn;
    }

    function harvest() external override nonReentrant returns (uint256 harvested) {
        require(hasRole(STRATEGY_MANAGER_ROLE, msg.sender), "Not authorized");
        
        uint256 wethBalanceBefore = wethToken.balanceOf(address(this));
        uint256 esGmxBalanceBefore = esGmxToken.balanceOf(address(this));
        
        // Claim all rewards
        rewardRouter.handleRewards(
            false, // shouldClaimGmx
            false, // shouldStakeGmx  
            true,  // shouldClaimEsGmx
            false, // shouldStakeEsGmx
            false, // shouldStakeMultiplierPoints
            true,  // shouldClaimWeth
            false  // shouldConvertWethToEth
        );
        
        uint256 wethReceived = wethToken.balanceOf(address(this)) - wethBalanceBefore;
        uint256 esGmxReceived = esGmxToken.balanceOf(address(this)) - esGmxBalanceBefore;
        
        if (wethReceived > 0 || esGmxReceived > 0) {
            totalHarvestedWeth += wethReceived;
            totalHarvestedEsGmx += esGmxReceived;
            
            emit RewardsHarvested(wethReceived, esGmxReceived);
            
            // Auto-compound if enabled and threshold met
            if (autoCompoundEnabled && wethReceived >= autoCompoundThreshold) {
                harvested = _compoundRewards(wethReceived);
            } else {
                harvested = _getWethValueInAsset(wethReceived) + _getEsGmxValueInAsset(esGmxReceived);
            }
        }
        
        lastHarvest = block.timestamp;
        _updateAPY();
        
        return harvested;
    }

    function emergencyWithdraw() external override nonReentrant returns (uint256 withdrawn) {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not authorized");
        
        // Harvest any pending rewards
        this.harvest();
        
        // Withdraw all GLP
        if (totalGLP > 0) {
            // Override cooldown in emergency
            uint256 minOut = 0; // Accept any amount in emergency
            
            withdrawn = rewardRouter.unstakeAndRedeemGlp(
                address(asset),
                totalGLP,
                minOut,
                address(this)
            );
            
            emit GLPRedeemed(totalGLP, withdrawn);
            totalGLP = 0;
        }
        
        // Add any direct balance
        uint256 directBalance = asset.balanceOf(address(this));
        withdrawn += directBalance;
        
        // Transfer all assets
        if (withdrawn > 0) {
            asset.safeTransfer(msg.sender, withdrawn);
        }
        
        active = false;
        
        return withdrawn;
    }

    function isActive() external view override returns (bool) {
        return active;
    }

    function maxInvestable() external view override returns (uint256) {
        if (!active) return 0;
        
        // GLP has high capacity, limit based on reasonable portfolio allocation
        uint256 currentAUM = glpManager.getAum(true);
        
        // Allow up to 5% of total GLP AUM
        return currentAUM / 20;
    }

    function getRiskLevel() external pure override returns (uint8) {
        return riskLevel;
    }

    /*//////////////////////////////////////////////////////////////
                        COMPOUND FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function compoundRewards() external onlyStrategyManager returns (uint256 compounded) {
        uint256 wethBalance = wethToken.balanceOf(address(this));
        
        if (wethBalance >= autoCompoundThreshold) {
            compounded = _compoundRewards(wethBalance);
        }
        
        return compounded;
    }

    function _compoundRewards(uint256 wethAmount) internal returns (uint256 compounded) {
        if (wethAmount == 0) return 0;
        
        // Convert WETH to underlying asset (simplified - use DEX in production)
        uint256 assetAmount = _swapWethForAsset(wethAmount);
        
        if (assetAmount >= minMintAmount) {
            // Reinvest into GLP
            compounded = this.invest(assetAmount);
            emit RewardsCompounded(wethAmount);
        }
        
        return compounded;
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _swapWethForAsset(uint256 wethAmount) internal returns (uint256 assetAmount) {
        // Simplified swap - in production, use DEX aggregator or GMX swap
        // For now, return equivalent value based on prices
        uint256 wethPrice = vault.getMaxPrice(address(wethToken));
        uint256 assetPrice = vault.getMinPrice(address(asset));
        
        assetAmount = (wethAmount * wethPrice) / assetPrice;
        
        // Mock transfer - in production, execute actual swap
        // This is a simplified implementation
        return assetAmount;
    }

    function _getWethValueInAsset(uint256 wethAmount) internal view returns (uint256) {
        if (wethAmount == 0) return 0;
        
        uint256 wethPrice = vault.getMaxPrice(address(wethToken));
        uint256 assetPrice = vault.getMinPrice(address(asset));
        
        return (wethAmount * wethPrice) / assetPrice;
    }

    function _getEsGmxValueInAsset(uint256 esGmxAmount) internal view returns (uint256) {
        if (esGmxAmount == 0) return 0;
        
        // esGMX value is typically discounted compared to GMX
        // Assume 50% discount for conservative estimation
        uint256 gmxPrice = vault.getMaxPrice(address(gmxToken));
        uint256 assetPrice = vault.getMinPrice(address(asset));
        
        uint256 discountedValue = (esGmxAmount * gmxPrice * 50) / 100; // 50% discount
        
        return discountedValue / assetPrice;
    }

    function _updateAPY() internal {
        uint256 newAPY = this.getAPY();
        
        if (newAPY != currentAPY) {
            emit APYUpdated(currentAPY, newAPY);
            currentAPY = newAPY;
            lastAPYUpdate = block.timestamp;
        }
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getStakedGLP() external view returns (uint256) {
        return stakedGlpTracker.stakedAmounts(address(this));
    }

    function getPendingRewards() external view returns (uint256 weth, uint256 esGmx) {
        weth = feeGlpTracker.claimable(address(this));
        esGmx = stakedGlpTracker.claimable(address(this));
    }

    function getGLPPrice() external view returns (uint256 buyPrice, uint256 sellPrice) {
        buyPrice = glpManager.getPrice(true);
        sellPrice = glpManager.getPrice(false);
    }

    function getRemainingCooldown() external view returns (uint256) {
        uint256 lastAdded = glpManager.lastAddedAt(address(this));
        uint256 cooldown = glpManager.cooldownDuration();
        
        if (block.timestamp >= lastAdded + cooldown) {
            return 0;
        }
        
        return (lastAdded + cooldown) - block.timestamp;
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setMaxSlippage(uint256 newSlippage) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newSlippage <= 1000, "Slippage too high"); // Max 10%
        maxSlippage = newSlippage;
    }

    function setMinMintAmount(uint256 newAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        minMintAmount = newAmount;
    }

    function setAutoCompoundParams(bool enabled, uint256 threshold) external onlyRole(DEFAULT_ADMIN_ROLE) {
        autoCompoundEnabled = enabled;
        autoCompoundThreshold = threshold;
    }

    function setActive(bool _active) external onlyRole(DEFAULT_ADMIN_ROLE) {
        active = _active;
    }

    function recoverToken(address token, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(token != address(asset), "Cannot recover main asset");
        require(token != address(glpToken), "Cannot recover GLP");
        IERC20(token).safeTransfer(msg.sender, amount);
    }
}