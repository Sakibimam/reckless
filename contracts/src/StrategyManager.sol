// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./interfaces/IStrategy.sol";

/**
 * @title StrategyManager
 * @dev Manages and routes funds to optimal yield strategies based on AI recommendations
 * @notice This contract optimizes yield by selecting the best strategies for different market conditions
 */
contract StrategyManager is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    // Roles
    bytes32 public constant STRATEGY_MANAGER_ROLE = keccak256("STRATEGY_MANAGER_ROLE");
    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");
    bytes32 public constant AI_OPERATOR_ROLE = keccak256("AI_OPERATOR_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    // Constants
    uint256 public constant MAX_BPS = 10_000;
    uint256 public constant MAX_STRATEGIES = 20;
    uint256 public constant MIN_ALLOCATION = 50; // 0.5%
    uint256 public constant REBALANCE_THRESHOLD = 500; // 5%
    uint256 public constant EMERGENCY_THRESHOLD = 1000; // 10%

    // Supported assets
    IERC20[] public supportedAssets;
    mapping(address => bool) public isSupportedAsset;
    mapping(address => uint256) public assetIndex;

    // Strategy registry
    struct StrategyInfo {
        IStrategy strategy;
        address asset;
        uint256 allocation; // In basis points
        uint256 maxAllocation; // Maximum allowed allocation
        uint256 minAllocation; // Minimum required allocation
        bool active;
        bool approved;
        uint8 riskLevel; // 1-10 scale
        uint256 performanceScore; // Running performance score
        uint256 lastHarvest;
        uint256 totalDeposited;
        uint256 totalWithdrawn;
        uint256 totalProfit;
        uint256 totalLoss;
        uint256 lastUpdate;
    }

    mapping(address => StrategyInfo) public strategies;
    address[] public strategyList;
    mapping(address => address[]) public assetStrategies; // asset => strategies for that asset

    // AI-driven optimization
    struct OptimizationParams {
        uint256 targetAPY;
        uint256 maxRiskLevel;
        uint256 rebalanceInterval;
        uint256 profitThreshold;
        bool autoRebalanceEnabled;
        bool emergencyExitEnabled;
    }

    OptimizationParams public optimizationParams;
    
    // Performance tracking
    mapping(address => uint256) public strategyAPYHistory; // 30-day rolling APY
    mapping(address => uint256) public strategyVolatility;
    mapping(address => uint256) public sharpeRatio; // Risk-adjusted returns
    
    // Rebalancing
    uint256 public lastRebalance;
    uint256 public totalManagedAssets;
    mapping(address => uint256) public assetTargetAllocations;
    
    // Emergency controls
    bool public emergencyMode;
    uint256 public emergencyTimestamp;
    mapping(address => bool) public strategyEmergencyExit;
    
    // Events
    event StrategyAdded(address indexed strategy, address indexed asset, uint256 maxAllocation);
    event StrategyRemoved(address indexed strategy, address indexed asset);
    event StrategyUpdated(address indexed strategy, uint256 allocation, bool active);
    event AllocationOptimized(address indexed asset, uint256 totalAllocated);
    event StrategiesRebalanced(uint256 timestamp, uint256 totalAssets);
    event EmergencyModeActivated(uint256 timestamp, string reason);
    event PerformanceUpdated(address indexed strategy, uint256 apy, uint256 sharpeRatio);
    event ProfitHarvested(address indexed strategy, uint256 profit);
    
    modifier onlyVault() {
        require(hasRole(VAULT_ROLE, msg.sender), "SM: Not authorized vault");
        _;
    }
    
    modifier onlyAI() {
        require(hasRole(AI_OPERATOR_ROLE, msg.sender), "SM: Not authorized AI operator");
        _;
    }
    
    modifier validStrategy(address strategyAddr) {
        require(strategies[strategyAddr].strategy != IStrategy(address(0)), "SM: Strategy not found");
        _;
    }
    
    constructor(address admin_) {
        require(admin_ != address(0), "SM: Invalid admin");
        
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(STRATEGY_MANAGER_ROLE, admin_);
        _grantRole(AI_OPERATOR_ROLE, admin_);
        _grantRole(EMERGENCY_ROLE, admin_);
        
        // Set default optimization parameters
        optimizationParams = OptimizationParams({
            targetAPY: 1500, // 15%
            maxRiskLevel: 7,
            rebalanceInterval: 1 days,
            profitThreshold: 100, // 1%
            autoRebalanceEnabled: true,
            emergencyExitEnabled: true
        });
        
        lastRebalance = block.timestamp;
    }
    
    /*//////////////////////////////////////////////////////////////\n                        STRATEGY MANAGEMENT\n    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Add a new strategy to the manager
     */\n    function addStrategy(\n        address strategyAddr,\n        uint256 maxAllocation,\n        uint256 minAllocation\n    ) external onlyRole(STRATEGY_MANAGER_ROLE) {\n        require(strategyAddr != address(0), \"SM: Invalid strategy\");\n        require(maxAllocation <= MAX_BPS, \"SM: Max allocation too high\");\n        require(minAllocation <= maxAllocation, \"SM: Min > Max allocation\");\n        require(strategies[strategyAddr].strategy == IStrategy(address(0)), \"SM: Strategy exists\");\n        require(strategyList.length < MAX_STRATEGIES, \"SM: Too many strategies\");\n        \n        IStrategy strategy = IStrategy(strategyAddr);\n        address asset = strategy.asset();\n        \n        require(isSupportedAsset[asset], \"SM: Asset not supported\");\n        require(strategy.isActive(), \"SM: Strategy not active\");\n        \n        // Add to registry\n        strategies[strategyAddr] = StrategyInfo({\n            strategy: strategy,\n            asset: asset,\n            allocation: 0,\n            maxAllocation: maxAllocation,\n            minAllocation: minAllocation,\n            active: false, // Starts inactive until approved\n            approved: false,\n            riskLevel: strategy.getRiskLevel(),\n            performanceScore: 5000, // Start at 50%\n            lastHarvest: block.timestamp,\n            totalDeposited: 0,\n            totalWithdrawn: 0,\n            totalProfit: 0,\n            totalLoss: 0,\n            lastUpdate: block.timestamp\n        });\n        \n        strategyList.push(strategyAddr);\n        assetStrategies[asset].push(strategyAddr);\n        \n        emit StrategyAdded(strategyAddr, asset, maxAllocation);\n    }\n    \n    /**\n     * @notice Remove a strategy from management\n     */\n    function removeStrategy(address strategyAddr) external onlyRole(STRATEGY_MANAGER_ROLE) validStrategy(strategyAddr) {\n        StrategyInfo storage info = strategies[strategyAddr];\n        \n        // Emergency withdraw all funds\n        if (info.active) {\n            try info.strategy.emergencyWithdraw() returns (uint256 withdrawn) {\n                info.totalWithdrawn += withdrawn;\n            } catch {\n                // Continue with removal even if emergency withdrawal fails\n            }\n        }\n        \n        address asset = info.asset;\n        \n        // Remove from strategy list\n        for (uint256 i = 0; i < strategyList.length; i++) {\n            if (strategyList[i] == strategyAddr) {\n                strategyList[i] = strategyList[strategyList.length - 1];\n                strategyList.pop();\n                break;\n            }\n        }\n        \n        // Remove from asset strategies\n        address[] storage assetStrats = assetStrategies[asset];\n        for (uint256 i = 0; i < assetStrats.length; i++) {\n            if (assetStrats[i] == strategyAddr) {\n                assetStrats[i] = assetStrats[assetStrats.length - 1];\n                assetStrats.pop();\n                break;\n            }\n        }\n        \n        delete strategies[strategyAddr];\n        emit StrategyRemoved(strategyAddr, asset);\n    }\n    \n    /**\n     * @notice Approve a strategy for active management\n     */\n    function approveStrategy(address strategyAddr) external onlyRole(STRATEGY_MANAGER_ROLE) validStrategy(strategyAddr) {\n        StrategyInfo storage info = strategies[strategyAddr];\n        require(!info.approved, \"SM: Already approved\");\n        \n        info.approved = true;\n        info.active = true;\n        info.lastUpdate = block.timestamp;\n        \n        emit StrategyUpdated(strategyAddr, info.allocation, true);\n    }\n    \n    /**\n     * @notice Update strategy allocation based on AI recommendations\n     */\n    function updateStrategyAllocation(\n        address strategyAddr,\n        uint256 newAllocation\n    ) external onlyAI validStrategy(strategyAddr) {\n        StrategyInfo storage info = strategies[strategyAddr];\n        require(info.approved, \"SM: Strategy not approved\");\n        require(newAllocation <= info.maxAllocation, \"SM: Exceeds max allocation\");\n        \n        uint256 oldAllocation = info.allocation;\n        info.allocation = newAllocation;\n        info.active = newAllocation >= info.minAllocation;\n        info.lastUpdate = block.timestamp;\n        \n        emit StrategyUpdated(strategyAddr, newAllocation, info.active);\n    }\n    \n    /*//////////////////////////////////////////////////////////////\n                        ASSET MANAGEMENT\n    //////////////////////////////////////////////////////////////*/\n    \n    /**\n     * @notice Add a supported asset\n     */\n    function addSupportedAsset(address asset) external onlyRole(DEFAULT_ADMIN_ROLE) {\n        require(asset != address(0), \"SM: Invalid asset\");\n        require(!isSupportedAsset[asset], \"SM: Asset already supported\");\n        \n        supportedAssets.push(IERC20(asset));\n        isSupportedAsset[asset] = true;\n        assetIndex[asset] = supportedAssets.length - 1;\n    }\n    \n    /**\n     * @notice Remove a supported asset\n     */\n    function removeSupportedAsset(address asset) external onlyRole(DEFAULT_ADMIN_ROLE) {\n        require(isSupportedAsset[asset], \"SM: Asset not supported\");\n        require(assetStrategies[asset].length == 0, \"SM: Asset has active strategies\");\n        \n        uint256 index = assetIndex[asset];\n        uint256 lastIndex = supportedAssets.length - 1;\n        \n        if (index != lastIndex) {\n            IERC20 lastAsset = supportedAssets[lastIndex];\n            supportedAssets[index] = lastAsset;\n            assetIndex[address(lastAsset)] = index;\n        }\n        \n        supportedAssets.pop();\n        delete isSupportedAsset[asset];\n        delete assetIndex[asset];\n    }\n    \n    /*//////////////////////////////////////////////////////////////\n                        OPTIMIZATION & REBALANCING\n    //////////////////////////////////////////////////////////////*/\n    \n    /**\n     * @notice Optimize allocations based on AI recommendations\n     */\n    function optimizeAllocations(\n        address[] calldata strategyAddrs,\n        uint256[] calldata allocations\n    ) external onlyAI nonReentrant {\n        require(strategyAddrs.length == allocations.length, \"SM: Array length mismatch\");\n        \n        uint256 totalAllocation = 0;\n        mapping(address => uint256) storage tempAllocations;\n        \n        // Validate and set new allocations\n        for (uint256 i = 0; i < strategyAddrs.length; i++) {\n            address strategyAddr = strategyAddrs[i];\n            uint256 allocation = allocations[i];\n            \n            StrategyInfo storage info = strategies[strategyAddr];\n            require(info.approved, \"SM: Strategy not approved\");\n            require(allocation <= info.maxAllocation, \"SM: Exceeds max allocation\");\n            \n            info.allocation = allocation;\n            info.active = allocation >= info.minAllocation;\n            info.lastUpdate = block.timestamp;\n            \n            totalAllocation += allocation;\n            \n            // Group by asset for validation\n            address asset = info.asset;\n            tempAllocations[asset] += allocation;\n        }\n        \n        require(totalAllocation <= MAX_BPS, \"SM: Total allocation exceeds 100%\");\n        \n        // Update asset target allocations\n        for (uint256 i = 0; i < supportedAssets.length; i++) {\n            address asset = address(supportedAssets[i]);\n            assetTargetAllocations[asset] = tempAllocations[asset];\n            emit AllocationOptimized(asset, tempAllocations[asset]);\n        }\n    }\n    \n    /**\n     * @notice Rebalance strategies based on current allocations\n     */\n    function rebalanceStrategies() external onlyVault nonReentrant {\n        require(\n            block.timestamp >= lastRebalance + optimizationParams.rebalanceInterval ||\n            _shouldForceRebalance(),\n            \"SM: Too early for rebalance\"\n        );\n        \n        uint256 totalAssetsManaged = 0;\n        \n        for (uint256 i = 0; i < supportedAssets.length; i++) {\n            address asset = address(supportedAssets[i]);\n            uint256 assetBalance = supportedAssets[i].balanceOf(address(this));\n            \n            if (assetBalance > 0) {\n                totalAssetsManaged += _rebalanceAssetStrategies(asset, assetBalance);\n            }\n        }\n        \n        totalManagedAssets = totalAssetsManaged;\n        lastRebalance = block.timestamp;\n        \n        emit StrategiesRebalanced(block.timestamp, totalAssetsManaged);\n    }\n    \n    function _rebalanceAssetStrategies(address asset, uint256 totalAssets) internal returns (uint256) {\n        address[] memory assetStrats = assetStrategies[asset];\n        uint256 totalAllocated = 0;\n        \n        for (uint256 i = 0; i < assetStrats.length; i++) {\n            address strategyAddr = assetStrats[i];\n            StrategyInfo storage info = strategies[strategyAddr];\n            \n            if (info.active && info.allocation > 0) {\n                uint256 targetAmount = (totalAssets * info.allocation) / MAX_BPS;\n                uint256 currentAmount = info.strategy.totalAssets();\n                \n                if (targetAmount > currentAmount) {\n                    // Need to deposit more\n                    uint256 toDeposit = targetAmount - currentAmount;\n                    if (toDeposit > 0 && supportedAssets[assetIndex[asset]].balanceOf(address(this)) >= toDeposit) {\n                        supportedAssets[assetIndex[asset]].safeTransfer(strategyAddr, toDeposit);\n                        \n                        try info.strategy.invest(toDeposit) returns (uint256 invested) {\n                            info.totalDeposited += invested;\n                        } catch {\n                            info.totalDeposited += toDeposit;\n                        }\n                    }\n                } else if (targetAmount < currentAmount) {\n                    // Need to withdraw excess\n                    uint256 toWithdraw = currentAmount - targetAmount;\n                    try info.strategy.withdraw(toWithdraw) returns (uint256 withdrawn) {\n                        info.totalWithdrawn += withdrawn;\n                    } catch {\n                        // Continue if withdrawal fails\n                    }\n                }\n                \n                totalAllocated += Math.min(targetAmount, currentAmount);\n            }\n        }\n        \n        return totalAllocated;\n    }\n    \n    function _shouldForceRebalance() internal view returns (bool) {\n        // Check if any strategy is significantly over/under allocated\n        for (uint256 i = 0; i < strategyList.length; i++) {\n            address strategyAddr = strategyList[i];\n            StrategyInfo storage info = strategies[strategyAddr];\n            \n            if (info.active) {\n                uint256 currentAssets = info.strategy.totalAssets();\n                uint256 totalAssets = totalManagedAssets;\n                \n                if (totalAssets > 0) {\n                    uint256 currentAllocation = (currentAssets * MAX_BPS) / totalAssets;\n                    \n                    if (currentAllocation > info.allocation + REBALANCE_THRESHOLD ||\n                        info.allocation > currentAllocation + REBALANCE_THRESHOLD) {\n                        return true;\n                    }\n                }\n            }\n        }\n        \n        return false;\n    }\n    \n    /*//////////////////////////////////////////////////////////////\n                        HARVEST & PERFORMANCE TRACKING\n    //////////////////////////////////////////////////////////////*/\n    \n    /**\n     * @notice Harvest yield from all active strategies\n     */\n    function harvestAll() external onlyVault nonReentrant returns (uint256 totalHarvested) {\n        for (uint256 i = 0; i < strategyList.length; i++) {\n            address strategyAddr = strategyList[i];\n            StrategyInfo storage info = strategies[strategyAddr];\n            \n            if (info.active) {\n                try info.strategy.harvest() returns (uint256 harvested) {\n                    if (harvested > 0) {\n                        totalHarvested += harvested;\n                        info.totalProfit += harvested;\n                        info.lastHarvest = block.timestamp;\n                        \n                        _updatePerformanceMetrics(strategyAddr, harvested);\n                        emit ProfitHarvested(strategyAddr, harvested);\n                    }\n                } catch {\n                    // Continue with other strategies if one fails\n                    continue;\n                }\n            }\n        }\n    }\n    \n    function _updatePerformanceMetrics(address strategyAddr, uint256 profit) internal {\n        StrategyInfo storage info = strategies[strategyAddr];\n        \n        // Update performance score based on profit\n        if (info.totalDeposited > 0) {\n            uint256 profitRate = (profit * MAX_BPS) / info.totalDeposited;\n            \n            // Exponential moving average for performance score\n            info.performanceScore = (info.performanceScore * 9 + profitRate) / 10;\n        }\n        \n        // Update APY and volatility (simplified)\n        uint256 currentAPY = info.strategy.getAPY();\n        strategyAPYHistory[strategyAddr] = currentAPY;\n        \n        // Calculate Sharpe ratio (simplified)\n        if (strategyVolatility[strategyAddr] > 0) {\n            sharpeRatio[strategyAddr] = currentAPY / strategyVolatility[strategyAddr];\n        }\n        \n        emit PerformanceUpdated(strategyAddr, currentAPY, sharpeRatio[strategyAddr]);\n    }\n    \n    /*//////////////////////////////////////////////////////////////\n                        EMERGENCY CONTROLS\n    //////////////////////////////////////////////////////////////*/\n    \n    /**\n     * @notice Activate emergency mode\n     */\n    function activateEmergencyMode(string memory reason) external onlyRole(EMERGENCY_ROLE) {\n        emergencyMode = true;\n        emergencyTimestamp = block.timestamp;\n        _pause();\n        \n        emit EmergencyModeActivated(block.timestamp, reason);\n    }\n    \n    /**\n     * @notice Emergency withdraw from specific strategy\n     */\n    function emergencyWithdrawStrategy(address strategyAddr) external onlyRole(EMERGENCY_ROLE) validStrategy(strategyAddr) {\n        StrategyInfo storage info = strategies[strategyAddr];\n        \n        try info.strategy.emergencyWithdraw() returns (uint256 withdrawn) {\n            info.totalWithdrawn += withdrawn;\n            strategyEmergencyExit[strategyAddr] = true;\n            info.active = false;\n        } catch {\n            // Mark as emergency exit even if withdrawal fails\n            strategyEmergencyExit[strategyAddr] = true;\n            info.active = false;\n        }\n    }\n    \n    /**\n     * @notice Emergency withdraw from all strategies\n     */\n    function emergencyWithdrawAll() external onlyRole(EMERGENCY_ROLE) {\n        for (uint256 i = 0; i < strategyList.length; i++) {\n            address strategyAddr = strategyList[i];\n            if (strategies[strategyAddr].active) {\n                this.emergencyWithdrawStrategy(strategyAddr);\n            }\n        }\n    }\n    \n    /*//////////////////////////////////////////////////////////////\n                        VIEW FUNCTIONS\n    //////////////////////////////////////////////////////////////*/\n    \n    function getTotalManagedAssets() external view returns (uint256) {\n        uint256 total = 0;\n        for (uint256 i = 0; i < strategyList.length; i++) {\n            StrategyInfo storage info = strategies[strategyList[i]];\n            if (info.active) {\n                total += info.strategy.totalAssets();\n            }\n        }\n        return total;\n    }\n    \n    function getStrategyCount() external view returns (uint256) {\n        return strategyList.length;\n    }\n    \n    function getActiveStrategies() external view returns (address[] memory activeStrats) {\n        uint256 activeCount = 0;\n        \n        // Count active strategies\n        for (uint256 i = 0; i < strategyList.length; i++) {\n            if (strategies[strategyList[i]].active) {\n                activeCount++;\n            }\n        }\n        \n        // Create array of active strategies\n        activeStrats = new address[](activeCount);\n        uint256 index = 0;\n        \n        for (uint256 i = 0; i < strategyList.length; i++) {\n            if (strategies[strategyList[i]].active) {\n                activeStrats[index] = strategyList[i];\n                index++;\n            }\n        }\n    }\n    \n    function getAssetStrategies(address asset) external view returns (address[] memory) {\n        return assetStrategies[asset];\n    }\n    \n    function getWeightedAPY() external view returns (uint256) {\n        uint256 totalAssets = getTotalManagedAssets();\n        if (totalAssets == 0) return 0;\n        \n        uint256 weightedAPY = 0;\n        \n        for (uint256 i = 0; i < strategyList.length; i++) {\n            StrategyInfo storage info = strategies[strategyList[i]];\n            if (info.active) {\n                uint256 strategyAssets = info.strategy.totalAssets();\n                uint256 weight = (strategyAssets * MAX_BPS) / totalAssets;\n                uint256 strategyAPY = info.strategy.getAPY();\n                weightedAPY += (strategyAPY * weight) / MAX_BPS;\n            }\n        }\n        \n        return weightedAPY;\n    }\n    \n    /*//////////////////////////////////////////////////////////////\n                        ADMIN FUNCTIONS\n    //////////////////////////////////////////////////////////////*/\n    \n    function setOptimizationParams(\n        uint256 targetAPY,\n        uint256 maxRiskLevel,\n        uint256 rebalanceInterval,\n        uint256 profitThreshold,\n        bool autoRebalanceEnabled,\n        bool emergencyExitEnabled\n    ) external onlyRole(DEFAULT_ADMIN_ROLE) {\n        optimizationParams = OptimizationParams({\n            targetAPY: targetAPY,\n            maxRiskLevel: maxRiskLevel,\n            rebalanceInterval: rebalanceInterval,\n            profitThreshold: profitThreshold,\n            autoRebalanceEnabled: autoRebalanceEnabled,\n            emergencyExitEnabled: emergencyExitEnabled\n        });\n    }\n    \n    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {\n        _pause();\n    }\n    \n    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {\n        _unpause();\n        emergencyMode = false;\n    }\n}