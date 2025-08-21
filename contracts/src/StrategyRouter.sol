// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IStrategy.sol";

/**
 * @title StrategyRouter
 * @dev Routes funds to highest yield strategies with risk management
 */
contract StrategyRouter is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    bytes32 public constant ROUTER_MANAGER_ROLE = keccak256("ROUTER_MANAGER_ROLE");
    bytes32 public constant STRATEGY_UPDATER_ROLE = keccak256("STRATEGY_UPDATER_ROLE");

    uint256 public constant MAX_BPS = 10_000;
    uint256 public constant MAX_STRATEGIES = 20;
    uint256 public constant MIN_ROUTE_AMOUNT = 1000; // Minimum routing amount
    
    struct StrategyData {
        IStrategy strategy;
        uint256 currentAPY;
        uint256 maxCapacity;
        uint256 currentDeposits;
        uint8 riskLevel;
        bool active;
        uint256 lastUpdate;
        uint256 performanceScore; // 0-10000 based on historical performance
    }

    struct RouteRequest {
        IERC20 asset;
        uint256 amount;
        uint8 maxRiskLevel;
        uint256 minAPY;
        bool prioritizeAPY; // true = max APY, false = risk-adjusted return
    }

    struct RouteResult {
        address[] strategies;
        uint256[] amounts;
        uint256[] expectedAPYs;
        uint256 totalAmount;
        uint256 weightedAPY;
        uint8 maxRiskLevel;
    }

    mapping(address => mapping(address => StrategyData)) public strategies; // asset => strategy => data
    mapping(address => address[]) public assetStrategies; // asset => strategy addresses
    
    uint256 public routerPerformanceFee = 50; // 0.5% of profits
    address public performanceFeeRecipient;
    
    // Risk parameters
    uint256 public maxSingleStrategyAllocation = 5000; // 50% max to single strategy
    uint256 public riskToleranceMultiplier = 100; // Risk adjustment factor
    
    // Performance tracking
    mapping(address => mapping(address => uint256)) public strategyProfits; // strategy => asset => profits
    mapping(address => mapping(address => uint256)) public strategyLosses; // strategy => asset => losses
    mapping(address => uint256) public lastPerformanceUpdate;

    event StrategyRegistered(address indexed asset, address indexed strategy, uint256 apy, uint8 riskLevel);
    event StrategyUpdated(address indexed asset, address indexed strategy, uint256 newAPY, bool active);
    event FundsRouted(address indexed asset, uint256 amount, address[] strategies, uint256[] amounts);
    event PerformanceUpdated(address indexed strategy, address indexed asset, uint256 performance);
    event RouteOptimized(address indexed asset, uint256 oldAPY, uint256 newAPY);

    modifier onlyRouterManager() {
        require(hasRole(ROUTER_MANAGER_ROLE, msg.sender), "Not router manager");
        _;
    }

    modifier onlyStrategyUpdater() {
        require(hasRole(STRATEGY_UPDATER_ROLE, msg.sender), "Not strategy updater");
        _;
    }

    constructor(address admin, address feeRecipient) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ROUTER_MANAGER_ROLE, admin);
        _grantRole(STRATEGY_UPDATER_ROLE, admin);
        performanceFeeRecipient = feeRecipient;
    }

    /*//////////////////////////////////////////////////////////////
                        STRATEGY MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    function registerStrategy(
        address asset,
        address strategy,
        uint256 initialAPY,
        uint256 maxCapacity,
        uint8 riskLevel
    ) external onlyRouterManager {
        require(asset != address(0) && strategy != address(0), "Invalid addresses");
        require(riskLevel <= 10, "Invalid risk level");
        require(assetStrategies[asset].length < MAX_STRATEGIES, "Too many strategies");
        
        IStrategy strategyContract = IStrategy(strategy);
        require(strategyContract.asset() == asset, "Asset mismatch");
        require(strategyContract.isActive(), "Strategy not active");
        
        strategies[asset][strategy] = StrategyData({
            strategy: strategyContract,
            currentAPY: initialAPY,
            maxCapacity: maxCapacity,
            currentDeposits: 0,
            riskLevel: riskLevel,
            active: true,
            lastUpdate: block.timestamp,
            performanceScore: 5000 // Start with neutral score
        });
        
        assetStrategies[asset].push(strategy);
        
        emit StrategyRegistered(asset, strategy, initialAPY, riskLevel);
    }

    function updateStrategyAPY(address asset, address strategy, uint256 newAPY) 
        external 
        onlyStrategyUpdater 
    {
        require(strategies[asset][strategy].active, "Strategy not active");
        strategies[asset][strategy].currentAPY = newAPY;
        strategies[asset][strategy].lastUpdate = block.timestamp;
        
        emit StrategyUpdated(asset, strategy, newAPY, true);
    }

    function updateStrategyStatus(address asset, address strategy, bool active) 
        external 
        onlyRouterManager 
    {
        require(strategies[asset][strategy].strategy != IStrategy(address(0)), "Strategy not found");
        strategies[asset][strategy].active = active;
        strategies[asset][strategy].lastUpdate = block.timestamp;
        
        emit StrategyUpdated(asset, strategy, strategies[asset][strategy].currentAPY, active);
    }

    function updateStrategyCapacity(address asset, address strategy, uint256 newMaxCapacity) 
        external 
        onlyRouterManager 
    {
        require(strategies[asset][strategy].active, "Strategy not active");
        strategies[asset][strategy].maxCapacity = newMaxCapacity;
    }

    /*//////////////////////////////////////////////////////////////
                        ROUTING LOGIC
    //////////////////////////////////////////////////////////////*/

    function getOptimalRoute(RouteRequest calldata request) 
        external 
        view 
        returns (RouteResult memory result) 
    {
        require(request.amount >= MIN_ROUTE_AMOUNT, "Amount too small");
        
        address[] memory availableStrategies = _getAvailableStrategies(
            address(request.asset),
            request.maxRiskLevel,
            request.minAPY
        );
        
        if (availableStrategies.length == 0) {
            return result; // Empty result
        }
        
        return _optimizeAllocation(request, availableStrategies);
    }

    function routeFunds(RouteRequest calldata request) 
        external 
        nonReentrant 
        whenNotPaused 
        returns (RouteResult memory result) 
    {
        require(hasRole(ROUTER_MANAGER_ROLE, msg.sender) || hasRole(DEFAULT_ADMIN_ROLE, msg.sender), 
                "Not authorized");
        
        result = getOptimalRoute(request);
        require(result.strategies.length > 0, "No suitable strategies");
        
        // Execute the routing
        for (uint256 i = 0; i < result.strategies.length; i++) {
            if (result.amounts[i] > 0) {
                address strategy = result.strategies[i];
                uint256 amount = result.amounts[i];
                
                // Transfer funds to strategy
                request.asset.safeTransferFrom(msg.sender, strategy, amount);
                
                // Invest in strategy
                IStrategy(strategy).invest(amount);
                
                // Update tracking
                strategies[address(request.asset)][strategy].currentDeposits += amount;
            }
        }
        
        emit FundsRouted(address(request.asset), request.amount, result.strategies, result.amounts);
    }

    function rebalanceStrategies(address asset, uint256 totalAmount) 
        external 
        onlyRouterManager 
        nonReentrant 
    {
        RouteRequest memory request = RouteRequest({
            asset: IERC20(asset),
            amount: totalAmount,
            maxRiskLevel: 10, // Max risk for rebalancing
            minAPY: 0,
            prioritizeAPY: true
        });
        
        // Get current optimal allocation
        RouteResult memory optimalRoute = getOptimalRoute(request);
        
        // Rebalance existing positions
        address[] memory currentStrategies = assetStrategies[asset];
        for (uint256 i = 0; i < currentStrategies.length; i++) {
            address strategy = currentStrategies[i];
            StrategyData storage data = strategies[asset][strategy];
            
            if (!data.active || data.currentDeposits == 0) continue;
            
            // Calculate target allocation for this strategy
            uint256 targetAmount = 0;
            for (uint256 j = 0; j < optimalRoute.strategies.length; j++) {
                if (optimalRoute.strategies[j] == strategy) {
                    targetAmount = optimalRoute.amounts[j];
                    break;
                }
            }
            
            // Rebalance if needed
            if (data.currentDeposits > targetAmount) {
                uint256 toWithdraw = data.currentDeposits - targetAmount;
                uint256 withdrawn = data.strategy.withdraw(toWithdraw);
                data.currentDeposits -= withdrawn;
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                        PERFORMANCE TRACKING
    //////////////////////////////////////////////////////////////*/

    function updateStrategyPerformance(address asset, address strategy) external {
        StrategyData storage data = strategies[asset][strategy];
        require(data.active, "Strategy not active");
        
        // Get current strategy value
        uint256 currentValue = data.strategy.totalAssets();
        uint256 expectedValue = data.currentDeposits;
        
        if (currentValue > expectedValue) {
            // Profit
            uint256 profit = currentValue - expectedValue;
            strategyProfits[strategy][asset] += profit;
            
            // Update performance score (increase)
            uint256 profitBPS = (profit * MAX_BPS) / expectedValue;
            data.performanceScore = _adjustPerformanceScore(data.performanceScore, profitBPS, true);
        } else if (currentValue < expectedValue) {
            // Loss
            uint256 loss = expectedValue - currentValue;
            strategyLosses[strategy][asset] += loss;
            
            // Update performance score (decrease)
            uint256 lossBPS = (loss * MAX_BPS) / expectedValue;
            data.performanceScore = _adjustPerformanceScore(data.performanceScore, lossBPS, false);
        }
        
        lastPerformanceUpdate[strategy] = block.timestamp;
        emit PerformanceUpdated(strategy, asset, data.performanceScore);
    }

    function batchUpdatePerformances(address asset, address[] calldata strategiesToUpdate) 
        external 
        onlyStrategyUpdater 
    {
        for (uint256 i = 0; i < strategiesToUpdate.length; i++) {
            if (strategies[asset][strategiesToUpdate[i]].active) {
                updateStrategyPerformance(asset, strategiesToUpdate[i]);
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getStrategiesForAsset(address asset) 
        external 
        view 
        returns (address[] memory activeStrategies, uint256[] memory apys, uint8[] memory riskLevels) 
    {
        address[] memory allStrategies = assetStrategies[asset];
        uint256 activeCount = 0;
        
        // Count active strategies
        for (uint256 i = 0; i < allStrategies.length; i++) {
            if (strategies[asset][allStrategies[i]].active) {
                activeCount++;
            }
        }
        
        activeStrategies = new address[](activeCount);
        apys = new uint256[](activeCount);
        riskLevels = new uint8[](activeCount);
        
        uint256 index = 0;
        for (uint256 i = 0; i < allStrategies.length; i++) {
            address strategy = allStrategies[i];
            StrategyData memory data = strategies[asset][strategy];
            if (data.active) {
                activeStrategies[index] = strategy;
                apys[index] = data.currentAPY;
                riskLevels[index] = data.riskLevel;
                index++;
            }
        }
    }

    function getStrategyPerformance(address asset, address strategy) 
        external 
        view 
        returns (
            uint256 totalProfits,
            uint256 totalLosses,
            uint256 performanceScore,
            uint256 lastUpdate
        ) 
    {
        totalProfits = strategyProfits[strategy][asset];
        totalLosses = strategyLosses[strategy][asset];
        performanceScore = strategies[asset][strategy].performanceScore;
        lastUpdate = lastPerformanceUpdate[strategy];
    }

    function getHighestAPYStrategy(address asset, uint8 maxRiskLevel) 
        external 
        view 
        returns (address bestStrategy, uint256 apy) 
    {
        address[] memory availableStrategies = _getAvailableStrategies(asset, maxRiskLevel, 0);
        
        uint256 highestAPY = 0;
        for (uint256 i = 0; i < availableStrategies.length; i++) {
            address strategy = availableStrategies[i];
            uint256 strategyAPY = strategies[asset][strategy].currentAPY;
            if (strategyAPY > highestAPY) {
                highestAPY = strategyAPY;
                bestStrategy = strategy;
            }
        }
        
        apy = highestAPY;
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _getAvailableStrategies(address asset, uint8 maxRiskLevel, uint256 minAPY) 
        internal 
        view 
        returns (address[] memory) 
    {
        address[] memory allStrategies = assetStrategies[asset];
        address[] memory temp = new address[](allStrategies.length);
        uint256 count = 0;
        
        for (uint256 i = 0; i < allStrategies.length; i++) {
            address strategy = allStrategies[i];
            StrategyData memory data = strategies[asset][strategy];
            
            if (data.active && 
                data.riskLevel <= maxRiskLevel && 
                data.currentAPY >= minAPY &&
                data.currentDeposits < data.maxCapacity) {
                temp[count] = strategy;
                count++;
            }
        }
        
        // Resize array
        address[] memory available = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            available[i] = temp[i];
        }
        
        return available;
    }

    function _optimizeAllocation(RouteRequest memory request, address[] memory availableStrategies) 
        internal 
        view 
        returns (RouteResult memory result) 
    {
        result.strategies = availableStrategies;
        result.amounts = new uint256[](availableStrategies.length);
        result.expectedAPYs = new uint256[](availableStrategies.length);
        
        uint256 remainingAmount = request.amount;
        uint256 totalWeightedAPY = 0;
        
        if (request.prioritizeAPY) {
            // Sort by APY descending and allocate greedily
            for (uint256 i = 0; i < availableStrategies.length && remainingAmount > 0; i++) {
                address strategy = _getHighestAPYStrategy(request, availableStrategies);
                StrategyData memory data = strategies[address(request.asset)][strategy];
                
                uint256 maxAllocation = (request.amount * maxSingleStrategyAllocation) / MAX_BPS;
                uint256 availableCapacity = data.maxCapacity - data.currentDeposits;
                uint256 allocation = _min3(remainingAmount, maxAllocation, availableCapacity);
                
                if (allocation > 0) {
                    result.amounts[i] = allocation;
                    result.expectedAPYs[i] = data.currentAPY;
                    totalWeightedAPY += data.currentAPY * allocation;
                    remainingAmount -= allocation;
                }
            }
        } else {
            // Risk-adjusted allocation using performance scores
            uint256 totalScore = 0;
            for (uint256 i = 0; i < availableStrategies.length; i++) {
                address strategy = availableStrategies[i];
                StrategyData memory data = strategies[address(request.asset)][strategy];
                uint256 riskAdjustedScore = _calculateRiskAdjustedScore(data);
                totalScore += riskAdjustedScore;
            }
            
            for (uint256 i = 0; i < availableStrategies.length && totalScore > 0; i++) {
                address strategy = availableStrategies[i];
                StrategyData memory data = strategies[address(request.asset)][strategy];
                
                uint256 riskAdjustedScore = _calculateRiskAdjustedScore(data);
                uint256 baseAllocation = (request.amount * riskAdjustedScore) / totalScore;
                
                uint256 maxAllocation = (request.amount * maxSingleStrategyAllocation) / MAX_BPS;
                uint256 availableCapacity = data.maxCapacity - data.currentDeposits;
                uint256 allocation = _min3(baseAllocation, maxAllocation, availableCapacity);
                
                result.amounts[i] = allocation;
                result.expectedAPYs[i] = data.currentAPY;
                totalWeightedAPY += data.currentAPY * allocation;
            }
        }
        
        result.totalAmount = request.amount - remainingAmount;
        result.weightedAPY = result.totalAmount > 0 ? totalWeightedAPY / result.totalAmount : 0;
        result.maxRiskLevel = _getMaxRiskLevel(request, result);
    }

    function _getHighestAPYStrategy(RouteRequest memory request, address[] memory strategies) 
        internal 
        view 
        returns (address bestStrategy) 
    {
        uint256 highestAPY = 0;
        for (uint256 i = 0; i < strategies.length; i++) {
            address strategy = strategies[i];
            StrategyData memory data = strategies[address(request.asset)][strategy];
            if (data.currentAPY > highestAPY) {
                highestAPY = data.currentAPY;
                bestStrategy = strategy;
            }
        }
    }

    function _calculateRiskAdjustedScore(StrategyData memory data) internal view returns (uint256) {
        uint256 baseScore = data.performanceScore;
        
        // Adjust for risk - lower risk gets bonus
        uint256 riskPenalty = (data.riskLevel * riskToleranceMultiplier);
        if (baseScore > riskPenalty) {
            return baseScore - riskPenalty;
        }
        return baseScore / 2; // Minimum score
    }

    function _getMaxRiskLevel(RouteRequest memory request, RouteResult memory result) 
        internal 
        view 
        returns (uint8 maxRisk) 
    {
        for (uint256 i = 0; i < result.strategies.length; i++) {
            if (result.amounts[i] > 0) {
                address strategy = result.strategies[i];
                uint8 strategyRisk = strategies[address(request.asset)][strategy].riskLevel;
                if (strategyRisk > maxRisk) {
                    maxRisk = strategyRisk;
                }
            }
        }
    }

    function _adjustPerformanceScore(uint256 currentScore, uint256 changeBPS, bool isProfit) 
        internal 
        pure 
        returns (uint256) 
    {
        uint256 adjustment = (changeBPS * 50) / MAX_BPS; // Scale adjustment
        
        if (isProfit) {
            uint256 newScore = currentScore + adjustment;
            return newScore > MAX_BPS ? MAX_BPS : newScore;
        } else {
            if (adjustment >= currentScore) {
                return 100; // Minimum score
            }
            return currentScore - adjustment;
        }
    }

    function _min3(uint256 a, uint256 b, uint256 c) internal pure returns (uint256) {
        return a < b ? (a < c ? a : c) : (b < c ? b : c);
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setRouterPerformanceFee(uint256 newFee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newFee <= 1000, "Fee too high"); // Max 10%
        routerPerformanceFee = newFee;
    }

    function setPerformanceFeeRecipient(address newRecipient) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newRecipient != address(0), "Invalid recipient");
        performanceFeeRecipient = newRecipient;
    }

    function setMaxSingleStrategyAllocation(uint256 newAllocation) external onlyRouterManager {
        require(newAllocation <= MAX_BPS && newAllocation >= 1000, "Invalid allocation");
        maxSingleStrategyAllocation = newAllocation;
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}