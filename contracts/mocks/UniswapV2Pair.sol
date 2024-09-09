// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../interface/IUniswapV2Pair.sol";
import "../libs/TransferHelper.sol";

contract UniswapV2Pair is IUniswapV2Pair {
    address public token0;
    address public token1;
    address public factory;

    uint256 public totalSupply;
    mapping (address => uint256) _balances;
    mapping (address owner => mapping (address spender => uint)) _allowances;

    constructor(address token0_, address token1_, address factory_) {
        token0 = token0_;
        token1 = token1_;
        factory = factory_;
    }

    function name() external pure override returns (string memory) {
        return "MOCK_UNIV2_PAIR";
    }

    function symbol() external pure override returns (string memory) {
        return "MOCK_PAIR";
    }

    function decimals() external pure override returns (uint8) {
        return 18;
    }

    function balanceOf(
        address owner
    ) external view override returns (uint256) {
        return _balances[owner];
    }

    function allowance(
        address owner,
        address spender
    ) external view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(
        address spender,
        uint256 value
    ) external override returns (bool) {
        _allowances[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transfer(
        address to,
        uint256 value
    ) external override returns (bool) {
        require(_balances[msg.sender] >= value, "Insufficient balance");
        _balances[msg.sender] -= value;
        _balances[to] += value;
        emit Transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external override returns (bool) {
        require(_allowances[from][msg.sender] >= value, "Insufficient Approval");
        require(_balances[from] >= value, "Insufficient balance");
        _balances[from] -= value;
        _balances[to] += value;
        emit Transfer(msg.sender, to, value);

        // decrease allowance
        _allowances[from][msg.sender] -= value;
        emit Approval(from, msg.sender, _allowances[from][msg.sender]);
        return true;
    }

    function DOMAIN_SEPARATOR() external view override returns (bytes32) {}

    function PERMIT_TYPEHASH() external pure override returns (bytes32) {}

    function nonces(address owner) external view override returns (uint256) {}

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override {}

    function MINIMUM_LIQUIDITY() external pure override returns (uint256) {}


    function getReserves()
        external
        view
        override
        returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast)
    {}

    function price0CumulativeLast() external view override returns (uint256) {}

    function price1CumulativeLast() external view override returns (uint256) {}

    function kLast() external view override returns (uint256) {}

    function mint(address to) external override returns (uint256 liquidity) {
        TransferHelper.safeTransferFrom(token0, to, address(this), 1000 ether);
        TransferHelper.safeTransferFrom(token1, to, address(this), 1000 ether);
        liquidity = 1000 ether;
        _balances[to] += liquidity;
        emit Transfer(address(0), to, liquidity);
    }

    function burn(
        address to
    ) external override returns (uint256 amount0, uint256 amount1) {
        TransferHelper.safeTransfer(token0, to, 1000 ether);
        TransferHelper.safeTransfer(token1, to, 1000 ether);
        amount0 = 1000 ether;
        amount1 = 1000 ether;
    }

    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external override {}

    function skim(address to) external override {}

    function sync() external override {}

    function initialize(address, address) external override {}
}