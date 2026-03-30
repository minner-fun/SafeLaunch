// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BalanceDelta} from '@uniswap/v4-core/src/types/BalanceDelta.sol';
import {BeforeSwapDelta, BeforeSwapDeltaLibrary, toBeforeSwapDelta} from '@uniswap/v4-core/src/types/BeforeSwapDelta.sol';
import {Currency} from '@uniswap/v4-core/src/types/Currency.sol';
import {Hooks, IHooks} from '@uniswap/v4-core/src/libraries/Hooks.sol';
import {IPoolManager} from '@uniswap/v4-core/src/interfaces/IPoolManager.sol';
import {PoolId, PoolIdLibrary} from '@uniswap/v4-core/src/types/PoolId.sol';
import {PoolKey} from '@uniswap/v4-core/src/types/PoolKey.sol';
import {SafeCast} from '@uniswap/v4-core/src/libraries/SafeCast.sol';
import {StateLibrary} from '@uniswap/v4-core/src/libraries/StateLibrary.sol';

import {BaseHook} from '@uniswap/v4-periphery/src/base/hooks/BaseHook.sol';


contract PositionManager is BaseHook {


    struct MLaunchParams {
        string name;
        string symbol;
        string tokenUri;
        uint256 initialTokenFairLaunch;
        // uint premineAmount;
        address creator;
        uint24 creatorFeeAllocation;
        uint256 mlaunchAt;
        bytes initialPriceParams;
        bytes feeCalculatorParams;
    }

    address nativeToken = address(0);

    event PoolCreated(PoolId indexed _poolId, address _memecoin, uint _tokenId, bool _currencyFlipped, uint _flaunchFee, MLaunchParams _params);


    constructor(address _poolManager) {
        poolManager = IPoolManager(_poolManager);
        Hooks.validateHookPermissions(address(this), getHookPermissions());
    }

    function getHookPermissions()
        public
        pure
        returns (Hooks.Permissions memory)
    {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function mlaunch(MLaunchParams calldata _params) external payable returns (address memecoin_) {
        uint tokenId;
        // address payable memecoinTreasury;

        (memecoin_, tokenId) = flaunchContract.flaunch(_params);   // tokenId是nft的id



        // Check if our pool currency is flipped
        bool currencyFlipped = nativeToken >= memecoin_;   // 检查我们的池货币是否翻转
        

        // Create our Uniswap pool and store the pool key for lookups 
        // 创建我们的Uniswap池 并存储池key用于查找
        PoolKey memory _poolKey = PoolKey({
            currency0: Currency.wrap(!currencyFlipped ? nativeToken : memecoin_),
            currency1: Currency.wrap(currencyFlipped ? nativeToken : memecoin_),
            fee: 0,
            tickSpacing: 60,
            hooks: IHooks(address(this))
        });


        // Set the PoolKey to storage
        // _poolKeys[memecoin_] = _poolKey;   // 存储池key
        PoolId poolId = _poolKey.toId();   // 计算池id
        

        // Check if we have an initial flaunching fee, check that enough ETH has been sent
        // 检查我们是否有初始的flaunching创建费用，检查是否发送了足够的ETH
        // uint flaunchFee = getFlaunchingFee(_params.initialPriceParams);   // 返回的也是在initialPrice.sol中部署的时候设定的初始值
        

        emit PoolCreated({
            _poolId: poolId,
            _memecoin: memecoin_,
            _tokenId: tokenId,
            _currencyFlipped: currencyFlipped,
            _flaunchFee: flaunchFee,
            _params: _params
        });


        // IMemecoin(memecoin_).approve(address(fairLaunch), type(uint).max);   // 授权FairLaunch合约使用代币



        uint160 sqrtPriceX96 = initialPrice.getSqrtPriceX96(msg.sender, currencyFlipped, _params.initialPriceParams);
        
        // Initialize our memecoin with the sqrtPriceX96
        // 初始化我们的memecoin与sqrtPriceX96， sqrtPriceX96表示价格的开方后乘以2的96次方
        int24 initialTick = poolManager.initialize(   // 初始化池，返回初始tick
            _poolKey,
            sqrtPriceX96
        );
        

        // fairLaunch.createPosition({
        //     _poolId: poolId,
        //     _initialTick: initialTick,
        //     _flaunchesAt: _params.flaunchAt > block.timestamp ? _params.flaunchAt : block.timestamp,
        //     _initialTokenFairLaunch: _params.initialTokenFairLaunch,
        //     _fairLaunchDuration: _params.fairLaunchDuration
        // });
        


        // if (_params.flaunchAt > block.timestamp) {
        //     flaunchesAt[poolId] = _params.flaunchAt;
        //     emit PoolScheduled(poolId, _params.flaunchAt);
        // } else {
        //     // If the `flaunchAt` timestamp has already passed, then use the current timestamp
        //     // 如果`flaunchAt`时间戳已经过去，那么使用当前时间戳
        //     flaunchesAt[poolId] = block.timestamp;
        // }


    }


    function setFlaunch(address _flaunchContract) public onlyOwner {
        flaunchContract = IFlaunch(_flaunchContract);
    }

}
