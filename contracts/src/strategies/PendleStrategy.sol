// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "../interfaces/IStrategy.sol";

// Pendle Protocol interfaces
interface IPendleMarket {
    function readTokens() external view returns (address sy, address pt, address yt);
    function getRewardTokens() external view returns (address[] memory);
    function userReward(address token, address user) external view returns (uint128 index, uint128 accrued);
    function redeemRewards(address user) external returns (uint256[] memory);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function totalStaked() external view returns (uint256);
    function mint(address to, uint256 amount) external returns (uint256);
    function burn(address from, uint256 amount) external returns (uint256);
}

interface IPendleRouter {
    struct TokenInput {
        address tokenIn;
        uint256 netTokenIn;
        address tokenMintSy;
        address pendleSwap;
        SwapData swapData;
    }
    
    struct SwapData {
        SwapType swapType;
        address extRouter;
        bytes extCalldata;
        bool needScale;
    }
    
    enum SwapType {
        NONE,
        KYBERSWAP,
        ONE_INCH,
        ETH_WETH
    }
    
    struct TokenOutput {
        address tokenOut;
        uint256 minTokenOut;
        address tokenRedeemSy;
        address pendleSwap;
        SwapData swapData;
    }
    
    function addLiquidityDualSyAndPt(
        address receiver,
        address market,
        uint256 netSyDesired,
        uint256 netPtDesired,
        uint256 minLpOut
    ) external returns (uint256 netLpOut, uint256 netSyUsed, uint256 netPtUsed);
    
    function addLiquiditySingleToken(
        address receiver,
        address market,
        uint256 minLpOut,
        ApproxParams calldata guessPtReceivedFromSy,
        TokenInput calldata input
    ) external payable returns (uint256 netLpOut, uint256 netYtOut);
    
    function removeLiquidityDualSyAndPt(
        address receiver,
        address market,
        uint256 netLpToRemove,
        uint256 minSyOut,
        uint256 minPtOut
    ) external returns (uint256 netSyOut, uint256 netPtOut);
    
    function removeLiquiditySingleToken(
        address receiver,
        address market,
        uint256 netLpToRemove,
        TokenOutput calldata output
    ) external returns (uint256 netTokenOut);
    
    struct ApproxParams {
        uint256 guessMin;
        uint256 guessMax;
        uint256 guessOffchain;
        uint256 maxIteration;
        uint256 eps;
    }
}

interface IPendleSY {
    function deposit(
        address receiver,
        address tokenIn,
        uint256 amountTokenToDeposit,
        uint256 minSharesOut
    ) external payable returns (uint256 amountSharesOut);
    
    function redeem(
        address receiver,
        uint256 amountSharesToRedeem,
        address tokenOut,
        uint256 minTokenOut,
        bool burnFromInternalBalance
    ) external returns (uint256 amountTokenOut);
    
    function exchangeRate() external view returns (uint256);
    
    function totalSupply() external view returns (uint256);
    
    function balanceOf(address account) external view returns (uint256);
    
    function previewDeposit(address tokenIn, uint256 amountTokenToDeposit)
        external
        view
        returns (uint256 amountSharesOut);
    
    function previewRedeem(address tokenOut, uint256 amountSharesToRedeem)
        external
        view
        returns (uint256 amountTokenOut);
}

interface IPendleYT {
    function mintPY(address receiver, address SY) external returns (uint256 amountPYOut);
    function redeemPY(address receiver) external returns (uint256 amountSyOut);
    function redeemDueInterestAndRewards(address user, bool redeemInterest, bool redeemRewards)
        external
        returns (uint256 interestOut, uint256[] memory rewardsOut);
    function getRewardTokens() external view returns (address[] memory);
    function userReward(address token, address user) external view returns (uint128);
}

/**
 * @title PendleStrategy
 * @dev Strategy for yield tokenization and trading on Pendle Protocol
 * @notice Provides exposure to yield tokens and principal tokens with additional rewards
 */
