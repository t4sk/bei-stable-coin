// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

// Pip
interface IPriceFeed {
    function peek() external returns (uint256 val, bool ok);
}
