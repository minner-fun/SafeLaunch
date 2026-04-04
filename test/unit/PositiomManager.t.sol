// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {DeployMLaunch} from "script/DeployMLaunch.s.sol";
import {IMemecoin} from "src/interfaces/IMemecoin.sol";

import {MLaunch} from "src/contracts/MLaunch.sol";
import {PositionManager} from "src/contracts/PositionManager.sol";
import {IPoolManager, PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Hooks} from "src/contracts/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IHooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {SwapParams, ModifyLiquidityParams} from "src/contracts/types/PoolOperation.sol";
import {FairLaunch} from "src/contracts/hooks/FairLaunch.sol";

import {console2} from "forge-std/Console2.sol";

import {Memecoin} from "../mock/Memecoin.sol";

contract PositionManagerTest is Test {
    using SafeCast for int256;

    string constant MEME_NAME = "minner";
    string constant MEME_SYMBOL = "MINNER";
    uint256 constant INITIAL_TOKEN_FAIRLAUNCH = 10e20;
    uint256 constant FAIRLAUNCH_DURATION = 60;
    MLaunch mlaunch;
    PositionManager positionManager;
    PoolManager poolManager;
    FairLaunch fairLaunch;
    IMemecoin memecoin;

    int24 constant MIN_TICK = -887272;
    int24 constant MAX_TICK = 887272;
    int24 constant TICK_SPACING = 60;
    int256 constant LIQUIDITY_DELTA = 1e12;

    uint256 constant SWAP = 1;
    uint256 constant ADD_LIQUIDITY = 2;
    uint256 constant REMOVE_LIQUIDITY = 3;
    uint160 constant MIN_SQRT_PRICE = 4295128739;

    uint256 action;

    PoolKey key;
    address nativeToken = address(0);

    event PoolCreated(
        PoolId indexed _poolId,
        address _memecoin,
        uint256 _tokenId,
        bool _currencyFlipped,
        PositionManager.MLaunchParams _params
    );

    function setUp() external {
        DeployMLaunch deploy = new DeployMLaunch();
        (mlaunch, positionManager, poolManager, fairLaunch) = deploy.run();
        positionManager.setMlaunch(address(mlaunch));
    }

    function test_permissions() public {
        Hooks.validateHookPermissions(address(positionManager), positionManager.getHookPermissions());
    }

    function testPositionManagerCanMlaunch() public {
        address memecoin_ = positionManager.mlaunch(
            PositionManager.MLaunchParams({
                name: MEME_NAME,
                symbol: MEME_SYMBOL,
                initialTokenFairLaunch: INITIAL_TOKEN_FAIRLAUNCH,
                fairLaunchDuration: FAIRLAUNCH_DURATION,
                creator: msg.sender,
                mlaunchAt: 0
            })
        );

        memecoin = IMemecoin(memecoin_);
        vm.assertEq(memecoin.name(), MEME_NAME);
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (action == ADD_LIQUIDITY) {
            (BalanceDelta delta,) = poolManager.modifyLiquidity({
                key: key,
                params: IPoolManager.ModifyLiquidityParams({
                    tickLower: MIN_TICK / TICK_SPACING * TICK_SPACING,
                    tickUpper: MAX_TICK / TICK_SPACING * TICK_SPACING,
                    liquidityDelta: LIQUIDITY_DELTA,
                    salt: bytes32(0)
                }),
                hookData: ""
            });
            if (delta.amount0() < 0) {
                uint256 amount0 = uint128(-delta.amount0());
                console2.log("Add liquidity amount 0: %e", amount0);
                poolManager.sync(key.currency0);
                poolManager.settle{value: amount0}();
            }
            if (delta.amount1() < 0) {
                uint256 amount1 = uint128(-delta.amount1());
                console2.log("Add liquidity amount 1: %e", amount1);
                poolManager.sync(key.currency1);
                memecoin.transfer(address(poolManager), amount1);
                poolManager.settle();
            }
            return "";
        } else if (action == REMOVE_LIQUIDITY) {
            (BalanceDelta delta,) = poolManager.modifyLiquidity({
                key: key,
                params: IPoolManager.ModifyLiquidityParams({
                    tickLower: MIN_TICK / TICK_SPACING * TICK_SPACING,
                    tickUpper: MAX_TICK / TICK_SPACING * TICK_SPACING,
                    liquidityDelta: -LIQUIDITY_DELTA,
                    salt: bytes32(0)
                }),
                hookData: ""
            });
            if (delta.amount0() > 0) {
                uint256 amount0 = uint128(delta.amount0());
                console2.log("Remove liquidity amount 0: %e", amount0);
                poolManager.take(key.currency0, address(this), amount0);
            }
            if (delta.amount1() > 0) {
                uint256 amount1 = uint128(delta.amount1());
                console2.log("Remove liquidity amount 1: %e", amount1);
                poolManager.take(key.currency1, address(this), amount1);
            }
            return "";
        } else if (action == SWAP) {
            // Swap ETH -> USDC
            uint256 bal = memecoin.balanceOf(address(this));
            BalanceDelta delta = poolManager.swap({
                key: key,
                params: IPoolManager.SwapParams({
                    zeroForOne: true, amountSpecified: -(int256(bal)), sqrtPriceLimitX96: MIN_SQRT_PRICE + 1
                }),
                hookData: ""
            });

            // BalanceDelta delta = BalanceDelta.wrap(d);
            int128 amount0 = delta.amount0();
            int128 amount1 = delta.amount1();

            (Currency currencyIn, Currency currencyOut, uint256 amountIn, uint256 amountOut) =
                (key.currency0, key.currency1, int256(-amount0).toUint256(), int256(amount1).toUint256());

            poolManager.take({currency: currencyOut, to: address(this), amount: amountOut});

            poolManager.sync(currencyIn);
            poolManager.settle{value: amountIn}();
            return "";
        }

        revert("Invalid action");
    }

    function test_liquidity() public {
        Memecoin m = new Memecoin("test", "TEST");
        m.mint(address(this), 1e6 * 1e18);
        memecoin = IMemecoin(address(m));
        // memecoin = IMemecoin(memecoin_);

        // deal(memecoin, address(this), 1e6 * 1e6);

        deal(address(this), 1e6 * 1e18);

        key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(memecoin)),
            fee: 0,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(positionManager))
        });

        int24 initialTick = poolManager.initialize( // 初始化池，返回初始tick
            key,
            // sqrtPriceX96
            1e6 * (1 << 96)
        );

        action = ADD_LIQUIDITY;
        poolManager.unlock("");
        assertEq(positionManager.counts(key.toId(), "beforeAddLiquidity"), 1);
        assertEq(positionManager.counts(key.toId(), "afterAddLiquidity"), 0);

        action = REMOVE_LIQUIDITY;
        poolManager.unlock("");
        assertEq(positionManager.counts(key.toId(), "beforeRemoveLiquidity"), 1);
        assertEq(positionManager.counts(key.toId(), "afterRemoveLiquidity"), 0);
    }

    function testPositionManagerCanCreateFairLaunchPosition() public {
        address memecoin_ = positionManager.mlaunch(
            PositionManager.MLaunchParams({
                name: MEME_NAME,
                symbol: MEME_SYMBOL,
                initialTokenFairLaunch: INITIAL_TOKEN_FAIRLAUNCH,
                creator: msg.sender,
                mlaunchAt: 0,
                fairLaunchDuration: FAIRLAUNCH_DURATION
            })
        );

        IMemecoin memecoin = IMemecoin(memecoin_);

        bool currencyFlipped = nativeToken >= memecoin_; // 检查我们的池货币是否翻转

        key = PoolKey({
            currency0: Currency.wrap(!currencyFlipped ? nativeToken : memecoin_),
            currency1: Currency.wrap(currencyFlipped ? nativeToken : memecoin_),
            fee: 0,
            tickSpacing: 60,
            hooks: IHooks(address(positionManager))
        });

        console2.log("Test poolId: ");
        console2.logBytes32(PoolId.unwrap(key.toId()));

        FairLaunch.FairLaunchInfo memory fairLaunchInfo = fairLaunch.fairLaunchInfo(key.toId());

        assertEq(fairLaunchInfo.endsAt, block.timestamp + FAIRLAUNCH_DURATION);
    }

    receive() external payable {}
}
