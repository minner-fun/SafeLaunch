// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {DeployMLaunch} from "script/DeployMLaunch.s.sol";

import {MLaunch} from "src/contracts/MLaunch.sol";

contract MLaunchTest is Test {
    string ml_name = "Mlaunch";
    string ml_symbol = "MLAUNCH";
    MLaunch s_mlaunch;

    function setUp() external {
        DeployMLaunch delpy = new DeployMLaunch();
        (s_mlaunch,,,) = delpy.run();
    }

    function testMLaunchName() public view {
        string memory _name = s_mlaunch.name();
        vm.assertEq(ml_name, _name);
    }

    function testMLaunchSymbol() public view {
        string memory _symbol = s_mlaunch.symbol();
        vm.assertEq(ml_symbol, _symbol);
    }
}
