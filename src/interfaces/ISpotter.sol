// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IPriceFeed} from "./IPriceFeed.sol";

interface ISpotter {
    // par - reference per DAI
    function par() external returns (uint256);
    function collateral_types(bytes32) external returns (IPriceFeed, uint256);
}
