// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.24;

import {ICDPEngine} from "../interfaces/ICDPEngine.sol";
import {IDebtAuction} from "../interfaces/IDebtAuction.sol";
import {ISurplusAuction} from "../interfaces/ISurplusAuction.sol";
import {Math} from "../lib/Math.sol";
import {Auth} from "../lib/Auth.sol";
import {CircuitBreaker} from "../lib/CircuitBreaker.sol";

// Vow - Debt and surplus engine (receiver of surplus and debt)
/*
System Debt: In the case where Vaults are bitten (liquidated), their debt is
taken on by the Vow contract as a Sin (the system debt unit). The Sin amount
is then placed in the Sin queue. Note: When the Sin is not covered by a flip
auction (within the dedicated wait time, the Sin is considered to have bad
debt to the Vow. This bad debt is then covered through a debt auction (flop)
when it exceeds a minimum value (the lot size).
*/
contract DSEngine is Auth, CircuitBreaker {
    ICDPEngine public immutable cdp_engine;
    // flapper
    ISurplusAuction public surplus_auction;
    // flopper
    IDebtAuction public debt_auction;

    // sin (mapping timestamp => rad)
    mapping(uint256 => uint256) public debt_queue;
    // Sin [rad] - total debt pushed from liquidation engine
    uint256 public total_debt_on_queue;
    // Ash [rad]
    uint256 public total_debt_on_debt_auction;

    // wait [seconds]
    // 561600
    uint256 public pop_debt_delay;
    // dump [wad]
    // Amount of protocol tokens to be minted post-auction
    // 250000000000000000000
    uint256 public debt_auction_lot_size;
    // sump [rad]
    // Amount of debt sold in one debt auction
    // 50000000000000000000000000000000000000000000000000
    uint256 public debt_auction_bid_size;

    // bump [rad]
    // Amount of surplus stability fees sold in one surplus auction
    // 65000000000000000000000000000000000000000000000000
    uint256 public surplus_auction_lot_size;
    // hump [rad]
    // Amount of stability fees that need to accrue in this contract before any
    // surplus auction can start
    // 55000000000000000000000000000000000000000000000000000
    uint256 public min_surplus;

    constructor(
        address _cdp_engine,
        address _surplus_auction,
        address _debt_auction
    ) {
        cdp_engine = ICDPEngine(_cdp_engine);
        surplus_auction = ISurplusAuction(_surplus_auction);
        debt_auction = IDebtAuction(_debt_auction);
        cdp_engine.allow_account_modification(_surplus_auction);
    }

    // --- Administration ---
    function set(bytes32 key, uint256 val) external auth {
        if (key == "pop_debt_delay") {
            pop_debt_delay = val;
        } else if (key == "surplus_auction_lot_size") {
            surplus_auction_lot_size = val;
        } else if (key == "debt_auction_bid_size") {
            debt_auction_bid_size = val;
        } else if (key == "debt_auction_lot_size") {
            debt_auction_lot_size = val;
        } else if (key == "min_surplus") {
            min_surplus = val;
        } else {
            revert("unrecognized param");
        }
    }

    function set(bytes32 key, address val) external auth {
        if (key == "surplus_auction") {
            cdp_engine.deny_account_modification(address(surplus_auction));
            surplus_auction = ISurplusAuction(val);
            cdp_engine.allow_account_modification(val);
        } else if (key == "debt_auction") {
            debt_auction = IDebtAuction(val);
        } else {
            revert("unrecognized param");
        }
    }

    // fess
    // Called by LiquidationEngine
    function push_debt_to_queue(uint256 debt) external auth {
        debt_queue[block.timestamp] += debt;
        total_debt_on_queue += debt;
    }

    // flog - Pop from debt-queue
    // liquidation ok -> pop debt from queue
    //                -> total debt on queue is approx = unbacked debt
    //                -> cannot start debt auction
    // liquidation x  -> pop debt from queue
    //                -> total debt on queue < unbacked debt
    //                -> can start debt auction
    function pop_debt_from_queue(uint256 t) external {
        require(t + pop_debt_delay <= block.timestamp, "delay not finished");
        total_debt_on_queue -= debt_queue[t];
        debt_queue[t] = 0;
    }

    // heal - Debt settlement
    function settle_debt(uint256 rad) external {
        require(rad <= cdp_engine.coin(address(this)), "insufficient coin");
        // rad + total debt on queue + total debt on debt auction <= unbacked debt
        require(
            rad
                <= cdp_engine.unbacked_debts(address(this))
                    - total_debt_on_queue - total_debt_on_debt_auction,
            "insufficient debt"
        );
        cdp_engine.burn(rad);
    }

    // kiss
    // Called by DebtAuction.bid
    function decrease_auction_debt(uint256 rad) external {
        require(rad <= total_debt_on_debt_auction, "not enough debt on auction");
        require(rad <= cdp_engine.coin(address(this)), "insufficient coin");
        total_debt_on_debt_auction -= rad;
        // Decrease unbacked debt
        cdp_engine.burn(rad);
    }

    // flop
    // Debt auction
    function start_debt_auction() external returns (uint256 id) {
        //   bid size (amount to go into debt auction)
        // + total debt on queue (collateral auction)
        // + total debt on debt auction
        // <= unbacked debts
        require(
            debt_auction_bid_size + total_debt_on_queue
                    + total_debt_on_debt_auction
                <= cdp_engine.unbacked_debts(address(this)),
            "insufficient debt"
        );
        require(cdp_engine.coin(address(this)) == 0, "coin not zero");
        total_debt_on_debt_auction += debt_auction_bid_size;
        id = debt_auction.start({
            highest_bidder: address(this),
            lot: debt_auction_lot_size,
            bid_amount: debt_auction_bid_size
        });
    }

    // flap
    // Surplus auction
    function start_surplus_auction() external returns (uint256 id) {
        require(
            cdp_engine.coin(address(this))
                >= cdp_engine.unbacked_debts(address(this))
                    + surplus_auction_lot_size + min_surplus,
            "insufficient coin"
        );
        // unbacked debt = total debt on queue + total debt on auction
        // All unbacked debt must currently be in auctions
        require(
            cdp_engine.unbacked_debts(address(this))
                == total_debt_on_queue + total_debt_on_debt_auction,
            "debt not zero"
        );
        id = surplus_auction.start(surplus_auction_lot_size, 0);
    }

    function stop() external auth {
        _stop();
        total_debt_on_queue = 0;
        total_debt_on_debt_auction = 0;
        surplus_auction.stop(cdp_engine.coin(address(surplus_auction)));
        debt_auction.stop();
        cdp_engine.burn(
            Math.min(
                cdp_engine.coin(address(this)),
                cdp_engine.unbacked_debts(address(this))
            )
        );
    }
}
