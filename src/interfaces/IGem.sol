// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

interface IGem {
    function decimals() external view returns (uint256);
    function approve(address, uint256) external;
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
    function deposit() external payable;
    function withdraw(uint256) external;
    function mint(address, uint256) external;
    function burn(address, uint256) external;
    function push(address usr, uint256 amount) external;
    function pull(address usr, uint256 amount) external;
    function move(address src, address dst, uint256 amount) external;
}
