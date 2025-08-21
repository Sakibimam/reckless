# DeFi Yield Optimizer - Smart Contracts

A comprehensive ERC4626-compliant vault system for automated DeFi yield optimization with cross-chain capabilities.

## 🏗️ Architecture

### Core Contracts

- **BaseVault.sol** - ERC4626-compliant yield vault with multi-strategy support
- **CrossChainVault.sol** - Cross-chain vault using LayerZero protocol
- **StrategyRouter.sol** - Routes funds to optimal yield strategies
- **YieldAggregator.sol** - Manages multiple yield sources for diversified returns
- **VaultFactory.sol** - Factory for deploying and managing vaults

### Strategy Implementations

- **AerodromeStrategy.sol** - Liquidity provision on Aerodrome DEX
- **GMXStrategy.sol** - GLP staking on GMX protocol
- **PendleStrategy.sol** - Yield trading on Pendle protocol

## 🚀 Features

### Vault Features
- ✅ ERC4626 standard compliance
- ✅ Multi-asset support (ETH, USDC, USDT, etc.)
- ✅ Automatic yield optimization
- ✅ Cross-chain deposits via LayerZero
- ✅ Emergency pause/withdrawal mechanisms
- ✅ Role-based access control
- ✅ Slippage protection
- ✅ Performance and management fees

### Strategy Features
- ✅ Risk-adjusted yield calculations
- ✅ Automated rebalancing
- ✅ Harvest optimization
- ✅ Multi-protocol integration
- ✅ Capacity-aware allocation
- ✅ Performance tracking

### Security Features
- ✅ Pausable operations
- ✅ Emergency withdrawal
- ✅ Access control (Admin, Manager, Pauser roles)
- ✅ Slippage protection
- ✅ Reentrancy guards
- ✅ Input validation

## 📋 Contract Overview

| Contract | Purpose | Key Features |
|----------|---------|--------------|
| `BaseVault` | Core ERC4626 vault | Multi-strategy, auto-rebalancing, fee management |
| `CrossChainVault` | Cross-chain operations | LayerZero integration, multi-chain deposits |
| `StrategyRouter` | Strategy optimization | Risk-adjusted routing, performance tracking |
| `YieldAggregator` | Yield source management | Multi-protocol support, automated harvesting |
| `VaultFactory` | Vault deployment | Template-based deployment, registry |
| `AerodromeStrategy` | Aerodrome integration | LP farming, reward harvesting |
| `GMXStrategy` | GMX integration | GLP staking, esGMX rewards |
| `PendleStrategy` | Pendle integration | Yield trading, PT/YT positions |

## 🛠️ Setup

