// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IVow {
    function pushDebtToQueue(uint256 debt) external;
}
