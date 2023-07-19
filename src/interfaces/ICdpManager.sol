// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ICdpManager {
    function vat() external view returns (address);
    function safes(uint) external view returns (address);
    function collateralTypes(uint) external view returns (bytes32);
    function open(bytes32, address) external returns (uint256);
}
