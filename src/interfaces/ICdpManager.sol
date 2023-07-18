// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ICdpManager {
    function open(bytes32, address) external returns (uint256);
}
