// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ICollateralAuctionHouseCallee {
    function callback(address, uint256, uint256, bytes calldata) external;
}
