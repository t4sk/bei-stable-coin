// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

interface ICollateralAuctionCallee {
    function callback(address, uint256, uint256, bytes calldata) external;
}
