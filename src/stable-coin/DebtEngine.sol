// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import {ISafeEngine} from "../interfaces/ISafeEngine.sol";
import {IDebtAuction} from "../interfaces/IDebtAuction.sol";
import {ISurplusAuction} from "../interfaces/ISurplusAuction.sol";
import {Math} from "../lib/Math.sol";
import {Auth} from "../lib/Auth.sol";
import {CircuitBreaker} from "../lib/CircuitBreaker.sol";

// Vow - Debt engine
contract DebtEngine is Auth, CircuitBreaker {
    ISafeEngine public immutable safe_engine;
    // flapper
    ISurplusAuction public surplus_auction;
    // flopper
    IDebtAuction public debt_auction;

    // sin (mapping timestamp => rad)
    mapping(uint256 => uint256) public debt_queue;
    // Sin [rad]
    uint256 public total_debt_on_queue;
    // Ash [rad]
    uint256 public total_debt_on_auction;

    // wait [seconds]
    uint256 public pop_debt_delay;
    // dump [wad]
    // Amount of protocol tokens to be minted post-auction
    uint256 public debt_auction_lot_size;
    // sump [rad]
    // Amount of debt sold in one debt auction
    uint256 public debt_auction_bid_size;

    // bump [rad]
    // Amount of surplus stability fees sold in one surplus auction
    uint256 public surplus_auction_lot_size;
    // hump [rad]
    // Amount of stability fees that need to accrue in this contract before any
    // surplus auction can start
    uint256 public min_surplus;

    constructor(address _safe_engine, address _surplus_auction_house, address _debt_auction_house) {
        safe_engine = ISafeEngine(_safe_engine);
        surplus_auction = ISurplusAuction(_surplus_auction_house);
        debt_auction = IDebtAuction(_debt_auction_house);
        safe_engine.allow_account_modification(_surplus_auction_house);
    }

    // --- Administration ---
    function set(bytes32 key, uint256 val) external auth {
        if (key == "wait") {
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
            revert("invalid param");
        }
    }

    function set(bytes32 key, address addr) external auth {
        if (key == "surplus_auction") {
            safe_engine.deny_account_modification(address(surplus_auction));
            surplus_auction = ISurplusAuction(addr);
            safe_engine.allow_account_modification(addr);
        } else if (key == "debt_auction") {
            debt_auction = IDebtAuction(addr);
        } else {
            revert("invalid param");
        }
    }

    // fess
    function push_debt_to_queue(uint256 debt) external auth {
        debt_queue[block.timestamp] += debt;
        total_debt_on_queue += debt;
    }

    // flog - Pop from debt-queue
    function pop_debt_from_queue(uint256 t) external {
        require(t + pop_debt_delay <= block.timestamp, "wait not finished");
        total_debt_on_queue -= debt_queue[t];
        debt_queue[t] = 0;
    }

    // heal - Debt settlement
    function settle_debt(uint256 rad) external {
        require(rad <= safe_engine.coin(address(this)), "insufficient surplus");
        // TODO: what?
        require(
            rad <= safe_engine.debts(address(this)) - total_debt_on_queue - total_debt_on_auction,
            "insufficient debt"
        );
        safe_engine.burn(rad);
    }

    // kiss
    function cancel_auctioned_debt_with_surplus(uint256 rad) external {
        require(rad <= total_debt_on_auction, "not enough debt on auction");
        require(rad <= safe_engine.coin(address(this)), "insufficient surplus");
        // TODO: what?
        total_debt_on_auction -= rad;
        safe_engine.burn(rad);
    }

    // flop
    // Debt auction
    function start_debt_auction() external returns (uint256 id) {
        // TODO: what?
        require(
            debt_auction_bid_size
                <= safe_engine.debts(address(this)) - total_debt_on_queue - total_debt_on_auction,
            "insufficient debt"
        );
        require(safe_engine.coin(address(this)) == 0, "surplus not zero");
        total_debt_on_auction += debt_auction_bid_size;
        id = debt_auction.start(address(this), debt_auction_lot_size, debt_auction_bid_size);
    }

    // flap
    // Surplus auction
    function start_surplus_auction() external returns (uint256 id) {
        require(
            safe_engine.coin(address(this))
                >= safe_engine.debts(address(this)) + surplus_auction_lot_size + min_surplus,
            "insufficient surplus"
        );
        require(
            safe_engine.debts(address(this)) - total_debt_on_queue - total_debt_on_auction == 0,
            "debt not zero"
        );
        id = surplus_auction.start(surplus_auction_lot_size, 0);
    }

    function stop() external auth {
        _stop();
        total_debt_on_queue = 0;
        total_debt_on_auction = 0;
        surplus_auction.stop(safe_engine.coin(address(surplus_auction)));
        debt_auction.stop();
        safe_engine.burn(
            Math.min(safe_engine.coin(address(this)), safe_engine.debts(address(this)))
        );
    }
}
