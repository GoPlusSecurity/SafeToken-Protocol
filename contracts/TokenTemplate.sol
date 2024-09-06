// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";

import "./interface/IToken.sol";

contract TokenTemplate is IToken, ERC20Upgradeable, ERC20PermitUpgradeable, OwnableUpgradeable{

    bool public _constraints = true;
    address public _tokenHook;
    
    // 黑名单
    mapping (address => bool) _blacklist;

    // 白名单 不扣税，不限制巨鲸，
    mapping (address => bool) _whitelist;

    // 池子只能设置一次，需要提前计算好
    mapping (address => bool) _pool;


    uint256 constant DENOMINATOR = 10000;

    // tax
    uint256 public _buyTax;
    uint256 public _sellTax;
    address public _taxReceiver;

    // 防巨鲸，地址最大持仓
    uint256 public _maxWalletLimit;

    // 防巨鲸，单比最大转账
    uint256 public _maxTransferLimit;

    // 是否收费，初始为 true，只能改为 false
    bool public hasTax = true;

    // 是否有黑名单
    bool public hasBlacklist = true;

    // 是否 anti-bot

    // 代币发行方是否初始化过，默认false, 只能初始化一次
    bool public hasDevInit = false;


    function initialize(string memory _symbol, string memory _name, uint256 _totalSupply, address _owner, address _dest) 
        external 
        initializer
    {   
        _transferOwnership(_owner);
        __ERC20_init(_name, _symbol);
        _mint(_dest, _totalSupply);

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
            _blacklist[blacks_[i]] = true;
        }

        // set whitelist
        for(uint256 i = whites_.length; i > 0; ) {
            unchecked {
                i--;
            }
            _whitelist[whites_[i]] = true;
        }

        for(uint256 i= pool_.length; i > 0;) {
            unchecked {
                i--;
            }
            _pool[pool_[i]] = true;
        }

        // set tax
        _buyTax = buyTax_;
        _sellTax = sellTax_;
        _taxReceiver = taxReceiver_;

        // set dev initialized
        hasDevInit = true;
    }

    function _transfer(address from, address to, uint256 amount) internal override {
        if(_whitelist[from] || _whitelist[to]) {
            return super._transfer(from, to, amount);
        }

        if(hasBlacklist) {
            require(!_blacklist[from] && !_blacklist[to], "Address is blocked");
        }

        if(hasTax) {
            uint256 taxAmount = 0;
            // buy
            if(_pool[from]) { 
                taxAmount = amount * _buyTax / DENOMINATOR;
            } 
            // sell
            else if(_pool[to]) {  
                taxAmount = amount * _sellTax / DENOMINATOR;
            } 
            if(taxAmount > 0) {
                super._transfer(from, _taxReceiver, taxAmount);
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