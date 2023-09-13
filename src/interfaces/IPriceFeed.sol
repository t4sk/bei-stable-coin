// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

// Pip
interface IPriceFeed {
    function peek() external returns (uint256, bool);
}
