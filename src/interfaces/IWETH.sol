// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.24;

interface IWETH {
    function decimals() external view returns (uint8);
    function approve(address spender, uint256 amount) external;
    function transfer(address dst, uint256 amount) external returns (bool);
    function transferFrom(address src, address dst, uint256 amount)
        external
        returns (bool);
    function deposit() external payable;
    function withdraw(uint256) external;
}
