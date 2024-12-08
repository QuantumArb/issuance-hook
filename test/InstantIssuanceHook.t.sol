// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "v4-core/src/types/BeforeSwapDelta.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {EasyPosm} from "./utils/EasyPosm.sol";
import {Fixtures} from "./utils/Fixtures.sol";

import {MockPoolManager} from "./mock/MockPoolManager.sol";
import {MockInstantIssuanceHook} from "./mock/MockInstantIssuanceHook.sol";
import {MockIssuance} from "./mock/MockIssuance.sol";

contract InstantIssuanceHookTest is Test, Fixtures {
    using stdStorage for StdStorage;
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    MockInstantIssuanceHook hook;
    PoolId poolId;
    V4Quoter quoter;

    uint256 tokenId;
    int24 tickLower;
    int24 tickUpper;

    function setUp() public {
        // creates the pool manager, utility routers, and test tokens
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();

        MockPoolManager mockPoolManager = new MockPoolManager(address(this));
        vm.etch(address(manager), address(mockPoolManager).code);

        deployAndApprovePosm(manager);

        quoter = new V4Quoter(IPoolManager(manager));

        // Deploy Mock Instant Issuance
        address paymentToken = Currency.unwrap(currency0);
        address issuanceToken = Currency.unwrap(currency1);
        MockIssuance issuance = new MockIssuance(paymentToken, issuanceToken);
        deal(paymentToken, address(issuance), 1000000e18);
        deal(paymentToken, address(issuance), 1000000e18);

        // Deploy the hook to an address with the correct flags
        address flags = address(uint160(Hooks.BEFORE_SWAP_FLAG) | uint160(Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG) | uint160(0x4444 << 144));
        bytes memory constructorArgs = abi.encode(manager, currency0, currency1, quoter, issuance); //Add all the necessary constructor arguments from the hook
        deployCodeTo("MockInstantIssuanceHook", constructorArgs, flags);
        hook = MockInstantIssuanceHook(flags);

        // Create the pool
        key = PoolKey(currency0, currency1, 3000, 60, IHooks(hook));
        poolId = key.toId();
        manager.initialize(key, SQRT_PRICE_1_1);

        // Provide full-range liquidity to the pool
        tickLower = TickMath.minUsableTick(key.tickSpacing);
        tickUpper = TickMath.maxUsableTick(key.tickSpacing);

        uint128 liquidityAmount = 100e18;

        (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts.getAmountsForLiquidity(
            SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidityAmount
        );

        (tokenId,) = posm.mint(
            key,
            tickLower,
            tickUpper,
            liquidityAmount,
            amount0Expected + 1,
            amount1Expected + 1,
            address(this),
            block.timestamp,
            ZERO_BYTES
        );
    }

    function test_swap_no_hook() public {
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: int256(-(10 ether)),
            sqrtPriceLimitX96: 0
        });

        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: true,
            settleUsingBurn: false
        });

        swapRouter.swap(key, params, testSettings, bytes(""));
    }
}