// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import {IGem} from "./IGem.sol";

interface IGemJoin {
    function dec() external returns (uint256);
    function gem() external returns (IGem);
    function join(address, uint256) external payable;
    function exit(address, uint256) external;
}
