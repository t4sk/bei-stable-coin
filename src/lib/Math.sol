// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

uint256 constant WAD = 10 ** 18;
uint256 constant RAY = 10 ** 27;
uint256 constant RAD = 10 ** 45;

library Math {
    // TODO: test
    function add(uint256 x, int256 y) internal pure returns (uint256 z) {
        z = y >= 0 ? x + uint256(y) : x - uint256(-y);
    }

    function sub(uint256 x, int256 y) internal pure returns (uint256 z) {
        z = y >= 0 ? x - uint256(y) : x + uint256(-y);
    }
}
