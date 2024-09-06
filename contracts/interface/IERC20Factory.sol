// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IERC20Factory {

    event TokenCreated(
        uint256 tempKey,
        address token,
        string symbol,
        string name,
        uint256 totalSupply,
        address owner,
        address dest
    );

    event FeeUpdated(uint256 fee, address feeReceiver);
    event TemplateUpdated(uint256 key, address template);

    // cumpute token address before create
    function cumputeTokenAddress(uint256 tempKey_) external view returns (address tokenAddress);

    // create token contract and initial mint to dest_
    function createToken(
        uint256 tempKey_,
        string memory symbol_,
        string memory name_,
        uint256 totalSupply_,
        address owner_,
        address dest_
    ) external payable returns (address token);
}