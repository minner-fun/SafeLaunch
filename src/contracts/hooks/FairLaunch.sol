// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager, PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta, toBalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";

import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";

import {CurrencySettler} from "src/contracts/libraries/CurrencySettler.sol";

import {TickFinder} from "src/contracts/types/TickFinder.sol";

contract FairLaunch {
    using SafeCast for *;
    using PoolIdLibrary for PoolKey;
    using CurrencySettler for Currency;
    using TickFinder for int24;

    IPoolManager poolManager;

    struct FairLaunchInfo {
        uint256 startsAt;
        uint256 endsAt;
        int24 initialTick;
        uint256 revenue;
        uint256 supply;
        bool closed;
    }

    mapping(PoolId _poolId => FairLaunchInfo _info) internal _fairLaunchInfo;

    event FairLaunchCreated(PoolId indexed _poolId, uint256 _tokens, uint256 _startAt, uint256 _endsAt);
    event FairLaunchEnded(PoolId indexed _poolId, uint256 _revenue, uint256 _supply, uint256 _endedAt);

    constructor(IPoolManager _poolManager) {
        poolManager = _poolManager;
    }

    function createPosition(
        PoolId _poolId,
        int24 _initialTick,
        uint256 _mlaunchesAt,
        uint256 _initialTokenFairLaunch,
        uint256 _fairLaunchDuration
    ) public returns (FairLaunchInfo memory) {
        if (_initialTokenFairLaunch == 0) {
            _fairLaunchDuration = 0;
        }

        uint256 endsAt = _mlaunchesAt + _fairLaunchDuration;
        _fairLaunchInfo[_poolId] = FairLaunchInfo({
            startsAt: _mlaunchesAt,
            endsAt: endsAt,
            initialTick: _initialTick,
            revenue: 0,
            supply: _initialTokenFairLaunch,
            closed: false
        });

        emit FairLaunchCreated(_poolId, _initialTokenFairLaunch, _mlaunchesAt, endsAt);

        return _fairLaunchInfo[_poolId];
    }

    function fillFromPositiom(
        PoolKey memory _poolKey,
        int256 _amountSpecified, // 负数，表示输入是精确的，正，表示输出是精确的
        bool _nativeIsZero
    )
        public
        returns (BeforeSwapDelta beforeSwapDelta_, BalanceDelta balanceDelta_, FairLaunchInfo memory fairLaunchInfo)
    {
        PoolId poolId = _poolKey.toId();
        FairLaunchInfo storage info = _fairLaunchInfo[poolId];

        if (_amountSpecified == 0) {
            return (beforeSwapDelta_, balanceDelta_, info);
        }

        uint256 ethIn;
        uint256 tokensOut;

        if (_amountSpecified < 0) {
            ethIn = uint256(-_amountSpecified);
            tokensOut = _getQuoteAtTick(
                info.initialTick,
                ethIn,
                Currency.unwrap(_nativeIsZero ? _poolKey.currency0 : _poolKey.currency1),
                Currency.unwrap(_nativeIsZero ? _poolKey.currency1 : _poolKey.currency0)
            );
        } else {
            tokensOut = uint256(_amountSpecified);
            ethIn = _getQuoteAtTick(
                info.initialTick,
                tokensOut,
                Currency.unwrap(!_nativeIsZero ? _poolKey.currency0 : _poolKey.currency1),
                Currency.unwrap(!_nativeIsZero ? _poolKey.currency1 : _poolKey.currency0)
            );
        }

        if (tokensOut > info.supply) {
            uint256 percentage = info.supply * 1e18 / tokensOut; // 乘以1e18为了保护精度
            ethIn = (ethIn * percentage) / 1e18;
            tokensOut = info.supply;
        }

        beforeSwapDelta_ = (_amountSpecified < 0) // _amountSpecified的正 表示这个_amountSpecified的值 指得是输出的token数量，负表示的输入的数量
            ? toBeforeSwapDelta(ethIn.toInt128(), -tokensOut.toInt128()) // BeforeSwapDelta  规定前128位位指定的token的数量，后128位为非指定
            : toBeforeSwapDelta(-tokensOut.toInt128(), ethIn.toInt128()); // 对于-tokenOut的负号，表示是要给出去的。符合settle，take的正负规则。
        balanceDelta_ = toBalanceDelta(
            _nativeIsZero ? ethIn.toInt128() : -tokensOut.toInt128(), // balanceDelta, 前128是token0，后128是token1
            _nativeIsZero ? -tokensOut.toInt128() : ethIn.toInt128()
        );

        info.revenue += ethIn;
        info.supply -= tokensOut;

        return (beforeSwapDelta_, balanceDelta_, info);
    }

    /**
     * @dev 关闭fairlaunch，在uni pool中创建仓位。创建两个单边流动性，eth侧用所有的fair期间的收益eth创建，emme侧用余下的创建
     */
    function closedPosition(PoolKey memory _poolKey, uint256 _tokenFees, bool _nativeIsZero)
        public
        returns (FairLaunchInfo memory)
    {
        FairLaunchInfo storage info = _fairLaunchInfo[_poolKey.toId()];
        int24 tickLower;
        int24 tickUpper;

        if (_nativeIsZero) {
            // 0是eth，标准的形态，tick表示的是eth的价格，所以，对于meme来说，meme的最低价对应 此刻的tickUpper。
            tickLower = (info.initialTick + 1).validTick(false); //往大了找，找到一个符合的tick   在高于initialTick的一个spacing区间里添加eth的单边流动性。
            tickUpper = tickLower + TickFinder.TICK_SPACING; // TICK_SPACING = 60
            _createImmutablePosition(_poolKey, tickLower, tickUpper, info.revenue, true);

            tickLower = TickFinder.MIN_TICK; // 在最小tick到小于initialTick一个spacing的地方添加所有剩余的meme代币。单边流动性。
            tickUpper = (info.initialTick - 1).validTick(true);
            _createImmutablePosition(
                _poolKey,
                tickLower,
                tickUpper,
                _poolKey.currency1.balanceOf(msg.sender) - _tokenFees - info.supply,
                false
            );
        } else {
            tickUpper = (info.initialTick - 1).validTick(true);
            tickLower = tickUpper - TickFinder.TICK_SPACING;
            _createImmutablePosition(_poolKey, tickLower, tickUpper, info.revenue, false);

            tickLower = (info.initialTick + 1).validTick(false);
            tickUpper = TickFinder.MAX_TICK;
            _createImmutablePosition(
                _poolKey,
                tickLower,
                tickUpper,
                _poolKey.currency0.balanceOf(msg.sender) - _tokenFees - info.supply,
                true
            );
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
        uint256 _tokens,
        bool _tokenIsZero
    ) internal {
        uint128 liquidityDelta = _tokenIsZero
            ? LiquidityAmounts.getLiquidityForAmount0({
                sqrtPriceAX96: TickMath.getSqrtPriceAtTick(_tickLower),
                sqrtPriceBX96: TickMath.getSqrtPriceAtTick(_tickUpper),
                amount0: _tokens
            })
            : LiquidityAmounts.getLiquidityForAmount1({
                sqrtPriceAX96: TickMath.getSqrtPriceAtTick(_tickLower),
                sqrtPriceBX96: TickMath.getSqrtPriceAtTick(_tickUpper),
                amount1: _tokens
            });

        if (liquidityDelta == 0) {
            return;
        }

        (BalanceDelta delta,) = poolManager.modifyLiquidity({
            key: _poolKey,
            params: IPoolManager.ModifyLiquidityParams({
                tickLower: _tickLower,
                tickUpper: _tickUpper,
                liquidityDelta: liquidityDelta.toInt128(),
                salt: ""
            }),
            hookData: ""
        });

        if (delta.amount0() < 0) {
            _poolKey.currency0.settle(poolManager, msg.sender, uint256(-int256(delta.amount0())), false); // settle方法是在CurrencySettle中定义的，其中包含了sync的步骤
        }

        if (delta.amount1() < 0) {
            _poolKey.currency1.settle(poolManager, msg.sender, uint256(-int256(delta.amount1())), false);
        }
    }

    function _getQuoteAtTick(int24 _tick, uint256 _baseAmount, address _baseToken, address _quoteToken)
        internal
        pure
        returns (uint256 quoteAmount_)
    {
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(_tick);
        if (sqrtPriceX96 <= type(uint128).max) {
            // 判断sqrtPriceX96是不是小于uint128,因为接下来要算sqrtPriceX96 的平方，防止平方后超过uint256。溢出
            uint256 ratioX192 = uint256(sqrtPriceX96) * sqrtPriceX96;
            quoteAmount_ = _baseToken < _quoteToken
                ? FullMath.mulDiv(ratioX192, _baseAmount, 1 << 192) // mulDiv  就是前两个参数相乘，然后÷最后一个参数
                : FullMath.mulDiv(1 << 192, _baseAmount, ratioX192);
        } else {
            uint256 ratioX128 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, 1 << 64); // 其实是 Price X192,Price已经拿到了，然后把X192缩小一下到X128
            quoteAmount_ = _baseToken < _quoteToken
                ? FullMath.mulDiv(ratioX128, _baseAmount, 11 << 128)
                : FullMath.mulDiv(1 << 128, _baseAmount, ratioX128);
        }
    }
}
