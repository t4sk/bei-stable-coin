// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IDebtEngine {
    function push_debt_to_queue(uint256 debt) external;
}
