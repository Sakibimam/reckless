// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IStrategy.sol";

// Aerodrome Protocol interfaces
interface IAerodromePool {
    function getReserves() external view returns (uint256, uint256, bool);
    function mint(address to) external returns (uint256 liquidity);
    function burn(address to) external returns (uint256 amount0, uint256 amount1);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
    function token0() external view returns (address);
    function token1() external view returns (address);
    function totalSupply() external view returns (uint256);
}

interface IAerodromeGauge {
    function deposit(uint256 amount, uint256 tokenId) external;
    function withdraw(uint256 amount) external;
    function getReward(address account, address[] memory tokens) external;
    function balanceOf(address account) external view returns (uint256);
    function earned(address account, address token) external view returns (uint256);
}

interface IAerodromeRouter {
    struct Route {
        address from;
        address to;
        bool stable;
    }
    
    function addLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);
    
    function removeLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);
    
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        Route[] calldata routes,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
    
    function getAmountsOut(uint256 amountIn, Route[] calldata routes)
        external view returns (uint256[] memory amounts);
}

/**
 * @title AerodromeStrategy
 * @dev Strategy for providing liquidity to Aerodrome pools and earning AERO rewards
 */
contract AerodromeStrategy is IStrategy, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant STRATEGY_MANAGER_ROLE = keccak256("STRATEGY_MANAGER_ROLE");
    
    uint256 public constant MAX_BPS = 10_000;
    uint256 public constant SLIPPAGE_BPS = 100; // 1%
    
    IERC20 public immutable override asset;
    IERC20 public immutable pairedAsset;
    IERC20 public immutable aeroToken;
    
    IAerodromePool public immutable pool;
    IAerodromeGauge public immutable gauge;
    IAerodromeRouter public immutable router;
    
    bool public immutable isStable;
    uint8 public constant override riskLevel = 4; // Medium risk for LP strategies
    
    uint256 public totalLPTokens;
    uint256 public lastHarvest;
    uint256 public totalHarvestedAero;
    bool public active = true;
    
    // Strategy parameters
    uint256 public rebalanceThreshold = 500; // 5%
    uint256 public maxSlippage = 200; // 2%
    uint256 public minHarvestAmount = 1e18; // 1 AERO
    
    // Performance tracking
    uint256 public totalDeposited;
    uint256 public totalWithdrawn;
    uint256 public lastAPYUpdate;
    uint256 public currentAPY;
    
    event LiquidityAdded(uint256 amount0, uint256 amount1, uint256 liquidity);
    event LiquidityRemoved(uint256 amount0, uint256 amount1, uint256 liquidity);
    event RewardsHarvested(uint256 aeroAmount, uint256 swappedAmount);
    event APYUpdated(uint256 oldAPY, uint256 newAPY);

    modifier onlyStrategyManager() {
        require(hasRole(STRATEGY_MANAGER_ROLE, msg.sender), "Not strategy manager");
        _;
    }

    constructor(
        address _asset,
        address _pairedAsset,
        address _aeroToken,
        address _pool,
        address _gauge,
        address _router,
        bool _isStable,
        address _admin
    ) {
        require(_asset != address(0), "Invalid asset");
        require(_pool != address(0), "Invalid pool");
        
        asset = IERC20(_asset);
        pairedAsset = IERC20(_pairedAsset);
        aeroToken = IERC20(_aeroToken);
        pool = IAerodromePool(_pool);
        gauge = IAerodromeGauge(_gauge);
        router = IAerodromeRouter(_router);
        isStable = _isStable;
        
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(STRATEGY_MANAGER_ROLE, _admin);
        
        // Approve tokens for router and gauge
        asset.safeApprove(_router, type(uint256).max);
        pairedAsset.safeApprove(_router, type(uint256).max);
        IERC20(_pool).safeApprove(_gauge, type(uint256).max);
        aeroToken.safeApprove(_router, type(uint256).max);
        
        lastHarvest = block.timestamp;
        lastAPYUpdate = block.timestamp;
    }

    /*//////////////////////////////////////////////////////////////
                        STRATEGY IMPLEMENTATION
    //////////////////////////////////////////////////////////////*/

    function getAPY() external view override returns (uint256 apy) {
        if (totalLPTokens == 0) return 0;
        
        // Calculate APY based on AERO rewards and trading fees
        uint256 aeroRewards = gauge.earned(address(this), address(aeroToken));
        uint256 timeSinceLastHarvest = block.timestamp - lastHarvest;
        
        if (timeSinceLastHarvest > 0 && totalDeposited > 0) {
            // Annualize the rewards
            uint256 annualizedRewards = (aeroRewards * 365 days) / timeSinceLastHarvest;
            
            // Convert AERO rewards to asset value (simplified)
            uint256 rewardValue = _getAeroValueInAsset(annualizedRewards);
            
            // Calculate APY as percentage (basis points)
            apy = (rewardValue * MAX_BPS) / totalDeposited;
            
            // Add estimated trading fees (2-5% additional APY for active pairs)
            apy += 200; // 2% base trading fee APY
        }
        
        return apy;
    }

    function totalAssets() external view override returns (uint256) {
        if (totalLPTokens == 0) return asset.balanceOf(address(this));
        
        // Calculate the value of LP tokens in terms of the base asset
        uint256 totalSupply = pool.totalSupply();
        (uint256 reserve0, uint256 reserve1,) = pool.getReserves();
        
        uint256 lpValue;
        if (address(asset) == pool.token0()) {
            lpValue = (totalLPTokens * reserve0 * 2) / totalSupply; // Assume balanced pool
        } else {
            lpValue = (totalLPTokens * reserve1 * 2) / totalSupply;
        }
        
        return lpValue + asset.balanceOf(address(this));
    }

    function invest(uint256 amount) external override nonReentrant returns (uint256 invested) {
        require(hasRole(STRATEGY_MANAGER_ROLE, msg.sender), "Not authorized");
        require(active, "Strategy not active");
        require(amount > 0, "Invalid amount");
        
        uint256 assetBalance = asset.balanceOf(address(this));
        amount = amount > assetBalance ? assetBalance : amount;
        
        if (amount == 0) return 0;
        
        // Convert half of the asset to paired asset for LP
        uint256 halfAmount = amount / 2;
        uint256 pairedAmount = _swapForPairedAsset(halfAmount);
        
        if (pairedAmount > 0) {
            // Add liquidity
            (uint256 amount0, uint256 amount1, uint256 liquidity) = router.addLiquidity(
                address(asset),
                address(pairedAsset),
                isStable,
                amount - halfAmount, // remaining asset amount
                pairedAmount,
                (amount - halfAmount) * (MAX_BPS - maxSlippage) / MAX_BPS,
                pairedAmount * (MAX_BPS - maxSlippage) / MAX_BPS,
                address(this),
                block.timestamp + 300
            );
            
            // Stake LP tokens in gauge
            gauge.deposit(liquidity, 0);
            
            totalLPTokens += liquidity;
            invested = amount0 + _getPairedAssetValueInAsset(amount1);
            totalDeposited += invested;
            
            emit LiquidityAdded(amount0, amount1, liquidity);
        }
        
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
        } else {
            // Need to remove liquidity
            uint256 neededFromLP = amount - directBalance;
            uint256 lpToRemove = (neededFromLP * totalLPTokens) / (availableAssets - directBalance);
            
            if (lpToRemove > 0) {
                // Withdraw LP tokens from gauge
                gauge.withdraw(lpToRemove);
                
                // Remove liquidity
                (uint256 amount0, uint256 amount1) = router.removeLiquidity(
                    address(asset),
                    address(pairedAsset),
                    isStable,
                    lpToRemove,
                    0,
                    0,
                    address(this),
                    block.timestamp + 300
                );
                
                // Swap paired asset back to main asset if needed
                uint256 swappedAmount = _swapPairedAssetForAsset(amount1);
                
                totalLPTokens -= lpToRemove;
                withdrawn = directBalance + amount0 + swappedAmount;
                
                emit LiquidityRemoved(amount0, amount1, lpToRemove);
            } else {
                withdrawn = directBalance;
            }
        }
        
        totalWithdrawn += withdrawn;
        
        // Transfer withdrawn amount
        if (withdrawn > 0) {
            asset.safeTransfer(msg.sender, withdrawn);
        }
        
        return withdrawn;
    }

    function harvest() external override nonReentrant returns (uint256 harvested) {
        require(hasRole(STRATEGY_MANAGER_ROLE, msg.sender), "Not authorized");
        
        // Harvest AERO rewards
        address[] memory tokens = new address[](1);
        tokens[0] = address(aeroToken);
        gauge.getReward(address(this), tokens);
        
        uint256 aeroBalance = aeroToken.balanceOf(address(this));
        
        if (aeroBalance >= minHarvestAmount) {
            // Swap AERO for main asset
            harvested = _swapAeroForAsset(aeroBalance);
            totalHarvestedAero += aeroBalance;
            
            emit RewardsHarvested(aeroBalance, harvested);
        }
        
        lastHarvest = block.timestamp;
        _updateAPY();
        
        return harvested;
    }

    function emergencyWithdraw() external override nonReentrant returns (uint256 withdrawn) {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not authorized");
        
        // Harvest any pending rewards
        this.harvest();
        
        // Withdraw all LP tokens from gauge
        if (totalLPTokens > 0) {
            gauge.withdraw(totalLPTokens);
            
            // Remove all liquidity
            (uint256 amount0, uint256 amount1) = router.removeLiquidity(
                address(asset),
                address(pairedAsset),
                isStable,
                totalLPTokens,
                0,
                0,
                address(this),
                block.timestamp + 300
            );
            
            // Swap all paired asset to main asset
            uint256 swappedAmount = _swapPairedAssetForAsset(amount1);
            
            withdrawn = amount0 + swappedAmount;
            totalLPTokens = 0;
            
            emit LiquidityRemoved(amount0, amount1, totalLPTokens);
        }
        
        // Add any direct balance
        uint256 directBalance = asset.balanceOf(address(this));
        withdrawn += directBalance;
        
        // Transfer all assets to caller
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
        
        // Check pool capacity and paired asset availability
        (uint256 reserve0, uint256 reserve1,) = pool.getReserves();
        uint256 poolSize = address(asset) == pool.token0() ? reserve0 : reserve1;
        
        // Limit to 10% of pool size to avoid excessive price impact
        return poolSize / 10;
    }

    function getRiskLevel() external pure override returns (uint8) {
        return riskLevel;
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _swapForPairedAsset(uint256 amountIn) internal returns (uint256 amountOut) {
        if (amountIn == 0) return 0;
        
        IAerodromeRouter.Route[] memory routes = new IAerodromeRouter.Route[](1);
        routes[0] = IAerodromeRouter.Route({
            from: address(asset),
            to: address(pairedAsset),
            stable: isStable
        });
        
        uint256[] memory amountsOut = router.getAmountsOut(amountIn, routes);
        uint256 expectedOut = amountsOut[amountsOut.length - 1];
        
        uint256[] memory amounts = router.swapExactTokensForTokens(
            amountIn,
            expectedOut * (MAX_BPS - maxSlippage) / MAX_BPS,
            routes,
            address(this),
            block.timestamp + 300
        );
        
        return amounts[amounts.length - 1];
    }

    function _swapPairedAssetForAsset(uint256 amountIn) internal returns (uint256 amountOut) {
        if (amountIn == 0) return 0;
        
        IAerodromeRouter.Route[] memory routes = new IAerodromeRouter.Route[](1);
        routes[0] = IAerodromeRouter.Route({
            from: address(pairedAsset),
            to: address(asset),
            stable: isStable
        });
        
        uint256[] memory amountsOut = router.getAmountsOut(amountIn, routes);
        uint256 expectedOut = amountsOut[amountsOut.length - 1];
        
        uint256[] memory amounts = router.swapExactTokensForTokens(
            amountIn,
            expectedOut * (MAX_BPS - maxSlippage) / MAX_BPS,
            routes,
            address(this),
            block.timestamp + 300
        );
        
        return amounts[amounts.length - 1];
    }

    function _swapAeroForAsset(uint256 amountIn) internal returns (uint256 amountOut) {
        if (amountIn == 0) return 0;
        
        IAerodromeRouter.Route[] memory routes = new IAerodromeRouter.Route[](2);
        routes[0] = IAerodromeRouter.Route({
            from: address(aeroToken),
            to: address(pairedAsset), // AERO -> USDC/ETH
            stable: false
        });
        routes[1] = IAerodromeRouter.Route({
            from: address(pairedAsset),
            to: address(asset),
            stable: isStable
        });
        
        uint256[] memory amountsOut = router.getAmountsOut(amountIn, routes);
        uint256 expectedOut = amountsOut[amountsOut.length - 1];
        
        uint256[] memory amounts = router.swapExactTokensForTokens(
            amountIn,
            expectedOut * (MAX_BPS - maxSlippage) / MAX_BPS,
            routes,
            address(this),
            block.timestamp + 300
        );
        
        return amounts[amounts.length - 1];
    }

    function _getAeroValueInAsset(uint256 aeroAmount) internal view returns (uint256) {
        if (aeroAmount == 0) return 0;
        
        // Simplified price conversion - in production, use oracle or DEX pricing
        IAerodromeRouter.Route[] memory routes = new IAerodromeRouter.Route[](2);
        routes[0] = IAerodromeRouter.Route({
            from: address(aeroToken),
            to: address(pairedAsset),
            stable: false
        });
        routes[1] = IAerodromeRouter.Route({
            from: address(pairedAsset),
            to: address(asset),
            stable: isStable
        });
        
        try router.getAmountsOut(aeroAmount, routes) returns (uint256[] memory amounts) {
            return amounts[amounts.length - 1];
        } catch {
            return 0;
        }
    }

    function _getPairedAssetValueInAsset(uint256 pairedAmount) internal view returns (uint256) {
        if (pairedAmount == 0) return 0;
        
        IAerodromeRouter.Route[] memory routes = new IAerodromeRouter.Route[](1);
        routes[0] = IAerodromeRouter.Route({
            from: address(pairedAsset),
            to: address(asset),
            stable: isStable
        });
        
        try router.getAmountsOut(pairedAmount, routes) returns (uint256[] memory amounts) {
            return amounts[amounts.length - 1];
        } catch {
            return pairedAmount; // 1:1 fallback for stablecoins
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

    function setMaxSlippage(uint256 newSlippage) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newSlippage <= 1000, "Slippage too high"); // Max 10%
        maxSlippage = newSlippage;
    }

    function setMinHarvestAmount(uint256 newAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        minHarvestAmount = newAmount;
    }

    function setActive(bool _active) external onlyRole(DEFAULT_ADMIN_ROLE) {
        active = _active;
    }

    function recoverToken(address token, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(token != address(asset), "Cannot recover main asset");
        require(token != address(pool), "Cannot recover LP tokens");
        IERC20(token).safeTransfer(msg.sender, amount);
    }
}