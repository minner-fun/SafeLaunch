// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager, PoolManager} from '@uniswap/v4-core/src/PoolManager.sol';
import {PoolId, PoolIdLibrary} from '@uniswap/v4-core/src/types/PoolId.sol';
import {PoolKey} from '@uniswap/v4-core/src/types/PoolKey.sol';

contract FairLaunch {


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

    function closedPosition(
        PoolKey memeory _poolKey,
        uint _tokenFees,
        bool _nativeIsZero
    ) public returns (FairLaunchInfo memory){

    }

    function _createImmutablePosition(
        PoolKey memory _poolKey,
        int24 _tickLower,
        int24 _tickUpper,
        uint _tokens,
        bool _tokenIsZero
    ) internal {
        
    }

}