### Prerequisites
- [Foundry](https://getfoundry.sh/)
- [Node.js](https://nodejs.org/) v16+
- Git

### Installation

```bash
# Clone the repository
cd ai-powered-defi-yield-optimizer/contracts

# Install dependencies
forge install

# Build contracts
forge build

# Run tests
forge test

# Generate gas report
forge test --gas-report
```

### Environment Setup

Create a `.env` file:

```bash
# Private keys (never commit these!)
PRIVATE_KEY=your_private_key_here
ADMIN_PRIVATE_KEY=admin_private_key_here

# RPC URLs
MAINNET_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/your_key
BASE_RPC_URL=https://base-mainnet.g.alchemy.com/v2/your_key
ARBITRUM_RPC_URL=https://arb-mainnet.g.alchemy.com/v2/your_key
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/your_key
BASE_SEPOLIA_RPC_URL=https://base-sepolia.g.alchemy.com/v2/your_key

# API Keys for verification
ETHERSCAN_API_KEY=your_etherscan_key
BASESCAN_API_KEY=your_basescan_key
ARBISCAN_API_KEY=your_arbiscan_key
```

## 🚢 Deployment

### Local Testing

```bash
# Start local anvil node
anvil

# Deploy to local network
forge script script/Deploy.s.sol:DeployTestnet --rpc-url http://localhost:8545 --broadcast --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

### Testnet Deployment

```bash
# Deploy to Base Sepolia
forge script script/Deploy.s.sol:DeployTestnet --rpc-url $BASE_SEPOLIA_RPC_URL --broadcast --verify

# Verify contracts
forge verify-contract --chain base-sepolia --constructor-args $(cast abi-encode "constructor(address,string,string,address,address)" $TOKEN_ADDRESS "Test Vault" "TV" $ADMIN $FEE_RECIPIENT) $VAULT_ADDRESS src/BaseVault.sol:BaseVault
```

### Mainnet Deployment

```bash
# Deploy to Base mainnet
forge script script/Deploy.s.sol:DeployScript --rpc-url $BASE_RPC_URL --broadcast --verify --slow

# Deploy with Ledger hardware wallet
forge script script/Deploy.s.sol:DeployScript --rpc-url $BASE_RPC_URL --broadcast --verify --ledger
```

## 🧪 Testing

### Run All Tests
```bash
forge test
```

### Run Specific Test Files
```bash
forge test --match-path test/BaseVault.test.sol
```

### Run with Gas Reporting
```bash
forge test --gas-report
```

### Run Fuzzing Tests
```bash
forge test --fuzz-runs 10000
```

### Coverage Report
```bash
forge coverage
```

## 🔧 Usage Examples

### Deploy a Simple Vault

```solidity
// 1. Deploy factory
VaultFactory factory = new VaultFactory(admin, feeRecipient, lzEndpoint);

// 2. Configure vault
VaultFactory.VaultConfig memory config = VaultFactory.VaultConfig({
    asset: address(USDC),
    name: "USDC Yield Vault",
    symbol: "yvUSDC",
    feeRecipient: feeRecipient,
    performanceFeeBPS: 1000, // 10%
    managementFeeBPS: 200,   // 2%
    vaultType: VaultFactory.VaultType.BASE_VAULT,
    extraData: ""
});

// 3. Deploy vault
(address vault, bytes32 vaultHash) = factory.deployVault{value: 0.1 ether}(
    config,
    salt
);
```

### Add Strategy to Vault

```solidity
// 1. Deploy strategy
AerodromeStrategy strategy = new AerodromeStrategy(
    USDC,
    USDC_ETH_PAIR,
    // ... other parameters
);

// 2. Add to vault
BaseVault(vault).addStrategy(address(strategy), 5000); // 50% allocation

// 3. Rebalance
BaseVault(vault).rebalance();
```

### User Interactions

```solidity
// 1. Approve tokens
IERC20(USDC).approve(vault, amount);

// 2. Deposit
uint256 shares = BaseVault(vault).deposit(amount, user);

// 3. Withdraw
uint256 assets = BaseVault(vault).withdraw(amount, user, user);
```

## 📊 Integration Points

### Supported Protocols

| Protocol | Assets | Strategy Type | Risk Level | Expected APY |
|----------|--------|---------------|------------|--------------|
| Aerodrome | USDC/WETH/USDT | LP Farming | Medium (4/10) | 15-40% |
| GMX | Multi-asset | GLP Staking | Medium-Low (3/10) | 20-35% |
| Pendle | Various | Yield Trading | Medium (5/10) | 8-25% |

### Cross-Chain Support

- **Base**: Native deployment
- **Arbitrum**: LayerZero bridge
- **Ethereum**: LayerZero bridge
- **Polygon**: LayerZero bridge
- **Optimism**: Future support

## 🔒 Security Considerations

### Access Control
- **Admin**: Full control, emergency functions
- **Strategy Manager**: Add/remove strategies, rebalancing
- **Vault Manager**: Operational management
- **Pauser**: Emergency pause capabilities

### Risk Management
- Maximum single strategy allocation (50%)
- Slippage protection (configurable)
- Emergency withdrawal mechanisms
- Cooldown periods for large operations
- Performance monitoring and alerting

### Auditing Checklist
- [ ] Access control implementation
- [ ] Reentrancy protection
- [ ] Integer overflow/underflow
- [ ] ERC4626 compliance
- [ ] Cross-chain message validation
- [ ] Strategy isolation
- [ ] Fee calculation accuracy
- [ ] Emergency procedures

## 🔍 Monitoring & Analytics

### Key Metrics
- Total Value Locked (TVL)
- Annual Percentage Yield (APY)
- Strategy performance
- Fee collection
- User deposits/withdrawals
- Cross-chain volume

### Events to Monitor
```solidity
// Vault events
event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
event Withdraw(address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares);
event YieldHarvested(address indexed strategy, uint256 yieldAmount);
event StrategyUpdated(address indexed strategy, uint256 allocation, bool active);

// Cross-chain events
event CrossChainDepositInitiated(address indexed user, uint16 indexed destinationChain, uint256 amount, bytes32 indexed nonce);
event CrossChainDepositCompleted(address indexed user, uint16 indexed sourceChain, uint256 amount, uint256 shares, bytes32 indexed nonce);
```

## 🚨 Emergency Procedures

### Emergency Shutdown
```solidity
// Admin can activate emergency shutdown
BaseVault(vault).activateEmergencyShutdown();

// Users can emergency withdraw
BaseVault(vault).emergencyWithdraw(shares, receiver);
```

### Pause Operations
```solidity
// Pause all vault operations
BaseVault(vault).pause();

// Resume operations
BaseVault(vault).unpause();
```

## 📈 Optimization Strategies

### Gas Optimization
- Batch operations where possible
- Use CREATE2 for deterministic addresses
- Optimize struct packing
- Minimize external calls

### Yield Optimization
- Regular rebalancing based on APY changes
- Automated harvest scheduling
- Risk-adjusted allocation
- Capacity-aware distribution

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Write tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

### Development Guidelines
- Follow Solidity style guide
- Write comprehensive tests
- Document all functions
- Use NatSpec comments
- Implement proper error handling

## 📄 License

MIT License - see LICENSE file for details

## 🔗 Links

- [Documentation](../docs/)
- [Frontend Application](../app/)
- [API Server](../api/)
- [Deployment Scripts](./script/)

---

**⚠️ Disclaimer**: This code is for educational and research purposes. Always audit smart contracts before using in production with real funds.