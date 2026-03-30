// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PositionManager} from "src/contracts/PositionManager.sol";

interface IMLaunch {
    function mlaunch(PositionManager.MLaunchParams memory calldate)
        external
        returns (address memecoin_, uint256 tokenId_);
}
