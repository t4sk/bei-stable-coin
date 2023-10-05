// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ICollateralAuctionHouse {
    function startAuction(
        // address forgoneCollateralReceiver,
        // address initialBidder,
        // uint256 amountToRaise,
        // uint256 collateralToSell,
        // uint256 initialBid
        uint256 tab,
        uint256 lot,
        address user,
        address keeper
    ) external returns (uint256);
}
