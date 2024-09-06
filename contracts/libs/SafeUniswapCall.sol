// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../interface/IUniswapV2Factory.sol";
import "../interface/IUniswapV2Pair.sol";
contract SafeUniswapCall {

    function checkIsPair(address pair) public view returns (bool isPair) {
        address factory = safeCallPair(pair, IUniswapV2Pair.factory.selector);
        if(factory == address(0)) return false;
        address token0 = safeCallPair(pair, IUniswapV2Pair.token0.selector);
        if(token0 == address(0)) return false;
        address token1 = safeCallPair(pair, IUniswapV2Pair.token1.selector);
        if(token1 == address(0)) return false;
        address _pair = safeCallFactory(factory, token0, token1);
        isPair = pair == _pair;
    }

    function safeCallFactory(address factory, address token0, address token1) public view returns(address addr) {
        (bool success, bytes memory result) = factory.staticcall(
            abi.encodeWithSelector(IUniswapV2Factory.getPair.selector, token0, token1)
        );

        if (success && result.length >= 32) {
            try SafeUniswapCall(this).decodeRet2Address(result) returns(address ret){
                addr = ret;
            }catch {}
        } 
    }

    function safeCallPair(address pair, bytes4 selector) public view returns(address addr) {
        (bool success, bytes memory result) = pair.staticcall(
            abi.encodeWithSelector(selector)
        );

        if (success && result.length >= 32) {
            try SafeUniswapCall(this).decodeRet2Address(result) returns(address ret){
                addr = ret;
            }catch {}
        } 
    }

    function decodeRet2Address(bytes memory input) public pure returns (address){
        return abi.decode(input, (address));
    }
}