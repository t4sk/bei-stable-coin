// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import {IPriceFeed} from "./IPriceFeed.sol";

interface ISpotter {
    // par - reference per BEI
    function par() external returns (uint256);
    function collateral_types(bytes32) external returns (IPriceFeed, uint256);
}
