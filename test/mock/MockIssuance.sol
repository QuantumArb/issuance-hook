// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {MockERC20} from "forge-std/mocks/MockERC20.sol";

contract MockIssuance {
    MockERC20 public immutable paymentToken;
    MockERC20 public immutable issuanceToken;

    constructor(address _paymentToken, address _issuanceToken) {
        paymentToken = MockERC20(_paymentToken);
        issuanceToken = MockERC20(_issuanceToken);
    }

    function mint(uint256 amount) external {
        uint256 amountToIssue = calculateMint(amount);
        paymentToken.transferFrom(msg.sender, address(this), amountToIssue);
    }

    function calculateMint(uint256 amount) public pure returns (uint256) {
        return amount * exchangeRate() / 1 ether;
    }

    function exchangeRate() public pure returns (uint256) {
        return 0.95 ether;
    }
}
