// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

import "./interface/IToken.sol";
import "./interface/ISafeTokenFactory.sol";
import "./libs/TransferHelper.sol";

contract SafeTokenFactory is ISafeTokenFactory, Ownable {
    mapping(uint256 => address) public templates;
    mapping(address => uint) public nonces;

    constructor() Ownable(_msgSender()) {
    }

    // 预先计算 token 地址
    function cumputeTokenAddress(
        uint256 tempKey_
    ) external override view returns (address tokenAddress) {
        tokenAddress = Clones.predictDeterministicAddress(
            templates[tempKey_],
            keccak256(abi.encode(_msgSender(), nonces[_msgSender()] + 1))
        );
    }

    //
    function createToken(
        uint256 tempKey_,
        string memory symbol_,
        string memory name_,
        uint256 totalSupply_,
        address owner_,
        address dest_
    ) external override returns (address token) {
        require(templates[tempKey_] != address(0), "Template not exists");
        nonces[_msgSender()]++;
        // deploy token
        token = Clones.cloneDeterministic(
            templates[tempKey_],
            keccak256(abi.encode(_msgSender(), nonces[_msgSender()]))
        );
        // init token
        IToken(token).initialize(symbol_, name_, totalSupply_, owner_, dest_);
        // emit event
        emit TokenCreated(
            tempKey_,
            token,
            symbol_,
            name_,
            totalSupply_,
            owner_,
            dest_
        );
    }

    function updateTemplates(
        uint256 tempKey_,
        address templete_
    ) external onlyOwner {
        templates[tempKey_] = templete_;
        emit TemplateUpdated(tempKey_, templete_);
    }

}
