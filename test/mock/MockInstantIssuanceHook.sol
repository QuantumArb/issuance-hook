// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "src/InstantIssuanceHook.sol";
import {MockIssuance} from "./MockIssuance.sol";
import {MockERC20} from "forge-std/mocks/MockERC20.sol";

contract MockInstantIssuanceHook is InstantIssuanceHook, Test {
    MockIssuance public immutable issuance;

    constructor(IPoolManager _poolManager, Currency _paymentToken, Currency _issuanceToken, MockIssuance _issuance) InstantIssuanceHook(_poolManager, _paymentToken, _issuanceToken) {
        issuance = _issuance;
    }

    function _getIssuanceRate() internal view override returns(uint256) {
        return issuance.exchangeRate();
    }
    
    function _issueTokens(uint256 amountIn) internal override {
        MockERC20(Currency.unwrap(paymentToken)).approve(address(issuance), amountIn);
        issuance.mint(amountIn);
    }
}