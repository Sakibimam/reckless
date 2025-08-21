// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/interfaces/IERC4626.sol";

/**
 * @title IERC4626Vault
 * @dev Extended ERC4626 interface for yield optimization vaults
 */
interface IERC4626Vault is IERC4626 {
    /// @notice Emitted when a strategy is added or updated
    event StrategyUpdated(address indexed strategy, uint256 allocation, bool active);
    
    /// @notice Emitted when vault is paused or unpaused
    event VaultPaused(bool paused);
    
    /// @notice Emitted when emergency withdrawal is triggered
    event EmergencyWithdrawal(address indexed user, uint256 assets, uint256 shares);
    
    /// @notice Emitted when yield is harvested
    event YieldHarvested(address indexed strategy, uint256 yieldAmount);
    
    /// @notice Emitted when cross-chain deposit is initiated
    event CrossChainDeposit(
        address indexed user,
        uint16 indexed chainId,
        uint256 amount,
        bytes32 indexed txHash
    );

    /**
     * @notice Get the current APY for the vault
     * @return apy The current annualized percentage yield
     */
    function getCurrentAPY() external view returns (uint256 apy);

    /**
     * @notice Get total value locked in the vault
     * @return tvl Total value locked in underlying asset
     */
    function getTotalValueLocked() external view returns (uint256 tvl);

    /**
     * @notice Get strategy allocation for a specific strategy
     * @param strategy Address of the strategy
     * @return allocation Percentage allocation (basis points)
     */
    function getStrategyAllocation(address strategy) external view returns (uint256 allocation);

    /**
     * @notice Emergency withdraw - bypasses normal flow for security
     * @param shares Number of shares to withdraw
     * @param receiver Address to receive withdrawn assets
     * @return assets Amount of underlying assets withdrawn
     */
    function emergencyWithdraw(uint256 shares, address receiver) external returns (uint256 assets);

    /**
     * @notice Harvest yield from all active strategies
     * @return totalHarvested Total yield harvested
     */
    function harvestYield() external returns (uint256 totalHarvested);

    /**
     * @notice Check if vault is paused
     * @return paused True if vault operations are paused
     */
    function paused() external view returns (bool paused);
}