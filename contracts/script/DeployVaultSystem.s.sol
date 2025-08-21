// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/YieldVault.sol";
import "../src/CrossChainVault.sol";
import "../src/StrategyManager.sol";
import "../src/VaultFactory.sol";
import "../src/strategies/AerodromeStrategy.sol";
import "../src/strategies/GMXStrategy.sol";
import "../src/strategies/PendleStrategy.sol";

/**
 * @title DeployVaultSystem
 * @dev Deployment script for the complete vault system
 */
contract DeployVaultSystem is Script {
    
    // Deployment configuration
    struct DeployConfig {
        address admin;
        address feeRecipient;
        address layerZeroEndpoint;
        // Asset addresses
        address usdc;
        address usdt;
        address weth;
        address wbtc;
        // Aerodrome contracts (Base)
        address aerodromeRouter;
        address aerodromeUSDCETHPool;
        address aerodromeUSDCETHGauge;
        address aeroToken;
        // GMX contracts (Arbitrum)
        address gmxRewardRouter;
        address gmxGlpManager;
        address gmxVault;
        address gmxFeeGlpTracker;
        address gmxStakedGlpTracker;
        address glpToken;
        address esGmxToken;
        address gmxToken;
        // Pendle contracts
        address pendleRouter;
        address pendleUSDCMarket;
        address pendleUSDCSY;
    }
    
    // Deployment results
    struct DeployedContracts {
        address vaultFactory;
        address strategyManager;
        address[] vaults;
        address[] strategies;
    }
    
    function run() external returns (DeployedContracts memory deployed) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        
        // Get deployment configuration
        DeployConfig memory config = getDeployConfig();
        
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("Deploying vault system with admin:", config.admin);
        console.log("Fee recipient:", config.feeRecipient);
        
        // Deploy core contracts
        deployed = deployCore(config, deployerAddress);
        
        // Deploy strategies
        deployStrategies(config, deployed);
        
        // Setup vault factory with supported assets
        setupVaultFactory(config, deployed);
        
        vm.stopBroadcast();
        
        console.log("Deployment completed successfully!");
        logDeployedAddresses(deployed);
        
        return deployed;
    }
    
    function deployCore(DeployConfig memory config, address deployer) internal returns (DeployedContracts memory deployed) {
        console.log("Deploying core contracts...");
        
        // Deploy Strategy Manager
        deployed.strategyManager = address(new StrategyManager(config.admin));
        console.log("StrategyManager deployed at:", deployed.strategyManager);
        
        // Deploy Vault Factory
        deployed.vaultFactory = address(new VaultFactory(config.admin, config.feeRecipient));
        console.log("VaultFactory deployed at:", deployed.vaultFactory);
        
        return deployed;
    }
    
    function deployStrategies(DeployConfig memory config, DeployedContracts memory deployed) internal {
        console.log("Deploying strategies...");
        
        deployed.strategies = new address[](3);
        
        // Deploy Aerodrome Strategy (for Base)
        if (config.aerodromeRouter != address(0)) {
            deployed.strategies[0] = address(new AerodromeStrategy(
                config.usdc, // asset
                config.weth,  // paired asset
                config.aeroToken,
                config.aerodromeUSDCETHPool,
                config.aerodromeUSDCETHGauge,
                config.aerodromeRouter,
                false, // not stable pair
                config.admin
            ));
            console.log("AerodromeStrategy deployed at:", deployed.strategies[0]);
        }
        
        // Deploy GMX Strategy (for Arbitrum)
        if (config.gmxRewardRouter != address(0)) {
            deployed.strategies[1] = address(new GMXStrategy(
                config.usdc,
                config.glpToken,
                config.esGmxToken,
                config.gmxToken,
                config.weth,
                config.gmxRewardRouter,
                config.gmxFeeGlpTracker,
                config.gmxStakedGlpTracker,
                config.gmxGlpManager,
                config.gmxVault,
                config.admin
            ));
            console.log("GMXStrategy deployed at:", deployed.strategies[1]);
        }
        
        // Deploy Pendle Strategy
        if (config.pendleRouter != address(0)) {
            deployed.strategies[2] = address(new PendleStrategy(
                config.usdc,
                config.pendleUSDCMarket,
                config.pendleRouter,
                config.pendleUSDCSY,
                config.admin
            ));
            console.log("PendleStrategy deployed at:", deployed.strategies[2]);
        }
    }
    
    function setupVaultFactory(DeployConfig memory config, DeployedContracts memory deployed) internal {
        console.log("Setting up VaultFactory...");
        
        VaultFactory factory = VaultFactory(deployed.vaultFactory);
        
        // Configure supported assets
        if (config.usdc != address(0)) {
            factory.configureAsset(
                config.usdc,
                true,  // supported
                1000 * 1e6,    // min deposit: 1,000 USDC
                10000000 * 1e6 // max deposit: 10M USDC
            );
            console.log("USDC configured as supported asset");
        }
        
        if (config.usdt != address(0)) {
            factory.configureAsset(
                config.usdt,
                true,
                1000 * 1e6,    // min deposit: 1,000 USDT
                10000000 * 1e6 // max deposit: 10M USDT
            );
            console.log("USDT configured as supported asset");
        }
        
        if (config.weth != address(0)) {
            factory.configureAsset(
                config.weth,
                true,
                1 * 1e18,    // min deposit: 1 ETH
                10000 * 1e18 // max deposit: 10,000 ETH
            );
            console.log("WETH configured as supported asset");
        }
        
        if (config.wbtc != address(0)) {
            factory.configureAsset(
                config.wbtc,
                true,
                1e6,        // min deposit: 0.01 BTC
                1000 * 1e8  // max deposit: 1,000 BTC
            );
            console.log("WBTC configured as supported asset");
        }
    }
    
    function getDeployConfig() internal view returns (DeployConfig memory config) {
        // Get chain ID to determine deployment configuration
        uint256 chainId = block.chainid;
        
        // Common configuration
        config.admin = vm.envOr("ADMIN_ADDRESS", vm.addr(vm.envUint("PRIVATE_KEY")));
        config.feeRecipient = vm.envOr("FEE_RECIPIENT", config.admin);
        
        if (chainId == 1) {
            // Ethereum Mainnet
            console.log("Configuring for Ethereum Mainnet");
            config.layerZeroEndpoint = 0x66A71Dcef29A0fFBDBE3c6a460a3B5BC225Cd675;
            config.usdc = 0xA0b86a33E6c2BC3b8D4a8EC48d4FDdE8E59eab87;
            config.usdt = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
            config.weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
            config.wbtc = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
            
        } else if (chainId == 8453) {
            // Base Mainnet
            console.log("Configuring for Base Mainnet");
            config.layerZeroEndpoint = 0xb6319cC6c8c27A8F5dAF0dD3DF91EA35C4720dd7;
            config.usdc = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
            config.weth = 0x4200000000000000000000000000000000000006;
            
            // Aerodrome contracts
            config.aerodromeRouter = 0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43;
            config.aeroToken = 0x940181a94A35A4569E4529A3CDfB74e38FD98631;
            config.aerodromeUSDCETHPool = 0xB4885Bc63399BF5518b994c1d0C153334Ee579D0;
            config.aerodromeUSDCETHGauge = 0x519BBD1Dd8C6A94C46080E24f316c14Ee758C025;
            
        } else if (chainId == 42161) {
            // Arbitrum One
            console.log("Configuring for Arbitrum One");
            config.layerZeroEndpoint = 0x3c2269811836af69497E5F486A85D7316753cf62;
            config.usdc = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
            config.usdt = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
            config.weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
            config.wbtc = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
            
            // GMX contracts
            config.gmxRewardRouter = 0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1;
            config.gmxGlpManager = 0x3963FfC9dff443c2A94f21b129D429891E32ec18;
            config.gmxVault = 0x489ee077994B6658eAfA855C308275EAd8097C4A;
            config.gmxFeeGlpTracker = 0x4e971a87900b931fF39d1Aad67697F49835400b6;
            config.gmxStakedGlpTracker = 0x1aDDD80E6039594eE970E5872D247bf0414C8903;
            config.glpToken = 0x4277f8F2c384827B5273592FF7CeBd9f2C1ac258;
            config.esGmxToken = 0xf42Ae1D54fd613C9bb14810b0588FaAa09a426cA;
            config.gmxToken = 0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a;
            
        } else if (chainId == 137) {
            // Polygon
            console.log("Configuring for Polygon");
            config.layerZeroEndpoint = 0x3c2269811836af69497E5F486A85D7316753cf62;
            config.usdc = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
            config.usdt = 0xc2132D05D31c914a87C6611C10748AEb04B58e8F;
            config.weth = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
            config.wbtc = 0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6;
            
        } else {
            // Local/Testnet - use mock addresses
            console.log("Configuring for local/testnet deployment");
            config.layerZeroEndpoint = 0x66A71Dcef29A0fFBDBE3c6a460a3B5BC225Cd675;
            
            // Deploy mock tokens if needed
            config.usdc = deployMockToken("USD Coin", "USDC", 6);
            config.usdt = deployMockToken("Tether USD", "USDT", 6);
            config.weth = deployMockToken("Wrapped Ether", "WETH", 18);
            config.wbtc = deployMockToken("Wrapped Bitcoin", "WBTC", 8);
        }
        
        return config;
    }
    
    function deployMockToken(string memory name, string memory symbol, uint8 decimals) internal returns (address) {
        // For testing purposes, deploy a simple ERC20 mock
        bytes memory bytecode = abi.encodePacked(
            type(MockERC20).creationCode,
            abi.encode(name, symbol, decimals)
        );
        
        address token;
        assembly {
            token := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }
        
        console.log(string(abi.encodePacked("Mock ", symbol, " deployed at:")), token);
        return token;
    }
    
    function logDeployedAddresses(DeployedContracts memory deployed) internal view {
        console.log("\n=== DEPLOYED CONTRACTS ===");
        console.log("VaultFactory:", deployed.vaultFactory);
        console.log("StrategyManager:", deployed.strategyManager);
        
        console.log("\nStrategies:");
        for (uint256 i = 0; i < deployed.strategies.length; i++) {
            if (deployed.strategies[i] != address(0)) {
                console.log("Strategy", i, ":", deployed.strategies[i]);
            }
        }
        
        console.log("\n=== VERIFICATION COMMANDS ===");
        console.log("VaultFactory:");
        console.log("forge verify-contract", deployed.vaultFactory, "src/VaultFactory.sol:VaultFactory");
        
        console.log("StrategyManager:");
        console.log("forge verify-contract", deployed.strategyManager, "src/StrategyManager.sol:StrategyManager");
        
        console.log("\n=== NEXT STEPS ===");
        console.log("1. Verify contracts on block explorer");
        console.log("2. Add strategies to StrategyManager");
        console.log("3. Create vaults using VaultFactory");
        console.log("4. Configure cross-chain settings if needed");
    }
}

// Simple mock ERC20 for testing
contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    
    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        totalSupply = 1000000000 * 10**_decimals; // 1B tokens
        balanceOf[msg.sender] = totalSupply;
    }
    
    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}