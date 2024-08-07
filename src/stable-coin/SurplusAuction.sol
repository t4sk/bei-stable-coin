// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.24;

import {ICDPEngine} from "../interfaces/ICDPEngine.sol";
import {ISurplusAuction} from "../interfaces/ISurplusAuction.sol";
import {IGem} from "../interfaces/IGem.sol";
import "../lib/Math.sol";
import {Auth} from "../lib/Auth.sol";
import {CircuitBreaker} from "../lib/CircuitBreaker.sol";

// Flapper
/*
Flapper is a Surplus Auction. 
- sell BEI, buy MKR
These auctions are used to auction off a fixed amount of the surplus BEI 
in the system for MKR. This surplus BEI will come from the Stability Fees 
that are accumulated from Vaults. In this auction type, bidders compete 
with increasing amounts of MKR. Once the auction has ended, 
the BEI auctioned off is sent to the winning bidder. 
The system then burns the MKR received from the winning bid.
*/

contract SurplusAuction is Auth, CircuitBreaker {
    // --- Events ---
    event Start(uint256 id, uint256 lot, uint256 bid);

    // --- Data ---
    mapping(uint256 => ISurplusAuction.Bid) public bids;

    // vat
    ICDPEngine public immutable cdp_engine;
    // gem - MKR
    IGem public immutable gem;

    // beg [wad] - minimum bid increase
    uint256 public min_bid_increase = 1.05e18;
    // ttl - bid lifetime (Max bid duration / single bid lifetime)
    uint48 public bid_duration = 3 hours;
    // tau - maximum auction duration
    uint48 public auction_duration = 2 days;
    // kicks - Total auction count, used to track auction ids
    uint256 public last_auction_id = 0;
    // lid [rad] - max BEI to be in auction at one time
    uint256 public max_coin_in_auction;
    // fill [rad] - current BEI in auction
    uint256 public total_coin_in_auction;

    constructor(address _cdp_engine, address _gem) {
        cdp_engine = ICDPEngine(_cdp_engine);
        gem = IGem(_gem);
    }

    // --- Admin ---
    function set(bytes32 key, uint256 val) external auth {
        if (key == "min_bid_increase") {
            min_bid_increase = val;
        } else if (key == "bid_duration") {
            bid_duration = uint48(val);
        } else if (key == "auction_duration") {
            auction_duration = uint48(val);
        } else if (key == "max_coin_in_auction") {
            max_coin_in_auction = val;
        } else {
            revert("unrecognized param");
        }
    }

    // --- Auction ---
    // kick
    function start(uint256 lot, uint256 bid_amount)
        external
        auth
        not_stopped
        returns (uint256 id)
    {
        total_coin_in_auction += lot;
        require(total_coin_in_auction <= max_coin_in_auction, "total > max");
        id = ++last_auction_id;

        bids[id] = ISurplusAuction.Bid({
            amount: bid_amount,
            lot: lot,
            highest_bidder: msg.sender,
            bid_expiry_time: 0,
            auction_end_time: uint48(block.timestamp) + auction_duration
        });

        cdp_engine.transfer_coin(msg.sender, address(this), lot);

        emit Start(id, lot, bid_amount);
    }

    // tick
    function restart(uint256 id) external {
        ISurplusAuction.Bid storage b = bids[id];
        require(b.auction_end_time < block.timestamp, "not finished");
        require(b.bid_expiry_time == 0, "bid already placed");
        b.auction_end_time = uint48(block.timestamp) + auction_duration;
    }

    // tend
    function bid(uint256 id, uint256 lot, uint256 bid_amount)
        external
        not_stopped
    {
        ISurplusAuction.Bid storage b = bids[id];
        require(b.highest_bidder != address(0), "bidder not set");
        // bid not expired or first bid
        require(
            block.timestamp < b.bid_expiry_time || b.bid_expiry_time == 0,
            "bid expired"
        );
        require(block.timestamp < b.auction_end_time, "auction ended");

        require(lot == b.lot, "lot not matching");
        require(bid_amount > b.amount, "bid <= current");
        require(
            bid_amount * WAD >= min_bid_increase * b.amount,
            "insufficient increase"
        );

        if (msg.sender != b.highest_bidder) {
            // 0   -> debt engine
            // 100 -> bidder 1
            // 110 -> bidder 2
            gem.move(msg.sender, b.highest_bidder, b.amount);
            b.highest_bidder = msg.sender;
        }
        // 100 <- bidder 1 (100 bid)
        // 10  <- bidder 2 (110 bid)
        // 20  <- bidder 3 (130 bid)
        gem.move(msg.sender, address(this), bid_amount - b.amount);

        b.amount = bid_amount;
        b.bid_expiry_time = uint48(block.timestamp) + auction_duration;
    }

    // deal
    function claim(uint256 id) external not_stopped {
        ISurplusAuction.Bid storage b = bids[id];
        require(
            b.bid_expiry_time != 0
                && (
                    b.bid_expiry_time < block.timestamp
                        || b.auction_end_time < block.timestamp
                ),
            "not finished"
        );
        cdp_engine.transfer_coin(address(this), b.highest_bidder, b.lot);
        gem.burn(address(this), b.amount);
        delete bids[id];
        total_coin_in_auction -= b.lot;
    }

    // cage
    function stop(uint256 rad) external auth {
        _stop();
        cdp_engine.transfer_coin(address(this), msg.sender, rad);
    }

    function yank(uint256 id) external not_stopped {
        ISurplusAuction.Bid storage b = bids[id];
        require(b.highest_bidder != address(0), "bidder not set");
        gem.move(address(this), b.highest_bidder, b.amount);
        delete bids[id];
    }
}
