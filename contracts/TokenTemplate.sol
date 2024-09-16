// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";

import "./interface/IToken.sol";

contract TokenTemplate is IToken, ERC20Upgradeable, ERC20PermitUpgradeable, OwnableUpgradeable{

    mapping (address => bool) blacklist;

    mapping (address => bool) whitelist;

    mapping (address => bool) pools;

    uint256 constant DENOMINATOR = 10000;

    // tax
    uint256 public buyTax;
    uint256 public sellTax;
    address public taxReceiver;

    bool public hasTax = true;

    bool public hasBlacklist = true;

    bool public hasDevInit = false;


    function initialize(string memory symbol_, string memory name_, uint256 totalSupply_, address owner_, address dest_) 
        external 
        initializer
    {   
        _transferOwnership(owner_);
        __ERC20_init(name_, symbol_);
        _mint(dest_, totalSupply_);

    }

    function devInit(
        address[] calldata blacks_, 
        address[] calldata whites_, 
        address[] calldata pool_, 
        uint256 buyTax_, 
        uint256 sellTax_,
        address taxReceiver_) external
    {
        require(!hasDevInit, "Already Initialized");
        require(blacks_.length <= 10, "Too many black addresses");
        require(whites_.length <= 10, "Too many white addresses");
        require(buyTax_ <= 500 && sellTax_ <= 500, "Tax must lte 5%");

        // set blacklist
        for(uint256 i = blacks_.length; i > 0; ) {
            unchecked {
                i--;
            }
            blacklist[blacks_[i]] = true;
        }

        // set whitelist
        for(uint256 i = whites_.length; i > 0; ) {
            unchecked {
                i--;
            }
            whitelist[whites_[i]] = true;
        }

        for(uint256 i= pool_.length; i > 0;) {
            unchecked {
                i--;
            }
            pools[pool_[i]] = true;
        }

        // set tax
        buyTax = buyTax_;
        sellTax = sellTax_;
        taxReceiver = taxReceiver_;

        // set dev initialized
        hasDevInit = true;
    }

    function _transfer(address from, address to, uint256 amount) internal override {
        if(whitelist[from] || whitelist[to]) {
            return super._transfer(from, to, amount);
        }

        if(hasBlacklist) {
            require(!blacklist[from] && !blacklist[to], "Address is blocked");
        }

        if(hasTax) {
            uint256 taxAmount = 0;
            // buy
            if(pools[from]) { 
                taxAmount = amount * buyTax / DENOMINATOR;
            } 
            // sell
            else if(pools[to]) {  
                taxAmount = amount * sellTax / DENOMINATOR;
            } 
            if(taxAmount > 0) {
                super._transfer(from, taxReceiver, taxAmount);
                amount -= taxAmount;
            }
        }

        super._transfer(from, to, amount);
    }

    /**
     * @dev Destroys `amount` tokens from the caller.
     *
     * See {ERC20-_burn}.
     */
    function burn(uint256 amount) public virtual {
        _burn(_msgSender(), amount);
    }

    function removeBlacklist() external onlyOwner {
        hasBlacklist = false;
    }

    function removeTax() external onlyOwner {
        hasTax = false;
    }

}