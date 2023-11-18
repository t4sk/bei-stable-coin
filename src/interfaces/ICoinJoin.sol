// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

interface ICoinJoin {
    function cdp_engine() external returns (address);
    function coin() external returns (address);
    function join(address user, uint256 wad) external payable;
    function exit(address user, uint256 wad) external;
}
