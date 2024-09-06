// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../interface/IUniswapV2Factory.sol";
import "./UniswapV2Pair.sol";

contract UniswapV2Factory is IUniswapV2Factory {

    address[] private pairList;
    mapping(address base => mapping(address quote => address)) private pairs;

    function feeTo() external view override returns (address) {}

    function feeToSetter() external view override returns (address) {}

    function getPair(
        address tokenA,
        address tokenB
    ) external view override returns (address pair) {
        return pairs[tokenA][tokenB];
    }

    function allPairs(uint256 index) external view override returns (address pair) {
        return pairList[index];
    }

    function allPairsLength() external view override returns (uint256) {
        return pairList.length;
    }

    function createPair(
        address tokenA,
        address tokenB
    ) external override returns (address pair) {
        UniswapV2Pair pairObj = new UniswapV2Pair(tokenA, tokenB, address(this));
        pair = address(pairObj);
        pairList.push(pair);
        pairs[tokenA][tokenB] = pair;
        pairs[tokenB][tokenA] = pair;

        emit PairCreated(tokenA, tokenB, pair, pairList.length - 1);
    }

    function setFeeTo(address) external override {}

    function setFeeToSetter(address) external override {}
}