// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

interface ISurplusAuction {
    struct Bid {
        // bid [wad] - MKR paid
        uint256 amount;
        // lot [rad] - BEI in return for bid
        uint256 lot;
        // guy - high bidder
        address highest_bidder;
        // tic - bid expiry time
        uint48 bid_expiry_time;
        // end - auction expiry time
        uint48 auction_end_time;
    }

    function bids(uint256 id) external view returns (Bid memory);
    function start(uint256 lot, uint256 bid_amount)
        external
        returns (uint256);
    function stop(uint256) external;
}
