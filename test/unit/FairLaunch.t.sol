
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

contract FairLaunchTest is Test{

    MLaunch mlaunch;
    PositionManager positionManager;
    PoolManager poolManager;
    FairLaunch fairLaunch;
    IMemecoin memecoin;
    PoolKey poolKey;
    PoolId poolId;
    int24 initialTick;

    uint160 constant INITIAL_SQRT_PRICE_X96 = 1e6 * (1 << 96);

    function setUp() external {
        DeployMLaunch deploy = new DeployMLaunch();
        (mlaunch, positionManager, poolManager, fairLaunch) = deploy.run();
        positionManager.setMlaunch(address(mlaunch));
        Memecoin m = new Memecoin('test', 'TEST');
        m.mint(address(this), 1e6 * 1e18);
        memecoin = IMemecoin(address(m));
        address memecoin_ = address(memecoin);
        address nativeToken = address(0);

        bool currencyFlipped = nativeToken >= memecoin_; // 检查我们的池货币是否翻转


        poolKey = PoolKey({
            currency0: Currency.wrap(!currencyFlipped ? nativeToken : memecoin_),
            currency1: Currency.wrap(currencyFlipped ? nativeToken : memecoin_),
            fee: 0,
            tickSpacing: 60,
            hooks: IHooks(address(positionManager))
        });

        poolId = poolKey.toId();

        initialTick = poolManager.initialize( // 初始化池，返回初始tick
            poolKey,
            // sqrtPriceX96
            INITIAL_SQRT_PRICE_X96
        );

    }

    function testFairLaunchCanCreatePosition() public {

        fairLaunch.createPosition({
            _poolId: poolId,
            _initialTick: initialTick,
            _mlaunchesAt: block.timestamp,
            _initialTokenFairLaunch: 10e12,
            _fairLaunchDuration: 40
        });

        FairLaunch.FairLaunchInfo memory info = fairLaunch.fairLaunchInfo(poolId);

        assertEq(info.startsAt, block.timestamp);
        assertEq(info.endsAt, block.timestamp + 40);
        assertEq(info.initialTick, initialTick);
        assertEq(info.revenue, 0);
        assertEq(info.supply, 10e12);
        assertEq(info.closed, false);
    }
    function testFairLaunchWhetherInFairlaunchWindow() public {
        fairLaunch.createPosition({
            _poolId: poolId,
            _initialTick: initialTick,
            _mlaunchesAt: block.timestamp + 30,
            _initialTokenFairLaunch: 10e12,
            _fairLaunchDuration: 40
        });

        bool inFairLaunchWindow = fairLaunch.inFairLaunchWindow(poolId);
        assertFalse(inFairLaunchWindow);

        vm.warp(block.timestamp + 30 + 1); // 改变时间戳
        inFairLaunchWindow = fairLaunch.inFairLaunchWindow(poolId);
        assertTrue(inFairLaunchWindow);

        
        vm.warp(block.timestamp + 30 + 40 + 1); // 改变时间戳
        inFairLaunchWindow = fairLaunch.inFairLaunchWindow(poolId);
        assertFalse(inFairLaunchWindow);
    }

}