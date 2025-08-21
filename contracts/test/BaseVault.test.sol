// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/BaseVault.sol";
import "../src/StrategyRouter.sol";
import "../src/YieldAggregator.sol";
import "../src/VaultFactory.sol";
import "../src/strategies/AerodromeStrategy.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract MockStrategy is IStrategy {
    IERC20 public immutable override asset;
    uint256 public override riskLevel = 3;
    uint256 private _totalAssets;
    uint256 private _apy = 1500; // 15% APY
    bool public override isActive = true;
    
    constructor(address _asset) {
        asset = IERC20(_asset);
    }
    
    function getAPY() external view override returns (uint256) {
        return _apy;
    }
    
    function totalAssets() external view override returns (uint256) {
        return _totalAssets;
    }
    
    function invest(uint256 amount) external override returns (uint256) {
        asset.transferFrom(msg.sender, address(this), amount);
        _totalAssets += amount;
        return amount;
    }
    
    function withdraw(uint256 amount) external override returns (uint256) {
        if (amount > _totalAssets) amount = _totalAssets;
        _totalAssets -= amount;
        asset.transfer(msg.sender, amount);
        return amount;
    }
    
    function harvest() external override returns (uint256) {
        // Mock harvest - generate 1% yield
        uint256 yield = _totalAssets / 100;
        return yield;
    }
    
    function emergencyWithdraw() external override returns (uint256) {
        uint256 amount = _totalAssets;
        _totalAssets = 0;
        asset.transfer(msg.sender, amount);
        return amount;
    }
    
    function maxInvestable() external pure override returns (uint256) {
        return 1000000 * 1e18; // 1M tokens
    }
    
    function getRiskLevel() external view override returns (uint8) {
        return uint8(riskLevel);
    }
    
    // Admin functions for testing
    function setAPY(uint256 newAPY) external {
        _apy = newAPY;
    }
    
    function setActive(bool active) external {
        isActive = active;
    }
}

