// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

contract MockPriceFeed {

    uint256 public price;

    constructor(uint256 _price) {
        price = _price;
    }

    function latestRoundData()
    external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (uint80(0), int256(price), block.timestamp, block.timestamp, uint80(0));
    }
}
