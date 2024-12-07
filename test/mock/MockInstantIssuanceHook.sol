// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {InstantIssuanceHook} from "src/InstantIssuanceHook.sol";
import {MockIssuance} from "./MockIssuance.sol";

contract MockInstantIssuanceHook is InstantIssuanceHook {
    MockIssuance public immutable issuance;

    constructor(IPoolManager _poolManager, Currency _paymentToken, Currency _issuanceToken, IV4Quoter _quoter, MockIssuance _issuance) InstantIssuanceHook(_poolManager, _paymentToken, _issuanceToken, _quoter) {
        issuance = _issuance;
    }


    function _previewIssuanceExactInput(uint256 amountIn) internal override returns(uint256 amountOut) {
        return issuance.calculateMint(amountIn);
    }
    
    function _issueTokens(uint256 amountIn) internal override {
        issuance.mint(amountIn);
    }

}