// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./YieldVault.sol";
import "./interfaces/ICrossChainVault.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title CrossChainVault
 * @dev ERC4626 vault with cross-chain deposit/withdrawal capabilities via LayerZero
 */
contract CrossChainVault is YieldVault, ICrossChainVault {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // LayerZero message types
    uint16 public constant PT_DEPOSIT = 1;
    uint16 public constant PT_WITHDRAW = 2;
    uint16 public constant PT_SYNC_STATE = 3;

    // Cross-chain configuration
    mapping(uint16 => bool) public supportedChains;
    mapping(uint16 => address) public trustedRemotes;
    uint16[] public supportedChainIds;
    
    // Cross-chain state
    mapping(bytes32 => bool) public processedNonces;
    mapping(address => mapping(uint16 => uint256)) public userBalanceByChain;
    
    // Cross-chain parameters
    uint256 public crossChainDepositFee = 0.001 ether; // Base fee for cross-chain deposits
    uint256 public minCrossChainDeposit = 100 * 10**18; // Minimum cross-chain deposit (100 tokens)
    uint256 public maxCrossChainDeposit = 1000000 * 10**18; // Maximum cross-chain deposit
    
    // Gas limits for LayerZero
    uint256 public constant DEPOSIT_GAS_LIMIT = 200000;
    uint256 public constant WITHDRAW_GAS_LIMIT = 300000;
    uint256 public constant SYNC_GAS_LIMIT = 150000;

    // Events
    event CrossChainConfigUpdated(uint16 indexed chainId, bool supported, address trustedRemote);
    event CrossChainFeeUpdated(uint256 oldFee, uint256 newFee);
    event CrossChainDepositLimitsUpdated(uint256 minDeposit, uint256 maxDeposit);

    struct CrossChainDepositPayload {
        address user;
        uint256 amount;
        bytes32 nonce;
    }

    struct CrossChainWithdrawPayload {
        address user;
        uint256 shares;
        bytes32 nonce;
    }

    constructor(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        address admin_,
        address feeRecipient_,
        address lzEndpoint_
    ) 
        YieldVault(asset_, name_, symbol_, admin_, feeRecipient_) 
    {
        // Grant cross-chain roles
        _grantRole(STRATEGY_MANAGER_ROLE, admin_);
    }

    /*//////////////////////////////////////////////////////////////
                        CROSS-CHAIN CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    function addSupportedChain(uint16 chainId, address trustedRemote) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(chainId != 0, "Invalid chain ID");
        require(trustedRemote != address(0), "Invalid trusted remote");
        
        if (!supportedChains[chainId]) {
            supportedChains[chainId] = true;
            supportedChainIds.push(chainId);
        }
        
        trustedRemotes[chainId] = trustedRemote;
        _setTrustedRemote(chainId, abi.encodePacked(trustedRemote, address(this)));
        
        emit CrossChainConfigUpdated(chainId, true, trustedRemote);
    }

    function removeSupportedChain(uint16 chainId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(supportedChains[chainId], "Chain not supported");
        
        supportedChains[chainId] = false;
        trustedRemotes[chainId] = address(0);
        
        // Remove from array
        for (uint256 i = 0; i < supportedChainIds.length; i++) {
            if (supportedChainIds[i] == chainId) {
                supportedChainIds[i] = supportedChainIds[supportedChainIds.length - 1];
                supportedChainIds.pop();
                break;
            }
        }
        
        emit CrossChainConfigUpdated(chainId, false, address(0));
    }

    function setCrossChainFee(uint256 newFee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 oldFee = crossChainDepositFee;
        crossChainDepositFee = newFee;
        emit CrossChainFeeUpdated(oldFee, newFee);
    }

    function setCrossChainDepositLimits(uint256 minDeposit, uint256 maxDeposit) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(minDeposit < maxDeposit, "Invalid limits");
        minCrossChainDeposit = minDeposit;
        maxCrossChainDeposit = maxDeposit;
        emit CrossChainDepositLimitsUpdated(minDeposit, maxDeposit);
    }

    /*//////////////////////////////////////////////////////////////
                        CROSS-CHAIN DEPOSIT/WITHDRAW
    //////////////////////////////////////////////////////////////*/

    function crossChainDeposit(
        uint16 destinationChain,
        uint256 amount,
        address receiver,
        bytes calldata adapterParams
    ) external payable override nonReentrant returns (bytes32 nonce) {
        require(supportedChains[destinationChain], "Chain not supported");
        require(amount >= minCrossChainDeposit && amount <= maxCrossChainDeposit, "Amount out of bounds");
        require(receiver != address(0), "Invalid receiver");
        
        // Generate nonce for tracking
        nonce = keccak256(abi.encodePacked(msg.sender, block.timestamp, amount, destinationChain));
        require(!processedNonces[nonce], "Nonce already used");
        
        // Collect cross-chain fee
        require(msg.value >= crossChainDepositFee, "Insufficient cross-chain fee");
        
        // Transfer tokens to this contract
        _asset.safeTransferFrom(msg.sender, address(this), amount);
        
        // Prepare cross-chain message
        CrossChainDepositPayload memory payload = CrossChainDepositPayload({
            user: receiver,
            amount: amount,
            nonce: nonce
        });
        
        bytes memory encodedPayload = abi.encode(PT_DEPOSIT, payload);
        
        // Send LayerZero message
        _lzSend(
            destinationChain,
            encodedPayload,
            payable(msg.sender),
            address(0),
            adapterParams.length > 0 ? adapterParams : abi.encodePacked(uint16(1), DEPOSIT_GAS_LIMIT)
        );
        
        processedNonces[nonce] = true;
        userBalanceByChain[msg.sender][destinationChain] = userBalanceByChain[msg.sender][destinationChain].add(amount);
        
        emit CrossChainDepositInitiated(msg.sender, destinationChain, amount, nonce);
    }

    function crossChainWithdraw(
        uint16 destinationChain,
        uint256 shares,
        address receiver,
        bytes calldata adapterParams
    ) external payable override nonReentrant returns (bytes32 nonce) {
        require(supportedChains[destinationChain], "Chain not supported");
        require(shares > 0 && shares <= balanceOf(msg.sender), "Invalid shares amount");
        require(receiver != address(0), "Invalid receiver");
        
        // Generate nonce
        nonce = keccak256(abi.encodePacked(msg.sender, block.timestamp, shares, destinationChain));
        require(!processedNonces[nonce], "Nonce already used");
        
        // Collect cross-chain fee
        require(msg.value >= crossChainDepositFee, "Insufficient cross-chain fee");
        
        // Calculate assets to withdraw
        uint256 assets = previewRedeem(shares);
        
        // Burn shares locally
        _burn(msg.sender, shares);
        
        // Prepare cross-chain message
        CrossChainWithdrawPayload memory payload = CrossChainWithdrawPayload({
            user: receiver,
            shares: shares,
            nonce: nonce
        });
        
        bytes memory encodedPayload = abi.encode(PT_WITHDRAW, payload);
        
        // Send LayerZero message
        _lzSend(
            destinationChain,
            encodedPayload,
            payable(msg.sender),
            address(0),
            adapterParams.length > 0 ? adapterParams : abi.encodePacked(uint16(1), WITHDRAW_GAS_LIMIT)
        );
        
        processedNonces[nonce] = true;
        
        emit CrossChainWithdrawalInitiated(msg.sender, destinationChain, shares, nonce);
    }

    /*//////////////////////////////////////////////////////////////
                        LAYERZERO MESSAGE HANDLING
    //////////////////////////////////////////////////////////////*/

    function _nonblockingLzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) internal override {
        require(supportedChains[_srcChainId], "Source chain not supported");
        
        (uint16 messageType, bytes memory data) = abi.decode(_payload, (uint16, bytes));
        
        if (messageType == PT_DEPOSIT) {
            _handleCrossChainDeposit(_srcChainId, data);
        } else if (messageType == PT_WITHDRAW) {
            _handleCrossChainWithdraw(_srcChainId, data);
        } else if (messageType == PT_SYNC_STATE) {
            _handleStateSync(_srcChainId, data);
        }
    }

    function _handleCrossChainDeposit(uint16 srcChainId, bytes memory data) internal {
        CrossChainDepositPayload memory payload = abi.decode(data, (CrossChainDepositPayload));
        
        require(!processedNonces[payload.nonce], "Already processed");
        require(payload.user != address(0), "Invalid user");
        require(payload.amount > 0, "Invalid amount");
        
        // Mark as processed
        processedNonces[payload.nonce] = true;
        
        // Calculate shares and mint
        uint256 shares = previewDeposit(payload.amount);
        _mint(payload.user, shares);
        
        // Update tracking
        userBalanceByChain[payload.user][srcChainId] = userBalanceByChain[payload.user][srcChainId].add(payload.amount);
        
        emit CrossChainDepositCompleted(payload.user, srcChainId, payload.amount, shares, payload.nonce);
        
        // Auto-invest if significant deposit
        if (payload.amount > totalAssets() / 20) {
            _autoRebalance();
        }
    }

    function _handleCrossChainWithdraw(uint16 srcChainId, bytes memory data) internal {
        CrossChainWithdrawPayload memory payload = abi.decode(data, (CrossChainWithdrawPayload));
        
        require(!processedNonces[payload.nonce], "Already processed");
        require(payload.user != address(0), "Invalid user");
        require(payload.shares > 0, "Invalid shares");
        
        // Mark as processed
        processedNonces[payload.nonce] = true;
        
        // Calculate assets to withdraw
        uint256 assets = previewRedeem(payload.shares);
        
        // Ensure we have enough liquid assets
        uint256 vaultBalance = _asset.balanceOf(address(this));
        if (vaultBalance < assets) {
            _withdrawFromStrategies(assets - vaultBalance);
        }
        
        // Transfer assets to user
        _asset.safeTransfer(payload.user, assets);
        
        emit Withdraw(address(this), payload.user, payload.user, assets, payload.shares);
    }

    function _handleStateSync(uint16 srcChainId, bytes memory data) internal {
        // Implementation for state synchronization between chains
        // This could include TVL updates, APY syncing, etc.
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getSupportedChains() external view override returns (uint16[] memory chainIds) {
        return supportedChainIds;
    }

    function isChainSupported(uint16 chainId) external view override returns (bool supported) {
        return supportedChains[chainId];
    }

    function estimateFees(
        uint16 destinationChain,
        bool payInZRO,
        bytes calldata adapterParams
    ) external view override returns (uint256 nativeFee, uint256 zroFee) {
        require(supportedChains[destinationChain], "Chain not supported");
        
        // Create dummy payload for fee estimation
        CrossChainDepositPayload memory dummyPayload = CrossChainDepositPayload({
            user: msg.sender,
            amount: minCrossChainDeposit,
            nonce: bytes32(0)
        });
        
        bytes memory encodedPayload = abi.encode(PT_DEPOSIT, dummyPayload);
        
        (nativeFee, zroFee) = lzEndpoint.estimateFees(
            destinationChain,
            address(this),
            encodedPayload,
            payInZRO,
            adapterParams.length > 0 ? adapterParams : abi.encodePacked(uint16(1), DEPOSIT_GAS_LIMIT)
        );
        
        // Add our cross-chain fee
        nativeFee = nativeFee.add(crossChainDepositFee);
    }

    function getUserCrossChainBalance(address user, uint16 chainId) 
        external 
        view 
        returns (uint256 balance) 
    {
        return userBalanceByChain[user][chainId];
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function retryFailedMessage(
        uint16 _srcChainId,
        bytes calldata _srcAddress,
        uint64 _nonce,
        bytes calldata _payload
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        failedMessages[_srcChainId][_srcAddress][_nonce] = bytes32(0);
        _nonblockingLzReceive(_srcChainId, _srcAddress, _nonce, _payload);
    }

    function syncStateWithChain(uint16 destinationChain) 
        external 
        payable 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(supportedChains[destinationChain], "Chain not supported");
        
        // Prepare state sync payload
        bytes memory stateData = abi.encode(
            totalAssets(),
            totalSupply(),
            getCurrentAPY(),
            block.timestamp
        );
        
        bytes memory encodedPayload = abi.encode(PT_SYNC_STATE, stateData);
        
        _lzSend(
            destinationChain,
            encodedPayload,
            payable(msg.sender),
            address(0),
            abi.encodePacked(uint16(1), SYNC_GAS_LIMIT)
        );
    }

    function emergencyWithdrawCrossChain(
        uint16 destinationChain,
        address user,
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(emergencyShutdown, "Emergency not active");
        require(supportedChains[destinationChain], "Chain not supported");
        
        _asset.safeTransfer(user, amount);
    }

    // Override pause function to also pause cross-chain operations
    function pause() public override onlyRole(PAUSER_ROLE) {
        super.pause();
        // Additional cross-chain pause logic could be added here
    }

    // Function to collect cross-chain fees
    function collectCrossChainFees() external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            payable(feeRecipient).transfer(balance);
        }
    }

    // Receive function for LayerZero gas refunds
    receive() external payable {
        // Accept ETH for LayerZero operations
    }
}