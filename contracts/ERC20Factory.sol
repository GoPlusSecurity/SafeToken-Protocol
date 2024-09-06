// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

import "./interface/IToken.sol";
import "./interface/IERC20Factory.sol";
import "./libs/TransferHelper.sol";

contract ERC20Factory is IERC20Factory, Ownable {
    mapping(uint256 => address) public _templates;
    mapping(address => uint) _nonces;

    uint256 public _fee;
    address public _feeReceiver;

    constructor(uint256 fee_, address feeReceiver_) Ownable(_msgSender()) {
        _fee = fee_;
        _feeReceiver = feeReceiver_;
        emit FeeUpdated(fee_, feeReceiver_);
    }

    // 预先计算 token 地址
    function cumputeTokenAddress(
        uint256 tempKey_
    ) external override view returns (address tokenAddress) {
        tokenAddress = Clones.predictDeterministicAddress(
            _templates[tempKey_],
            keccak256(abi.encode(_msgSender(), _nonces[_msgSender()]))
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
    ) external payable override returns (address token) {
        require(_templates[tempKey_] != address(0), "Template not exists");
        require(msg.value >= _fee, "Insufficient fee");
        // deploy token
        token = Clones.cloneDeterministic(
            _templates[tempKey_],
            keccak256(abi.encode(_msgSender(), _nonces[_msgSender()]))
        );
        // init token
        IToken(token).initialize(symbol_, name_, totalSupply_, owner_, dest_);
        _nonces[_msgSender()]++;
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
        // tranfer fee
        if (msg.value > 0) {
            TransferHelper.safeTransferETH(_feeReceiver, msg.value);
        }
    }

    function updateTemplates(
        uint256 tempKey_,
        address templete_
    ) external onlyOwner {
        _templates[tempKey_] = templete_;
        emit TemplateUpdated(tempKey_, templete_);
    }

    function updateFee(uint256 fee_, address feeReceiver_) external onlyOwner {
        _fee = fee_;
        _feeReceiver = feeReceiver_;
        emit FeeUpdated(fee_, feeReceiver_);
    }
}
