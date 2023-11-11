// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

interface IJug {
    function drip(bytes32 col_type) external returns (uint256 rate);
}
