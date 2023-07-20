// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IDai {
    function mint(address, uint256) external;
    function burn(address, uint256) external;
}
