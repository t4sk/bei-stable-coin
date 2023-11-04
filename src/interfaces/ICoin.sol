// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ICoin {
    function mint(address, uint256) external;
    function burn(address, uint256) external;
    function decimals() external view returns (uint256);
    function approve(address, uint256) external;
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
    // function deposit() external payable;
    // function withdraw(uint256) external;
}
