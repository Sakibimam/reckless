// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./interfaces/IStrategy.sol";

/**
 * @title YieldAggregator
 * @dev Aggregates and manages multiple yield sources for optimized returns
 */
contract YieldAggregator is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    bytes32 public constant AGGREGATOR_MANAGER_ROLE = keccak256("AGGREGATOR_MANAGER_ROLE");
    bytes32 public constant YIELD_HARVESTER_ROLE = keccak256("YIELD_HARVESTER_ROLE");
    bytes32 public constant REBALANCER_ROLE = keccak256("REBALANCER_ROLE");

    uint256 public constant MAX_BPS = 10_000;
    uint256 public constant PRECISION = 1e18;
    uint256 public constant MAX_YIELD_SOURCES = 50;
    uint256 public constant MIN_HARVEST_INTERVAL = 3600; // 1 hour

    enum YieldSourceType {
        LENDING_POOL,     // Aave, Compound
        DEX_LP,          // Uniswap, Sushiswap LPs
        STAKING,         // ETH 2.0, protocol staking
        YIELD_FARMING,   // Yield farms
        DERIVATIVES,     // Options, futures
        SYNTHETIC,       // Synthetix, Mirror
        LENDING_BORROW,  // Leverage farming
        INSURANCE        // Nexus Mutual, etc.
    }

    struct YieldSource {
        IStrategy strategy;
        YieldSourceType sourceType;
        uint256 allocation; // Basis points
        uint256 currentAPY;
        uint256 averageAPY; // 30-day average
        uint256 totalDeposited;
        uint256 totalHarvested;
        uint256 lastHarvest;
        uint256 maxCapacity;
        uint8 riskLevel; // 1-10
        bool active;
        bool autoHarvest;
        uint256 minHarvestAmount;
    }

    struct AssetData {
        mapping(address => YieldSource) sources; // strategy address => YieldSource
        address[] sourceList;
        uint256 totalAllocation;
        uint256 lastRebalance;
        uint256 totalAssets;
        uint256 weightedAPY;
    }

    // asset address => AssetData
    mapping(address => AssetData) private assetData;
    address[] public supportedAssets;
    
    // Yield optimization parameters
    uint256 public rebalanceThreshold = 500; // 5% APY difference
    uint256 public maxSlippage = 100; // 1%
    uint256 public rebalanceInterval = 86400; // 24 hours
    uint256 public performanceFee = 1000; // 10%
    address public performanceFeeRecipient;
    
    // Historical tracking
    struct HistoricalData {
        uint256 timestamp;
        uint256 apy;
        uint256 tvl;
    }
    
    mapping(address => mapping(address => HistoricalData[])) public sourceHistory; // asset => strategy => history
    mapping(address => uint256) public lastHistoryUpdate;
    
    // Events
    event YieldSourceAdded(
        address indexed asset,
        address indexed strategy,
        YieldSourceType sourceType,
        uint256 allocation
    );
    event YieldSourceRemoved(address indexed asset, address indexed strategy);
    event YieldHarvested(
        address indexed asset,
        address indexed strategy,
        uint256 yieldAmount,
        uint256 feeAmount
    );
    event Rebalanced(
        address indexed asset,
        uint256 oldWeightedAPY,
        uint256 newWeightedAPY
    );
    event AllocationUpdated(
        address indexed asset,
        address indexed strategy,
        uint256 oldAllocation,
        uint256 newAllocation
    );

    modifier onlyAggregatorManager() {
        require(hasRole(AGGREGATOR_MANAGER_ROLE, msg.sender), "Not aggregator manager");
        _;
    }

    modifier onlyYieldHarvester() {
        require(hasRole(YIELD_HARVESTER_ROLE, msg.sender), "Not yield harvester");
        _;
    }

    modifier onlyRebalancer() {
        require(hasRole(REBALANCER_ROLE, msg.sender), "Not rebalancer");
        _;
    }

    constructor(address admin, address feeRecipient) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(AGGREGATOR_MANAGER_ROLE, admin);
        _grantRole(YIELD_HARVESTER_ROLE, admin);
        _grantRole(REBALANCER_ROLE, admin);
        performanceFeeRecipient = feeRecipient;
    }

    /*//////////////////////////////////////////////////////////////
                        YIELD SOURCE MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    function addYieldSource(
        address asset,
        address strategy,
        YieldSourceType sourceType,
        uint256 allocation,
        uint256 maxCapacity,
        uint8 riskLevel,
        bool autoHarvest,
        uint256 minHarvestAmount
    ) external onlyAggregatorManager {
        require(asset != address(0) && strategy != address(0), "Invalid addresses");
        require(riskLevel >= 1 && riskLevel <= 10, "Invalid risk level");
        require(allocation <= MAX_BPS, "Invalid allocation");
        
        AssetData storage data = assetData[asset];
        require(data.sources[strategy].strategy == IStrategy(address(0)), "Source already exists");
        require(data.sourceList.length < MAX_YIELD_SOURCES, "Too many sources");
        require(data.totalAllocation + allocation <= MAX_BPS, "Exceeds max allocation");
        
        IStrategy strategyContract = IStrategy(strategy);
        require(strategyContract.asset() == asset, "Asset mismatch");
        require(strategyContract.isActive(), "Strategy not active");
        
        // Add asset to supported list if first source
        if (data.sourceList.length == 0) {
            supportedAssets.push(asset);
        }
        
        data.sources[strategy] = YieldSource({
            strategy: strategyContract,
            sourceType: sourceType,
            allocation: allocation,
            currentAPY: strategyContract.getAPY(),
            averageAPY: strategyContract.getAPY(),
            totalDeposited: 0,
            totalHarvested: 0,
            lastHarvest: block.timestamp,
            maxCapacity: maxCapacity,
            riskLevel: riskLevel,
            active: true,
            autoHarvest: autoHarvest,
            minHarvestAmount: minHarvestAmount
        });
        
        data.sourceList.push(strategy);
        data.totalAllocation += allocation;
        
        emit YieldSourceAdded(asset, strategy, sourceType, allocation);
    }

    function removeYieldSource(address asset, address strategy) 
        external 
        onlyAggregatorManager 
        nonReentrant 
    {
        AssetData storage data = assetData[asset];
        require(data.sources[strategy].strategy != IStrategy(address(0)), "Source not found");
        
        YieldSource storage source = data.sources[strategy];
        
        // Emergency withdraw all funds
        if (source.totalDeposited > 0) {
            uint256 withdrawn = source.strategy.emergencyWithdraw();
            source.totalDeposited = 0;
        }
        
        data.totalAllocation -= source.allocation;
        
        // Remove from array
        for (uint256 i = 0; i < data.sourceList.length; i++) {
            if (data.sourceList[i] == strategy) {
                data.sourceList[i] = data.sourceList[data.sourceList.length - 1];
                data.sourceList.pop();
                break;
            }
        }
        
        delete data.sources[strategy];
        emit YieldSourceRemoved(asset, strategy);
    }

    function updateAllocation(
        address asset,
        address strategy,
        uint256 newAllocation
    ) external onlyAggregatorManager {
        AssetData storage data = assetData[asset];
        YieldSource storage source = data.sources[strategy];
        require(source.strategy != IStrategy(address(0)), "Source not found");
        
        uint256 oldAllocation = source.allocation;
        uint256 newTotalAllocation = data.totalAllocation - oldAllocation + newAllocation;
        require(newTotalAllocation <= MAX_BPS, "Exceeds max allocation");
        
        source.allocation = newAllocation;
        data.totalAllocation = newTotalAllocation;
        
        emit AllocationUpdated(asset, strategy, oldAllocation, newAllocation);
    }

    function updateYieldSourceParams(
        address asset,
        address strategy,
        uint256 maxCapacity,
        bool autoHarvest,
        uint256 minHarvestAmount
    ) external onlyAggregatorManager {
        YieldSource storage source = assetData[asset].sources[strategy];
        require(source.strategy != IStrategy(address(0)), "Source not found");
        
        source.maxCapacity = maxCapacity;
        source.autoHarvest = autoHarvest;
        source.minHarvestAmount = minHarvestAmount;
    }

    /*//////////////////////////////////////////////////////////////
                        YIELD HARVESTING
    //////////////////////////////////////////////////////////////*/

    function harvestYield(address asset, address strategy) 
        external 
        onlyYieldHarvester 
        nonReentrant 
        returns (uint256 harvested, uint256 feeAmount) 
    {
        YieldSource storage source = assetData[asset].sources[strategy];
        require(source.active, "Source not active");
        require(
            block.timestamp >= source.lastHarvest + MIN_HARVEST_INTERVAL,
            "Harvest too frequent"
        );
        
        // Get yield amount before harvest
        uint256 preHarvestBalance = IERC20(asset).balanceOf(address(this));
        
        // Harvest from strategy
        harvested = source.strategy.harvest();
        
        if (harvested > 0) {
            // Calculate performance fee
            feeAmount = (harvested * performanceFee) / MAX_BPS;
            
            if (feeAmount > 0 && performanceFeeRecipient != address(0)) {
                IERC20(asset).safeTransfer(performanceFeeRecipient, feeAmount);
            }
            
            source.totalHarvested += harvested;
            source.lastHarvest = block.timestamp;
            
            emit YieldHarvested(asset, strategy, harvested, feeAmount);
        }
        
        // Update APY based on harvest
        _updateAPY(asset, strategy);
    }

    function harvestAllSources(address asset) 
        external 
        onlyYieldHarvester 
        nonReentrant 
        returns (uint256 totalHarvested, uint256 totalFees) 
    {
        AssetData storage data = assetData[asset];
        
        for (uint256 i = 0; i < data.sourceList.length; i++) {
            address strategy = data.sourceList[i];
            YieldSource storage source = data.sources[strategy];
            
            if (source.active && 
                source.autoHarvest && 
                block.timestamp >= source.lastHarvest + MIN_HARVEST_INTERVAL) {
                
                (uint256 harvested, uint256 feeAmount) = this.harvestYield(asset, strategy);
                totalHarvested += harvested;
                totalFees += feeAmount;
            }
        }
    }

    function autoHarvestBatch(address[] calldata assets) 
        external 
        onlyYieldHarvester 
    {
        for (uint256 i = 0; i < assets.length; i++) {
            this.harvestAllSources(assets[i]);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        REBALANCING
    //////////////////////////////////////////////////////////////*/

    function rebalance(address asset) 
        external 
        onlyRebalancer 
        nonReentrant 
    {
        AssetData storage data = assetData[asset];
        require(
            block.timestamp >= data.lastRebalance + rebalanceInterval,
            "Rebalance too frequent"
        );
        
        uint256 oldWeightedAPY = data.weightedAPY;
        
        // Update all APYs first
        for (uint256 i = 0; i < data.sourceList.length; i++) {
            _updateAPY(asset, data.sourceList[i]);
        }
        
        // Calculate optimal allocation
        (address[] memory strategies, uint256[] memory newAllocations) = 
            _calculateOptimalAllocation(asset);
        
        // Execute rebalancing
        _executeRebalance(asset, strategies, newAllocations);
        
        data.lastRebalance = block.timestamp;
        data.weightedAPY = _calculateWeightedAPY(asset);
        
        emit Rebalanced(asset, oldWeightedAPY, data.weightedAPY);
    }

    function rebalanceMultipleAssets(address[] calldata assets) 
        external 
        onlyRebalancer 
    {
        for (uint256 i = 0; i < assets.length; i++) {
            if (assetData[assets[i]].sourceList.length > 0) {
                this.rebalance(assets[i]);
            }
        }
    }

    function emergencyRebalance(address asset) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
        nonReentrant 
    {
        AssetData storage data = assetData[asset];
        
        // Emergency withdraw from all sources
        for (uint256 i = 0; i < data.sourceList.length; i++) {
            address strategy = data.sourceList[i];
            YieldSource storage source = data.sources[strategy];
            
            if (source.totalDeposited > 0) {
                uint256 withdrawn = source.strategy.emergencyWithdraw();
                source.totalDeposited = 0;
            }
        }
        
        data.totalAssets = IERC20(asset).balanceOf(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getAssetAPY(address asset) external view returns (uint256 weightedAPY) {
        return assetData[asset].weightedAPY;
    }

    function getSourceAPY(address asset, address strategy) 
        external 
        view 
        returns (uint256 currentAPY, uint256 averageAPY) 
    {
        YieldSource storage source = assetData[asset].sources[strategy];
        return (source.currentAPY, source.averageAPY);
    }

    function getAssetSources(address asset) 
        external 
        view 
        returns (
            address[] memory strategies,
            uint256[] memory allocations,
            uint256[] memory apys,
            YieldSourceType[] memory sourceTypes,
            uint8[] memory riskLevels
        ) 
    {
        AssetData storage data = assetData[asset];
        uint256 length = data.sourceList.length;
        
        strategies = new address[](length);
        allocations = new uint256[](length);
        apys = new uint256[](length);
        sourceTypes = new YieldSourceType[](length);
        riskLevels = new uint8[](length);
        
        for (uint256 i = 0; i < length; i++) {
            address strategy = data.sourceList[i];
            YieldSource storage source = data.sources[strategy];
            
            strategies[i] = strategy;
            allocations[i] = source.allocation;
            apys[i] = source.currentAPY;
            sourceTypes[i] = source.sourceType;
            riskLevels[i] = source.riskLevel;
        }
    }

    function getSourcePerformance(address asset, address strategy) 
        external 
        view 
        returns (
            uint256 totalDeposited,
            uint256 totalHarvested,
            uint256 lastHarvest,
            uint256 netReturn
        ) 
    {
        YieldSource storage source = assetData[asset].sources[strategy];
        totalDeposited = source.totalDeposited;
        totalHarvested = source.totalHarvested;
        lastHarvest = source.lastHarvest;
        
        if (totalDeposited > 0) {
            netReturn = (totalHarvested * PRECISION) / totalDeposited;
        }
    }

    function getOptimalAllocation(address asset) 
        external 
        view 
        returns (address[] memory strategies, uint256[] memory allocations) 
    {
        return _calculateOptimalAllocation(asset);
    }

    function shouldRebalance(address asset) external view returns (bool) {
        AssetData storage data = assetData[asset];
        
        if (block.timestamp < data.lastRebalance + rebalanceInterval) {
            return false;
        }
        
        // Check if current allocation is significantly suboptimal
        (,uint256[] memory optimalAllocations) = _calculateOptimalAllocation(asset);
        
        for (uint256 i = 0; i < data.sourceList.length; i++) {
            address strategy = data.sourceList[i];
            uint256 currentAllocation = data.sources[strategy].allocation;
            uint256 optimalAllocation = optimalAllocations[i];
            
            if (currentAllocation > optimalAllocation) {
                if ((currentAllocation - optimalAllocation) > rebalanceThreshold) {
                    return true;
                }
            } else {
                if ((optimalAllocation - currentAllocation) > rebalanceThreshold) {
                    return true;
                }
            }
        }
        
        return false;
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _calculateOptimalAllocation(address asset) 
        internal 
        view 
        returns (address[] memory strategies, uint256[] memory allocations) 
    {
        AssetData storage data = assetData[asset];
        strategies = data.sourceList;
        allocations = new uint256[](strategies.length);
        
        if (strategies.length == 0) return (strategies, allocations);
        
        // Calculate risk-adjusted APY scores
        uint256[] memory scores = new uint256[](strategies.length);
        uint256 totalScore = 0;
        
        for (uint256 i = 0; i < strategies.length; i++) {
            YieldSource storage source = data.sources[strategies[i]];
            if (source.active) {
                // Risk-adjusted score: APY / (1 + riskLevel)
                scores[i] = (source.currentAPY * PRECISION) / (PRECISION + (source.riskLevel * PRECISION / 10));
                totalScore += scores[i];
            }
        }
        
        if (totalScore == 0) return (strategies, allocations);
        
        // Allocate based on risk-adjusted scores
        for (uint256 i = 0; i < strategies.length; i++) {
            if (scores[i] > 0) {
                allocations[i] = (scores[i] * MAX_BPS) / totalScore;
            }
        }
        
        // Adjust for capacity constraints
        _adjustForCapacity(asset, strategies, allocations);
    }

    function _adjustForCapacity(
        address asset,
        address[] memory strategies,
        uint256[] memory allocations
    ) internal view {
        AssetData storage data = assetData[asset];
        uint256 totalAssets = data.totalAssets;
        
        for (uint256 i = 0; i < strategies.length; i++) {
            YieldSource storage source = data.sources[strategies[i]];
            if (source.active) {
                uint256 targetAmount = (totalAssets * allocations[i]) / MAX_BPS;
                uint256 availableCapacity = source.maxCapacity > source.totalDeposited 
                    ? source.maxCapacity - source.totalDeposited 
                    : 0;
                
                if (targetAmount > availableCapacity) {
                    // Reduce allocation due to capacity constraint
                    allocations[i] = availableCapacity > 0 
                        ? (availableCapacity * MAX_BPS) / totalAssets 
                        : 0;
                }
            }
        }
        
        // Normalize allocations to sum to MAX_BPS
        uint256 totalAllocation = 0;
        for (uint256 i = 0; i < allocations.length; i++) {
            totalAllocation += allocations[i];
        }
        
        if (totalAllocation > 0 && totalAllocation != MAX_BPS) {
            for (uint256 i = 0; i < allocations.length; i++) {
                allocations[i] = (allocations[i] * MAX_BPS) / totalAllocation;
            }
        }
    }

    function _executeRebalance(
        address asset,
        address[] memory strategies,
        uint256[] memory newAllocations
    ) internal {
        AssetData storage data = assetData[asset];
        uint256 totalAssets = data.totalAssets;
        
        // First, withdraw excess funds from strategies
        for (uint256 i = 0; i < strategies.length; i++) {
            YieldSource storage source = data.sources[strategies[i]];
            uint256 targetAmount = (totalAssets * newAllocations[i]) / MAX_BPS;
            
            if (source.totalDeposited > targetAmount) {
                uint256 toWithdraw = source.totalDeposited - targetAmount;
                uint256 withdrawn = source.strategy.withdraw(toWithdraw);
                source.totalDeposited -= withdrawn;
            }
        }
        
        // Then, deposit into strategies that need more funds
        for (uint256 i = 0; i < strategies.length; i++) {
            YieldSource storage source = data.sources[strategies[i]];
            uint256 targetAmount = (totalAssets * newAllocations[i]) / MAX_BPS;
            
            if (source.totalDeposited < targetAmount && source.active) {
                uint256 toDeposit = targetAmount - source.totalDeposited;
                uint256 available = IERC20(asset).balanceOf(address(this));
                toDeposit = Math.min(toDeposit, available);
                
                if (toDeposit > 0) {
                    IERC20(asset).safeTransfer(strategies[i], toDeposit);
                    uint256 invested = source.strategy.invest(toDeposit);
                    source.totalDeposited += invested;
                }
            }
        }
        
        // Update allocations
        for (uint256 i = 0; i < strategies.length; i++) {
            data.sources[strategies[i]].allocation = newAllocations[i];
        }
    }

    function _updateAPY(address asset, address strategy) internal {
        YieldSource storage source = assetData[asset].sources[strategy];
        
        uint256 newAPY = source.strategy.getAPY();
        
        // Update 30-day average APY (simplified moving average)
        source.averageAPY = ((source.averageAPY * 29) + newAPY) / 30;
        source.currentAPY = newAPY;
        
        // Record historical data
        HistoricalData[] storage history = sourceHistory[asset][strategy];
        if (history.length == 0 || 
            block.timestamp > history[history.length - 1].timestamp + 3600) { // 1 hour
            
            history.push(HistoricalData({
                timestamp: block.timestamp,
                apy: newAPY,
                tvl: source.totalDeposited
            }));
            
            // Limit history to last 720 entries (30 days if hourly)
            if (history.length > 720) {
                // Shift array left
                for (uint256 i = 0; i < history.length - 1; i++) {
                    history[i] = history[i + 1];
                }
                history.pop();
            }
        }
    }

    function _calculateWeightedAPY(address asset) internal view returns (uint256) {
        AssetData storage data = assetData[asset];
        uint256 totalWeighted = 0;
        uint256 totalAllocation = 0;
        
        for (uint256 i = 0; i < data.sourceList.length; i++) {
            address strategy = data.sourceList[i];
            YieldSource storage source = data.sources[strategy];
            
            if (source.active) {
                totalWeighted += source.currentAPY * source.allocation;
                totalAllocation += source.allocation;
            }
        }
        
        return totalAllocation > 0 ? totalWeighted / totalAllocation : 0;
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setRebalanceThreshold(uint256 newThreshold) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newThreshold <= 2000, "Threshold too high"); // Max 20%
        rebalanceThreshold = newThreshold;
    }

    function setPerformanceFee(uint256 newFee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newFee <= 2000, "Fee too high"); // Max 20%
        performanceFee = newFee;
    }

    function setPerformanceFeeRecipient(address newRecipient) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newRecipient != address(0), "Invalid recipient");
        performanceFeeRecipient = newRecipient;
    }

    function setRebalanceInterval(uint256 newInterval) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newInterval >= 3600, "Interval too short"); // Min 1 hour
        rebalanceInterval = newInterval;
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function getSupportedAssets() external view returns (address[] memory) {
        return supportedAssets;
    }
}