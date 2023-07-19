// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IGem {
    function approve(address, uint256) external;
    function transfer(address, uint256) external;
    function transferFrom(address, address, uint256) external;
    function deposit() external payable;
    function withdraw(uint256) external;
}
