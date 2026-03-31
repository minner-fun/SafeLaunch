// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/Console2.sol";

import {MLaunch} from "src/contracts/MLaunch.sol";
import {PositionManager} from "src/contracts/PositionManager.sol";
// import {Memecoin} from "src/contracts/Memecoin.sol";
import {HookMiner} from "src/contracts/libraries/HookMiner.sol";
import {Deployers} from '@uniswap/v4-core/test/utils/Deployers.sol';

import {IPoolManager, PoolManager} from '@uniswap/v4-core/src/PoolManager.sol';
import {Hooks} from '@uniswap/v4-core/src/libraries/Hooks.sol';

contract DeployMLaunch is Script, Deployers{

    PoolManager internal poolManager;



    function run() external returns(MLaunch){
        return deployContracts();
    }

    function deployContracts () internal returns(MLaunch){
        vm.startBroadcast();

        poolManager = new PoolManager(msg.sender);
        MLaunch mlaunch = new MLaunch();

        bytes32 salt = findSalt();

        PositionManager positionManager = new PositionManager{salt: salt}(address(poolManager));


        vm.stopBroadcast();

        console2.log('MLaunch deployed at: ', address(mlaunch));
        console2.log('PositionManager deployed at: ', address(positionManager));


        return mlaunch;
    }

    function findSalt() public returns (bytes32) {
        (address addr, bytes32 salt) = find(
            msg.sender,
            type(PositionManager).creationCode,
            abi.encode(poolManager),
            uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG
            )
        );
        return salt;

        // assertEq(addr, address(new CounterHook{salt: salt}(POOL_MANAGER)));
    }

    function find(
        address deployer,
        bytes memory code,
        bytes memory args,
        uint160 flags
    ) private returns (address, bytes32) {
        (address addr, bytes32 salt) = HookMiner.find({
            deployer: deployer,
            flags: flags,
            creationCode: code,
            constructorArgs: args
        });

        console2.log("Deployer:", deployer);
        console2.log("Hook address:", addr);
        console2.log("Hook salt:");
        console2.logBytes32(salt);

        return (addr, salt);
    }

} 