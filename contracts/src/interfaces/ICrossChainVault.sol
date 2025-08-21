// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ICrossChainVault
 * @dev Interface for cross-chain vault operations
 */
interface ICrossChainVault {
    /// @notice Emitted when cross-chain deposit is initiated
    event CrossChainDepositInitiated(
        address indexed user,
        uint16 indexed destinationChain,
        uint256 amount,
        bytes32 indexed nonce
    );
    
    /// @notice Emitted when cross-chain deposit is completed
    event CrossChainDepositCompleted(
        address indexed user,
        uint16 indexed sourceChain,
        uint256 amount,
        uint256 shares,
        bytes32 indexed nonce
    );
    
    /// @notice Emitted when cross-chain withdrawal is initiated
    event CrossChainWithdrawalInitiated(
        address indexed user,
        uint16 indexed destinationChain,
        uint256 shares,
        bytes32 indexed nonce
    );

    /**
     * @notice Initiate cross-chain deposit
     * @param destinationChain Target chain ID
     * @param amount Amount to deposit
     * @param receiver Address to receive shares on destination chain
     * @param adapterParams LayerZero adapter parameters
     * @return nonce Transaction nonce for tracking
     */
    function crossChainDeposit(
        uint16 destinationChain,
        uint256 amount,
        address receiver,
        bytes calldata adapterParams
    ) external payable returns (bytes32 nonce);

    /**
     * @notice Initiate cross-chain withdrawal
     * @param destinationChain Target chain ID
     * @param shares Amount of shares to withdraw
     * @param receiver Address to receive assets on destination chain
     * @param adapterParams LayerZero adapter parameters
     * @return nonce Transaction nonce for tracking
     */
    function crossChainWithdraw(
        uint16 destinationChain,
        uint256 shares,
        address receiver,
        bytes calldata adapterParams
    ) external payable returns (bytes32 nonce);

    /**
     * @notice Get supported chains
     * @return chainIds Array of supported chain IDs
     */
    function getSupportedChains() external view returns (uint16[] memory chainIds);

    /**
     * @notice Check if chain is supported
     * @param chainId Chain ID to check
     * @return supported True if chain is supported
     */
    function isChainSupported(uint16 chainId) external view returns (bool supported);

    /**
     * @notice Get cross-chain fee estimate
     * @param destinationChain Target chain ID
     * @param payInZRO Pay in ZRO token
     * @param adapterParams LayerZero adapter parameters
     * @return nativeFee Fee in native token
     * @return zroFee Fee in ZRO token
     */
    function estimateFees(
        uint16 destinationChain,
        bool payInZRO,
        bytes calldata adapterParams
    ) external view returns (uint256 nativeFee, uint256 zroFee);
}