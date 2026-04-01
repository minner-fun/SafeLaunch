// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager, PoolManager} from '@uniswap/v4-core/src/PoolManager.sol';
import {PoolId, PoolIdLibrary} from '@uniswap/v4-core/src/types/PoolId.sol';
import {BalanceDelta} from '@uniswap/v4-core/src/types/BalanceDelta.sol';
import {Currency} from '@uniswap/v4-core/src/types/Currency.sol';

import {PoolKey} from '@uniswap/v4-core/src/types/PoolKey.sol';

import {SafeCast} from '@uniswap/v4-core/src/libraries/SafeCast.sol';
import {TickMath} from '@uniswap/v4-core/src/libraries/TickMath.sol';
import {LiquidityAmounts} from '@uniswap/v4-core/test/utils/LiquidityAmounts.sol';

import {CurrencySettler} from 'src/contracts/libraries/CurrencySettler.sol';

import {TickFinder} from 'src/contracts/types/TickFinder.sol';

contract FairLaunch {

    using SafeCast for *;
    using PoolIdLibrary for PoolKey;
    using CurrencySettler for Currency;
    using TickFinder for int24;


    IPoolManager poolManager;


    struct FairLaunchInfo{
        uint startsAt;
        uint endsAt;
        int24 initialTick;
        uint revenue;
        uint supply;
        bool closed;
    }

    mapping(PoolId _poolId => FairLaunchInfo _info) internal _fairLaunchInfo;

    event FairLaunchCreated(PoolId indexed _poolId, uint _tokens, uint _startAt, uint _endsAt);
    event FairLaunchEnded(PoolId indexed _poolId, uint _revenue, uint _supply, uint _endedAt);
    constructor(IPoolManager _poolManager){
        poolManager = _poolManager;
    }

    function createPosition(
        PoolId _poolId,
        int24 _initialTick,
        uint _flaunchesAt,
        uint _initialTokenFairLaunch,
        uint _fairLaunchDuration
    ) public returns (FairLaunchInfo memory){
        if (_initialTokenFairLaunch == 0){
            _fairLaunchDuration = 0;
        }

        uint endsAt = _flaunchesAt + _fairLaunchDuration;
        _fairLaunchInfo[_poolId] = FairLaunchInfo({
            startsAt: _flaunchesAt,
            endsAt: endsAt,
            initialTick: _initialTick,
            revenue: 0,
            supply: _initialTokenFairLaunch,
            closed: false
        });

        emit FairLaunchCreated(_poolId, _initialTokenFairLaunch, _flaunchesAt, endsAt);

        return _fairLaunchInfo[_poolId];
    }
    /**
     * @dev 关闭fairlaunch，在uni pool中创建仓位。创建两个单边流动性，eth侧用所有的fair期间的收益eth创建，emme侧用余下的创建
     */
    function closedPosition(
        PoolKey memory _poolKey,
        uint _tokenFees,
        bool _nativeIsZero) public returns (FairLaunchInfo memory){
        FairLaunchInfo storage info = _fairLaunchInfo[_poolKey.toId()];
        int24 tickLower;
        int24 tickUpper;

        if (_nativeIsZero){  // 0是eth，标准的形态，tick表示的是eth的价格，所以，对于meme来说，meme的最低价对应 此刻的tickUpper。
            tickLower = (info.initialTick +1).validTick(false);  //往大了找，找到一个符合的tick   在高于initialTick的一个spacing区间里添加eth的单边流动性。
            tickUpper = tickLower + TickFinder.TICK_SPACING;  // TICK_SPACING = 60
            _createImmutablePosition(_poolKey, tickLower, tickUpper, info.revenue, true);

            tickLower = TickFinder.MIN_TICK;  // 在最小tick到小于initialTick一个spacing的地方添加所有剩余的meme代币。单边流动性。
            tickUpper = (info.initialTick -1).validTick(true);
            _createImmutablePosition(_poolKey, tickLower, tickUpper, _poolKey.currency1.balanceOf(msg.sender) - _tokenFees - info.supply, false);
        }else{
            tickUpper = (info.initialTick -1).validTick(true);
            tickLower = tickUpper - TickFinder.TICK_SPACING;
            _createImmutablePosition(_poolKey, tickLower, tickUpper, info.revenue, false);

            tickLower = (info.initialTick +1).validTick(false);
            tickUpper = TickFinder.MAX_TICK;
            _createImmutablePosition(_poolKey, tickLower, tickUpper, _poolKey.currency0.balanceOf(msg.sender) - _tokenFees - info.supply, true);

        }
        info.endsAt = block.timestamp;
        info.closed = true;

        emit FairLaunchEnded(_poolKey.toId(), info.revenue, info.supply, info.endsAt);
        return info;
    }

    function _createImmutablePosition(
        PoolKey memory _poolKey,
        int24 _tickLower,
        int24 _tickUpper,
        uint _tokens,
        bool _tokenIsZero
    ) internal {
        uint128 liquidityDelta = _tokenIsZero ? LiquidityAmounts.getLiquidityForAmount0({
            sqrtPriceAX96: TickMath.getSqrtPriceAtTick(_tickLower),
            sqrtPriceBX96: TickMath.getSqrtPriceAtTick(_tickUpper),
            amount0: _tokens
        }) : LiquidityAmounts.getLiquidityForAmount1({
            sqrtPriceAX96: TickMath.getSqrtPriceAtTick(_tickLower),
            sqrtPriceBX96: TickMath.getSqrtPriceAtTick(_tickUpper),
            amount1: _tokens
        });

        if (liquidityDelta == 0){
            return;
        }

        (BalanceDelta delta, ) = poolManager.modifyLiquidity({
            key: _poolKey,
            params: IPoolManager.ModifyLiquidityParams({
                tickLower: _tickLower,
                tickUpper: _tickUpper,
                liquidityDelta: liquidityDelta.toInt128(),
                salt: ''
            }),
            hookData: ''
        });

        if (delta.amount0() < 0){
            _poolKey.currency0.settle(poolManager, msg.sender, uint(-int(delta.amount0())), false); // settle方法是在CurrencySettle中定义的，其中包含了sync的步骤
        }

        if (delta.amount1() < 0){
            _poolKey.currency1.settle(poolManager, msg.sender, uint(-int(delta.amount1())), false);
        }


    }

}