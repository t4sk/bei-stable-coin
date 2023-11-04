// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IVat} from "../interfaces/IVat.sol";
import {IDebtAuction} from "../interfaces/IDebtAuction.sol";
import {ISurplusAuction} from "../interfaces/ISurplusAuction.sol";
import {Math} from "../lib/Math.sol";
import {Auth} from "../lib/Auth.sol";
import {Pause} from "../lib/Pause.sol";

// TODO: rename to debt_engine
// Vow - Debt engine
contract Vow is Auth, Pause {
    IVat public immutable vat;
    // flapper
    ISurplusAuction public surplus_auction;
    // flopper
    IDebtAuction public debt_auction;

    // sin (mapping timestamp => rad)
    mapping(uint256 => uint256) public debt_queue; // debt queue
    // Sin
    uint256 public total_debt_on_queue; // Queued debt [rad]
    // Ash
    uint256 public total_debt_on_auction; // On-auction debt [rad]

    // wait
    uint256 public pop_debt_delay; // debt auction delay [seconds]
    // dump [wad]
    // Amount of protocol tokens to be minted post-auction
    uint256 public debt_auction_lot_size;
    // sump [rad]
    // Amount of debt sold in one debt auction
    // (initial coin bid for debt_auction_lot_size protocol tokens)
    uint256 public debt_auction_bid_size;

    // bump [rad]
    // Amount of surplus stability fees sold in one surplus auction
    uint256 public surplus_auction_lot_size;
    // hump [rad]
    // Amount of stability fees that need to accrue in this contract before any surplus auction can start
    uint256 public surplus_buffer;

    constructor(address _vat, address _surplus_auction_house, address _debt_auction_house) {
        vat = IVat(_vat);
        surplus_auction = ISurplusAuction(_surplus_auction_house);
        debt_auction = IDebtAuction(_debt_auction_house);
        vat.allow_account_modification(_surplus_auction_house);
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
        } else if (key == "surplus_buffer") {
            surplus_buffer = val;
        } else {
            revert("unrecognized param");
        }
    }

    function set(bytes32 key, address addr) external auth {
        if (key == "surplus_auction") {
            vat.deny_account_modification(address(surplus_auction));
            surplus_auction = ISurplusAuction(addr);
            vat.allow_account_modification(addr);
        } else if (key == "debt_auction") {
            debt_auction = IDebtAuction(addr);
        } else {
            revert("unrecognized param");
        }
    }

    // fess
    /**
     * @notice Push bad debt into a queue
     * @dev Debt is locked in a queue to give the system enough time to auction collateral
     *      and gather surplus
     */
    function push_debt_to_queue(uint256 debt) external auth {
        debt_queue[block.timestamp] += debt;
        total_debt_on_queue += debt;
    }

    // flog - Pop from debt-queue
    /**
     * @notice Pop a block of bad debt from the debt queue
     */
    function pop_debt_from_queue(uint256 t) external {
        require(t + pop_debt_delay <= block.timestamp, "wait not finished");
        total_debt_on_queue -= debt_queue[t];
        debt_queue[t] = 0;
    }

    // heal - Debt settlement
    /**
     * @notice Destroy an equal amount of coins and bad debt
     * @dev We can only destroy debt that is not locked in the queue and also not in a debt auction
     *
     */
    function settle_debt(uint256 rad) external {
        require(rad <= vat.coin(address(this)), "insufficient surplus");
        // TODO: what?
        require(rad <= vat.debts(address(this)) - total_debt_on_queue - total_debt_on_auction, "insufficient debt");
        vat.burn(rad);
    }

    // kiss
    /**
     * @notice Use surplus coins to destroy debt that was in a debt auction
     *
     */
    function cancel_auctioned_debt_with_surplus(uint256 rad) external {
        require(rad <= total_debt_on_auction, "not enough debt on auction");
        require(rad <= vat.coin(address(this)), "insufficient surplus");
        // TODO: what?
        total_debt_on_auction -= rad;
        vat.burn(rad);
    }

    // Debt auction
    /**
     * @notice Start a debt auction (print protocol tokens in exchange for coins so that the
     *         system can be recapitalized)
     * @dev We can only auction debt that is not already being auctioned and is not locked in the debt queue
     *
     */
    function start_debt_auction() external returns (uint256 id) {
        // TODO: what?
        require(
            debt_auction_bid_size <= vat.debts(address(this)) - total_debt_on_queue - total_debt_on_auction,
            "insufficient debt"
        );
        require(vat.coin(address(this)) == 0, "surplus not zero");
        total_debt_on_auction += debt_auction_bid_size;
        id = debt_auction.start_auction(address(this), debt_auction_lot_size, debt_auction_bid_size);
    }

    // Surplus auction
    /**
     * @notice Start a surplus auction
     * @dev We can only auction surplus if we wait at least 'surplusAuctionDelay' seconds since the last
     *      surplus auction trigger, if we keep enough surplus in the buffer and if there is no bad debt left to burn
     *
     */
    function start_surplus_auction() external returns (uint256 id) {
        require(
            vat.coin(address(this)) >= vat.debts(address(this)) + surplus_auction_lot_size + surplus_buffer,
            "insufficient surplus"
        );
        require(vat.debts(address(this)) - total_debt_on_queue - total_debt_on_auction == 0, "debt not zero");
        id = surplus_auction.start_auction(surplus_auction_lot_size, 0);
    }

    function stop() external auth {
        _stop();
        total_debt_on_queue = 0;
        total_debt_on_auction = 0;
        surplus_auction.stop(vat.coin(address(surplus_auction)));
        debt_auction.stop();
        vat.burn(Math.min(vat.coin(address(this)), vat.debts(address(this))));
    }
}
