// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

interface IGem {
    function decimals() external view returns (uint8);
    function approve(address spender, uint256 amount) external;
    function transfer(address dst, uint256 amount) external returns (bool);
    function transferFrom(address src, address dst, uint256 amount) external returns (bool);
    // TODO: split interface for MKR
    function mint(address dst, uint256 amount) external;
    function burn(address src, uint256 amount) external;
    function push(address dst, uint256 wad) external;
    function pull(address src, uint256 wad) external;
    function move(address src, address dst, uint256 wad) external;
}
