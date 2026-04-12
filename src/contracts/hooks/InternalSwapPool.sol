// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from '@uniswap/v4-core/src/types/Currency.sol';

import {SwapMath} from "@uniswap/v4-core/src/libraries/SwapMath.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

import {StateLibrary} from '@uniswap/v4-core/src/libraries/StateLibrary.sol';
import {CurrencySettler} from 'src/contracts/libraries/CurrencySettler.sol';

abstract contract InternalSwapPool {
    using CurrencyLibrary for Currency;
    using CurrencySettler for Currency;
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    struct ClaimableFees {
        uint amount0;
        uint amount1;
    }

    mapping (PoolId _poolId => ClaimableFees _fees) internal _poolFees;


    event PoolFeesSwapped(PoolId indexed _poolId, bool zeroForOne, uint _amount0, uint _amount1);

    function poolFees(
        PoolKey memory _poolKey
    ) public view returns (ClaimableFees memory){
        return _poolFees[_poolKey.toId()];
    }


    function _internalSwap(
        IPoolManager _poolManager,
        PoolKey calldata _key,
        IPoolManager.SwapParams memory _params,
        bool _nativeIsZero
    ) internal returns(uint ethIn_, uint tokenOut_){
        PoolId poolId = _key.toId();

        ClaimableFees storage pendingPoolFees = _poolFees[poolId];
        if (pendingPoolFees.amount1 == 0){
            return (ethIn_, tokenOut_);
        }

        if (_nativeIsZero != _params.zeroForOne){
            return (ethIn_, tokenOut_);
        }

        (uint160 sqrtPriceX96,,,) = _poolManager.getSlot0(poolId);

        if (_params.amountSpecified >= 0){  // 输出的meme是精确的
            uint amountSpecified = (uint(_params.amountSpecified) > pendingPoolFees.amount1)
                ? pendingPoolFees.amount1
                : uint(_params.amountSpecified);
            
            (, ethIn_, tokenOut_, ) = SwapMath.computeSwapStep({
                sqrtPriceCurrentX96: sqrtPriceX96,
                sqrtPriceTargetX96: _params.sqrtPriceLimitX96,
                liquidity: _poolManager.getLiquidity(poolId),
                amountRemaining: int(amountSpecified),
                feePips:0
            });
        
        }else{  // 输入的eth数量是精确的情况
            (, tokenOut_, ethIn_, ) = SwapMath.computeSwapStep({
                sqrtPriceCurrentX96: sqrtPriceX96,
                sqrtPriceTargetX96: _params.zeroForOne? TickMath.MAX_SQRT_PRICE - 1 : TickMath.MIN_SQRT_PRICE +1,
                liquidity: _poolManager.getLiquidity(poolId),
                amountRemaining: int(-_params.amountSpecified),
                feePips: 0
            });

            if (tokenOut_ > pendingPoolFees.amount1){   // 
                ethIn_ = (pendingPoolFees.amount1 * ethIn_) / tokenOut_;
                tokenOut_ = pendingPoolFees.amount1;
            }
        }

        if (ethIn_ == 0 && tokenOut_ == 0){
            return(ethIn_, tokenOut_);
        }

        pendingPoolFees.amount0 += ethIn_;
        pendingPoolFees.amount1 -= tokenOut_;

        _poolManager.take(_nativeIsZero ? _key.currency0:_key.currency1, address(this), ethIn_);
        (_nativeIsZero ? _key.currency1: _key.currency0).settle(_poolManager, address(this), tokenOut_, false);

        emit PoolFeesSwapped(poolId, _params.zeroForOne, ethIn_, tokenOut_);

    }
}