contract BaseVaultTest is Test {
    BaseVault public vault;
    ERC20Mock public token;
    MockStrategy public strategy1;
    MockStrategy public strategy2;
    StrategyRouter public router;
    YieldAggregator public aggregator;
    VaultFactory public factory;
    
    address public admin = makeAddr("admin");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public feeRecipient = makeAddr("feeRecipient");
    
    uint256 public constant INITIAL_SUPPLY = 1000000 * 1e18;
    uint256 public constant INITIAL_USER_BALANCE = 10000 * 1e18;
    
    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares);
    
    function setUp() public {
        // Deploy mock token
        token = new ERC20Mock();
        token.mint(address(this), INITIAL_SUPPLY);
        token.mint(user1, INITIAL_USER_BALANCE);
        token.mint(user2, INITIAL_USER_BALANCE);
        
        // Deploy vault
        vm.prank(admin);
        vault = new BaseVault(
            IERC20(address(token)),
            "Test Vault",
            "TV",
            admin,
            feeRecipient
        );
        
        // Deploy strategies
        strategy1 = new MockStrategy(address(token));
        strategy2 = new MockStrategy(address(token));
        
        // Setup strategy APYs
        strategy1.setAPY(1500); // 15%
        strategy2.setAPY(2000); // 20%
        
        // Fund strategies for testing
        token.transfer(address(strategy1), 1000 * 1e18);
        token.transfer(address(strategy2), 1000 * 1e18);
        
        // Deploy router and aggregator
        router = new StrategyRouter(admin, feeRecipient);
        aggregator = new YieldAggregator(admin, feeRecipient);
        
        // Deploy factory
        factory = new VaultFactory(admin, feeRecipient, address(0)); // No LayerZero for basic test
    }
    
    function testInitialState() public {
        assertEq(address(vault.asset()), address(token));
        assertEq(vault.name(), "Test Vault");
        assertEq(vault.symbol(), "TV");
        assertEq(vault.decimals(), 18);
        assertEq(vault.totalAssets(), 0);
        assertEq(vault.totalSupply(), 0);
        assertTrue(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), admin));
    }
    
    function testDeposit() public {
        uint256 depositAmount = 1000 * 1e18;
        
        vm.startPrank(user1);
        token.approve(address(vault), depositAmount);
        
        vm.expectEmit(true, true, false, true);
        emit Deposit(user1, user1, depositAmount, depositAmount);
        
        uint256 shares = vault.deposit(depositAmount, user1);
        vm.stopPrank();
        
        assertEq(shares, depositAmount);
        assertEq(vault.balanceOf(user1), depositAmount);
        assertEq(vault.totalAssets(), depositAmount);
        assertEq(vault.totalSupply(), depositAmount);
    }
    
    function testMint() public {
        uint256 sharesToMint = 500 * 1e18;
        
        vm.startPrank(user1);
        token.approve(address(vault), INITIAL_USER_BALANCE);
        
        uint256 assets = vault.mint(sharesToMint, user1);
        vm.stopPrank();
        
        assertEq(assets, sharesToMint); // 1:1 ratio initially
        assertEq(vault.balanceOf(user1), sharesToMint);
        assertEq(vault.totalAssets(), sharesToMint);
    }
    
    function testWithdraw() public {
        // First deposit
        uint256 depositAmount = 1000 * 1e18;
        vm.startPrank(user1);
        token.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        
        // Then withdraw
        uint256 withdrawAmount = 300 * 1e18;
        uint256 shares = vault.withdraw(withdrawAmount, user1, user1);
        vm.stopPrank();
        
        assertEq(shares, withdrawAmount);
        assertEq(vault.balanceOf(user1), depositAmount - withdrawAmount);
        assertEq(vault.totalAssets(), depositAmount - withdrawAmount);
        assertEq(token.balanceOf(user1), INITIAL_USER_BALANCE - depositAmount + withdrawAmount);
    }
    
    function testRedeem() public {
        // First deposit
        uint256 depositAmount = 1000 * 1e18;
        vm.startPrank(user1);
        token.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        
        // Then redeem shares
        uint256 sharesToRedeem = 400 * 1e18;
        uint256 assets = vault.redeem(sharesToRedeem, user1, user1);
        vm.stopPrank();
        
        assertEq(assets, sharesToRedeem);
        assertEq(vault.balanceOf(user1), depositAmount - sharesToRedeem);
    }
    
    function testAddStrategy() public {
        vm.startPrank(admin);
        vault.addStrategy(address(strategy1), 5000); // 50% allocation
        vm.stopPrank();
        
        assertEq(vault.getStrategyAllocation(address(strategy1)), 5000);
        assertEq(vault.totalStrategiesAllocation(), 5000);
    }
    
    function testInvestInStrategy() public {
        // Add strategy
        vm.prank(admin);
        vault.addStrategy(address(strategy1), 5000);
        
        // Deposit to vault
        uint256 depositAmount = 1000 * 1e18;
        vm.startPrank(user1);
        token.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();
        
        // Rebalance should invest in strategy
        vm.prank(admin);
        vault.rebalance();
        
        // Check that strategy received funds
        assertGt(strategy1.totalAssets(), 0);
    }
    
    function testHarvestYield() public {
        // Setup strategy and deposit
        vm.prank(admin);
        vault.addStrategy(address(strategy1), 5000);
        
        uint256 depositAmount = 1000 * 1e18;
        vm.startPrank(user1);
        token.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();
        
        vm.prank(admin);
        vault.rebalance();
        
        // Harvest yield
        uint256 harvested = vault.harvestYield();
        
        // Should have harvested some yield
        assertGt(harvested, 0);
    }
    
    function testMultipleStrategies() public {
        vm.startPrank(admin);
        vault.addStrategy(address(strategy1), 3000); // 30%
        vault.addStrategy(address(strategy2), 4000); // 40%
        vm.stopPrank();
        
        assertEq(vault.totalStrategiesAllocation(), 7000);
        
        // Test weighted APY calculation
        uint256 apy = vault.getCurrentAPY();
        
        // Should be weighted average: (15% * 30% + 20% * 40%) / 70% = ~17.14%
        assertGt(apy, 1500); // Greater than strategy1 APY
        assertLt(apy, 2000); // Less than strategy2 APY
    }
    
    function testEmergencyWithdraw() public {
        // Setup
        vm.prank(admin);
        vault.addStrategy(address(strategy1), 5000);
        
        uint256 depositAmount = 1000 * 1e18;
        vm.startPrank(user1);
        token.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();
        
        vm.prank(admin);
        vault.rebalance();
        
        // Activate emergency shutdown
        vm.prank(admin);
        vault.activateEmergencyShutdown();
        
        // User should be able to emergency withdraw
        vm.startPrank(user1);
        uint256 userShares = vault.balanceOf(user1);
        uint256 withdrawn = vault.emergencyWithdraw(userShares, user1);
        vm.stopPrank();
        
        assertGt(withdrawn, 0);
        assertEq(vault.balanceOf(user1), 0);
    }
    
    function testPauseUnpause() public {
        vm.prank(admin);
        vault.pause();
        assertTrue(vault.paused());
        
        // Should revert when trying to deposit while paused
        vm.startPrank(user1);
        token.approve(address(vault), 1000 * 1e18);
        vm.expectRevert("Pausable: paused");
        vault.deposit(1000 * 1e18, user1);
        vm.stopPrank();
        
        vm.prank(admin);
        vault.unpause();
        assertFalse(vault.paused());
        
        // Should work again after unpause
        vm.startPrank(user1);
        uint256 shares = vault.deposit(1000 * 1e18, user1);
        vm.stopPrank();
        assertEq(shares, 1000 * 1e18);
    }
    
    function testAccessControl() public {
        // Non-admin shouldn't be able to add strategy
        vm.prank(user1);
        vm.expectRevert("Not strategy manager");
        vault.addStrategy(address(strategy1), 5000);
        
        // Non-admin shouldn't be able to pause
        vm.prank(user1);
        vm.expectRevert();
        vault.pause();
    }
    
    function testFactoryDeployment() public {
        vm.startPrank(admin);
        
        VaultFactory.VaultConfig memory config = VaultFactory.VaultConfig({
            asset: address(token),
            name: "Factory Vault",
            symbol: "FV",
            feeRecipient: feeRecipient,
            performanceFeeBPS: 1000,
            managementFeeBPS: 200,
            vaultType: VaultFactory.VaultType.BASE_VAULT,
            extraData: ""
        });
        
        // Set vault template first
        factory.setVaultTemplate(VaultFactory.VaultType.BASE_VAULT, address(vault));
        
        (address deployedVault, bytes32 vaultHash) = factory.deployVault{value: 0.1 ether}(
            config,
            bytes32("test")
        );
        
        vm.stopPrank();
        
        assertTrue(deployedVault != address(0));
        assertTrue(vaultHash != bytes32(0));
        
        VaultFactory.DeployedVault memory vaultInfo = factory.getVaultInfo(vaultHash);
        assertEq(vaultInfo.vaultAddress, deployedVault);
        assertEq(vaultInfo.asset, address(token));
        assertTrue(vaultInfo.active);
    }
    
    function testSlippageProtection() public {
        // This would test slippage protection in strategy operations
        // Implementation would depend on DEX integration details
    }
    
    function testPreviewFunctions() public {
        uint256 assets = 1000 * 1e18;
        uint256 shares = vault.previewDeposit(assets);
        assertEq(shares, assets); // 1:1 initially
        
        uint256 previewAssets = vault.previewMint(shares);
        assertEq(previewAssets, assets);
        
        uint256 previewShares = vault.previewWithdraw(assets);
        assertEq(previewShares, assets);
        
        uint256 previewAssetsFromRedeem = vault.previewRedeem(shares);
        assertEq(previewAssetsFromRedeem, assets);
    }
    
    // Fuzz testing
    function testFuzzDeposit(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_USER_BALANCE);
        
        vm.startPrank(user1);
        token.approve(address(vault), amount);
        uint256 shares = vault.deposit(amount, user1);
        vm.stopPrank();
        
        assertEq(shares, amount);
        assertEq(vault.balanceOf(user1), amount);
        assertEq(vault.totalAssets(), amount);
    }
    
    function testFuzzWithdraw(uint256 depositAmount, uint256 withdrawAmount) public {
        depositAmount = bound(depositAmount, 1000, INITIAL_USER_BALANCE);
        withdrawAmount = bound(withdrawAmount, 1, depositAmount);
        
        vm.startPrank(user1);
        token.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        
        uint256 shares = vault.withdraw(withdrawAmount, user1, user1);
        vm.stopPrank();
        
        assertEq(shares, withdrawAmount);
        assertEq(vault.balanceOf(user1), depositAmount - withdrawAmount);
    }
    
    receive() external payable {}
}