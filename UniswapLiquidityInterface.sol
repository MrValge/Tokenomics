pragma solidity ^0.7.0;

import "UniswapV2Library.sol";
import "IUniswapV2Pair.sol";
import "SafeMath.sol";

interface ILiquidityValueCalculator {
    function computeLiquidityShareTokenBValue(uint liquidity, address tokenA, address tokenB) external returns (uint value);
}

abstract contract LiquidityValueCalculator is ILiquidityValueCalculator {
    address public factory;
    using SafeMath for uint256;

    constructor() {
        factory = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    }

function pairInfo(address tokenA, address tokenB) internal view returns (uint reserveA, uint reserveB, uint totalSupply) {
       IUniswapV2Pair pair = IUniswapV2Pair(UniswapV2Library.pairFor(factory, tokenA, tokenB));
       totalSupply = pair.totalSupply();
       (uint reserves0, uint reserves1,) = pair.getReserves();
       (reserveA, reserveB) = tokenA == pair.token0() ? (reserves0, reserves1) : (reserves1, reserves0);
}

function computeLiquidityShareTokenBValue(uint liquidity, address tokenA, address tokenB) public override view returns (uint value) {
    ( , uint tokenBAmount, uint totalSupply) = pairInfo(tokenA, tokenB);
    value = tokenBAmount.mul(liquidity).div(totalSupply);
    return(value);
}

}
