// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./interfaces/IERC4626Vault.sol";
import "./interfaces/IStrategy.sol";

/**
 * @title BaseVault
 * @dev ERC4626-compliant vault with yield optimization strategies
 */
contract BaseVault is ERC20, IERC4626Vault, ReentrancyGuard, Pausable, AccessControl {
    using SafeERC20 for IERC20;
    using Math for uint256;

    bytes32 public constant STRATEGY_MANAGER_ROLE = keccak256("STRATEGY_MANAGER_ROLE");
    bytes32 public constant VAULT_MANAGER_ROLE = keccak256("VAULT_MANAGER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    uint256 public constant MAX_BPS = 10_000; // 100% in basis points
    uint256 public constant PERFORMANCE_FEE_BPS = 1000; // 10%
    uint256 public constant MANAGEMENT_FEE_BPS = 200; // 2% annually
    uint256 public constant SECONDS_PER_YEAR = 31_536_000;

    IERC20 private immutable _asset;
    uint8 private immutable _decimals;

    struct StrategyInfo {
        IStrategy strategy;
        uint256 allocation; // Basis points (0-10000)
        bool active;
        uint256 lastHarvest;
        uint256 totalDeposited;
        uint256 totalWithdrawn;
    }

    mapping(address => StrategyInfo) public strategies;
    address[] public strategyList;
    
    uint256 public totalStrategiesAllocation;
    uint256 public lastFeeCollection;
    uint256 public totalPerformanceFees;
    uint256 public totalManagementFees;
    
    address public feeRecipient;
    uint256 public maxSlippageBPS = 100; // 1%
    uint256 public emergencyShutdownTime;
    bool public emergencyShutdown;

    event StrategyAdded(address indexed strategy, uint256 allocation);
    event StrategyRemoved(address indexed strategy);
    event StrategyAllocationUpdated(address indexed strategy, uint256 newAllocation);
    event PerformanceFeeCollected(uint256 amount);
    event ManagementFeeCollected(uint256 amount);
    event EmergencyShutdownActivated(uint256 timestamp);
    event SlippageProtectionTriggered(uint256 expectedAssets, uint256 actualAssets);

    modifier onlyStrategyManager() {
        require(hasRole(STRATEGY_MANAGER_ROLE, msg.sender), "Not strategy manager");
        _;
    }

    modifier onlyVaultManager() {
        require(hasRole(VAULT_MANAGER_ROLE, msg.sender), "Not vault manager");
        _;
    }

    modifier notEmergencyShutdown() {
        require(!emergencyShutdown, "Emergency shutdown active");
        _;
    }

    constructor(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        address admin_,
        address feeRecipient_
    ) ERC20(name_, symbol_) {
        _asset = asset_;
        _decimals = IERC20Metadata(address(asset_)).decimals();
        
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(STRATEGY_MANAGER_ROLE, admin_);
        _grantRole(VAULT_MANAGER_ROLE, admin_);
        _grantRole(PAUSER_ROLE, admin_);
        
        feeRecipient = feeRecipient_;
        lastFeeCollection = block.timestamp;
    }

    /*//////////////////////////////////////////////////////////////
                        ERC4626 IMPLEMENTATION
    //////////////////////////////////////////////////////////////*/

    function asset() public view override returns (address) {
        return address(_asset);
    }

    function decimals() public view override(ERC20, IERC4626) returns (uint8) {
        return _decimals;
    }

    function totalAssets() public view override returns (uint256) {
        uint256 vaultBalance = _asset.balanceOf(address(this));
        uint256 strategiesBalance = 0;
        
        for (uint256 i = 0; i < strategyList.length; i++) {
            address strategyAddr = strategyList[i];
            if (strategies[strategyAddr].active) {
                strategiesBalance += strategies[strategyAddr].strategy.totalAssets();
            }
        }
        
        return vaultBalance + strategiesBalance;
    }

    function convertToShares(uint256 assets) public view override returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Down);
    }

    function convertToAssets(uint256 shares) public view override returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Down);
    }

    function maxDeposit(address) public view override returns (uint256) {
        if (paused() || emergencyShutdown) return 0;
        return type(uint256).max;
    }

    function maxMint(address) public view override returns (uint256) {
        if (paused() || emergencyShutdown) return 0;
        return type(uint256).max;
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        return _convertToAssets(balanceOf(owner), Math.Rounding.Down);
    }

    function maxRedeem(address owner) public view override returns (uint256) {
        return balanceOf(owner);
    }

    function previewDeposit(uint256 assets) public view override returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Down);
    }

    function previewMint(uint256 shares) public view override returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Up);
    }

    function previewWithdraw(uint256 assets) public view override returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Up);
    }

    function previewRedeem(uint256 shares) public view override returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Down);
    }

    function deposit(uint256 assets, address receiver) 
        public 
        override 
        nonReentrant 
        whenNotPaused 
        notEmergencyShutdown 
        returns (uint256) 
    {
        require(assets <= maxDeposit(receiver), "Exceeds max deposit");
        uint256 shares = previewDeposit(assets);
        
        _deposit(msg.sender, receiver, assets, shares);
        return shares;
    }

    function mint(uint256 shares, address receiver) 
        public 
        override 
        nonReentrant 
        whenNotPaused 
        notEmergencyShutdown 
        returns (uint256) 
    {
        require(shares <= maxMint(receiver), "Exceeds max mint");
        uint256 assets = previewMint(shares);
        
        _deposit(msg.sender, receiver, assets, shares);
        return assets;
    }

    function withdraw(uint256 assets, address receiver, address owner) 
        public 
        override 
        nonReentrant 
        returns (uint256) 
    {
        require(assets <= maxWithdraw(owner), "Exceeds max withdraw");
        uint256 shares = previewWithdraw(assets);
        
        _withdraw(msg.sender, receiver, owner, assets, shares);
        return shares;
    }

    function redeem(uint256 shares, address receiver, address owner) 
        public 
        override 
        nonReentrant 
        returns (uint256) 
    {
        require(shares <= maxRedeem(owner), "Exceeds max redeem");
        uint256 assets = previewRedeem(shares);
        
        _withdraw(msg.sender, receiver, owner, assets, shares);
        return assets;
    }

    /*//////////////////////////////////////////////////////////////
                        VAULT-SPECIFIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getCurrentAPY() public view override returns (uint256 apy) {
        uint256 totalAssets_ = totalAssets();
        if (totalAssets_ == 0) return 0;
        
        uint256 weightedAPY = 0;
        for (uint256 i = 0; i < strategyList.length; i++) {
            address strategyAddr = strategyList[i];
            StrategyInfo memory info = strategies[strategyAddr];
            if (info.active) {
                uint256 strategyAssets = info.strategy.totalAssets();
                uint256 weight = (strategyAssets * MAX_BPS) / totalAssets_;
                weightedAPY += (info.strategy.getAPY() * weight) / MAX_BPS;
            }
        }
        
        // Subtract management fee
        apy = weightedAPY > MANAGEMENT_FEE_BPS ? weightedAPY - MANAGEMENT_FEE_BPS : 0;
    }

    function getTotalValueLocked() public view override returns (uint256 tvl) {
        return totalAssets();
    }

    function getStrategyAllocation(address strategy) public view override returns (uint256 allocation) {
        return strategies[strategy].allocation;
    }

    function emergencyWithdraw(uint256 shares, address receiver) 
        external 
        override 
        nonReentrant 
        returns (uint256 assets) 
    {
        require(emergencyShutdown || hasRole(VAULT_MANAGER_ROLE, msg.sender), "Emergency not active");
        require(shares <= balanceOf(msg.sender), "Insufficient shares");
        
        assets = _convertToAssets(shares, Math.Rounding.Down);
        
        // Emergency withdraw from strategies if needed
        uint256 vaultBalance = _asset.balanceOf(address(this));
        if (vaultBalance < assets) {
            _emergencyWithdrawFromStrategies(assets - vaultBalance);
        }
        
        _burn(msg.sender, shares);
        _asset.safeTransfer(receiver, assets);
        
        emit EmergencyWithdrawal(msg.sender, assets, shares);
    }

    function harvestYield() external override nonReentrant returns (uint256 totalHarvested) {
        _collectManagementFees();
        
        for (uint256 i = 0; i < strategyList.length; i++) {
            address strategyAddr = strategyList[i];
            StrategyInfo storage info = strategies[strategyAddr];
            if (info.active) {
                uint256 harvested = info.strategy.harvest();
                if (harvested > 0) {
                    totalHarvested += harvested;
                    info.lastHarvest = block.timestamp;
                    emit YieldHarvested(strategyAddr, harvested);
                }
            }
        }
        
        if (totalHarvested > 0) {
            _collectPerformanceFees(totalHarvested);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        STRATEGY MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    function addStrategy(address strategy, uint256 allocation) 
        external 
        onlyStrategyManager 
        whenNotPaused 
    {
        require(strategy != address(0), "Invalid strategy");
        require(allocation > 0 && allocation <= MAX_BPS, "Invalid allocation");
        require(strategies[strategy].strategy == IStrategy(address(0)), "Strategy exists");
        require(totalStrategiesAllocation + allocation <= MAX_BPS, "Exceeds max allocation");
        
        IStrategy strategyContract = IStrategy(strategy);
        require(strategyContract.asset() == address(_asset), "Asset mismatch");
        
        strategies[strategy] = StrategyInfo({
            strategy: strategyContract,
            allocation: allocation,
            active: true,
            lastHarvest: block.timestamp,
            totalDeposited: 0,
            totalWithdrawn: 0
        });
        
        strategyList.push(strategy);
        totalStrategiesAllocation += allocation;
        
        emit StrategyAdded(strategy, allocation);
    }

    function removeStrategy(address strategy) external onlyStrategyManager {
        require(strategies[strategy].strategy != IStrategy(address(0)), "Strategy not found");
        
        // Emergency withdraw all funds from strategy
        uint256 withdrawn = strategies[strategy].strategy.emergencyWithdraw();
        if (withdrawn > 0) {
            strategies[strategy].totalWithdrawn += withdrawn;
        }
        
        totalStrategiesAllocation -= strategies[strategy].allocation;
        
        // Remove from array
        for (uint256 i = 0; i < strategyList.length; i++) {
            if (strategyList[i] == strategy) {
                strategyList[i] = strategyList[strategyList.length - 1];
                strategyList.pop();
                break;
            }
        }
        
        delete strategies[strategy];
        emit StrategyRemoved(strategy);
    }

    function updateStrategyAllocation(address strategy, uint256 newAllocation) 
        external 
        onlyStrategyManager 
    {
        require(strategies[strategy].strategy != IStrategy(address(0)), "Strategy not found");
        require(newAllocation <= MAX_BPS, "Invalid allocation");
        
        uint256 oldAllocation = strategies[strategy].allocation;
        uint256 newTotal = totalStrategiesAllocation - oldAllocation + newAllocation;
        require(newTotal <= MAX_BPS, "Exceeds max allocation");
        
        strategies[strategy].allocation = newAllocation;
        totalStrategiesAllocation = newTotal;
        
        emit StrategyAllocationUpdated(strategy, newAllocation);
    }

    function rebalance() external onlyVaultManager nonReentrant {
        uint256 totalAssets_ = totalAssets();
        if (totalAssets_ == 0) return;
        
        // Calculate target allocations
        for (uint256 i = 0; i < strategyList.length; i++) {
            address strategyAddr = strategyList[i];
            StrategyInfo storage info = strategies[strategyAddr];
            if (info.active) {
                uint256 targetAssets = (totalAssets_ * info.allocation) / MAX_BPS;
                uint256 currentAssets = info.strategy.totalAssets();
                
                if (targetAssets > currentAssets) {
                    // Need to deposit more
                    uint256 toDeposit = targetAssets - currentAssets;
                    uint256 vaultBalance = _asset.balanceOf(address(this));
                    toDeposit = Math.min(toDeposit, vaultBalance);
                    
                    if (toDeposit > 0) {
                        _asset.safeTransfer(strategyAddr, toDeposit);
                        info.strategy.invest(toDeposit);
                        info.totalDeposited += toDeposit;
                    }
                } else if (targetAssets < currentAssets) {
                    // Need to withdraw excess
                    uint256 toWithdraw = currentAssets - targetAssets;
                    uint256 withdrawn = info.strategy.withdraw(toWithdraw);
                    info.totalWithdrawn += withdrawn;
                }
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
        emit VaultPaused(true);
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
        emit VaultPaused(false);
    }

    function activateEmergencyShutdown() external onlyVaultManager {
        emergencyShutdown = true;
        emergencyShutdownTime = block.timestamp;
        _pause();
        emit EmergencyShutdownActivated(block.timestamp);
    }

    function setFeeRecipient(address newFeeRecipient) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newFeeRecipient != address(0), "Invalid fee recipient");
        feeRecipient = newFeeRecipient;
    }

    function setMaxSlippage(uint256 newMaxSlippageBPS) external onlyVaultManager {
        require(newMaxSlippageBPS <= 1000, "Slippage too high"); // Max 10%
        maxSlippageBPS = newMaxSlippageBPS;
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal {
        _asset.safeTransferFrom(caller, address(this), assets);
        _mint(receiver, shares);
        
        emit Deposit(caller, receiver, assets, shares);
        
        // Auto-rebalance if significant deposit
        if (assets > totalAssets() / 20) { // > 5% of TVL
            _autoRebalance();
        }
    }

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares) internal {
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }
        
        uint256 vaultBalance = _asset.balanceOf(address(this));
        if (vaultBalance < assets) {
            _withdrawFromStrategies(assets - vaultBalance);
        }
        
        _burn(owner, shares);
        _asset.safeTransfer(receiver, assets);
        
        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    function _withdrawFromStrategies(uint256 neededAssets) internal {
        uint256 totalWithdrawn = 0;
        
        // Withdraw proportionally from strategies
        for (uint256 i = 0; i < strategyList.length && totalWithdrawn < neededAssets; i++) {
            address strategyAddr = strategyList[i];
            StrategyInfo storage info = strategies[strategyAddr];
            if (info.active) {
                uint256 strategyAssets = info.strategy.totalAssets();
                if (strategyAssets > 0) {
                    uint256 toWithdraw = Math.min(
                        (neededAssets * strategyAssets) / totalAssets(),
                        neededAssets - totalWithdrawn
                    );
                    
                    uint256 withdrawn = info.strategy.withdraw(toWithdraw);
                    info.totalWithdrawn += withdrawn;
                    totalWithdrawn += withdrawn;
                }
            }
        }
        
        require(totalWithdrawn >= neededAssets * (MAX_BPS - maxSlippageBPS) / MAX_BPS, "Slippage protection");
    }

    function _emergencyWithdrawFromStrategies(uint256 neededAssets) internal {
        uint256 totalWithdrawn = 0;
        
        for (uint256 i = 0; i < strategyList.length && totalWithdrawn < neededAssets; i++) {
            address strategyAddr = strategyList[i];
            StrategyInfo storage info = strategies[strategyAddr];
            if (info.active) {
                uint256 withdrawn = info.strategy.emergencyWithdraw();
                info.totalWithdrawn += withdrawn;
                totalWithdrawn += withdrawn;
            }
        }
    }

    function _autoRebalance() internal {
        // Simple auto-rebalancing logic
        uint256 vaultBalance = _asset.balanceOf(address(this));
        uint256 totalAssets_ = totalAssets();
        
        if (vaultBalance > totalAssets_ / 10) { // If > 10% idle
            for (uint256 i = 0; i < strategyList.length; i++) {
                address strategyAddr = strategyList[i];
                StrategyInfo storage info = strategies[strategyAddr];
                if (info.active && info.allocation > 0) {
                    uint256 targetAssets = (totalAssets_ * info.allocation) / MAX_BPS;
                    uint256 currentAssets = info.strategy.totalAssets();
                    
                    if (targetAssets > currentAssets) {
                        uint256 toDeposit = Math.min(
                            targetAssets - currentAssets,
                            vaultBalance / 4 // Deposit max 25% at a time
                        );
                        
                        if (toDeposit > 0) {
                            _asset.safeTransfer(strategyAddr, toDeposit);
                            info.strategy.invest(toDeposit);
                            info.totalDeposited += toDeposit;
                            vaultBalance -= toDeposit;
                        }
                    }
                }
            }
        }
    }

    function _collectPerformanceFees(uint256 yieldAmount) internal {
        uint256 feeAmount = (yieldAmount * PERFORMANCE_FEE_BPS) / MAX_BPS;
        if (feeAmount > 0 && feeRecipient != address(0)) {
            uint256 feeShares = _convertToShares(feeAmount, Math.Rounding.Down);
            _mint(feeRecipient, feeShares);
            totalPerformanceFees += feeAmount;
            emit PerformanceFeeCollected(feeAmount);
        }
    }

    function _collectManagementFees() internal {
        uint256 timeSinceLastCollection = block.timestamp - lastFeeCollection;
        uint256 totalAssets_ = totalAssets();
        
        if (timeSinceLastCollection > 0 && totalAssets_ > 0) {
            uint256 feeAmount = (totalAssets_ * MANAGEMENT_FEE_BPS * timeSinceLastCollection) / 
                               (MAX_BPS * SECONDS_PER_YEAR);
            
            if (feeAmount > 0 && feeRecipient != address(0)) {
                uint256 feeShares = _convertToShares(feeAmount, Math.Rounding.Down);
                _mint(feeRecipient, feeShares);
                totalManagementFees += feeAmount;
                lastFeeCollection = block.timestamp;
                emit ManagementFeeCollected(feeAmount);
            }
        }
    }

    function _convertToShares(uint256 assets, Math.Rounding rounding) internal view returns (uint256) {
        return assets.mulDiv(totalSupply() + 10**_decimals, totalAssets() + 1, rounding);
    }

    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view returns (uint256) {
        return shares.mulDiv(totalAssets() + 1, totalSupply() + 10**_decimals, rounding);
    }
}