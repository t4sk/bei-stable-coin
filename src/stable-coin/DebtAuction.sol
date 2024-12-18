// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.24;

import {ICDPEngine} from "../interfaces/ICDPEngine.sol";
import {IDSEngine} from "../interfaces/IDSEngine.sol";
import {IDebtAuction} from "../interfaces/IDebtAuction.sol";
import {IGem} from "../interfaces/IGem.sol";
import "../lib/Math.sol";
import {Auth} from "../lib/Auth.sol";
import {CircuitBreaker} from "../lib/CircuitBreaker.sol";

// Flopper
/*
Debt Auctions are used to recapitalize the system by auctioning off MKR
for a fixed amount of BEI
*/
contract DebtAuction is Auth, CircuitBreaker {
    // --- Events ---
    event Start(uint256 id, uint256 lot, uint256 bid, address indexed gal);

    // --- Data ---
    mapping(uint256 => IDebtAuction.Bid) public bids;

    // vat
    ICDPEngine public immutable cdp_engine;
    // gem - MKR
    IGem public immutable gem;

    // beg [wad] - minimum bid decrease
    uint256 public min_lot_decrease = 1.05e18; // 5% minimum bid increase
    // pad [wad] - increase for lot size during tick (default to 50%)
    uint256 public lot_increase = 1.5e18; // 50% lot increase for tick
    // ttl - bid lifetime (Max bid duration / single bid lifetime)
    uint48 public bid_duration = 3 hours; // 3 hours bid lifetime
    // tau - maximum auction duration
    uint48 public auction_duration = 2 days; // 2 days total auction length
    // kicks - Total auction count, used to track auction ids
    uint256 public last_auction_id = 0;
    // vow
    address public ds_engine; // not used until shutdown TODO: why?

    constructor(address _cdp_engine, address _gem) {
        cdp_engine = ICDPEngine(_cdp_engine);
        gem = IGem(_gem);
    }

    // --- Admin ---
    function set(bytes32 key, uint256 val) external auth {
        if (key == "min_lot_decrease") {
            min_lot_decrease = val;
        } else if (key == "lot_increase") {
            lot_increase = val;
        } else if (key == "bid_duration") {
            bid_duration = uint48(val);
        } else if (key == "auction_duration") {
            auction_duration = uint48(val);
        } else {
            revert("unrecognized param");
        }
    }

    // --- Auction ---
    // kick
    // start an auction / Put up a new MKR bid for auction
    // Called by DSEngine (vow)
    function start(address highest_bidder, uint256 lot, uint256 bid_amount)
        external
        auth
        not_stopped
        returns (uint256 id)
    {
        id = ++last_auction_id;

        bids[id] = IDebtAuction.Bid({
            amount: bid_amount,
            lot: lot,
            // highest_bidder = vow
            highest_bidder: highest_bidder,
            bid_expiry_time: 0,
            auction_end_time: uint48(block.timestamp) + auction_duration
        });

        emit Start(id, lot, bid_amount, highest_bidder);
    }

    // tick
    // restarts an auction
    function restart(uint256 id) external {
        IDebtAuction.Bid storage b = bids[id];
        require(b.auction_end_time < block.timestamp, "not finished");
        require(b.bid_expiry_time == 0, "bid already placed");
        b.lot = lot_increase * b.lot / WAD;
        b.auction_end_time = uint48(block.timestamp) + auction_duration;
    }

    // dent
    // make a bid, decreasing the lot size (Submit a fixed BEI bid with decreasing lot size)
    function bid(uint256 id, uint256 lot, uint256 bid_amount)
        external
        not_stopped
    {
        IDebtAuction.Bid storage b = bids[id];
        require(b.highest_bidder != address(0), "bidder not set");
        // bid not expired or no one has bid yet
        require(
            block.timestamp < b.bid_expiry_time || b.bid_expiry_time == 0,
            "already finished bid"
        );
        require(
            block.timestamp < b.auction_end_time, "already finished auction"
        );

        require(bid_amount == b.amount, "not matching bid");
        require(lot < b.lot, "lot not lower");
        // lot <= b.lot / min_lot_decrease
        require(min_lot_decrease * lot <= b.lot * WAD, "insufficient decrease");

        if (msg.sender != b.highest_bidder) {
            // Refund previous highest bidder
            cdp_engine.transfer_coin(msg.sender, b.highest_bidder, bid_amount);

            // on first dent, clear as much Ash as possible
            if (b.bid_expiry_time == 0) {
                uint256 debt =
                    IDSEngine(b.highest_bidder).total_debt_on_debt_auction();
                // On first dent, bid_expiry_time = 0 and highest_bidder = vow
                IDSEngine(b.highest_bidder).decrease_auction_debt(
                    Math.min(bid_amount, debt)
                );
            }

            b.highest_bidder = msg.sender;
        }

        b.lot = lot;
        b.bid_expiry_time = uint48(block.timestamp) + bid_duration;
    }

    // deal - claim a winning bid / settles a completed auction
    function claim(uint256 id) external not_stopped {
        IDebtAuction.Bid storage b = bids[id];
        require(
            b.bid_expiry_time != 0
                && (
                    b.bid_expiry_time < block.timestamp
                        || b.auction_end_time < block.timestamp
                ),
            "not finished"
        );
        gem.mint(b.highest_bidder, b.lot);
        delete bids[id];
    }

    // --- Shutdown ---
    function stop() external auth {
        _stop();
        // TODO: why?
        ds_engine = msg.sender;
    }

    function yank(uint256 id) external stopped {
        IDebtAuction.Bid storage b = bids[id];
        require(b.highest_bidder != address(0), "bidder not set");
        cdp_engine.mint(ds_engine, b.highest_bidder, b.amount);
        delete bids[id];
    }
}
