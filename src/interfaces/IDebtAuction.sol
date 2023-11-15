// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

interface IDebtAuction {
    function start(address highest_bidder, uint256 lot, uint256 bid_amount)
        external
        returns (uint256 id);
    function stop() external;
}
