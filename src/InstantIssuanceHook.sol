// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook, IHooks} from "v4-periphery/src/base/hooks/BaseHook.sol";

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IV4Quoter} from "v4-periphery/src/interfaces/IV4Quoter.sol";
import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {CurrencySettler} from "v4-core/test/utils/CurrencySettler.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary, toBeforeSwapDelta} from "v4-core/src/types/BeforeSwapDelta.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

abstract contract InstantIssuanceHook is BaseHook {
    using PoolIdLibrary for PoolKey;
    using CurrencySettler for Currency;
    using SafeCast for uint256;

    uint256 constant X192_PRECISION = 2**192;

    Currency public immutable paymentToken;
    Currency public immutable issuanceToken;

    constructor(IPoolManager _poolManager, Currency _paymentToken, Currency _issuanceToken) BaseHook(_poolManager) {
        paymentToken = _paymentToken;
        issuanceToken = _issuanceToken;

        // Approve the issuance token
        IERC20(Currency.unwrap(issuanceToken)).approve(address(poolManager), type(uint256).max);
    }

    function getHookPermissions() public pure override(BaseHook) returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: true,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata params, bytes calldata hookData)
        external
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        // Get the input and output currencies
        (Currency inputCurrency, Currency outputCurrency) = _getInputOutput(params.zeroForOne, key);

        // If the currencies are not the correct ones, skip
        if (!_validateTokens(inputCurrency, outputCurrency)) return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);

        // NOTE: We are working on a much more accurate way to do this, which would also allow partial issuance and swap
        // Get the pool rate
        uint256 poolRateX192 = _getPoolRate(key) ** 2;

        // Get the issuance rate and convert to X192
        uint256 issuanceRate = _getIssuanceRate();
        uint256 issuanceRateX192 = issuanceRate * uint256(X192_PRECISION / 1e18);

        if (issuanceRateX192 > poolRateX192) {
            // If the issuance rate is greater than the pool rate, we issue
            uint256 amountIn;
            uint256 amountOut;
            if (params.amountSpecified < 0) {
                // If amountSpecified is negative, we are swapping for an exact amount of input
                amountIn = uint256(-params.amountSpecified);
                amountOut = _calculateAmountOut(issuanceRate, amountIn);
            } else {
                // If amountSpecified is positive, we are swapping for an exact amount of output
                amountOut = uint256(params.amountSpecified);
                amountIn = _calculateAmountIn(issuanceRate, amountOut);
            }

            // Issue the tokens
            inputCurrency.take(poolManager, address(this), amountIn, false);
            _issueTokens(amountIn);
            IERC20(Currency.unwrap(outputCurrency)).balanceOf(address(this));
            outputCurrency.settle(poolManager, address(this), amountOut, false);

            return (BaseHook.beforeSwap.selector, toBeforeSwapDelta(amountIn.toInt128(), -amountOut.toInt128()), 0);
        } else {
            // Otherwise, we swap
            return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }
    }

    // -------------------------------------------------------------
    // Issuance Functions - To be overridden by the implementation
    // -------------------------------------------------------------
    
    function _getIssuanceRate() internal view virtual returns(uint256 rate) {}

    function _calculateAmountOut(uint256 rate, uint256 amountIn) internal view virtual returns(uint256 amountOut) {
        return amountIn * rate / 1e18;
    }

    function _calculateAmountIn(uint256 rate, uint256 amountOut) internal view virtual returns(uint256 amountIn) {
        return amountOut * 1e18 / rate;
    }

    function _issueTokens(uint256 amountIn) internal virtual;

    // -----------------------------------------------
    // Internal Pool Swap Preview Functions
    // -----------------------------------------------

    function _getPoolRate(PoolKey memory key) internal view returns(uint256 price) {
        (uint160 sqrtPriceX96, , ,) = StateLibrary.getSlot0(poolManager, PoolIdLibrary.toId(key));
    }

    // -----------------------------------------------
    // Internal Utility Functions
    // -----------------------------------------------
    function _getInputOutput(bool zeroForOne, PoolKey memory key) internal pure returns(Currency inputCurrency, Currency outputCurrency) {
        if (zeroForOne) {
            return (key.currency0, key.currency1);
        } else {
            return (key.currency1, key.currency0);
        }
    }

    function _validateTokens(Currency inputCurrency, Currency outputCurrency) internal view returns(bool) {
        return inputCurrency == paymentToken && outputCurrency == issuanceToken;
    }
}
