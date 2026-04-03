// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IMemecoin is IERC20Metadata {
    function mint(address _to, uint256 _amount) external;
}
