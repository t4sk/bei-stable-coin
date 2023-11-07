// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

// Abacus
interface IAuctionPriceCalculator {
    // 1st arg: initial price               [ray]
    // 2nd arg: seconds since auction start [seconds]
    // returns: current auction price       [ray]
    function price(uint256, uint256) external view returns (uint256);
}
