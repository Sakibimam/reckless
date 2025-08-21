// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/interfaces/IERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./interfaces/IERC4626Vault.sol";
import "./interfaces/IStrategy.sol";
import "./ShareToken.sol";

/**
 * @title YieldVault
 * @dev Enhanced ERC4626-compliant vault for yield optimization with cross-chain capabilities
 * @notice This vault manages multiple yield strategies and automatically rebalances for optimal returns
 */
contract YieldVault is IERC4626Vault, ReentrancyGuard, Pausable, AccessControl {
    using SafeERC20 for IERC20;
    using Math for uint256;

    // Roles
    bytes32 public constant STRATEGY_MANAGER_ROLE = keccak256("STRATEGY_MANAGER_ROLE");
    bytes32 public constant VAULT_MANAGER_ROLE = keccak256("VAULT_MANAGER_ROLE");
    bytes32 public constant DEPOSITOR_ROLE = keccak256("DEPOSITOR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // Constants
    uint256 public constant MAX_BPS = 10_000; // 100% in basis points
    uint256 public constant PERFORMANCE_FEE_BPS = 1000; // 10%
    uint256 public constant MANAGEMENT_FEE_BPS = 200; // 2% annually
    uint256 public constant SECONDS_PER_YEAR = 31_536_000;
    uint256 public constant MIN_LIQUIDITY = 1000; // Minimum liquidity to prevent attacks
    uint256 public constant MAX_STRATEGIES = 10; // Maximum number of strategies

    // Core vault properties
    IERC20 private immutable _asset;
    ShareToken private immutable _shareToken;
    uint8 private immutable _decimals;
    string private _name;
    string private _symbol;

    // Strategy management
    struct StrategyInfo {
        IStrategy strategy;
        uint256 allocation; // Basis points (0-10000)
        bool active;
        uint256 lastHarvest;
        uint256 totalDeposited;
        uint256 totalWithdrawn;
        uint256 maxLoss; // Maximum acceptable loss in basis points
        uint256 lastUpdate;
    }

    mapping(address => StrategyInfo) public strategies;
    address[] public strategyList;
    uint256 public totalStrategiesAllocation;

    // Fee management
    uint256 public lastFeeCollection;
    uint256 public totalPerformanceFees;
    uint256 public totalManagementFees;
    address public feeRecipient;

    // Risk management
    uint256 public maxSlippageBPS = 100; // 1%
    uint256 public maxDepositAmount = type(uint256).max;
    uint256 public emergencyShutdownTime;
    bool public emergencyShutdown;
    uint256 public lastRebalance;
    uint256 public rebalanceInterval = 1 days;

    // Performance tracking
    uint256 public highWaterMark;
    uint256 public totalDeposits;
    uint256 public totalWithdrawals;
    uint256 public lastPricePerShare;

    // Events
    event StrategyAdded(address indexed strategy, uint256 allocation, uint256 maxLoss);
    event StrategyRemoved(address indexed strategy);
    event StrategyAllocationUpdated(address indexed strategy, uint256 oldAllocation, uint256 newAllocation);
    event PerformanceFeeCollected(uint256 amount, address indexed recipient);
    event ManagementFeeCollected(uint256 amount, address indexed recipient);
    event EmergencyShutdownActivated(uint256 timestamp, address indexed activator);
    event SlippageProtectionTriggered(uint256 expectedAssets, uint256 actualAssets, uint256 slippage);
    event VaultRebalanced(uint256 totalAssets, uint256 timestamp);
    event HighWaterMarkUpdated(uint256 oldMark, uint256 newMark);
    event MaxDepositUpdated(uint256 oldMax, uint256 newMax);

    modifier onlyStrategyManager() {
        require(hasRole(STRATEGY_MANAGER_ROLE, msg.sender), "YV: Not strategy manager");
        _;
    }

    modifier onlyVaultManager() {
        require(hasRole(VAULT_MANAGER_ROLE, msg.sender), "YV: Not vault manager");
        _;
    }

    modifier onlyDepositor() {
        require(hasRole(DEPOSITOR_ROLE, msg.sender) || hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "YV: Not authorized depositor");
        _;
    }

    modifier notEmergencyShutdown() {
        require(!emergencyShutdown, "YV: Emergency shutdown active");
        _;
    }

    modifier validStrategy(address strategyAddr) {
        require(strategyAddr != address(0), "YV: Invalid strategy address");
        require(strategies[strategyAddr].strategy != IStrategy(address(0)), "YV: Strategy not found");
        _;
    }

    constructor(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        address admin_,
        address feeRecipient_
    ) {
        require(address(asset_) != address(0), "YV: Invalid asset");
        require(admin_ != address(0), "YV: Invalid admin");
        require(feeRecipient_ != address(0), "YV: Invalid fee recipient");

        _asset = asset_;
        _name = name_;
        _symbol = symbol_;
        _decimals = IERC20Metadata(address(asset_)).decimals();
        
        // Deploy share token
        _shareToken = new ShareToken(name_, symbol_, _decimals);
        
        // Setup roles
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(ADMIN_ROLE, admin_);
        _grantRole(STRATEGY_MANAGER_ROLE, admin_);
        _grantRole(VAULT_MANAGER_ROLE, admin_);
        _grantRole(DEPOSITOR_ROLE, admin_);
        _grantRole(PAUSER_ROLE, admin_);
        
        feeRecipient = feeRecipient_;
        lastFeeCollection = block.timestamp;
        lastRebalance = block.timestamp;
        highWaterMark = 10**_decimals; // Start at 1.0 price per share
        lastPricePerShare = highWaterMark;
    }

    /*//////////////////////////////////////////////////////////////
                        ERC4626 IMPLEMENTATION
    //////////////////////////////////////////////////////////////*/

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function asset() public view override returns (address) {
        return address(_asset);
    }

    function totalSupply() public view returns (uint256) {
        return _shareToken.totalSupply();
    }

    function balanceOf(address account) public view returns (uint256) {
        return _shareToken.balanceOf(account);
    }

    function totalAssets() public view override returns (uint256) {
        uint256 vaultBalance = _asset.balanceOf(address(this));
        uint256 strategiesBalance = 0;
        
        for (uint256 i = 0; i < strategyList.length; i++) {
            address strategyAddr = strategyList[i];
            StrategyInfo storage info = strategies[strategyAddr];
            if (info.active) {
                strategiesBalance += info.strategy.totalAssets();
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
        return maxDepositAmount;
    }

    function maxMint(address receiver) public view override returns (uint256) {
        uint256 maxAssets = maxDeposit(receiver);
        return maxAssets == type(uint256).max ? type(uint256).max : convertToShares(maxAssets);
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        return convertToAssets(balanceOf(owner));
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
        onlyDepositor
        nonReentrant 
        whenNotPaused 
        notEmergencyShutdown 
        returns (uint256 shares) 
    {
        require(assets <= maxDeposit(receiver), "YV: Exceeds max deposit");
        require(assets > 0, "YV: Invalid deposit amount");
        
        shares = previewDeposit(assets);
        require(shares > 0, "YV: Zero shares");
        
        _deposit(msg.sender, receiver, assets, shares);
        return shares;
    }

    function mint(uint256 shares, address receiver) 
        public 
        override 
        onlyDepositor
        nonReentrant 
        whenNotPaused 
        notEmergencyShutdown 
        returns (uint256 assets) 
    {
        require(shares <= maxMint(receiver), "YV: Exceeds max mint");
        require(shares > 0, "YV: Invalid mint amount");
        
        assets = previewMint(shares);
        _deposit(msg.sender, receiver, assets, shares);
        return assets;
    }

    function withdraw(uint256 assets, address receiver, address owner) 
        public 
        override 
        nonReentrant 
        returns (uint256 shares) 
    {
        require(assets <= maxWithdraw(owner), "YV: Exceeds max withdraw");
        require(assets > 0, "YV: Invalid withdraw amount");
        
        shares = previewWithdraw(assets);
        _withdraw(msg.sender, receiver, owner, assets, shares);
        return shares;
    }

    function redeem(uint256 shares, address receiver, address owner) 
        public 
        override 
        nonReentrant 
        returns (uint256 assets) 
    {
        require(shares <= maxRedeem(owner), "YV: Exceeds max redeem");
        require(shares > 0, "YV: Invalid redeem amount");
        
        assets = previewRedeem(shares);
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
            StrategyInfo storage info = strategies[strategyAddr];
            if (info.active) {
                uint256 strategyAssets = info.strategy.totalAssets();
                if (strategyAssets > 0) {
                    uint256 weight = (strategyAssets * MAX_BPS) / totalAssets_;
                    uint256 strategyAPY = info.strategy.getAPY();
                    weightedAPY += (strategyAPY * weight) / MAX_BPS;
                }
            }
        }
        
        // Subtract management fee from total APY
        apy = weightedAPY > MANAGEMENT_FEE_BPS ? weightedAPY - MANAGEMENT_FEE_BPS : 0;
    }

    function getTotalValueLocked() public view override returns (uint256 tvl) {
        return totalAssets();
    }

    function getStrategyAllocation(address strategy) public view override returns (uint256 allocation) {
        return strategies[strategy].allocation;
    }

    function getPricePerShare() public view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return 10**_decimals; // 1.0 when no shares
        return (totalAssets() * 10**_decimals) / supply;
    }

    function emergencyWithdraw(uint256 shares, address receiver) 
        external 
        override 
        nonReentrant 
        returns (uint256 assets) 
    {
        require(
            emergencyShutdown || hasRole(VAULT_MANAGER_ROLE, msg.sender), 
            "YV: Emergency not active or not authorized"
        );
        require(shares <= balanceOf(msg.sender), "YV: Insufficient shares");
        require(shares > 0, "YV: Invalid shares amount");
        
        assets = _convertToAssets(shares, Math.Rounding.Down);
        
        // Emergency withdraw from strategies if needed
        uint256 vaultBalance = _asset.balanceOf(address(this));
        if (vaultBalance < assets) {
            _emergencyWithdrawFromStrategies(assets - vaultBalance);
        }
        
        _shareToken.burn(msg.sender, shares);
        
        // Ensure we have enough assets after emergency withdrawal
        uint256 actualBalance = _asset.balanceOf(address(this));
        uint256 transferAmount = Math.min(assets, actualBalance);
        
        if (transferAmount > 0) {
            _asset.safeTransfer(receiver, transferAmount);
        }
        
        emit EmergencyWithdrawal(msg.sender, transferAmount, shares);
        return transferAmount;
    }

    function harvestYield() external override nonReentrant returns (uint256 totalHarvested) {
        _collectManagementFees();
        
        uint256 beforeBalance = _asset.balanceOf(address(this));
        
        for (uint256 i = 0; i < strategyList.length; i++) {
            address strategyAddr = strategyList[i];
            StrategyInfo storage info = strategies[strategyAddr];
            if (info.active) {
                try info.strategy.harvest() returns (uint256 harvested) {
                    if (harvested > 0) {
                        totalHarvested += harvested;
                        info.lastHarvest = block.timestamp;
                        emit YieldHarvested(strategyAddr, harvested);
                    }
                } catch {
                    // Continue with other strategies if one fails
                    continue;
                }
            }
        }
        
        uint256 afterBalance = _asset.balanceOf(address(this));
        uint256 actualHarvested = afterBalance > beforeBalance ? afterBalance - beforeBalance : 0;
        
        if (actualHarvested > 0) {
            _collectPerformanceFees(actualHarvested);
            _updateHighWaterMark();
        }
        
        return actualHarvested;
    }

    /*//////////////////////////////////////////////////////////////
                        STRATEGY MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    function addStrategy(
        address strategy, 
        uint256 allocation,
        uint256 maxLoss
    ) external onlyStrategyManager whenNotPaused {
        require(strategy != address(0), "YV: Invalid strategy");
        require(allocation > 0 && allocation <= MAX_BPS, "YV: Invalid allocation");
        require(maxLoss <= 1000, "YV: Max loss too high"); // Max 10%
        require(strategies[strategy].strategy == IStrategy(address(0)), "YV: Strategy exists");
        require(totalStrategiesAllocation + allocation <= MAX_BPS, "YV: Exceeds max allocation");
        require(strategyList.length < MAX_STRATEGIES, "YV: Too many strategies");
        
        IStrategy strategyContract = IStrategy(strategy);
        require(strategyContract.asset() == address(_asset), "YV: Asset mismatch");
        require(strategyContract.isActive(), "YV: Strategy not active");
        
        strategies[strategy] = StrategyInfo({
            strategy: strategyContract,
            allocation: allocation,
            active: true,
            lastHarvest: block.timestamp,
            totalDeposited: 0,
            totalWithdrawn: 0,
            maxLoss: maxLoss,
            lastUpdate: block.timestamp
        });
        
        strategyList.push(strategy);
        totalStrategiesAllocation += allocation;
        
        emit StrategyAdded(strategy, allocation, maxLoss);
    }

    function removeStrategy(address strategy) external onlyStrategyManager validStrategy(strategy) {
        StrategyInfo storage info = strategies[strategy];
        
        // Emergency withdraw all funds from strategy
        uint256 withdrawn = 0;
        try info.strategy.emergencyWithdraw() returns (uint256 amount) {
            withdrawn = amount;
            info.totalWithdrawn += amount;
        } catch {
            // Strategy might be broken, continue with removal
        }
        
        totalStrategiesAllocation -= info.allocation;
        
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

    function updateStrategyAllocation(
        address strategy, 
        uint256 newAllocation
    ) external onlyStrategyManager validStrategy(strategy) {
        require(newAllocation <= MAX_BPS, "YV: Invalid allocation");
        
        StrategyInfo storage info = strategies[strategy];
        uint256 oldAllocation = info.allocation;
        uint256 newTotal = totalStrategiesAllocation - oldAllocation + newAllocation;
        require(newTotal <= MAX_BPS, "YV: Exceeds max allocation");
        
        info.allocation = newAllocation;
        info.lastUpdate = block.timestamp;
        totalStrategiesAllocation = newTotal;
        
        emit StrategyAllocationUpdated(strategy, oldAllocation, newAllocation);
    }

    function rebalance() external onlyVaultManager nonReentrant {
        require(block.timestamp >= lastRebalance + rebalanceInterval, "YV: Too early for rebalance");
        
        _collectManagementFees();
        uint256 totalAssets_ = totalAssets();
        
        if (totalAssets_ == 0) return;
        
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
                        try info.strategy.invest(toDeposit) returns (uint256 invested) {
                            info.totalDeposited += invested;
                        } catch {
                            // If investment fails, funds are still in strategy
                            info.totalDeposited += toDeposit;
                        }
                    }
                } else if (targetAssets < currentAssets && currentAssets > 0) {
                    // Need to withdraw excess
                    uint256 toWithdraw = currentAssets - targetAssets;
                    try info.strategy.withdraw(toWithdraw) returns (uint256 withdrawn) {
                        info.totalWithdrawn += withdrawn;
                    } catch {
                        // Continue if withdrawal fails
                        continue;
                    }
                }
            }
        }
        
        lastRebalance = block.timestamp;
        emit VaultRebalanced(totalAssets_, block.timestamp);
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
        emit EmergencyShutdownActivated(block.timestamp, msg.sender);
    }

    function setFeeRecipient(address newFeeRecipient) external onlyRole(ADMIN_ROLE) {
        require(newFeeRecipient != address(0), "YV: Invalid fee recipient");
        feeRecipient = newFeeRecipient;
    }

    function setMaxSlippage(uint256 newMaxSlippageBPS) external onlyVaultManager {
        require(newMaxSlippageBPS <= 1000, "YV: Slippage too high"); // Max 10%
        maxSlippageBPS = newMaxSlippageBPS;
    }

    function setMaxDepositAmount(uint256 newMaxDeposit) external onlyVaultManager {
        uint256 oldMax = maxDepositAmount;
        maxDepositAmount = newMaxDeposit;
        emit MaxDepositUpdated(oldMax, newMaxDeposit);
    }

    function setRebalanceInterval(uint256 newInterval) external onlyVaultManager {
        require(newInterval >= 1 hours, "YV: Interval too short");
        rebalanceInterval = newInterval;
    }

    function recoverToken(address token, uint256 amount) external onlyRole(ADMIN_ROLE) {
        require(token != address(_asset), "YV: Cannot recover main asset");
        require(token != address(_shareToken), "YV: Cannot recover share token");
        IERC20(token).safeTransfer(msg.sender, amount);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal {
        // Transfer assets from caller
        _asset.safeTransferFrom(caller, address(this), assets);
        
        // Mint shares to receiver
        _shareToken.mint(receiver, shares);
        
        // Update tracking
        totalDeposits += assets;
        
        emit Deposit(caller, receiver, assets, shares);
        
        // Auto-rebalance if significant deposit (> 5% of TVL)
        if (assets > totalAssets() / 20 && block.timestamp >= lastRebalance + (rebalanceInterval / 2)) {
            _autoRebalance();
        }
    }

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares) internal {
        // Check allowance if caller is not owner
        if (caller != owner) {
            uint256 allowed = _shareToken.allowance(owner, caller);
            require(allowed >= shares, "YV: Insufficient allowance");
            _shareToken.decreaseAllowance(owner, caller, shares);
        }
        
        // Ensure we have enough liquid assets
        uint256 vaultBalance = _asset.balanceOf(address(this));
        if (vaultBalance < assets) {
            _withdrawFromStrategies(assets - vaultBalance);
        }
        
        // Burn shares
        _shareToken.burn(owner, shares);
        
        // Transfer assets
        uint256 actualBalance = _asset.balanceOf(address(this));
        uint256 transferAmount = Math.min(assets, actualBalance);
        
        if (transferAmount > 0) {
            _asset.safeTransfer(receiver, transferAmount);
        }
        
        // Update tracking
        totalWithdrawals += transferAmount;
        
        // Check for slippage
        if (transferAmount < assets) {
            uint256 slippage = ((assets - transferAmount) * MAX_BPS) / assets;
            require(slippage <= maxSlippageBPS, "YV: Excessive slippage");
            emit SlippageProtectionTriggered(assets, transferAmount, slippage);
        }
        
        emit Withdraw(caller, receiver, owner, transferAmount, shares);
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
                    uint256 totalStrategiesAssets = totalAssets() - _asset.balanceOf(address(this));
                    uint256 withdrawRatio = totalStrategiesAssets > 0 ? 
                        (strategyAssets * MAX_BPS) / totalStrategiesAssets : 0;
                    
                    uint256 toWithdraw = Math.min(
                        (neededAssets * withdrawRatio) / MAX_BPS,
                        Math.min(neededAssets - totalWithdrawn, strategyAssets)
                    );
                    
                    if (toWithdraw > 0) {
                        try info.strategy.withdraw(toWithdraw) returns (uint256 withdrawn) {
                            info.totalWithdrawn += withdrawn;
                            totalWithdrawn += withdrawn;
                        } catch {
                            // Continue with other strategies if withdrawal fails
                            continue;
                        }
                    }
                }
            }
        }
    }

    function _emergencyWithdrawFromStrategies(uint256 neededAssets) internal {
        uint256 totalWithdrawn = 0;
        
        for (uint256 i = 0; i < strategyList.length && totalWithdrawn < neededAssets; i++) {
            address strategyAddr = strategyList[i];
            StrategyInfo storage info = strategies[strategyAddr];
            
            if (info.active) {
                try info.strategy.emergencyWithdraw() returns (uint256 withdrawn) {
                    info.totalWithdrawn += withdrawn;
                    totalWithdrawn += withdrawn;
                } catch {
                    // Continue with other strategies
                    continue;
                }
            }
        }
    }

    function _autoRebalance() internal {
        uint256 vaultBalance = _asset.balanceOf(address(this));
        uint256 totalAssets_ = totalAssets();
        
        // Only auto-rebalance if we have > 10% idle cash
        if (vaultBalance > totalAssets_ / 10) {
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
                            try info.strategy.invest(toDeposit) returns (uint256 invested) {
                                info.totalDeposited += invested;
                            } catch {
                                info.totalDeposited += toDeposit;
                            }
                            vaultBalance -= toDeposit;
                        }
                    }
                }
            }
        }
    }

    function _collectPerformanceFees(uint256 yieldAmount) internal {
        if (yieldAmount == 0 || feeRecipient == address(0)) return;
        
        uint256 feeAmount = (yieldAmount * PERFORMANCE_FEE_BPS) / MAX_BPS;
        if (feeAmount > 0) {
            uint256 feeShares = _convertToShares(feeAmount, Math.Rounding.Down);
            if (feeShares > 0) {
                _shareToken.mint(feeRecipient, feeShares);
                totalPerformanceFees += feeAmount;
                emit PerformanceFeeCollected(feeAmount, feeRecipient);
            }
        }
    }

    function _collectManagementFees() internal {
        uint256 timeSinceLastCollection = block.timestamp - lastFeeCollection;
        uint256 totalAssets_ = totalAssets();
        
        if (timeSinceLastCollection > 0 && totalAssets_ > 0 && feeRecipient != address(0)) {
            uint256 feeAmount = (totalAssets_ * MANAGEMENT_FEE_BPS * timeSinceLastCollection) / 
                               (MAX_BPS * SECONDS_PER_YEAR);
            
            if (feeAmount > 0) {
                uint256 feeShares = _convertToShares(feeAmount, Math.Rounding.Down);
                if (feeShares > 0) {
                    _shareToken.mint(feeRecipient, feeShares);
                    totalManagementFees += feeAmount;
                    lastFeeCollection = block.timestamp;
                    emit ManagementFeeCollected(feeAmount, feeRecipient);
                }
            }
        }
    }

    function _updateHighWaterMark() internal {
        uint256 currentPricePerShare = getPricePerShare();
        if (currentPricePerShare > highWaterMark) {
            uint256 oldMark = highWaterMark;
            highWaterMark = currentPricePerShare;
            emit HighWaterMarkUpdated(oldMark, highWaterMark);
        }
        lastPricePerShare = currentPricePerShare;
    }

    function _convertToShares(uint256 assets, Math.Rounding rounding) internal view returns (uint256) {
        uint256 supply = totalSupply();
        return supply == 0 ? assets : assets.mulDiv(supply, totalAssets(), rounding);
    }

    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view returns (uint256) {
        uint256 supply = totalSupply();
        return supply == 0 ? shares : shares.mulDiv(totalAssets(), supply, rounding);
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getStrategyInfo(address strategy) external view returns (
        address strategyAddress,
        uint256 allocation,
        bool active,
        uint256 totalAssets_,
        uint256 lastHarvest,
        uint256 apy
    ) {
        StrategyInfo storage info = strategies[strategy];
        return (
            address(info.strategy),
            info.allocation,
            info.active,
            address(info.strategy) != address(0) ? info.strategy.totalAssets() : 0,
            info.lastHarvest,
            address(info.strategy) != address(0) ? info.strategy.getAPY() : 0
        );
    }

    function getAllStrategies() external view returns (address[] memory) {
        return strategyList;
    }

    function getVaultStats() external view returns (
        uint256 totalAssets_,
        uint256 totalSupply_,
        uint256 pricePerShare,
        uint256 currentAPY,
        uint256 totalStrategies
    ) {
        return (
            totalAssets(),
            totalSupply(),
            getPricePerShare(),
            getCurrentAPY(),
            strategyList.length
        );
    }

    function paused() public view override returns (bool) {
        return super.paused();
    }
}