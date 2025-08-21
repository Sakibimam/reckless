// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title ShareToken
 * @dev ERC20 token representing shares in the yield vault
 * @notice This token represents proportional ownership in the vault's assets
 */
contract ShareToken is ERC20, Ownable, Pausable {
    uint8 private immutable _decimals;
    
    // Only the vault can mint and burn shares
    mapping(address => bool) public minters;
    mapping(address => bool) public burners;
    
    event MinterAdded(address indexed minter);
    event MinterRemoved(address indexed minter);
    event BurnerAdded(address indexed burner);
    event BurnerRemoved(address indexed burner);
    
    modifier onlyMinter() {
        require(minters[msg.sender], "ST: Not authorized minter");
        _;
    }
    
    modifier onlyBurner() {
        require(burners[msg.sender], "ST: Not authorized burner");
        _;
    }
    
    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) ERC20(name_, symbol_) {
        _decimals = decimals_;
        
        // The deployer (vault) is the initial owner and has minting/burning rights
        minters[msg.sender] = true;
        burners[msg.sender] = true;
        
        emit MinterAdded(msg.sender);
        emit BurnerAdded(msg.sender);
    }
    
    function decimals() public view override returns (uint8) {
        return _decimals;
    }
    
    /**
     * @notice Mint new share tokens
     * @param to Address to mint tokens to
     * @param amount Amount of tokens to mint
     */
    function mint(address to, uint256 amount) external onlyMinter whenNotPaused {
        require(to != address(0), "ST: Invalid recipient");
        require(amount > 0, "ST: Invalid amount");
        _mint(to, amount);
    }
    
    /**
     * @notice Burn share tokens
     * @param from Address to burn tokens from
     * @param amount Amount of tokens to burn
     */
    function burn(address from, uint256 amount) external onlyBurner {
        require(from != address(0), "ST: Invalid address");
        require(amount > 0, "ST: Invalid amount");
        require(balanceOf(from) >= amount, "ST: Insufficient balance");
        _burn(from, amount);
    }
    
    /**
     * @notice Add a new minter
     * @param minter Address to add as minter
     */
    function addMinter(address minter) external onlyOwner {
        require(minter != address(0), "ST: Invalid minter");
        require(!minters[minter], "ST: Already minter");
        minters[minter] = true;
        emit MinterAdded(minter);
    }
    
    /**
     * @notice Remove a minter
     * @param minter Address to remove as minter
     */
    function removeMinter(address minter) external onlyOwner {
        require(minters[minter], "ST: Not a minter");
        minters[minter] = false;
        emit MinterRemoved(minter);
    }
    
    /**
     * @notice Add a new burner
     * @param burner Address to add as burner
     */
    function addBurner(address burner) external onlyOwner {
        require(burner != address(0), "ST: Invalid burner");
        require(!burners[burner], "ST: Already burner");
        burners[burner] = true;
        emit BurnerAdded(burner);
    }
    
    /**
     * @notice Remove a burner
     * @param burner Address to remove as burner
     */
    function removeBurner(address burner) external onlyOwner {
        require(burners[burner], "ST: Not a burner");
        burners[burner] = false;
        emit BurnerRemoved(burner);
    }
    
    /**
     * @notice Pause token transfers
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @notice Unpause token transfers
     */
    function unpause() external onlyOwner {
        _unpause();
    }
    
    /**
     * @notice Decrease allowance for spender
     * @param owner Token owner
     * @param spender Address to decrease allowance for
     * @param subtractedValue Amount to decrease
     */
    function decreaseAllowance(address owner, address spender, uint256 subtractedValue) external {
        require(msg.sender == owner || burners[msg.sender], "ST: Not authorized");
        uint256 currentAllowance = allowance(owner, spender);
        require(currentAllowance >= subtractedValue, "ST: Decreased allowance below zero");
        _approve(owner, spender, currentAllowance - subtractedValue);
    }
    
    /**
     * @dev Override transfer to check pause status
     */
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        super._beforeTokenTransfer(from, to, amount);
        require(!paused(), "ST: Token transfer while paused");
    }
}