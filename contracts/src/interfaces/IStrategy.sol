// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IStrategy
 * @dev Interface for yield strategies
 */
interface IStrategy {
    /// @notice Emitted when assets are invested
    event Invested(uint256 amount);
    
    /// @notice Emitted when assets are withdrawn
    event Withdrawn(uint256 amount);
    
    /// @notice Emitted when yield is harvested
    event Harvested(uint256 yieldAmount);

    /**
     * @notice Get the underlying asset this strategy supports
     * @return asset Address of the underlying ERC20 token
     */
    function asset() external view returns (address asset);

    /**
     * @notice Get current APY for this strategy
     * @return apy Current annualized percentage yield
     */
    function getAPY() external view returns (uint256 apy);

    /**
     * @notice Get total assets managed by this strategy
     * @return totalAssets Amount of underlying assets
     */
    function totalAssets() external view returns (uint256 totalAssets);

    /**
     * @notice Invest assets into the strategy
     * @param amount Amount of assets to invest
     * @return invested Actual amount invested
     */
    function invest(uint256 amount) external returns (uint256 invested);

    /**
     * @notice Withdraw assets from the strategy
     * @param amount Amount of assets to withdraw
     * @return withdrawn Actual amount withdrawn
     */
    function withdraw(uint256 amount) external returns (uint256 withdrawn);

    /**
     * @notice Harvest accumulated yield
     * @return harvested Amount of yield harvested
     */
    function harvest() external returns (uint256 harvested);

    /**
     * @notice Emergency withdraw all assets
     * @return withdrawn Amount withdrawn
     */
    function emergencyWithdraw() external returns (uint256 withdrawn);

    /**
     * @notice Check if strategy is active
     * @return active True if strategy can accept deposits
     */
    function isActive() external view returns (bool active);

    /**
     * @notice Get maximum investable amount
     * @return maxInvestable Maximum amount that can be invested
     */
    function maxInvestable() external view returns (uint256 maxInvestable);

    /**
     * @notice Get strategy risk level (1-10 scale)
     * @return riskLevel Risk level of the strategy
     */
    function getRiskLevel() external view returns (uint8 riskLevel);
}