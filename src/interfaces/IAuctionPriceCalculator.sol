// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.24;

// Abacus
interface IAuctionPriceCalculator {
    // 1st arg: initial price               [ray]
    // 2nd arg: seconds since auction start [seconds]
    // returns: current auction price       [ray]
    function price(uint256 top, uint256 dt) external view returns (uint256);
}
