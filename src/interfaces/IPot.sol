// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

interface IPot {
    function pie(address user) external view returns (uint256);
    function collect_stability_fee() external returns (uint256 rate_acc);
    function join(uint256 wad) external;
    function exit(uint256 wad) external;
}
