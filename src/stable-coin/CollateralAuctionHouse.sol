// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IVat} from "../interfaces/IVat.sol";
import {ILiquidationEngine} from "../interfaces/ILiquidationEngine.sol";
import {ISpotter} from "../interfaces/ISpotter.sol";
import {IPriceCalculator} from "../interfaces/IPriceCalculator.sol";
import {ICollateralAuctionHouseCallee} from
    "../interfaces/ICollateralAuctionHouseCallee.sol";
import {IPriceFeed} from "../interfaces/IPriceFeed.sol";
import "../lib/Math.sol";
import {Auth} from "../lib/Auth.sol";

contract CollateralAuctionHouse is Auth {
    bytes32 public immutable collateral_type;
    IVat public immutable vat;

    // dog
    ILiquidationEngine public liquidation_engine;
    // vow
    address public debt_engine; // Recipient of dai raised in auctions
    ISpotter public spotter; // Collateral price module
    // Abacus
    IPriceCalculator public calc; // Current price calculator

    uint256 public buf; // Multiplicative factor to increase starting price                  [ray]
    // tail
    uint256 public max_duration; // Time elapsed before auction reset                                 [seconds]
    // cusp
    uint256 public min_delta_price_ratio; // Percentage drop before auction reset                              [ray]
    // chip
    uint64 public chip; // Percentage of dai_to_raise to mint from debt_engine to incentivize keepers         [wad]
    // tip
    uint192 public flat_fee; // Flat fee to mint from debt_engine to incentivize keepers                  [rad]
    // chost
    uint256 public cache; // Cache the collateral_type dust times the collateral_type chop to prevent excessive SLOADs [rad]

    // kicks
    uint256 public last_auction_id; // Total auctions
    uint256[] public active; // Array of active auction ids

    struct Sale {
        // Index in active array
        uint256 pos;
        // tab
        // Dai to raise       [rad]
        uint256 dai_to_raise;
        // lot
        // collateral to sell [wad]
        uint256 collateral_to_sell;
        // usr
        // Liquidated CDP
        address user;
        // tick
        // Auction start time
        uint96 start_time;
        // top
        // Starting price     [ray]
        uint256 starting_price;
    }

    mapping(uint256 => Sale) public sales;

    uint256 internal locked;

    // Levels for circuit breaker
    // 0: no breaker
    // 1: no new kick()
    // 2: no new kick() or redo()
    // 3: no new kick(), redo(), or take()
    uint256 public stopped = 0;

    // --- Events ---
    event File(bytes32 indexed what, uint256 data);
    event File(bytes32 indexed what, address data);

    event Kick(
        uint256 indexed id,
        uint256 starting_price,
        uint256 dai_to_raise,
        uint256 collateral_to_sell,
        address indexed user,
        address indexed keeper,
        uint256 coin
    );
    event Take(
        uint256 indexed id,
        uint256 max,
        uint256 price,
        uint256 owe,
        uint256 dai_to_raise,
        uint256 collateral_to_sell,
        address indexed user
    );
    event Redo(
        uint256 indexed id,
        uint256 starting_price,
        uint256 dai_to_raise,
        uint256 collateral_to_sell,
        address indexed user,
        address indexed keeper,
        uint256 coin
    );

    event Yank(uint256 id);

    // --- Init ---
    constructor(
        address vat_,
        address spotter_,
        address liquidation_engine_,
        bytes32 collateral_type_
    ) {
        vat = IVat(vat_);
        spotter = ISpotter(spotter_);
        liquidation_engine = ILiquidationEngine(liquidation_engine_);
        collateral_type = collateral_type_;
        buf = RAY;
    }

    // --- Synchronization ---
    modifier lock() {
        require(locked == 0, "Clipper/system-locked");
        locked = 1;
        _;
        locked = 0;
    }

    modifier isStopped(uint256 level) {
        require(stopped < level, "Clipper/stopped-incorrect");
        _;
    }

    // --- Administration ---
    // function file(bytes32 what, uint256 data) external auth lock {
    //     if (what == "buf") buf = data;
    //     else if (what == "max_duration") max_duration = data; // Time elapsed before auction reset

    //     else if (what == "min_delta_price_ratio") min_delta_price_ratio = data; // Percentage drop before auction reset

    //     else if (what == "chip") chip = uint64(data); // Percentage of dai_to_raise to incentivize (max: 2^64 - 1 => 18.xxx WAD = 18xx%)

    //     else if (what == "flat_fee") flat_fee = uint192(data); // Flat fee to incentivize keepers (max: 2^192 - 1 => 6.277T RAD)

    //     else if (what == "stopped") stopped = data; // Set breaker (0, 1, 2, or 3)

    //     else revert("Clipper/file-unrecognized-param");
    //     emit File(what, data);
    // }

    // function file(bytes32 what, address data) external auth lock {
    //     if (what == "spotter") {
    //         spotter = ISpotter(data);
    //     } else if (what == "liquidation_engine") {
    //         liquidation_engine = ILiquidationEngine(data);
    //     } else if (what == "debt_engine") {
    //         debt_engine = data;
    //     } else if (what == "calc") {
    //         calc = IPriceCalculator(data);
    //     } else {
    //         revert("Clipper/file-unrecognized-param");
    //     }
    //     emit File(what, data);
    // }

    // --- Auction ---

    // get the price directly from the OSM
    // Could get this from rmul(Vat.ilks(collateral_type).spot, Spotter.mat()) instead, but
    // if mat has changed since the last poke, the resulting value will be
    // incorrect.
    function get_price_feed() internal returns (uint256 price) {
        (IPriceFeed price_feed,) = spotter.collateral_types(collateral_type);
        (uint256 val, bool ok) = price_feed.peek();
        require(ok, "invalid-price");
        price = Math.rdiv(val * BLN, spotter.par());
    }

    // start an auction
    // note: trusts the caller to transfer collateral to the contract
    // The starting price `starting_price` is obtained as follows:
    //
    //     starting_price = val * buf / par
    //
    // Where `val` is the collateral's unitary value in USD, `buf` is a
    // multiplicative factor to increase the starting price, and `par` is a
    // reference per DAI.
    function kick(
        uint256 dai_to_raise, // Debt                   [rad]
        uint256 collateral_to_sell, // Collateral             [wad]
        address user, // Address that will receive any leftover collateral
        address keeper // Address that will receive incentives
    ) external auth lock isStopped(1) returns (uint256 id) {
        // Input validation
        require(dai_to_raise > 0, "Clipper/zero-dai_to_raise");
        require(collateral_to_sell > 0, "Clipper/zero-collateral_to_sell");
        require(user != address(0), "Clipper/zero-user");
        id = ++last_auction_id;
        require(id > 0, "Clipper/overflow");

        active.push(id);

        sales[id].pos = active.length - 1;
        sales[id].dai_to_raise = dai_to_raise;
        sales[id].collateral_to_sell = collateral_to_sell;
        sales[id].user = user;
        sales[id].start_time = uint96(block.timestamp);

        uint256 starting_price;
        starting_price = Math.rmul(get_price_feed(), buf);
        require(starting_price > 0, "Clipper/zero-starting_price-price");
        sales[id].starting_price = starting_price;

        // incentive to kick auction
        uint256 fee = flat_fee;
        uint256 _chip = chip;
        uint256 coin;
        if (fee > 0 || _chip > 0) {
            coin = fee + Math.wmul(dai_to_raise, _chip);
            vat.mint(debt_engine, keeper, coin);
        }

        emit Kick(
            id,
            starting_price,
            dai_to_raise,
            collateral_to_sell,
            user,
            keeper,
            coin
        );
    }

    // Reset an auction
    // See `kick` above for an explanation of the computation of `starting_price`.
    function redo(
        uint256 id, // id of the auction to reset
        address keeper // Address that will receive incentives
    ) external lock isStopped(2) {
        // Read auction data
        address user = sales[id].user;
        uint96 start_time = sales[id].start_time;
        uint256 starting_price = sales[id].starting_price;

        require(user != address(0), "not-running-auction");

        // Check that auction needs reset
        // and compute current price [ray]
        (bool done,) = status(start_time, starting_price);
        require(done, "cannot-reset");

        uint256 dai_to_raise = sales[id].dai_to_raise;
        uint256 collateral_to_sell = sales[id].collateral_to_sell;
        sales[id].start_time = uint96(block.timestamp);

        uint256 feed_price = get_price_feed();
        starting_price = Math.rmul(feed_price, buf);
        require(starting_price > 0, "zero-starting_price-price");
        sales[id].starting_price = starting_price;

        // incentive to redo auction
        uint256 fee = flat_fee;
        uint256 _chip = chip;
        uint256 coin;
        if (fee > 0 || _chip > 0) {
            uint256 _cache = cache;
            if (
                dai_to_raise >= _cache
                    && collateral_to_sell * feed_price >= _cache
            ) {
                coin = fee + Math.wmul(dai_to_raise, _chip);
                vat.mint(debt_engine, keeper, coin);
            }
        }

        emit Redo(
            id,
            starting_price,
            dai_to_raise,
            collateral_to_sell,
            user,
            keeper,
            coin
        );
    }

    // Buy up to `amt` of collateral from the auction indexed by `id`.
    //
    // Auctions will not collect more DAI than their assigned DAI target,`dai_to_raise`;
    // thus, if `amt` would cost more DAI than `dai_to_raise` at the current price, the
    // amount of collateral purchased will instead be just enough to collect `dai_to_raise` DAI.
    //
    // To avoid partial purchases resulting in very small leftover auctions that will
    // never be cleared, any partial purchase must leave at least `Clipper.chost`
    // remaining DAI target. `chost` is an asynchronously updated value equal to
    // (Vat.dust * Dog.chop(collateral_type) / WAD) where the values are understood to be determined
    // by whatever they were when Clipper.upchost() was last called. Purchase amounts
    // will be minimally decreased when necessary to respect this limit; i.e., if the
    // specified `amt` would leave `dai_to_raise < chost` but `dai_to_raise > 0`, the amount actually
    // purchased will be such that `dai_to_raise == chost`.
    //
    // If `dai_to_raise <= chost`, partial purchases are no longer possible; that is, the remaining
    // collateral can only be purchased entirely, or not at all.
    function take(
        uint256 id, // Auction id
        uint256 amt, // Upper limit on amount of collateral to buy  [wad]
        uint256 max, // Maximum acceptable price (DAI / collateral) [ray]
        // who
        address collateral_receiver, // Receiver of collateral and external call address
        bytes calldata data // Data to pass in external call; if length 0, no call is done
    ) external lock isStopped(3) {
        address user = sales[id].user;
        uint96 start_time = sales[id].start_time;

        require(user != address(0), "not-running-auction");

        uint256 price;
        {
            bool done;
            (done, price) = status(start_time, sales[id].starting_price);

            // Check that auction doesn't need reset
            require(!done, "needs-reset");
        }

        // Ensure price is acceptable to buyer
        require(max >= price, "too-expensive");

        uint256 collateral_to_sell = sales[id].collateral_to_sell;
        uint256 dai_to_raise = sales[id].dai_to_raise;
        uint256 owe;

        {
            // Purchase as much as possible, up to amt
            uint256 slice = Math.min(collateral_to_sell, amt); // slice <= collateral_to_sell

            // DAI needed to buy a slice of this sale
            owe = slice * price;

            // Don't collect more than dai_to_raise of DAI
            if (owe > dai_to_raise) {
                // Total debt will be paid
                owe = dai_to_raise; // owe' <= owe
                // Adjust slice
                slice = owe / price; // slice' = owe' / price <= owe / price == slice <= collateral_to_sell
            } else if (owe < dai_to_raise && slice < collateral_to_sell) {
                // If slice == collateral_to_sell => auction completed => dust doesn't matter
                uint256 _cache = cache;
                if (dai_to_raise - owe < _cache) {
                    // safe as owe < dai_to_raise
                    // If dai_to_raise <= chost, buyers have to take the entire collateral_to_sell.
                    require(dai_to_raise > _cache, "no-partial-purchase");
                    // Adjust amount to pay
                    owe = dai_to_raise - _cache; // owe' <= owe
                    // Adjust slice
                    slice = owe / price; // slice' = owe' / price < owe / price == slice < collateral_to_sell
                }
            }

            // Calculate remaining dai_to_raise after operation
            dai_to_raise -= owe; // safe since owe <= dai_to_raise
            // Calculate remaining collateral_to_sell after operation
            collateral_to_sell -= slice;

            // Send collateral to who
            vat.transfer_collateral(
                collateral_type, address(this), collateral_receiver, slice
            );

            // Do external call (if data is defined) but to be
            // extremely careful we don't allow to do it to the two
            // contracts which the Clipper needs to be authorized
            if (
                data.length > 0 && collateral_receiver != address(vat)
                    && collateral_receiver != address(liquidation_engine)
            ) {
                ICollateralAuctionHouseCallee(collateral_receiver).callback(
                    msg.sender, owe, slice, data
                );
            }

            // Get DAI from caller
            vat.transfer_coin(msg.sender, debt_engine, owe);

            // Removes Dai out for liquidation from accumulator
            liquidation_engine.removeDaiFromAuction(
                collateral_type,
                collateral_to_sell == 0 ? dai_to_raise + owe : owe
            );
        }

        if (collateral_to_sell == 0) {
            _remove(id);
        } else if (dai_to_raise == 0) {
            vat.transfer_collateral(
                collateral_type, address(this), user, collateral_to_sell
            );
            _remove(id);
        } else {
            sales[id].dai_to_raise = dai_to_raise;
            sales[id].collateral_to_sell = collateral_to_sell;
        }

        emit Take(id, max, price, owe, dai_to_raise, collateral_to_sell, user);
    }

    function _remove(uint256 id) internal {
        uint256 last = active[active.length - 1];
        if (id != last) {
            uint256 pos = sales[id].pos;
            active[pos] = last;
            sales[last].pos = pos;
        }
        active.pop();
        delete sales[id];
    }

    // The number of active auctions
    function count() external view returns (uint256) {
        return active.length;
    }

    // Return the entire array of active auctions
    function list() external view returns (uint256[] memory) {
        return active;
    }

    // Externally returns boolean for if an auction needs a redo and also the current price
    // function getStatus(uint256 id)
    //     external
    //     view
    //     returns (
    //         bool needsRedo,
    //         uint256 price,
    //         uint256 collateral_to_sell,
    //         uint256 dai_to_raise
    //     )
    // {
    //     // Read auction data
    //     address user = sales[id].user;
    //     uint96 start_time = sales[id].start_time;

    //     bool done;
    //     (done, price) = status(start_time, sales[id].starting_price);

    //     needsRedo = user != address(0) && done;
    //     collateral_to_sell = sales[id].collateral_to_sell;
    //     dai_to_raise = sales[id].dai_to_raise;
    // }

    // Internally returns boolean for if an auction needs a redo
    function status(uint96 start_time, uint256 starting_price)
        internal
        view
        returns (bool done, uint256 price)
    {
        price = calc.price(starting_price, block.timestamp - start_time);
        done = (
            block.timestamp - start_time > max_duration
                || Math.rdiv(price, starting_price) < min_delta_price_ratio
        );
    }

    // Public function to update the cached dust*chop value.
    // upchost
    function update_cache() external {
        IVat.CollateralType memory col = IVat(vat).cols(collateral_type);
        cache =
            Math.wmul(col.floor, liquidation_engine.penalty(collateral_type));
    }

    // // Cancel an auction during ES or via governance action.
    // function yank(uint256 id) external auth lock {
    //     require(sales[id].user != address(0), "Clipper/not-running-auction");
    //     liquidation_engine.digs(collateral_type, sales[id].dai_to_raise);
    //     vat.flux(
    //         collateral_type,
    //         address(this),
    //         msg.sender,
    //         sales[id].collateral_to_sell
    //     );
    //     _remove(id);
    //     emit Yank(id);
    // }
}
