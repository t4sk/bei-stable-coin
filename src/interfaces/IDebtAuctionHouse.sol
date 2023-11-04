// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IDebtAuctionHouse {
    function start_auction(
        address incomeReceiver,
        uint256 amountToSell,
        uint256 initialBid
    ) external returns (uint256);
    function protocolToken() external view returns (address);
    function stop() external;
}
