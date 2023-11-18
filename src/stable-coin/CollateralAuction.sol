// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import {ICDPEngine} from "../interfaces/ICDPEngine.sol";
import {ILiquidationEngine} from "../interfaces/ILiquidationEngine.sol";
import {ISpotter} from "../interfaces/ISpotter.sol";
import {IPriceFeed} from "../interfaces/IPriceFeed.sol";
import {IAuctionPriceCalculator} from
    "../interfaces/IAuctionPriceCalculator.sol";
import {ICollateralAuctionCallee} from
    "../interfaces/ICollateralAuctionCallee.sol";
import {IPriceFeed} from "../interfaces/IPriceFeed.sol";
import "../lib/Math.sol";
import {Auth} from "../lib/Auth.sol";
import {Guard} from "../lib/Guard.sol";

// Clipper
contract CollateralAuction is Auth, Guard {
    bytes32 public immutable collateral_type;
    ICDPEngine public immutable cdp_engine;

    // dog
    ILiquidationEngine public liquidation_engine;
    // debt_engine - Recipient of BEI raised in auctions
    address public debt_engine;
    // Collateral price module
    ISpotter public spotter;
    // calc - Current price calculator
    IAuctionPriceCalculator public calc;

    // buf - Multiplicative factor to increase starting price [ray]
    uint256 public buf;
    // tail - Time elapsed before auction reset [seconds]
    uint256 public max_duration;
    // cusp - Percentage drop before auction reset [ray]
    uint256 public min_delta_price_ratio;
    // chip - Percentage of coin to raise, to mint from debt_engine to incentivize keepers [wad]
    uint64 public fee_rate;
    // tip - Flat fee to mint from debt_engine to incentivize keepers [rad]
    uint192 public flat_fee;
    // chost - Cache the collateral_type dust times the collateral_type chop to prevent excessive SLOADs [rad]
    uint256 public cache;

    // kicks - Total auctions
    uint256 public last_auction_id;
    // Array of active auction ids
    uint256[] public active;

    struct Sale {
        // Index in active array
        uint256 pos;
        // tab - Amount of coin to raise [rad]
        uint256 coin_amount;
        // lot - Amount of collateral to sell [wad]
        uint256 collateral_amount;
        // usr - Liquidated CDP
        address user;
        // tick - Auction start time
        uint96 start_time;
        // top - Starting price [ray]
        uint256 starting_price;
    }

    // id => Sale
    mapping(uint256 => Sale) public sales;

    // Levels for circuit breaker
    // 0: no breaker
    // 1: no new kick()
    // 2: no new kick() or redo()
    // 3: no new kick(), redo(), or take()
    uint256 public stopped = 0;

    // --- Events ---
    event Start(
        uint256 indexed id,
        uint256 starting_price,
        uint256 coin_amount,
        uint256 collateral_amount,
        address indexed user,
        address indexed keeper,
        uint256 fee
    );
    event Take(
        uint256 indexed id,
        uint256 max_collateral_amount,
        uint256 price,
        uint256 owe,
        uint256 coin_amount,
        uint256 collateral_amount,
        address indexed user
    );
    event Redo(
        uint256 indexed id,
        uint256 starting_price,
        uint256 coin_amount,
        uint256 collateral_amount,
        address indexed user,
        address indexed keeper,
        uint256 fee
    );
    event Yank(uint256 id);

    // --- Init ---
    constructor(
        address vat_,
        address spotter_,
        address liquidation_engine_,
        bytes32 collateral_type_
    ) {
        cdp_engine = ICDPEngine(vat_);
        spotter = ISpotter(spotter_);
        liquidation_engine = ILiquidationEngine(liquidation_engine_);
        collateral_type = collateral_type_;
        buf = RAY;
    }

    // --- Synchronization ---
    modifier not_stopped(uint256 level) {
        require(stopped < level, "stopped");
        _;
    }

    // --- Administration ---
    // file
    function set(bytes32 key, uint256 val) external auth lock {
        if (key == "buf") {
            buf = val;
        } else if (key == "max_duration") {
            // Time elapsed before auction reset
            max_duration = val;
        } else if (key == "min_delta_price_ratio") {
            // Percentage drop before auction reset
            min_delta_price_ratio = val;
        } else if (key == "fee_rate") {
            // Percentage of coin_amount to incentivize (max: 2^64 - 1 => 18.xxx WAD = 18xx%)
            fee_rate = uint64(val);
        } else if (key == "flat_fee") {
            // Flat fee to incentivize keepers (max: 2^192 - 1 => 6.277T RAD)
            flat_fee = uint192(val);
        } else if (key == "stopped") {
            // Set breaker (0, 1, 2, or 3)
            stopped = val;
        } else {
            revert("invalid param");
        }
    }

    // file
    function set(bytes32 key, address addr) external auth lock {
        if (key == "spotter") {
            spotter = ISpotter(addr);
        } else if (key == "liquidation_engine") {
            liquidation_engine = ILiquidationEngine(addr);
        } else if (key == "debt_engine") {
            debt_engine = addr;
        } else if (key == "calc") {
            calc = IAuctionPriceCalculator(addr);
        } else {
            revert("invalid param");
        }
    }

    // --- Auction ---
    // get the price directly from the OSM
    // Could get this from rmul(CDPEngine.ilks(collateral_type).spot, Spotter.mat()) instead, but
    // if mat has changed since the last poke, the resulting value will be
    // incorrect.
    function get_price() internal returns (uint256 price) {
        ISpotter.Collateral memory col = spotter.collaterals(collateral_type);
        (uint256 val, bool ok) = IPriceFeed(col.price_feed).peek();
        require(ok, "invalid price");
        // TODO: math?
        price = Math.rdiv(val * 1e9, spotter.par());
    }

    // kick - start an auction
    // note: trusts the caller to transfer collateral to the contract
    // The starting price `starting_price` is obtained as follows:
    //
    //     starting_price = val * buf / par
    //
    // Where `val` is the collateral's unitary value in USD, `buf` is a
    // multiplicative factor to increase the starting price, and `par` is a
    // reference per BEI.
    function start(
        uint256 coin_amount, // tab - Debt [rad]
        uint256 collateral_amount, // lot - Collateral [wad]
        // TODO: rename user to cdp?
        address user, // Address that will receive any leftover collateral
        address keeper // Address that will receive incentives
    ) external auth lock not_stopped(1) returns (uint256 id) {
        require(coin_amount > 0, "zero coin amount");
        require(collateral_amount > 0, "zero collateral amount");
        require(user != address(0), "zero address user");
        id = ++last_auction_id;

        active.push(id);

        sales[id].pos = active.length - 1;
        sales[id].coin_amount = coin_amount;
        sales[id].collateral_amount = collateral_amount;
        sales[id].user = user;
        sales[id].start_time = uint96(block.timestamp);

        uint256 starting_price = Math.rmul(get_price(), buf);
        require(starting_price > 0, "zero starting price");
        sales[id].starting_price = starting_price;

        // incentive to start auction
        uint256 fee;
        if (flat_fee > 0 || fee_rate > 0) {
            // TODO: check units
            fee = flat_fee + Math.wmul(coin_amount, fee_rate);
            cdp_engine.mint({debt_dst: debt_engine, coin_dst: keeper, rad: fee});
        }

        emit Start(
            id,
            starting_price,
            coin_amount,
            collateral_amount,
            user,
            keeper,
            fee
        );
    }

    // Reset an auction
    // See `kick` above for an explanation of the computation of `starting_price`.
    function redo(
        uint256 id, // id of the auction to reset
        address keeper // Address that will receive incentives
    ) external lock not_stopped(2) {
        // Read auction data
        address user = sales[id].user;
        uint96 start_time = sales[id].start_time;
        uint256 starting_price = sales[id].starting_price;

        require(user != address(0), "not running auction");

        // Check that auction needs reset
        // and compute current price [ray]
        (bool done,) = status(start_time, starting_price);
        require(done, "cannot reset");

        uint256 coin_amount = sales[id].coin_amount;
        uint256 collateral_amount = sales[id].collateral_amount;
        sales[id].start_time = uint96(block.timestamp);

        uint256 price = get_price();
        starting_price = Math.rmul(price, buf);
        require(starting_price > 0, "zero starting price");
        sales[id].starting_price = starting_price;

        // incentive to redo auction
        // TODO: can call redo multiple times to farm fee?
        uint256 fee;
        if (flat_fee > 0 || fee_rate > 0) {
            if (coin_amount >= cache && collateral_amount * price >= cache) {
                fee = flat_fee + Math.wmul(coin_amount, fee_rate);
                cdp_engine.mint({
                    debt_dst: debt_engine,
                    coin_dst: keeper,
                    rad: fee
                });
            }
        }

        emit Redo(
            id,
            starting_price,
            coin_amount,
            collateral_amount,
            user,
            keeper,
            fee
        );
    }

    // Buy up to `amt` of collateral from the auction indexed by `id`.
    //
    // Auctions will not collect more BEI than their assigned BEI target,`coin_amount`;
    // thus, if `amt` would cost more BEI than `coin_amount` at the current price, the
    // amount of collateral purchased will instead be just enough to collect `coin_amount` BEI.
    //
    // To avoid partial purchases resulting in very small leftover auctions that will
    // never be cleared, any partial purchase must leave at least `Clipper.chost`
    // remaining BEI target. `chost` is an asynchronously updated value equal to
    // (CDPEngine.dust * Dog.chop(collateral_type) / WAD) where the values are understood to be determined
    // by whatever they were when Clipper.upchost() was last called. Purchase amounts
    // will be minimally decreased when necessary to respect this limit; i.e., if the
    // specified `amt` would leave `coin_amount < chost` but `coin_amount > 0`, the amount actually
    // purchased will be such that `coin_amount == chost`.
    //
    // If `coin_amount <= chost`, partial purchases are no longer possible; that is, the remaining
    // collateral can only be purchased entirely, or not at all.
    function take(
        uint256 id, // Auction id
        uint256 max_collateral_amount, // Upper limit on amount of collateral to buy  [wad]
        uint256 max_price, // Maximum acceptable price (BEI / collateral) [ray]
        // who
        address receiver, // Receiver of collateral and external call address
        bytes calldata data // Data to pass in external call; if length 0, no call is done
    ) external lock not_stopped(3) {
        address user = sales[id].user;
        uint96 start_time = sales[id].start_time;

        require(user != address(0), "not running auction");

        uint256 price;
        {
            bool done;
            (done, price) = status(start_time, sales[id].starting_price);
            // Check that auction doesn't need reset
            require(!done, "needs reset");
        }

        // Ensure price is acceptable to buyer
        require(max_price >= price, "too-expensive");

        uint256 collateral_amount = sales[id].collateral_amount;
        uint256 coin_amount = sales[id].coin_amount;
        // BEI needed to buy a slice of this sale
        uint256 owe;

        {
            // Purchase as much as possible, up to max_collateral_amount
            // slice <= collateral_amount
            uint256 slice = Math.min(collateral_amount, max_collateral_amount);

            // BEI needed to buy a slice of this sale
            owe = slice * price;

            // Don't collect more than coin_amount of BEI
            if (owe > coin_amount) {
                // Total debt will be paid
                // owe' <= owe
                owe = coin_amount;
                // Adjust slice
                // slice' = owe' / price <= owe / price = slice <= collateral_amount
                slice = owe / price;
            } else if (owe < coin_amount && slice < collateral_amount) {
                // If slice = collateral_amount -> auction completed -> dust doesn't matter
                // TODO: what?
                if (coin_amount - owe < cache) {
                    // safe as owe < coin_amount
                    // If coin_amount <= chost, buyers have to take the entire collateral_amount.
                    require(coin_amount > cache, "no partial purchase");
                    // Adjust amount to pay
                    // owe' <= owe
                    owe = coin_amount - cache;
                    // Adjust slice
                    // slice' = owe' / price < owe / price == slice < collateral_amount
                    slice = owe / price;
                }
            }

            // Calculate remaining coin_amount after operation
            // safe since owe <= coin_amount
            coin_amount -= owe;
            // Calculate remaining collateral_amount after operation
            collateral_amount -= slice;

            // Send collateral to receiver
            cdp_engine.transfer_collateral(
                collateral_type, address(this), receiver, slice
            );

            // Do external call (if data is defined) but to be
            // extremely careful we don't allow to do it to the two
            // contracts which the Clipper needs to be authorized
            if (
                data.length > 0 && receiver != address(cdp_engine)
                    && receiver != address(liquidation_engine)
            ) {
                ICollateralAuctionCallee(receiver).callback(
                    msg.sender, owe, slice, data
                );
            }

            // Get BEI from caller
            cdp_engine.transfer_coin(msg.sender, debt_engine, owe);

            // Removes BEI out for liquidation from accumulator
            liquidation_engine.remove_coin_from_auction(
                collateral_type,
                collateral_amount == 0 ? coin_amount + owe : owe
            );
        }

        if (collateral_amount == 0) {
            _remove(id);
        } else if (coin_amount == 0) {
            cdp_engine.transfer_collateral(
                collateral_type, address(this), user, collateral_amount
            );
            _remove(id);
        } else {
            sales[id].coin_amount = coin_amount;
            sales[id].collateral_amount = collateral_amount;
        }

        emit Take(
            id,
            max_collateral_amount,
            price,
            owe,
            coin_amount,
            collateral_amount,
            user
        );
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

    // Externally returns boolean for if an auction needs a redo and
    // also the current price
    function get_status(uint256 id)
        external
        view
        returns (
            bool needs_redo,
            uint256 price,
            uint256 collateral_amount,
            uint256 coin_amount
        )
    {
        // Read auction data
        address user = sales[id].user;
        uint96 start_time = sales[id].start_time;

        bool done;
        (done, price) = status(start_time, sales[id].starting_price);

        needs_redo = user != address(0) && done;
        collateral_amount = sales[id].collateral_amount;
        coin_amount = sales[id].coin_amount;
    }

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
        ICDPEngine.Collateral memory col =
            ICDPEngine(cdp_engine).collaterals(collateral_type);
        cache =
            Math.wmul(col.min_debt, liquidation_engine.penalty(collateral_type));
    }

    // Cancel an auction during ES or via governance action.
    function yank(uint256 id) external auth lock {
        require(sales[id].user != address(0), "Clipper/not-running-auction");
        // liquidation_engine.digs(collateral_type, sales[id].coin_amount);
        cdp_engine.transfer_collateral(
            collateral_type,
            address(this),
            msg.sender,
            sales[id].collateral_amount
        );
        _remove(id);
        emit Yank(id);
    }
}
