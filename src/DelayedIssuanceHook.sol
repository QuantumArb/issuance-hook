// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.24;

// import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";

// import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
// import {IV4Quoter} from "v4-periphery/src/interfaces/IV4Quoter.sol";

// import {Hooks} from "v4-core/src/libraries/Hooks.sol";
// import {PoolKey} from "v4-core/src/types/PoolKey.sol";
// import {Currency} from "v4-core/src/types/Currency.sol";
// import {CurrencySettler} from "v4-core/test/utils/CurrencySettler.sol";
// import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
// import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
// import {BeforeSwapDelta, BeforeSwapDeltaLibrary, toBeforeSwapDelta} from "v4-core/src/types/BeforeSwapDelta.sol";
// import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";
// import {SafeTransferLib} from "v4-core/lib/solmate/src/utils/SafeTransferLib.sol";

// abstract contract DelayedIssuanceHook is BaseHook {
//     using PoolIdLibrary for PoolKey;
//     using CurrencySettler for Currency;
//     using SafeCast for uint256;

//     error InvalidAmount();
//     error InsufficientBalance();
//     error NoAvailableFunds();

//     struct IssuanceData {
//         bool whitelisted;
//         Currency paymentToken;
//         Currency issuanceToken;
//         bytes32 paymentTokenPythID;
//         bytes32 issuanceTokenPythID;
//         uint256 fee;
//     }

//     struct Debt {
//         uint256 amount;
//         uint256 timestamp;
//     }

//     IV4Quoter public immutable quoter;

//     mapping(PoolId => IssuanceData) public issuanceData;
//     mapping(PoolId => Debt) public issuanceDebt;
    
//     mapping(address => mapping(Currency => uint256)) public userDeposits;

//     constructor(IPoolManager _poolManager, Currency _paymentToken, Currency _issuanceToken, IV4Quoter _quoter) BaseHook(_poolManager) {
//         // paymentToken = paymentToken;
//         // issuanceToken = issuanceToken;
//         quoter = _quoter;
//     }

//     function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
//         return Hooks.Permissions({
//             beforeInitialize: false,
//             afterInitialize: false,
//             beforeAddLiquidity: false,
//             afterAddLiquidity: false,
//             beforeRemoveLiquidity: false,
//             afterRemoveLiquidity: false,
//             beforeSwap: false,
//             afterSwap: false,
//             beforeDonate: false,
//             afterDonate: false,
//             beforeSwapReturnDelta: true,
//             afterSwapReturnDelta: false,
//             afterAddLiquidityReturnDelta: false,
//             afterRemoveLiquidityReturnDelta: false
//         });
//     }

//     function beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata params, bytes calldata hookData)
//         external
//         override
//         returns (bytes4, BeforeSwapDelta, uint24)
//     {
//         // Get the input and output currencies
//         (Currency inputCurrency, Currency outputCurrency) = _getInputOutput(params.zeroForOne, key);

//         // If the pool is not whitelisted, skip
//         if (!_validatePool (key)) return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);

//         // Preview the swap and get both the amount in and amount out regardless of exact input or output
//         (uint256 amountIn, uint256 amountOut) = _previewSwap(key, params, hookData);
        
//         // Calculate the issuance
//         uint256 amountIssued = previewIssuanceExactInput(amountOut);

//         // If issuance gives a better price than swapping, issue the tokens
//         if (amountIssued > amountOut) {
//             // Take the input tokens from the pool
//             inputCurrency.take(poolManager, address(this), amountIn, false);
//             // Pay the pool manager with the calculated output from the pool reserves
//             outputCurrency.settle(poolManager, address(this), amountIssued, false);

//             return (BaseHook.beforeSwap.selector, toBeforeSwapDelta(amountIn.toInt128(), -amountOut.toInt128()), 0);
//         } else {
//             // Otherwise, swap the tokens through the pool
//             return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
//         }
//     }

//     // -----------------------------------------------
//     // Issuance Functions
//     // -----------------------------------------------

//     function previewIssuanceExactInput(uint256 amountIn) public virtual returns(uint256 amountOut);
    
//     function _issueTokens(uint256 amountIn) internal virtual;

//     // -----------------------------------------------
//     // Side Pool Functions
//     // -----------------------------------------------
//     function deposit(Currency currency, uint256 amount) external payable {
//         if (Currency.isAddressZero(currency)) {
//             if (msg.value != amount) revert InvalidAmount();
//         } else {
//             SafeTransferLib.safeTransferFrom(currency, msg.sender, address(this), amount);
//         }

//         userDeposits[msg.sender][currency] += amount;
//     }

//     function withdraw(Currency currency, uint256 amount) external {
//         if (userDeposits[msg.sender][currency] < amount) revert InsufficientBalance();
//         if (currency.balanceOfSelf() < amount) revert NoAvailableFunds();

//         userDeposits[msg.sender][currency] -= amount;
//         Currency.transfer(msg.sender, amount);
//     }

//     // -----------------------------------------------
//     // Internal Pool Swap Preview Functions
//     // -----------------------------------------------

//     // NOTE: We are working on a way more gas-efficient method to calculate the swap, this is just for the MVP
//     function _previewSwap(PoolKey memory key, IPoolManager.SwapParams calldata params, bytes memory hookData) internal returns(uint256 amountIn, uint256 amountOut) {
//         if (params.amountSpecified < 0) {
//             // If amountSpecified is positive, we are swapping for an exact amount of output
//             // Because we already validated amountSpecified is negative, we can safely cast it to uint256 by negating it before casting to uint128
//             amountIn = uint256(-params.amountSpecified);
//             (amountOut) = _previewPoolExactInput(key, params.zeroForOne, amountIn.toUint128(), hookData);
//         } else {
//             // If amountSpecified is negative, we are swapping for an exact amount of input
//             // Because we already validated amountSpecified is positive, we can safely cast it to uint256 before casting to uint128
//             amountOut = uint256(params.amountSpecified);
//             (amountIn) = _previewPoolExactOutput(key, params.zeroForOne, amountIn.toUint128(), hookData);
//         }
//     }


//     function _previewPoolExactInput(PoolKey memory key, bool zeroForOne, uint128 amountIn, bytes memory hookData) internal returns(uint256 amountOut) {
//         IV4Quoter.QuoteExactSingleParams memory params = IV4Quoter.QuoteExactSingleParams({
//             poolKey: key,
//             zeroForOne: zeroForOne,
//             exactAmount: amountIn,
//             hookData: hookData
//         });
//         (amountOut, ) = quoter.quoteExactInputSingle(params);
//     }

//     function _previewPoolExactOutput(PoolKey memory key, bool zeroForOne, uint128 amountOut, bytes memory hookData) internal returns(uint256 amountIn) {
//         IV4Quoter.QuoteExactSingleParams memory params = IV4Quoter.QuoteExactSingleParams({
//             poolKey: key,
//             zeroForOne: zeroForOne,
//             exactAmount: amountOut,
//             hookData: hookData
//         });
//         (amountIn, ) = quoter.quoteExactInputSingle(params);
//     }

//     // -----------------------------------------------
//     // Internal Utility Functions
//     // -----------------------------------------------
//     function _getInputOutput(bool zeroForOne, PoolKey memory key) internal pure returns(Currency inputCurrency, Currency outputCurrency) {
//         if (zeroForOne) {
//             return (key.currency0, key.currency1);
//         } else {
//             return (key.currency1, key.currency0);
//         }
//     }

//     function _validatePool(PoolKey memory key) internal view returns(bool) {
//         PoolId poolId = key.toPoolId();
//         return issuanceData[poolId].whitelisted;
//     }
// }
