// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/BaseVault.sol";
import "../src/CrossChainVault.sol";
import "../src/StrategyRouter.sol";
import "../src/YieldAggregator.sol";
import "../src/VaultFactory.sol";
import "../src/strategies/AerodromeStrategy.sol";
import "../src/strategies/GMXStrategy.sol";
import "../src/strategies/PendleStrategy.sol";

contract DeployScript is Script {
    // Deployment addresses - update these for each network
    address public constant ADMIN = 0x1234567890123456789012345678901234567890; // Replace with actual admin
    address public constant FEE_RECIPIENT = 0x1234567890123456789012345678901234567890; // Replace with actual fee recipient
    address public constant LAYER_ZERO_ENDPOINT = 0x66A71Dcef29A0fFBDBE3c6a460a3B5BC225Cd675; // LayerZero endpoint
    
    // Token addresses (Base network examples)
    address public constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address public constant WETH = 0x4200000000000000000000000000000000000006;
    address public constant USDT = 0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2;
    
    // Protocol addresses (update with actual addresses)
    address public constant AERODROME_ROUTER = address(0); // Add actual address
    address public constant GMX_REWARD_ROUTER = address(0); // Add actual address
    address public constant PENDLE_ROUTER = address(0); // Add actual address
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy core contracts
        VaultFactory factory = deployFactory();
        
        // Deploy strategy components
        StrategyRouter router = deployStrategyRouter();
        YieldAggregator aggregator = deployYieldAggregator();
        
        // Deploy vault templates
        BaseVault baseVaultTemplate = deployBaseVaultTemplate();
        CrossChainVault crossChainVaultTemplate = deployCrossChainVaultTemplate();
        
        // Setup factory with templates
        setupFactory(factory, baseVaultTemplate, crossChainVaultTemplate, router, aggregator);
        
        // Deploy initial strategies (if protocol addresses are available)
        if (AERODROME_ROUTER != address(0)) {
            deployAerodromeStrategies();
        }
        
        if (GMX_REWARD_ROUTER != address(0)) {
            deployGMXStrategies();
        }
        
        if (PENDLE_ROUTER != address(0)) {
            deployPendleStrategies();
        }
        
        // Deploy example vaults
        deployExampleVaults(factory);
        
        vm.stopBroadcast();
        
        // Log deployment addresses
        logDeploymentInfo(factory, router, aggregator);
    }
    
    function deployFactory() internal returns (VaultFactory) {
        console.log("Deploying VaultFactory...");
        VaultFactory factory = new VaultFactory(
            ADMIN,
            FEE_RECIPIENT,
            LAYER_ZERO_ENDPOINT
        );
        console.log("VaultFactory deployed at:", address(factory));
        return factory;
    }
    
    function deployStrategyRouter() internal returns (StrategyRouter) {
        console.log("Deploying StrategyRouter...");
        StrategyRouter router = new StrategyRouter(ADMIN, FEE_RECIPIENT);
        console.log("StrategyRouter deployed at:", address(router));
        return router;
    }
    
    function deployYieldAggregator() internal returns (YieldAggregator) {
        console.log("Deploying YieldAggregator...");
        YieldAggregator aggregator = new YieldAggregator(ADMIN, FEE_RECIPIENT);
        console.log("YieldAggregator deployed at:", address(aggregator));
        return aggregator;
    }
    
    function deployBaseVaultTemplate() internal returns (BaseVault) {
        console.log("Deploying BaseVault template...");
        BaseVault template = new BaseVault(
            IERC20(USDC), // Use USDC as template asset
            "Base Vault Template",
            "BVT",
            ADMIN,
            FEE_RECIPIENT
        );
        console.log("BaseVault template deployed at:", address(template));
        return template;
    }
    
    function deployCrossChainVaultTemplate() internal returns (CrossChainVault) {
        console.log("Deploying CrossChainVault template...");
        CrossChainVault template = new CrossChainVault(
            IERC20(USDC),
            "CrossChain Vault Template",
            "CVT",
            ADMIN,
            FEE_RECIPIENT,
            LAYER_ZERO_ENDPOINT
        );
        console.log("CrossChainVault template deployed at:", address(template));
        return template;
    }
    
    function setupFactory(
        VaultFactory factory,
        BaseVault baseTemplate,
        CrossChainVault crossChainTemplate,
        StrategyRouter router,
        YieldAggregator aggregator
    ) internal {
        console.log("Setting up factory templates...");
        
        factory.setVaultTemplate(VaultFactory.VaultType.BASE_VAULT, address(baseTemplate));
        factory.setVaultTemplate(VaultFactory.VaultType.CROSS_CHAIN_VAULT, address(crossChainTemplate));
        factory.setStrategyTemplates(address(router), address(aggregator));
        
        console.log("Factory setup complete");
    }
    
    function deployAerodromeStrategies() internal {
        console.log("Deploying Aerodrome strategies...");
        // Implementation depends on actual Aerodrome addresses
        // This is a placeholder for when addresses are available
    }
    
    function deployGMXStrategies() internal {
        console.log("Deploying GMX strategies...");
        // Implementation depends on actual GMX addresses
    }
    
    function deployPendleStrategies() internal {
        console.log("Deploying Pendle strategies...");
        // Implementation depends on actual Pendle addresses
    }
    
    function deployExampleVaults(VaultFactory factory) internal {
        console.log("Deploying example vaults...");
        
        // USDC Vault
        VaultFactory.VaultConfig memory usdcConfig = VaultFactory.VaultConfig({
            asset: USDC,
            name: "USDC Yield Vault",
            symbol: "yvUSDC",
            feeRecipient: FEE_RECIPIENT,
            performanceFeeBPS: 1000, // 10%
            managementFeeBPS: 200,   // 2%
            vaultType: VaultFactory.VaultType.BASE_VAULT,
            extraData: ""
        });
        
        (address usdcVault,) = factory.deployVault{value: 0.1 ether}(
            usdcConfig,
            keccak256(abi.encodePacked("USDC_VAULT", block.timestamp))
        );
        console.log("USDC Vault deployed at:", usdcVault);
        
        // WETH CrossChain Vault
        VaultFactory.VaultConfig memory wethConfig = VaultFactory.VaultConfig({
            asset: WETH,
            name: "WETH CrossChain Vault",
            symbol: "ccWETH",
            feeRecipient: FEE_RECIPIENT,
            performanceFeeBPS: 1500, // 15%
            managementFeeBPS: 300,   // 3%
            vaultType: VaultFactory.VaultType.CROSS_CHAIN_VAULT,
            extraData: abi.encode(
                [uint16(1), uint16(137), uint16(42161)], // Ethereum, Polygon, Arbitrum
                [address(0x1), address(0x2), address(0x3)] // Trusted remotes
            )
        });
        
        (address wethVault,) = factory.deployVault{value: 0.1 ether}(
            wethConfig,
            keccak256(abi.encodePacked("WETH_VAULT", block.timestamp))
        );
        console.log("WETH CrossChain Vault deployed at:", wethVault);
    }
    
    function logDeploymentInfo(
        VaultFactory factory,
        StrategyRouter router,
        YieldAggregator aggregator
    ) internal view {
        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("Network:", block.chainid);
        console.log("Deployer:", msg.sender);
        console.log("Admin:", ADMIN);
        console.log("Fee Recipient:", FEE_RECIPIENT);
        console.log("\n=== CONTRACT ADDRESSES ===");
        console.log("VaultFactory:", address(factory));
        console.log("StrategyRouter:", address(router));
        console.log("YieldAggregator:", address(aggregator));
        console.log("\n=== INTEGRATION GUIDE ===");
        console.log("1. Update protocol addresses in this script");
        console.log("2. Deploy strategies for each protocol");
        console.log("3. Register strategies in StrategyRouter");
        console.log("4. Add yield sources to YieldAggregator");
        console.log("5. Create vaults using VaultFactory");
        console.log("6. Test with small amounts first");
    }
}

