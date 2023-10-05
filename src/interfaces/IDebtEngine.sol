// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IDebtEngine {
    function pushDebtToQueue(uint256 debt) external;
}
