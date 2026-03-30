// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

contract PositionManager {
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

    constructor() {}
}