contract PendleStrategy is IStrategy, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Math for uint256;

    bytes32 public constant STRATEGY_MANAGER_ROLE = keccak256("STRATEGY_MANAGER_ROLE");
    
    uint256 public constant MAX_BPS = 10_000;
    uint256 public constant PRECISION = 1e18;
    
    // Core tokens
    IERC20 public immutable override asset;
    
    // Pendle contracts
    IPendleMarket public immutable market;
    IPendleRouter public immutable router;
    IPendleSY public immutable sy; // Standardized Yield token
    address public immutable pt; // Principal Token
    address public immutable yt; // Yield Token
    
    // Strategy configuration
    enum StrategyType {
        LP_FARMING,      // Provide liquidity to PT-SY pools
        YT_HOLDING,      // Hold yield tokens for yield
        PT_HOLDING,      // Hold principal tokens for fixed yield
        MIXED            // Mixed strategy
    }
    
    StrategyType public strategyType = StrategyType.LP_FARMING;
    uint8 public constant override riskLevel = 5; // Medium risk
    
    // Position tracking
    uint256 public totalLPTokens;
    uint256 public totalSYTokens;
    uint256 public totalPTTokens;
    uint256 public totalYTTokens;
    
    // Performance tracking
    uint256 public totalDeposited;
    uint256 public totalWithdrawn;
    uint256 public totalYieldHarvested;
    uint256 public lastHarvest;
    uint256 public lastAPYUpdate;
    uint256 public currentAPY;
    bool public active = true;
    
    // Strategy parameters
    uint256 public maxSlippage = 200; // 2%
    uint256 public minInvestAmount = 10 * 1e18; // 10 tokens minimum
    uint256 public rebalanceThreshold = 500; // 5%
    uint256 public harvestThreshold = 1e18; // 1 token minimum to harvest
    
    // Reward tokens
    address[] public rewardTokens;
    mapping(address => uint256) public totalRewardsHarvested;
    
    event StrategyTypeChanged(StrategyType oldType, StrategyType newType);
    event LiquidityAdded(uint256 syAmount, uint256 ptAmount, uint256 lpReceived);
    event LiquidityRemoved(uint256 lpAmount, uint256 syReceived, uint256 ptReceived);
    event YieldHarvested(uint256 yieldAmount, address[] rewardTokens, uint256[] rewardAmounts);
    event PositionRebalanced(uint256 totalAssets, uint256 timestamp);
    event APYUpdated(uint256 oldAPY, uint256 newAPY);
    
    modifier onlyStrategyManager() {
        require(hasRole(STRATEGY_MANAGER_ROLE, msg.sender), "PS: Not strategy manager");
        _;
    }
    
    constructor(
        address _asset,
        address _market,
        address _router,
        address _sy,
        address _admin
    ) {
        require(_asset != address(0), "PS: Invalid asset");
        require(_market != address(0), "PS: Invalid market");
        require(_router != address(0), "PS: Invalid router");
        require(_sy != address(0), "PS: Invalid SY");
        
        asset = IERC20(_asset);
        market = IPendleMarket(_market);
        router = IPendleRouter(_router);
        sy = IPendleSY(_sy);
        
        // Get PT and YT addresses from market
        (, pt, yt) = market.readTokens();
        
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(STRATEGY_MANAGER_ROLE, _admin);
        
        // Approve tokens for router
        asset.safeApprove(_router, type(uint256).max);
        IERC20(address(sy)).safeApprove(_router, type(uint256).max);
        IERC20(pt).safeApprove(_router, type(uint256).max);
        IERC20(yt).safeApprove(_router, type(uint256).max);
        
        // Get reward tokens
        rewardTokens = market.getRewardTokens();
        
        lastHarvest = block.timestamp;
        lastAPYUpdate = block.timestamp;
    }
    
    /*//////////////////////////////////////////////////////////////
                        STRATEGY IMPLEMENTATION
    //////////////////////////////////////////////////////////////*/
    
    function getAPY() external view override returns (uint256 apy) {
        if (totalAssets() == 0) return 0;
        
        // Calculate APY based on strategy type and accumulated rewards
        uint256 baseAPY = 0;
        
        if (strategyType == StrategyType.LP_FARMING) {
            // LP farming APY includes trading fees + rewards
            baseAPY = _getLPFarmingAPY();
        } else if (strategyType == StrategyType.YT_HOLDING) {
            // YT APY is variable based on underlying yield
            baseAPY = _getYTHoldingAPY();
        } else if (strategyType == StrategyType.PT_HOLDING) {
            // PT APY is fixed until maturity
            baseAPY = _getPTHoldingAPY();
        } else {
            // Mixed strategy - weighted average
            baseAPY = _getMixedStrategyAPY();
        }
        
        // Add reward token yields
        uint256 rewardAPY = _getRewardAPY();
        
        return baseAPY + rewardAPY;
    }
    
    function totalAssets() external view override returns (uint256) {
        uint256 directBalance = asset.balanceOf(address(this));
        uint256 investedValue = 0;
        
        // Value LP positions
        if (totalLPTokens > 0) {
            investedValue += _getLPValue(totalLPTokens);
        }
        
        // Value SY positions
        if (totalSYTokens > 0) {
            investedValue += _getSYValue(totalSYTokens);
        }
        
        // Value PT positions
        if (totalPTTokens > 0) {
            investedValue += _getPTValue(totalPTTokens);
        }
        
        // Value YT positions
        if (totalYTTokens > 0) {
            investedValue += _getYTValue(totalYTTokens);
        }
        
        return directBalance + investedValue;
    }
    
    function invest(uint256 amount) external override nonReentrant returns (uint256 invested) {
        require(hasRole(STRATEGY_MANAGER_ROLE, msg.sender), "PS: Not authorized");
        require(active, "PS: Strategy not active");
        require(amount >= minInvestAmount, "PS: Amount too small");
        
        uint256 assetBalance = asset.balanceOf(address(this));
        amount = amount > assetBalance ? assetBalance : amount;
        
        if (amount == 0) return 0;
        
        if (strategyType == StrategyType.LP_FARMING) {
            invested = _investInLP(amount);
        } else if (strategyType == StrategyType.YT_HOLDING) {
            invested = _investInYT(amount);
        } else if (strategyType == StrategyType.PT_HOLDING) {
            invested = _investInPT(amount);
        } else {
            invested = _investMixed(amount);
        }
        
        totalDeposited += invested;
        return invested;
    }
    
    function withdraw(uint256 amount) external override nonReentrant returns (uint256 withdrawn) {
        require(hasRole(STRATEGY_MANAGER_ROLE, msg.sender), "PS: Not authorized");
        require(amount > 0, "PS: Invalid amount");
        
        uint256 availableAssets = this.totalAssets();
        amount = amount > availableAssets ? availableAssets : amount;
        
        uint256 directBalance = asset.balanceOf(address(this));
        
        if (amount <= directBalance) {
            // Can withdraw directly
            withdrawn = amount;
            asset.safeTransfer(msg.sender, withdrawn);
        } else {
            // Need to liquidate positions
            uint256 neededFromPositions = amount - directBalance;
            withdrawn = directBalance + _liquidatePositions(neededFromPositions);
            
            if (withdrawn > 0) {
                asset.safeTransfer(msg.sender, withdrawn);
            }
        }
        
        totalWithdrawn += withdrawn;
        return withdrawn;
    }
    
    function harvest() external override nonReentrant returns (uint256 harvested) {
        require(hasRole(STRATEGY_MANAGER_ROLE, msg.sender), "PS: Not authorized");
        
        uint256 beforeBalance = asset.balanceOf(address(this));
        
        // Harvest yield from YT positions
        if (totalYTTokens > 0) {
            _harvestYTRewards();
        }
        
        // Harvest LP rewards
        if (totalLPTokens > 0) {
            _harvestLPRewards();
        }
        
        // Claim market rewards
        _claimMarketRewards();
        
        uint256 afterBalance = asset.balanceOf(address(this));
        harvested = afterBalance > beforeBalance ? afterBalance - beforeBalance : 0;
        
        if (harvested > 0) {
            totalYieldHarvested += harvested;
            lastHarvest = block.timestamp;
            
            emit YieldHarvested(harvested, rewardTokens, _getRewardBalances());
        }
        
        _updateAPY();
        return harvested;
    }
    
    function emergencyWithdraw() external override nonReentrant returns (uint256 withdrawn) {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "PS: Not authorized");
        
        // Harvest any pending rewards
        try this.harvest() {} catch {}
        
        // Liquidate all positions
        withdrawn = _liquidateAllPositions();
        
        // Add direct balance
        uint256 directBalance = asset.balanceOf(address(this));
        withdrawn += directBalance;
        
        if (withdrawn > 0) {
            asset.safeTransfer(msg.sender, withdrawn);
        }
        
        // Reset position tracking
        totalLPTokens = 0;
        totalSYTokens = 0;
        totalPTTokens = 0;
        totalYTTokens = 0;
        
        active = false;
        return withdrawn;
    }
    
    function isActive() external view override returns (bool) {
        return active;
    }
    
    function maxInvestable() external view override returns (uint256) {
        if (!active) return 0;
        
        // Pendle markets have high liquidity, limit based on market size
        uint256 marketTVL = market.totalSupply();
        
        // Allow up to 10% of market TVL
        return marketTVL / 10;
    }
    
    function getRiskLevel() external pure override returns (uint8) {
        return riskLevel;
    }
    
    /*//////////////////////////////////////////////////////////////
                        STRATEGY-SPECIFIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function _investInLP(uint256 amount) internal returns (uint256 invested) {
        // Convert asset to SY first
        uint256 syReceived = sy.deposit(address(this), address(asset), amount, 0);
        
        if (syReceived > 0) {
            // Use half for PT, half for SY in LP
            uint256 syForLP = syReceived / 2;
            uint256 ptForLP = syForLP; // Assume 1:1 ratio for simplicity
            
            try router.addLiquidityDualSyAndPt(
                address(this),
                address(market),
                syForLP,
                ptForLP,
                0 // Accept any LP amount for now
            ) returns (uint256 lpOut, uint256 syUsed, uint256 ptUsed) {
                totalLPTokens += lpOut;
                totalSYTokens += syReceived - syUsed;
                invested = amount;
                
                emit LiquidityAdded(syUsed, ptUsed, lpOut);
            } catch {
                // If LP addition fails, keep as SY
                totalSYTokens += syReceived;
                invested = amount;
            }
        }
        
        return invested;
    }
    
    function _investInYT(uint256 amount) internal returns (uint256 invested) {
        // Convert to SY and mint YT
        uint256 syReceived = sy.deposit(address(this), address(asset), amount, 0);
        
        if (syReceived > 0) {
            // Mint PT+YT from SY (simplified)
            totalSYTokens += syReceived;
            invested = amount;
        }
        
        return invested;
    }
    
    function _investInPT(uint256 amount) internal returns (uint256 invested) {
        // Buy PT tokens (simplified - would use router in production)
        uint256 syReceived = sy.deposit(address(this), address(asset), amount, 0);
        
        if (syReceived > 0) {
            totalSYTokens += syReceived;
            invested = amount;
        }
        
        return invested;
    }
    
    function _investMixed(uint256 amount) internal returns (uint256 invested) {
        // Allocate across strategies based on current market conditions
        uint256 lpAllocation = amount * 40 / 100;  // 40% to LP
        uint256 ytAllocation = amount * 35 / 100;  // 35% to YT
        uint256 ptAllocation = amount * 25 / 100;  // 25% to PT
        
        _investInLP(lpAllocation);
        _investInYT(ytAllocation);
        _investInPT(ptAllocation);
        
        return amount;
    }
    
    function _liquidatePositions(uint256 targetAmount) internal returns (uint256 liquidated) {
        // Liquidate positions proportionally to reach target amount
        uint256 totalValue = this.totalAssets() - asset.balanceOf(address(this));
        if (totalValue == 0) return 0;
        
        // Calculate proportions to liquidate
        uint256 lpToLiquidate = (totalLPTokens * targetAmount) / totalValue;
        uint256 syToLiquidate = (totalSYTokens * targetAmount) / totalValue;
        uint256 ptToLiquidate = (totalPTTokens * targetAmount) / totalValue;
        uint256 ytToLiquidate = (totalYTTokens * targetAmount) / totalValue;
        
        // Liquidate LP positions
        if (lpToLiquidate > 0 && totalLPTokens > 0) {
            liquidated += _liquidateLP(lpToLiquidate);
        }
        
        // Liquidate SY positions
        if (syToLiquidate > 0 && totalSYTokens > 0) {
            liquidated += _liquidateSY(syToLiquidate);
        }
        
        // Liquidate PT positions (simplified)
        if (ptToLiquidate > 0 && totalPTTokens > 0) {
            totalPTTokens -= ptToLiquidate;
        }
        
        // Liquidate YT positions (simplified)
        if (ytToLiquidate > 0 && totalYTTokens > 0) {
            totalYTTokens -= ytToLiquidate;
        }
        
        return liquidated;
    }
    
    function _liquidateAllPositions() internal returns (uint256 liquidated) {
        // Remove all LP
        if (totalLPTokens > 0) {
            liquidated += _liquidateLP(totalLPTokens);
        }
        
        // Redeem all SY
        if (totalSYTokens > 0) {
            liquidated += _liquidateSY(totalSYTokens);
        }
        
        return liquidated;
    }
    
    function _liquidateLP(uint256 lpAmount) internal returns (uint256 liquidated) {
        if (lpAmount == 0) return 0;
        
        try router.removeLiquidityDualSyAndPt(
            address(this),
            address(market),
            lpAmount,
            0, // minSyOut
            0  // minPtOut
        ) returns (uint256 syOut, uint256 ptOut) {
            totalLPTokens -= lpAmount;
            totalSYTokens += syOut;
            totalPTTokens += ptOut;
            
            // Convert SY back to asset
            liquidated = _liquidateSY(syOut);
            
            emit LiquidityRemoved(lpAmount, syOut, ptOut);
        } catch {
            // If removal fails, mark LP as liquidated anyway
            totalLPTokens -= lpAmount;
        }
        
        return liquidated;
    }
    
    function _liquidateSY(uint256 syAmount) internal returns (uint256 liquidated) {
        if (syAmount == 0) return 0;
        
        try sy.redeem(
            address(this),
            syAmount,
            address(asset),
            0, // minTokenOut
            false
        ) returns (uint256 assetOut) {
            totalSYTokens -= syAmount;
            liquidated = assetOut;
        } catch {
            totalSYTokens -= syAmount;
        }
        
        return liquidated;
    }
    
    /*//////////////////////////////////////////////////////////////
                        HARVEST FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function _harvestYTRewards() internal {
        if (totalYTTokens == 0) return;
        
        // Harvest YT interest and rewards (simplified)
        // In production, call actual YT contract methods
    }
    
    function _harvestLPRewards() internal {
        if (totalLPTokens == 0) return;
        
        // Harvest LP farming rewards (simplified)
        // In production, call actual staking contract methods
    }
    
    function _claimMarketRewards() internal {
        try market.redeemRewards(address(this)) returns (uint256[] memory rewards) {
            // Process reward tokens (simplified)
            for (uint256 i = 0; i < rewardTokens.length && i < rewards.length; i++) {
                if (rewards[i] > 0) {
                    totalRewardsHarvested[rewardTokens[i]] += rewards[i];
                }
            }
        } catch {
            // Continue if reward claiming fails
        }
    }
    
    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function _getLPValue(uint256 lpAmount) internal view returns (uint256) {
        if (lpAmount == 0 || market.totalSupply() == 0) return 0;
        
        // Simplified LP valuation
        // In production, calculate based on underlying SY+PT reserves
        return lpAmount; // Placeholder
    }
    
    function _getSYValue(uint256 syAmount) internal view returns (uint256) {
        if (syAmount == 0) return 0;
        
        return sy.previewRedeem(address(asset), syAmount);
    }
    
    function _getPTValue(uint256 ptAmount) internal view returns (uint256) {
        // PT value approaches underlying at maturity
        // For now, use current market price (simplified)
        return ptAmount; // Placeholder
    }
    
    function _getYTValue(uint256 ytAmount) internal view returns (uint256) {
        // YT value is derived from expected future yield
        // Highly variable and depends on time to maturity
        return ytAmount / 2; // Conservative estimate
    }
    
    function _getLPFarmingAPY() internal view returns (uint256) {
        // Calculate based on trading fees + farming rewards
        return 1200; // 12% placeholder
    }
    
    function _getYTHoldingAPY() internal view returns (uint256) {
        // Variable APY based on underlying yield
        return 800; // 8% placeholder
    }
    
    function _getPTHoldingAPY() internal view returns (uint256) {
        // Fixed APY until maturity
        return 600; // 6% placeholder
    }
    
    function _getMixedStrategyAPY() internal view returns (uint256) {
        // Weighted average of all strategies
        return 900; // 9% placeholder
    }
    
    function _getRewardAPY() internal view returns (uint256) {
        // Additional APY from reward tokens
        return 200; // 2% placeholder
    }
    
    function _getRewardBalances() internal view returns (uint256[] memory balances) {
        balances = new uint256[](rewardTokens.length);
        
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            balances[i] = IERC20(rewardTokens[i]).balanceOf(address(this));
        }
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
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function setStrategyType(StrategyType newType) external onlyRole(DEFAULT_ADMIN_ROLE) {
        StrategyType oldType = strategyType;
        strategyType = newType;
        emit StrategyTypeChanged(oldType, newType);
    }
    
    function setStrategyParams(
        uint256 newMaxSlippage,
        uint256 newMinInvestAmount,
        uint256 newRebalanceThreshold,
        uint256 newHarvestThreshold
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newMaxSlippage <= 1000, "PS: Slippage too high"); // Max 10%
        
        maxSlippage = newMaxSlippage;
        minInvestAmount = newMinInvestAmount;
        rebalanceThreshold = newRebalanceThreshold;
        harvestThreshold = newHarvestThreshold;
    }
    
    function setActive(bool _active) external onlyRole(DEFAULT_ADMIN_ROLE) {
        active = _active;
    }
    
    function rebalanceStrategy() external onlyStrategyManager {
        // Rebalance positions based on current market conditions
        // Implementation depends on strategy type and market state
        
        emit PositionRebalanced(this.totalAssets(), block.timestamp);
    }
    
    function recoverToken(address token, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(token != address(asset), "PS: Cannot recover main asset");
        require(token != address(sy), "PS: Cannot recover SY");
        require(token != pt, "PS: Cannot recover PT");
        require(token != yt, "PS: Cannot recover YT");
        require(token != address(market), "PS: Cannot recover LP tokens");
        
        IERC20(token).safeTransfer(msg.sender, amount);
    }
    
    /*//////////////////////////////////////////////////////////////
                        EXTERNAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function getPositions() external view returns (
        uint256 lpTokens,
        uint256 syTokens,
        uint256 ptTokens,
        uint256 ytTokens
    ) {
        return (totalLPTokens, totalSYTokens, totalPTTokens, totalYTTokens);
    }
    
    function getRewardTokens() external view returns (address[] memory) {
        return rewardTokens;
    }
    
    function getPendingRewards() external view returns (uint256[] memory rewards) {
        rewards = new uint256[](rewardTokens.length);
        
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            (,uint128 accrued) = market.userReward(rewardTokens[i], address(this));
            rewards[i] = uint256(accrued);
        }
    }
    
    function getStrategyInfo() external view returns (
        StrategyType strategyType_,
        uint256 totalAssets_,
        uint256 currentAPY_,
        bool active_,
        uint256 lastHarvest_
    ) {
        return (
            strategyType,
            this.totalAssets(),
            currentAPY,
            active,
            lastHarvest
        );
    }
}