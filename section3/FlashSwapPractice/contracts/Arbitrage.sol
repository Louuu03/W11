// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IUniswapV2Pair } from "v2-core/interfaces/IUniswapV2Pair.sol";
import { IUniswapV2Callee } from "v2-core/interfaces/IUniswapV2Callee.sol";

// This is a pracitce contract for flash swap arbitrage
contract Arbitrage is IUniswapV2Callee, Ownable {
    struct CallbackData {
        address borrowPool;
        address targetSwapPool;
        address borrowToken;
        address debtToken;
        uint256 borrowAmount;
        uint256 debtAmount;
        uint256 debtAmountOut;
    }

    //
    // EXTERNAL NON-VIEW ONLY OWNER
    //

    function withdraw() external onlyOwner {
        (bool success, ) = msg.sender.call{ value: address(this).balance }("");
        require(success, "Withdraw failed");
    }

    function withdrawTokens(address token, uint256 amount) external onlyOwner {
        require(IERC20(token).transfer(msg.sender, amount), "Withdraw failed");
    }

    //
    // EXTERNAL NON-VIEW
    //

    // Method 1 is
    //  - borrow WETH from lower price pool 5 eth
    //  - swap WETH for USDC in higher price pool
    //  - repay USDC to lower pool
    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external override {
        require(sender == address(this), "Sender must be this contract");
        require(amount0 > 0 || amount1 > 0, "amount0 or amount1 must be greater than 0");

        // 3. decode callback data
        CallbackData memory callbackData = abi.decode(data, (CallbackData));

        // 4. swap WETH to USDC
        IERC20(callbackData.borrowToken).transfer(callbackData.targetSwapPool, callbackData.debtAmount);
        (uint112 targetWETH, uint112 targetUSDC, ) = IUniswapV2Pair(callbackData.targetSwapPool).getReserves();
        uint targetSwapUSDC = _getAmountOut(callbackData.borrowAmount, targetWETH, targetUSDC);
        IUniswapV2Pair(callbackData.targetSwapPool).swap(0, targetSwapUSDC, address(this), "");
        // 5. repay USDC to lower price pool
        IERC20(callbackData.debtToken).transfer(callbackData.borrowPool, callbackData.debtAmountOut);
    }

    function arbitrage(address priceLowerPool, address priceHigherPool, uint256 borrowETH) external {
        // 1. finish callbackData
        // 2. flash swap (borrow WETH from lower price pool)

        (uint112 weth, uint112 usdc, ) = IUniswapV2Pair(priceLowerPool).getReserves();

        CallbackData memory callbackData;

        callbackData.borrowPool = priceLowerPool;
        callbackData.targetSwapPool = priceHigherPool;
        callbackData.borrowToken = IUniswapV2Pair(priceLowerPool).token0();
        callbackData.debtToken = IUniswapV2Pair(priceLowerPool).token1();
        callbackData.borrowAmount = 5 ether;
        callbackData.debtAmount = borrowETH;
        callbackData.debtAmountOut = _getAmountIn(borrowETH, usdc, weth);

        IUniswapV2Pair(priceLowerPool).swap(borrowETH, 0, address(this), abi.encode(callbackData));
    }

    //
    // INTERNAL PURE
    //

    // copy from UniswapV2Library
    function _getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountIn) {
        require(amountOut > 0, "UniswapV2Library: INSUFFICIENT_OUTPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = numerator / denominator + 1;
    }

    // copy from UniswapV2Library
    function _getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, "UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }
}
