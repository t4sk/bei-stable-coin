// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IPriceCalculator {
    function price(uint256, uint256) external view returns (uint256);
}
