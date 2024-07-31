// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.24;

// Pip
interface IPriceFeed {
    // val [wad]
    function peek() external returns (uint256 val, bool ok);
}
