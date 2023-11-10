// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

interface ICoin {
    function decimals() external view returns (uint8);
    function transfer(address dst, uint256 wad) external returns (bool);
    function transferFrom(address src, address dst, uint256 wad) external returns (bool);
    function approve(address spender, uint256 wad) external;
    function mint(address dst, uint256 wad) external;
    function burn(address src, uint256 wad) external;
    function push(address dst, uint256 wad) external;
    function pull(address src, uint256 wad) external;
    function move(address src, address dst, uint256 wad) external;
}
