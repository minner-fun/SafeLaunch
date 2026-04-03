// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/Console2.sol";

import {MLaunch} from "src/contracts/MLaunch.sol";
import {PositionManager} from "src/contracts/PositionManager.sol";
// import {Memecoin} from "src/contracts/Memecoin.sol";
import {HookMiner} from "src/contracts/libraries/HookMiner.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";

import {IPoolManager, PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {FairLaunch} from "src/contracts/hooks/FairLaunch.sol";

contract DeployMLaunch is Script, Deployers {
    PoolManager internal poolManager;
    /// @dev Foundry CREATE2 Deployer Proxy used in scripts.
    address internal constant CREATE2_DEPLOYER_PROXY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    function run() external returns (MLaunch, PositionManager, PoolManager, FairLaunch) {
        return deployContracts();
    }

    function deployContracts() internal returns (MLaunch, PositionManager, PoolManager, FairLaunch) {
        vm.startBroadcast();

        poolManager = new PoolManager(msg.sender);
        MLaunch mlaunch = new MLaunch();
        FairLaunch fairLaunch = new FairLaunch(poolManager);

        bytes32 salt = findSalt(address(fairLaunch));

        PositionManager positionManager = new PositionManager{salt: salt}(address(poolManager), fairLaunch);

        vm.stopBroadcast();

        console2.log("MLaunch deployed at: ", address(mlaunch));
        console2.log("PositionManager deployed at: ", address(positionManager));

        return (mlaunch, positionManager, poolManager, fairLaunch);
    }

    function findSalt(address _fairLaunch) public returns (bytes32) {
        (address addr, bytes32 salt) = find(
            CREATE2_DEPLOYER_PROXY,
            type(PositionManager).creationCode,
            abi.encode(address(poolManager), _fairLaunch), // 看find方法，第三个参数是为positiomManager的args参数
            uint160(
                Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
                    | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
            )
        );
        return salt;

        // assertEq(addr, address(new CounterHook{salt: salt}(POOL_MANAGER)));
    }

    function find(address deployer, bytes memory code, bytes memory args, uint160 flags)
        private
        returns (address, bytes32)
    {
        (address addr, bytes32 salt) =
            HookMiner.find({deployer: deployer, flags: flags, creationCode: code, constructorArgs: args});

        console2.log("Deployer:", deployer);
        console2.log("Hook address:", addr);
        console2.log("Hook salt:");
        console2.logBytes32(salt);

        return (addr, salt);
    }
}
