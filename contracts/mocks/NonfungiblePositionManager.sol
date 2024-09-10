// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interface/INonfungiblePositionManager.sol";

contract NonfungiblePositionManager is ERC721 {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    struct IncreaseLiquidityParams {
        uint256 tokenId;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    struct DecreaseLiquidityParams {
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }

    address public t0;
    address public t1;
    address public factory;
    uint256 public nextId = 1;

    constructor(address t0_, address t1_, address fac) ERC721("Test NFT", "TEST") {
        t0 = t0_;
        t1 = t1_;
        factory = fac;
    }

    function approve(
        address to,
        uint256 tokenId
    ) public override(ERC721) {
        super.approve(to, tokenId);
    }

    function mint(
        MintParams calldata params
    )
        external
        payable
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        amount0 = params.amount0Desired;
        amount1 = params.amount0Desired;
        IERC20(t0).transferFrom(msg.sender, address(this), params.amount0Desired);
        IERC20(t1).transferFrom(msg.sender, address(this), params.amount1Desired);
        _mint(msg.sender, nextId);
        tokenId = nextId;
        liquidity = 1000 ether;
        nextId ++;
    }

    function positions(
        uint256 tokenId
    )
        external
        view
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        )
    {
        token0 = t0;
        token1 = t1;
        fee = 3000;
    }

    function increaseLiquidity(
        IncreaseLiquidityParams calldata params
    )
        external
        payable
        returns (uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        amount0 = params.amount0Desired * 90 / 100;
        amount1 = params.amount1Desired * 90 / 100;
        liquidity = 100 ether;
        IERC20(t0).transferFrom(msg.sender, address(this), amount0);
        IERC20(t1).transferFrom(msg.sender, address(this), amount1);
    }

    function decreaseLiquidity(
        DecreaseLiquidityParams calldata params
    ) external payable returns (uint256 amount0, uint256 amount1) {

    }

    function collect(
        CollectParams calldata params
    ) external payable returns (uint256 amount0, uint256 amount1) {
        amount0 = IERC20(t0).balanceOf(address(this)) / 10;
        amount1 = IERC20(t1).balanceOf(address(this)) / 10;
        IERC20(t0).transfer(params.recipient, amount0);
        IERC20(t1).transfer(params.recipient, amount1);
    }

    function burn(uint256 tokenId) external payable {}

}