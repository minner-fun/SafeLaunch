// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";


interface IMemecoin is IERC20 {
    function mint(address _to, uint256 _amount) external;
}
