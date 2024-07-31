// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.24;

interface IGemJoin {
    function decimals() external returns (uint8);
    function gem() external returns (address);
    function join(address user, uint256 amount) external payable;
    function exit(address user, uint256 amount) external;
}