contract DeployTestnet is Script {
    // Testnet addresses (Base Sepolia)
    address public constant ADMIN = 0x742d35Cc6495C4C04518C4CfA1d4D7f36E0F14Cf; // Replace with your address
    address public constant FEE_RECIPIENT = 0x742d35Cc6495C4C04518C4CfA1d4D7f36E0F14Cf;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy mock tokens for testing
        ERC20Mock usdc = new ERC20Mock();
        ERC20Mock weth = new ERC20Mock();
        
        console.log("Mock USDC deployed at:", address(usdc));
        console.log("Mock WETH deployed at:", address(weth));
        
        // Mint tokens for testing
        usdc.mint(msg.sender, 1000000 * 1e18);
        weth.mint(msg.sender, 1000 * 1e18);
        
        // Deploy factory without LayerZero for testing
        VaultFactory factory = new VaultFactory(
            ADMIN,
            FEE_RECIPIENT,
            address(0) // No LayerZero on testnet
        );
        
        console.log("Test VaultFactory deployed at:", address(factory));
        
        vm.stopBroadcast();
    }
}

// Mock ERC20 for testing
contract ERC20Mock {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    uint256 public totalSupply;
    string public name = "Mock Token";
    string public symbol = "MOCK";
    uint8 public decimals = 18;
    
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }
    
    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount);
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount);
        require(allowance[from][msg.sender] >= amount);
        
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        
        emit Transfer(from, to, amount);
        return true;
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
}