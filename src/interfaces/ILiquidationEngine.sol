// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

// Dog
interface ILiquidationEngine {
    function chop(bytes32) external returns (uint256);
    function digs(bytes32, uint256) external;
}
