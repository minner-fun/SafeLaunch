// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {
    BeforeSwapDelta, BeforeSwapDeltaLibrary, toBeforeSwapDelta
} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {Hooks} from "src/contracts/libraries/Hooks.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";

import {BaseHook} from "@uniswap/v4-periphery/src/base/hooks/BaseHook.sol";

import {IMLaunch} from "src/interfaces/IMLaunch.sol";
import {CurrencySettler} from "src/contracts/libraries/CurrencySettler.sol";

import {SwapParams, ModifyLiquidityParams} from "./types/PoolOperation.sol";

import {FairLaunch} from "src/contracts/hooks/FairLaunch.sol";
import {console2} from "forge-std/console2.sol";

contract PositionManager {
    using CurrencySettler for Currency;

    struct MLaunchParams {
        string name;
        string symbol;
        // string tokenUri;
        uint256 initialTokenFairLaunch;
        uint256 fairLaunchDuration;
        // uint premineAmount;
        address creator;
        // uint24 creatorFeeAllocation;
        uint256 mlaunchAt;
    }
    // bytes initialPriceParams;
    // bytes feeCalculatorParams;

    mapping(PoolId => mapping(string => uint256)) public counts;
    mapping(PoolId => uint256 _mlaunchTime) public mlaunchesAt;
    address nativeToken = address(0);
    IMLaunch public mlaunchContract;
    IPoolManager public immutable poolManager;
    FairLaunch public fairLaunch;

    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD; // `dEaD`地址，用于燃烧我们的未售出的memecoin

    event PoolCreated(
        PoolId indexed _poolId, address _memecoin, uint256 _tokenId, bool _currencyFlipped, MLaunchParams _params
    );
    event PoolScheduled(PoolId indexed _poolId, uint256 _mlaunchesAt);
    event FairLaunchBurn(PoolId indexed _poolId, uint256 _unsoldSupply);

    error HookNotImplemented();
    error NotPoolManager();

    modifier onlyPoolManager() {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        _;
    }

    constructor(address _poolManager, FairLaunch _fairLaunch) {
        poolManager = IPoolManager(_poolManager);
        fairLaunch = _fairLaunch;
        Hooks.validateHookPermissions(address(this), getHookPermissions());
    }

    function getHookPermissions() public pure returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: true,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: true,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function mlaunch(MLaunchParams calldata _params) external payable returns (address memecoin_) {
        uint256 tokenId;
        // address payable memecoinTreasury;

        (memecoin_, tokenId) = mlaunchContract.mlaunch(_params); // tokenId是nft的id

        // Check if our pool currency is flipped
        bool currencyFlipped = nativeToken >= memecoin_; // 检查我们的池货币是否翻转

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
        PoolId poolId = _poolKey.toId(); // 计算池id
        console2.log("PositionManager poolId: ");
        console2.logBytes32(PoolId.unwrap(_poolKey.toId()));

        // Check if we have an initial flaunching fee, check that enough ETH has been sent
        // 检查我们是否有初始的flaunching创建费用，检查是否发送了足够的ETH
        // uint flaunchFee = getFlaunchingFee(_params.initialPriceParams);   // 返回的也是在initialPrice.sol中部署的时候设定的初始值

        emit PoolCreated({
            _poolId: poolId,
            _memecoin: memecoin_,
            _tokenId: tokenId,
            _currencyFlipped: currencyFlipped,
            // _flaunchFee: flaunchFee,
            _params: _params
        });

        // IMemecoin(memecoin_).approve(address(fairLaunch), type(uint).max);   // 授权FairLaunch合约使用代币

        // uint160 sqrtPriceX96 = initialPrice.getSqrtPriceX96(msg.sender, currencyFlipped, _params.initialPriceParams);

        // // Initialize our memecoin with the sqrtPriceX96
        // // 初始化我们的memecoin与sqrtPriceX96， sqrtPriceX96表示价格的开方后乘以2的96次方
        int24 initialTick = poolManager.initialize( // 初始化池，返回初始tick
            _poolKey,
            // sqrtPriceX96
            1e6 * (1 << 96)
        );

        fairLaunch.createPosition({
            _poolId: poolId,
            _initialTick: initialTick,
            _mlaunchesAt: _params.mlaunchAt > block.timestamp ? _params.mlaunchAt : block.timestamp,
            _initialTokenFairLaunch: _params.initialTokenFairLaunch,
            _fairLaunchDuration: _params.fairLaunchDuration
        });

        if (_params.mlaunchAt > block.timestamp) {
            mlaunchesAt[poolId] = _params.mlaunchAt;
            emit PoolScheduled(poolId, _params.mlaunchAt);
        } else {
            // If the `flaunchAt` timestamp has already passed, then use the current timestamp
            // 如果`flaunchAt`时间戳已经过去，那么使用当前时间戳
            mlaunchesAt[poolId] = block.timestamp;
        }
    }

    function beforeInitialize(address sender, PoolKey calldata key, uint160 sqrtPriceX96)
        external
        onlyPoolManager
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function afterInitialize(address sender, PoolKey calldata key, uint160 sqrtPriceX96, int24 tick)
        external
        onlyPoolManager
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function beforeSwap(address sender, PoolKey calldata key, SwapParams calldata params, bytes calldata hookData)
        external
        onlyPoolManager
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        counts[key.toId()]["beforeSwap"] += 1;

        BeforeSwapDelta beforeSwapDelta_;
        BalanceDelta fairLaunchFillDelta;

        PoolId poolId = key.toId();
        uint256 _mlaunchsAt = mlaunchesAt[poolId];

        FairLaunch.FairLaunchInfo memory fairLaunchInfo = fairLaunch.fairLaunchInfo(poolId);

        if (!fairLaunchInfo.closed) {
            bool nativeIsZero = nativeToken == Currency.unwrap(key.currency0);

            if (!fairLaunch.inFairLaunchWindow(poolId)) {
                // 不在fair窗口期，所以执行关闭
                fairLaunch.closedPosition({_poolKey: key, _tokenFees: 0, _nativeIsZero: nativeIsZero});

                uint256 unsoldSupply = fairLaunchInfo.supply;
                if (unsoldSupply != 0) {
                    (nativeIsZero ? key.currency1 : key.currency0).transfer(BURN_ADDRESS, unsoldSupply);
                    emit FairLaunchBurn(poolId, unsoldSupply);
                }
            } else {
                // 在fairlaunch窗口期内
                if (nativeIsZero != params.zeroForOne) {
                    revert FairLaunch.CannotSellTokenDuringFairLaunch();
                }

                (beforeSwapDelta_, fairLaunchFillDelta, fairLaunchInfo) =
                    fairLaunch.fillFromPosition(key, params.amountSpecified, nativeIsZero);

                _settleDelta(key, fairLaunchFillDelta);

                if (fairLaunchInfo.supply == 0) {
                    fairLaunch.closedPosition({_poolKey: key, _tokenFees: 0, _nativeIsZero: nativeIsZero});
                }
            }
        }

        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) external onlyPoolManager returns (bytes4, int128) {
        counts[key.toId()]["afterSwap"] += 1;
        return (this.afterSwap.selector, 0);
    }

    function beforeAddLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        bytes calldata hookData
    ) external onlyPoolManager returns (bytes4) {
        counts[key.toId()]["beforeAddLiquidity"] += 1;
        return this.beforeAddLiquidity.selector;
    }

    function afterAddLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        BalanceDelta feesAccrued,
        bytes calldata hookData
    ) external onlyPoolManager returns (bytes4, BalanceDelta) {
        revert HookNotImplemented();
    }

    function beforeRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        bytes calldata hookData
    ) external onlyPoolManager returns (bytes4) {
        counts[key.toId()]["beforeRemoveLiquidity"] += 1;
        return this.beforeRemoveLiquidity.selector;
    }

    function afterRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        BalanceDelta feesAccrued,
        bytes calldata hookData
    ) external onlyPoolManager returns (bytes4, BalanceDelta) {
        revert HookNotImplemented();
    }

    function beforeDonate(
        address sender,
        PoolKey calldata key,
        uint256 amount0,
        uint256 amount1,
        bytes calldata hookData
    ) external onlyPoolManager returns (bytes4) {
        revert HookNotImplemented();
    }

    function afterDonate(
        address sender,
        PoolKey calldata key,
        uint256 amount0,
        uint256 amount1,
        bytes calldata hookData
    ) external onlyPoolManager returns (bytes4) {
        revert HookNotImplemented();
    }

    function setMlaunch(address _mlaunchContract) public {
        mlaunchContract = IMLaunch(_mlaunchContract);
    }

    function _settleDelta(PoolKey memory _poolKey, BalanceDelta _delta) internal {
        if (_delta.amount0() < 0) {
            _poolKey.currency0.settle(poolManager, address(this), uint256(-int256(_delta.amount0())), false);
        } else if (_delta.amount0() > 0) {
            poolManager.take(_poolKey.currency0, address(this), uint256(int256(_delta.amount0())));
        }

        if (_delta.amount1() < 0) {
            _poolKey.currency1.settle(poolManager, address(this), uint256(-int256(_delta.amount1())), false);
        } else if (_delta.amount1() > 0) {
            poolManager.take(_poolKey.currency1, address(this), uint256(int256(_delta.amount1())));
        }
    }
}
