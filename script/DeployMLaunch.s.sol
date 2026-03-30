// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/Console2.sol";

import {MLaunch} from "src/contracts/MLaunch.sol";
// import {Memecoin} from "src/contracts/Memecoin.sol";


contract DeployMLaunch is Script{
    function run() external returns(MLaunch){
        return deployContracts();
    }

    function deployContracts () internal returns(MLaunch){
        vm.startBroadcast();
        MLaunch mlaunch = new MLaunch();
        vm.stopBroadcast();

        console2.log('MLaunch deployed at: ', address(mlaunch));

        return mlaunch;
    }

} 