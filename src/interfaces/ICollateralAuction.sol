// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

interface ICollateralAuction {
    function collateral_type() external view returns (bytes32);
    // TODO: rename inputs
    function start_auction(
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
