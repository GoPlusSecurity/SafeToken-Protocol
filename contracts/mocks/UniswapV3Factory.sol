// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interface/INonfungiblePositionManager.sol";

contract UniswapV3Factory {
    mapping(address tokenA => mapping(address tokenB => mapping (uint24 fee => address pool))) public pools;

    function addPool(
        address tokenA,
        address tokenB,
        uint24 fee) external {
            pools[tokenA][tokenB][3000] = address(0);
            pools[tokenB][tokenA][3000] = address(0);
        }

    function getPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external view returns (address pool) {
        return pools[tokenA][tokenB][3000];
    }
}