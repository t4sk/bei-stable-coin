// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import {ICDPEngine} from "../interfaces/ICDPEngine.sol";
import {IDebtEngine} from "../interfaces/IDebtEngine.sol";
import {IGem} from "../interfaces/IGem.sol";
import "../lib/Math.sol";
import {Auth} from "../lib/Auth.sol";
import {CircuitBreaker} from "../lib/CircuitBreaker.sol";

// Flopper
/*
Debt Auctions are used to recapitalize the system by auctioning off MKR 
for a fixed amount of DAI
*/
contract DebtAuction is Auth, CircuitBreaker {
    // --- Events ---
    event Start(uint256 id, uint256 lot, uint256 bid, address indexed gal);

    // --- Data ---
    struct Bid {
        // bid - dai paid [rad]
        uint256 bid;
        // lot - gems in return for bid [wad]
        // An individual object or group of objects offered for sale at auction as a single unit.
        uint256 lot;
        // guy - high bidder
        address guy;
        // tic - bid expiry time [unix epoch time]
        uint48 tic;
        // end - auction expiry time [unix epoch time]
        uint48 end;
    }

    mapping(uint256 => Bid) public bids;

    ICDPEngine public immutable cdp_engine;
    // gem - MKR
    IGem public immutable gem;

    uint256 public beg = 1.05e18; // 5% minimum bid increase
    uint256 public pad = 1.5e18; // 50% lot increase for tick
    uint48 public ttl = 3 hours; // 3 hours bid lifetime         [seconds]
    uint48 public tau = 2 days; // 2 days total auction length  [seconds]
    uint256 public kicks = 0;
    address public debt_engine; // not used until shutdown

    constructor(address _cdp_engine, address _gem) {
        cdp_engine = ICDPEngine(_cdp_engine);
        gem = IGem(_gem);
    }

    // --- Admin ---
    function set(bytes32 key, uint256 val) external auth {
        if (key == "beg") {
            beg = val;
        } else if (key == "pad") {
            pad = val;
        } else if (key == "ttl") {
            ttl = uint48(val);
        } else if (key == "tau") {
            tau = uint48(val);
        } else {
            revert("invalid param");
        }
    }

    // --- Auction ---
    // kick
    function start(address guy, uint256 lot, uint256 bid)
        external
        auth
        live
        returns (uint256 id)
    {
        id = ++kicks;

        bids[id] = Bid({
            bid: bid,
            lot: lot,
            guy: guy,
            tic: 0,
            end: uint48(block.timestamp) + tau
        });

        emit Start(id, lot, bid, guy);
    }

    // tick
    function tick(uint256 id) external {
        Bid storage bid = bids[id];
        require(bid.end < block.timestamp, "not finished");
        require(bid.tic == 0, "bid already placed");
        bid.lot = pad * bid.lot / WAD;
        bid.end = uint48(block.timestamp) + tau;
    }

    // dent
    function dent(uint256 id, uint256 lot, uint256 _bid) external live {
        Bid storage bid = bids[id];
        require(bid.guy != address(0), "guy-not-set");
        require(
            bid.tic > block.timestamp || bid.tic == 0, "already-finished-tic"
        );
        require(bid.end > block.timestamp, "already-finished-end");

        require(_bid == bid.bid, "not-matching-bid");
        require(lot < bid.lot, "lot-not-lower");
        require(beg * lot <= bids[id].lot * WAD, "insufficient-decrease");

        if (msg.sender != bid.guy) {
            cdp_engine.transfer_coin(msg.sender, bid.guy, _bid);

            // on first dent, clear as much Ash as possible
            if (bid.tic == 0) {
                uint256 debt = IDebtEngine(bid.guy).total_debt_on_auction();
                IDebtEngine(bid.guy).cancel_auctioned_debt_with_surplus(
                    Math.min(_bid, debt)
                );
            }

            bid.guy = msg.sender;
        }

        bid.lot = lot;
        bid.tic = uint48(block.timestamp) + ttl;
    }

    // deal
    function deal(uint256 id) external live {
        Bid storage bid = bids[id];
        require(
            bid.tic != 0
                && (bid.tic < block.timestamp || bid.end < block.timestamp),
            "not finished"
        );
        gem.mint(bid.guy, bid.lot);
        delete bids[id];
    }

    // --- Shutdown ---
    function stop() external auth {
        _stop();
        // TODO: why?
        debt_engine = msg.sender;
    }

    function yank(uint256 id) external live {
        Bid storage bid = bids[id];
        require(bid.guy != address(0), "guy-not-set");
        cdp_engine.mint(debt_engine, bid.guy, bid.bid);
        delete bids[id];
    }
}
