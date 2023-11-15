// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

interface ICollateralAuctionCallee {
    function callback(
        address caller,
        uint256 owe,
        uint256 slice,
        bytes calldata data
    ) external;
}
