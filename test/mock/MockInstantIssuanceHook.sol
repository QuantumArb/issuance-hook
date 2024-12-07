// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "src/InstantIssuanceHook.sol";
import {MockIssuance} from "./MockIssuance.sol";
import {MockPoolManager} from "./MockPoolManager.sol";

contract MockInstantIssuanceHook is InstantIssuanceHook, Test {
    MockIssuance public immutable issuance;

    constructor(IPoolManager _poolManager, Currency _paymentToken, Currency _issuanceToken, IV4Quoter _quoter, MockIssuance _issuance) InstantIssuanceHook(_poolManager, _paymentToken, _issuanceToken, _quoter) {
        issuance = _issuance;
    }

    function _previewPoolExactInput(PoolKey memory key, bool zeroForOne, uint128 amountIn, bytes memory hookData) internal override returns (uint256 amountOut) {
       _unlockPool();
       amountOut = super._previewPoolExactInput(key, zeroForOne, amountIn, hookData);
       _lockPool();
    }

    function previewIssuanceExactInput(uint256 amountIn) public view override returns(uint256 amountOut) {
        return issuance.calculateMint(amountIn);
    }
    
    function _issueTokens(uint256 amountIn) internal override {
        issuance.mint(amountIn);
    }

    // NOTE: This is just to test while we work on a much more efficient way to estimate output before swap
    function _unlockPool() internal {
        MockPoolManager(address(poolManager)).mockUnlock();
    }

    function _lockPool() internal {
        MockPoolManager(address(poolManager)).mockLock();
    }

}