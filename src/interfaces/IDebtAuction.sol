// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

interface IDebtAuction {
    function start(
        address incomeReceiver,
        uint256 amountToSell,
        uint256 initialBid
    ) external returns (uint256);
    function protocolToken() external view returns (address);
    function stop() external;
}
