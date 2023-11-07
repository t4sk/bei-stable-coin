// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

interface IDebtEngine {
    function push_debt_to_queue(uint256 debt) external;
}
