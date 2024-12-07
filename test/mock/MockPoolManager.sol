// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "v4-core/src/PoolManager.sol";

contract MockPoolManager is PoolManager {
    constructor(address initialOwner) PoolManager(initialOwner) {}

    function mockUnlock() external {
        Lock.unlock();
    }

    function mockLock() external {
        Lock.lock();
    }
}
