// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Create2.sol";
import "./YieldVault.sol";
import "./CrossChainVault.sol";
import "./StrategyManager.sol";

/**
 * @title VaultFactory
 * @dev Factory contract for deploying and managing yield optimization vaults
 * @notice Creates vaults for different assets and strategies with standardized configuration
 */
contract VaultFactory is AccessControl, ReentrancyGuard {
    
    // Roles
    bytes32 public constant VAULT_CREATOR_ROLE = keccak256("VAULT_CREATOR_ROLE");
    bytes32 public constant VAULT_MANAGER_ROLE = keccak256("VAULT_MANAGER_ROLE");
    
    // Vault types
    enum VaultType {
        STANDARD,      // Basic ERC4626 vault
        CROSS_CHAIN,   // Cross-chain enabled vault
        STRATEGY_MANAGED // AI-managed strategy vault
    }
    
    // Vault configuration
    struct VaultConfig {
        IERC20 asset;
        string name;
        string symbol;
        VaultType vaultType;
        address feeRecipient;
        uint256 performanceFee; // In basis points
        uint256 managementFee;  // In basis points
        uint256 maxDepositAmount;
        bool crossChainEnabled;
        address layerZeroEndpoint;
        address strategyManager;
    }
    
    // Deployed vault info
    struct VaultInfo {
        address vault;
        address asset;
        VaultType vaultType;
        address creator;
        uint256 deployedAt;
        bool active;
        uint256 tvl;
        uint256 apy;
    }
    
    // State variables
    address public defaultFeeRecipient;
    uint256 public defaultPerformanceFee = 1000; // 10%
    uint256 public defaultManagementFee = 200;   // 2%
    uint256 public deploymentFee = 0.01 ether;   // Fee to deploy vault
    
    // Vault registry
    mapping(address => VaultInfo) public vaultInfo;
    address[] public allVaults;
    mapping(address => address[]) public userVaults; // user => vaults created
    mapping(address => address[]) public assetVaults; // asset => vaults for that asset
    mapping(VaultType => uint256) public vaultTypeCount;
    
    // Template addresses for cloning
    address public yieldVaultTemplate;
    address public crossChainVaultTemplate;
    address public strategyManagerTemplate;
    
    // Supported assets and configurations
    mapping(address => bool) public supportedAssets;
    mapping(address => uint256) public assetMinDeposit;
    mapping(address => uint256) public assetMaxDeposit;
    
    // Events
    event VaultCreated(
        address indexed vault,
        address indexed asset,
        address indexed creator,
        VaultType vaultType,
        string name,
        string symbol
    );
    event VaultStatusChanged(address indexed vault, bool active);
    event TemplateUpdated(VaultType vaultType, address template);
    event AssetConfigured(address indexed asset, bool supported, uint256 minDeposit, uint256 maxDeposit);
    event FeeUpdated(uint256 oldFee, uint256 newFee);
    
    modifier onlyVaultCreator() {
        require(hasRole(VAULT_CREATOR_ROLE, msg.sender) || hasRole(DEFAULT_ADMIN_ROLE, msg.sender), 
                "VF: Not authorized creator");
        _;
    }
    
    modifier validAsset(address asset) {
        require(supportedAssets[asset], "VF: Asset not supported");
        _;
    }
    
    constructor(
        address admin_,
        address defaultFeeRecipient_
    ) {
        require(admin_ != address(0), "VF: Invalid admin");
        require(defaultFeeRecipient_ != address(0), "VF: Invalid fee recipient");
        
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(VAULT_CREATOR_ROLE, admin_);
        _grantRole(VAULT_MANAGER_ROLE, admin_);
        
        defaultFeeRecipient = defaultFeeRecipient_;
        
        // Deploy template contracts
        _deployTemplates();
    }
    
    /*//////////////////////////////////////////////////////////////
                        VAULT CREATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Create a new yield vault
     * @param config Vault configuration parameters
     * @param salt Salt for deterministic deployment
     * @return vault Address of the created vault
     */
    function createVault(
        VaultConfig memory config,
        bytes32 salt
    ) external payable onlyVaultCreator validAsset(address(config.asset)) nonReentrant returns (address vault) {
        require(msg.value >= deploymentFee, "VF: Insufficient deployment fee");
        require(bytes(config.name).length > 0, "VF: Invalid name");
        require(bytes(config.symbol).length > 0, "VF: Invalid symbol");
        
        // Use default values if not specified
        if (config.feeRecipient == address(0)) {
            config.feeRecipient = defaultFeeRecipient;
        }
        if (config.performanceFee == 0) {
            config.performanceFee = defaultPerformanceFee;
        }
        if (config.managementFee == 0) {
            config.managementFee = defaultManagementFee;
        }
        if (config.maxDepositAmount == 0) {
            config.maxDepositAmount = assetMaxDeposit[address(config.asset)];
        }
        
        // Deploy vault based on type
        if (config.vaultType == VaultType.STANDARD) {
            vault = _createStandardVault(config, salt);
        } else if (config.vaultType == VaultType.CROSS_CHAIN) {
            require(config.layerZeroEndpoint != address(0), "VF: LayerZero endpoint required");
            vault = _createCrossChainVault(config, salt);
        } else if (config.vaultType == VaultType.STRATEGY_MANAGED) {
            vault = _createStrategyManagedVault(config, salt);
        } else {
            revert("VF: Invalid vault type");
        }
        
        // Register vault
        _registerVault(vault, config, msg.sender);
        
        // Return excess fee
        if (msg.value > deploymentFee) {
            payable(msg.sender).transfer(msg.value - deploymentFee);
        }
        
        emit VaultCreated(vault, address(config.asset), msg.sender, config.vaultType, config.name, config.symbol);
        
        return vault;
    }
    
    function _createStandardVault(VaultConfig memory config, bytes32 salt) internal returns (address) {
        bytes memory initCode = abi.encodePacked(
            type(YieldVault).creationCode,
            abi.encode(
                config.asset,
                config.name,
                config.symbol,
                msg.sender,
                config.feeRecipient
            )
        );
        
        return Create2.deploy(0, salt, initCode);
    }
    
    function _createCrossChainVault(VaultConfig memory config, bytes32 salt) internal returns (address) {
        bytes memory initCode = abi.encodePacked(
            type(CrossChainVault).creationCode,
            abi.encode(
                config.asset,
                config.name,
                config.symbol,
                msg.sender,
                config.feeRecipient,
                config.layerZeroEndpoint
            )
        );
        
        return Create2.deploy(0, salt, initCode);
    }
    
    function _createStrategyManagedVault(VaultConfig memory config, bytes32 salt) internal returns (address) {
        // First deploy strategy manager if not provided
        address strategyManager = config.strategyManager;
        if (strategyManager == address(0)) {\n            strategyManager = address(new StrategyManager(msg.sender));\n        }\n        \n        bytes memory initCode = abi.encodePacked(\n            type(YieldVault).creationCode,\n            abi.encode(\n                config.asset,\n                config.name,\n                config.symbol,\n                msg.sender,\n                config.feeRecipient\n            )\n        );\n        \n        address vault = Create2.deploy(0, salt, initCode);\n        \n        // Grant strategy manager role to the strategy manager contract\n        YieldVault(vault).grantRole(YieldVault(vault).STRATEGY_MANAGER_ROLE(), strategyManager);\n        \n        return vault;\n    }\n    \n    function _registerVault(address vault, VaultConfig memory config, address creator) internal {\n        VaultInfo memory info = VaultInfo({\n            vault: vault,\n            asset: address(config.asset),\n            vaultType: config.vaultType,\n            creator: creator,\n            deployedAt: block.timestamp,\n            active: true,\n            tvl: 0,\n            apy: 0\n        });\n        \n        vaultInfo[vault] = info;\n        allVaults.push(vault);\n        userVaults[creator].push(vault);\n        assetVaults[address(config.asset)].push(vault);\n        vaultTypeCount[config.vaultType]++;\n    }\n    \n    /*//////////////////////////////////////////////////////////////\n                        VAULT MANAGEMENT FUNCTIONS\n    //////////////////////////////////////////////////////////////*/\n    \n    /**\n     * @notice Update vault status (active/inactive)\n     */\n    function setVaultStatus(address vault, bool active) external onlyRole(VAULT_MANAGER_ROLE) {\n        require(vaultInfo[vault].vault != address(0), \"VF: Vault not found\");\n        \n        vaultInfo[vault].active = active;\n        emit VaultStatusChanged(vault, active);\n    }\n    \n    /**\n     * @notice Update vault TVL and APY (called by vaults or oracles)\n     */\n    function updateVaultMetrics(address vault, uint256 tvl, uint256 apy) external {\n        require(vaultInfo[vault].vault != address(0), \"VF: Vault not found\");\n        require(msg.sender == vault || hasRole(VAULT_MANAGER_ROLE, msg.sender), \"VF: Not authorized\");\n        \n        vaultInfo[vault].tvl = tvl;\n        vaultInfo[vault].apy = apy;\n    }\n    \n    /**\n     * @notice Batch update metrics for multiple vaults\n     */\n    function batchUpdateMetrics() external onlyRole(VAULT_MANAGER_ROLE) {\n        for (uint256 i = 0; i < allVaults.length; i++) {\n            address vault = allVaults[i];\n            if (vaultInfo[vault].active) {\n                try YieldVault(vault).getTotalValueLocked() returns (uint256 tvl) {\n                    try YieldVault(vault).getCurrentAPY() returns (uint256 apy) {\n                        vaultInfo[vault].tvl = tvl;\n                        vaultInfo[vault].apy = apy;\n                    } catch {}\n                } catch {}\n            }\n        }\n    }\n    \n    /*//////////////////////////////////////////////////////////////\n                        ASSET CONFIGURATION\n    //////////////////////////////////////////////////////////////*/\n    \n    /**\n     * @notice Configure supported asset\n     */\n    function configureAsset(\n        address asset,\n        bool supported,\n        uint256 minDeposit,\n        uint256 maxDeposit\n    ) external onlyRole(DEFAULT_ADMIN_ROLE) {\n        require(asset != address(0), \"VF: Invalid asset\");\n        require(minDeposit < maxDeposit || !supported, \"VF: Invalid deposit limits\");\n        \n        supportedAssets[asset] = supported;\n        if (supported) {\n            assetMinDeposit[asset] = minDeposit;\n            assetMaxDeposit[asset] = maxDeposit;\n        } else {\n            delete assetMinDeposit[asset];\n            delete assetMaxDeposit[asset];\n        }\n        \n        emit AssetConfigured(asset, supported, minDeposit, maxDeposit);\n    }\n    \n    /*//////////////////////////////////////////////////////////////\n                        VIEW FUNCTIONS\n    //////////////////////////////////////////////////////////////*/\n    \n    /**\n     * @notice Get all vaults\n     */\n    function getAllVaults() external view returns (address[] memory) {\n        return allVaults;\n    }\n    \n    /**\n     * @notice Get vaults created by user\n     */\n    function getUserVaults(address user) external view returns (address[] memory) {\n        return userVaults[user];\n    }\n    \n    /**\n     * @notice Get vaults for specific asset\n     */\n    function getAssetVaults(address asset) external view returns (address[] memory) {\n        return assetVaults[asset];\n    }\n    \n    /**\n     * @notice Get active vaults\n     */\n    function getActiveVaults() external view returns (address[] memory activeVaults) {\n        uint256 activeCount = 0;\n        \n        // Count active vaults\n        for (uint256 i = 0; i < allVaults.length; i++) {\n            if (vaultInfo[allVaults[i]].active) {\n                activeCount++;\n            }\n        }\n        \n        // Create array of active vaults\n        activeVaults = new address[](activeCount);\n        uint256 index = 0;\n        \n        for (uint256 i = 0; i < allVaults.length; i++) {\n            if (vaultInfo[allVaults[i]].active) {\n                activeVaults[index] = allVaults[i];\n                index++;\n            }\n        }\n    }\n    \n    /**\n     * @notice Get vault statistics\n     */\n    function getVaultStats() external view returns (\n        uint256 totalVaults,\n        uint256 activeVaults,\n        uint256 totalTVL,\n        uint256 averageAPY\n    ) {\n        totalVaults = allVaults.length;\n        uint256 activeTVL = 0;\n        uint256 totalAPY = 0;\n        uint256 activeCount = 0;\n        \n        for (uint256 i = 0; i < allVaults.length; i++) {\n            VaultInfo storage info = vaultInfo[allVaults[i]];\n            if (info.active) {\n                activeCount++;\n                activeTVL += info.tvl;\n                totalAPY += info.apy;\n            }\n        }\n        \n        activeVaults = activeCount;\n        totalTVL = activeTVL;\n        averageAPY = activeCount > 0 ? totalAPY / activeCount : 0;\n    }\n    \n    /**\n     * @notice Get top performing vaults\n     */\n    function getTopVaultsByAPY(uint256 limit) external view returns (\n        address[] memory vaults,\n        uint256[] memory apys\n    ) {\n        require(limit > 0 && limit <= allVaults.length, \"VF: Invalid limit\");\n        \n        // Create arrays for active vaults with APY > 0\n        address[] memory activeVaultAddrs = new address[](allVaults.length);\n        uint256[] memory activeVaultAPYs = new uint256[](allVaults.length);\n        uint256 activeCount = 0;\n        \n        for (uint256 i = 0; i < allVaults.length; i++) {\n            VaultInfo storage info = vaultInfo[allVaults[i]];\n            if (info.active && info.apy > 0) {\n                activeVaultAddrs[activeCount] = allVaults[i];\n                activeVaultAPYs[activeCount] = info.apy;\n                activeCount++;\n            }\n        }\n        \n        // Sort by APY (simple bubble sort for small arrays)\n        for (uint256 i = 0; i < activeCount - 1; i++) {\n            for (uint256 j = 0; j < activeCount - i - 1; j++) {\n                if (activeVaultAPYs[j] < activeVaultAPYs[j + 1]) {\n                    // Swap APYs\n                    uint256 tempAPY = activeVaultAPYs[j];\n                    activeVaultAPYs[j] = activeVaultAPYs[j + 1];\n                    activeVaultAPYs[j + 1] = tempAPY;\n                    \n                    // Swap addresses\n                    address tempAddr = activeVaultAddrs[j];\n                    activeVaultAddrs[j] = activeVaultAddrs[j + 1];\n                    activeVaultAddrs[j + 1] = tempAddr;\n                }\n            }\n        }\n        \n        // Return top vaults up to limit\n        uint256 returnCount = limit < activeCount ? limit : activeCount;\n        vaults = new address[](returnCount);\n        apys = new uint256[](returnCount);\n        \n        for (uint256 i = 0; i < returnCount; i++) {\n            vaults[i] = activeVaultAddrs[i];\n            apys[i] = activeVaultAPYs[i];\n        }\n    }\n    \n    /**\n     * @notice Calculate deployment address for vault\n     */\n    function computeVaultAddress(\n        VaultConfig memory config,\n        bytes32 salt\n    ) external view returns (address) {\n        bytes memory initCode;\n        \n        if (config.vaultType == VaultType.STANDARD || config.vaultType == VaultType.STRATEGY_MANAGED) {\n            initCode = abi.encodePacked(\n                type(YieldVault).creationCode,\n                abi.encode(\n                    config.asset,\n                    config.name,\n                    config.symbol,\n                    msg.sender,\n                    config.feeRecipient\n                )\n            );\n        } else if (config.vaultType == VaultType.CROSS_CHAIN) {\n            initCode = abi.encodePacked(\n                type(CrossChainVault).creationCode,\n                abi.encode(\n                    config.asset,\n                    config.name,\n                    config.symbol,\n                    msg.sender,\n                    config.feeRecipient,\n                    config.layerZeroEndpoint\n                )\n            );\n        }\n        \n        return Create2.computeAddress(salt, keccak256(initCode));\n    }\n    \n    /*//////////////////////////////////////////////////////////////\n                        ADMIN FUNCTIONS\n    //////////////////////////////////////////////////////////////*/\n    \n    function setDeploymentFee(uint256 newFee) external onlyRole(DEFAULT_ADMIN_ROLE) {\n        uint256 oldFee = deploymentFee;\n        deploymentFee = newFee;\n        emit FeeUpdated(oldFee, newFee);\n    }\n    \n    function setDefaultFees(\n        uint256 performanceFee,\n        uint256 managementFee\n    ) external onlyRole(DEFAULT_ADMIN_ROLE) {\n        require(performanceFee <= 2000, \"VF: Performance fee too high\"); // Max 20%\n        require(managementFee <= 500, \"VF: Management fee too high\");   // Max 5%\n        \n        defaultPerformanceFee = performanceFee;\n        defaultManagementFee = managementFee;\n    }\n    \n    function setDefaultFeeRecipient(address newRecipient) external onlyRole(DEFAULT_ADMIN_ROLE) {\n        require(newRecipient != address(0), \"VF: Invalid recipient\");\n        defaultFeeRecipient = newRecipient;\n    }\n    \n    function withdrawFees() external onlyRole(DEFAULT_ADMIN_ROLE) {\n        uint256 balance = address(this).balance;\n        if (balance > 0) {\n            payable(defaultFeeRecipient).transfer(balance);\n        }\n    }\n    \n    function _deployTemplates() internal {\n        // Templates are deployed as part of constructor - can be upgraded later\n        // This is a placeholder for template deployment logic\n    }\n    \n    // Allow contract to receive ETH for deployment fees\n    receive() external payable {}\n}