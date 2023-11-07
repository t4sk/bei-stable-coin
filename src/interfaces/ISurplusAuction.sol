// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

interface ISurplusAuction {
    function start(uint256, uint256) external returns (uint256);
    function protocolToken() external view returns (address);
    function stop(uint256) external;
}
