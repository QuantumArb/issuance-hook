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

import {V4Quoter} from "v4-periphery/src/lens/V4Quoter.sol";
import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {EasyPosm} from "./utils/EasyPosm.sol";
import {Fixtures} from "./utils/Fixtures.sol";

import {DelayedIssuanceHook} from "src/DelayedIssuanceHook.sol";
import {MockPriceFeed} from "./mock/MockPriceFeed.sol";

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract DelayedIssuanceHookTest is Test, Fixtures {
    using stdStorage for StdStorage;
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    address immutable USER = makeAddr("User");
    address immutable ISSUER = makeAddr("Issuer");
    address immutable STAKER = makeAddr("Staker");

    DelayedIssuanceHook hook;
    PoolId poolId;

    uint256 tokenId;
    int24 tickLower;
    int24 tickUpper;

    function setUp() public {
        // creates the pool manager, utility routers, and test tokens
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();

        deployAndApprovePosm(manager);

        // Deploy Mock Price Feeds
        MockPriceFeed paymentTokenFeed = new MockPriceFeed(0.5e18);
        MockPriceFeed issuanceTokenFeed = new MockPriceFeed(0.4e18);

        // Deploy the hook to an address with the correct flags
        address flags = address(uint160(Hooks.BEFORE_SWAP_FLAG) | uint160(Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG) | uint160(0x4444 << 144));
        bytes memory constructorArgs = abi.encode(manager, currency0, currency1, paymentTokenFeed, issuanceTokenFeed, 50, 25); //Add all the necessary constructor arguments from the hook
        deployCodeTo("DelayedIssuanceHook", constructorArgs, flags);
        hook = DelayedIssuanceHook(flags);

        hook.grantRole(hook.ISSUER_ROLE(), ISSUER);

        deal(Currency.unwrap(currency0), USER, 100e24);
        deal(Currency.unwrap(currency1), USER, 100e24);
        deal(Currency.unwrap(currency0), ISSUER, 100e24);
        deal(Currency.unwrap(currency1), ISSUER, 100e24);
        deal(Currency.unwrap(currency0), STAKER, 100e24);
        deal(Currency.unwrap(currency1), STAKER, 100e24);

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

    function test_swap_hook_delayed_issuance_triggered() public {
        console2.log("--- STARTING BALANCES ---");

        uint256 userBalanceBefore0 = currency0.balanceOf(USER);
        uint256 userBalanceBefore1 = currency1.balanceOf(USER);

        uint256 hookBalanceBefore0 = currency0.balanceOf(address(hook));
        uint256 hookBalanceBefore1 = currency1.balanceOf(address(hook));

        console2.log("User balance in currency0 before swapping: ", userBalanceBefore0);
        console2.log("User balance in currency1 before swapping: ", userBalanceBefore1);
        console2.log("Hook balance in currency0 before swapping and staking: ", hookBalanceBefore0);
        console2.log("Hook balance in currency1 before swapping and staking: ", hookBalanceBefore1);
        console2.log("-----------------------------------");
        console2.log("Staker balance in currency0 before staking: ", currency0.balanceOf(STAKER));
        console2.log("Staker balance in currency1 before staking: ", currency1.balanceOf(STAKER));

        console2.log("\nStaking...\n");
        // Stake in the hook
        vm.startPrank(STAKER);
        IERC20(Currency.unwrap(currency1)).approve(address(hook), 1e24);
        hook.deposit(1e24, STAKER);
        vm.stopPrank();

        console2.log("Staker balance in currency0 after staking: ", currency0.balanceOf(STAKER));
        console2.log("Staker balance in currency1 after staking: ", currency1.balanceOf(STAKER));
        console2.log("Hook balance in currency0 after staking: ", currency0.balanceOf(address(hook)));
        console2.log("Hook balance in currency1 after staking: ", currency1.balanceOf(address(hook)));
        console2.log("-----------------------------------");

        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: int256(-(10 ether)),
            sqrtPriceLimitX96: 0
        });

        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: true,
            settleUsingBurn: false
        });

        vm.startPrank(USER);
        IERC20(Currency.unwrap(currency0)).approve(address(swapRouter), 10000e24);
        swapRouter.swap(key, params, testSettings, bytes(""));
        vm.stopPrank();

        uint256 userBalanceAfter0 = currency0.balanceOf(USER);
        uint256 userBalanceAfter1 = currency1.balanceOf(USER);

        uint256 hookBalanceAfter0 = currency0.balanceOf(address(hook));
        uint256 hookBalanceAfter1 = currency1.balanceOf(address(hook));

        console2.log("--- ENDING BALANCES ---");

        console2.log("User balance in currency0 after swapping: ", userBalanceAfter0);
        console2.log("User balance in currency1 after swapping: ", userBalanceAfter1);
        console2.log("Hook balance in currency0 after swapping: ", hookBalanceAfter0);
        console2.log("Hook balance in currency1 after swapping: ", hookBalanceAfter1);

        console2.log("-----------------------------------");
        console2.log("Debt after swapping: ", hook.accruedDebt());
        console2.log("Payment tokens after swapping: ", hook.accruedPaymentToken());

        console.log("\nReplenishing by the issuer...\n");
        vm.startPrank(ISSUER);
        IERC20(Currency.unwrap(currency1)).approve(address(hook), 10000e24);
        hook.repayDebt(1e24);
        vm.stopPrank();

        console.log("\nUnstaking...\n");
        vm.startPrank(STAKER);
        hook.redeem(hook.balanceOf(STAKER), STAKER, STAKER);
        vm.stopPrank();

        console2.log("-----------------------------------");
        console2.log("Staker balance in currency0 after claiming rewards: ", currency0.balanceOf(STAKER));
        console2.log("Staker balance in currency1 after claiming rewards: ", currency1.balanceOf(STAKER));
    }
}
