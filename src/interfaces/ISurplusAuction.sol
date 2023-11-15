// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

interface ISurplusAuction {
    function start(uint256 lot, uint256 bid_amount)
        external
        returns (uint256);
    function stop(uint256) external;
}
