// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

interface IJug {
    // TODO: what does it do?
    function drip(bytes32) external returns (uint256);
}
