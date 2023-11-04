// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ISurplusAuction {
    function start_auction(uint256, uint256) external returns (uint256);
    function protocolToken() external view returns (address);
    function stop(uint256) external;
}
