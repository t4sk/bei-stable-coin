// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import {ICDPEngine} from "../interfaces/ICDPEngine.sol";
import {ILiquidationEngine} from "../interfaces/ILiquidationEngine.sol";
import {ISpotter} from "../interfaces/ISpotter.sol";
import {IPriceFeed} from "../interfaces/IPriceFeed.sol";
import {ICollateralAuction} from "../interfaces/ICollateralAuction.sol";
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
    // vow - Recipient of BEI raised in auctions
    address public debt_engine;
    // spotter - Collateral price module
    ISpotter public spotter;
    // calc - Current price calculator
    IAuctionPriceCalculator public calc;

    // buf [ray] - Multiplicative factor to increase starting price
    uint256 public boost;
    // tail [seconds] - Time elapsed before auction reset
    uint256 public max_duration;
    // cusp [ray] - Percentage drop before auction reset
    uint256 public min_delta_price_ratio;
    // chip [wad] - Percentage of coin to raise, to mint from debt_engine to
    //              incentivize keepers
    uint64 public fee_rate;
    // tip [rad] - Flat fee to mint from debt_engine to incentivize keepers
    uint192 public flat_fee;
    // chost [rad] - Cache the collateral_type dust times the collateral_type
    //               chop to prevent excessive SLOADs
    //               min debt x liquidation penalty multiplier
    uint256 public min_coin;

    // kicks - Total auctions
    uint256 public last_auction_id;
    // Array of active auction ids
    uint256[] public active;

    // id => Sale
    mapping(uint256 => ICollateralAuction.Sale) public sales;

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
        uint256 max_collateral,
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
        address _cdp_engine,
        address _spotter,
        address _liquidation_engine,
        bytes32 _collateral_type
    ) {
        cdp_engine = ICDPEngine(_cdp_engine);
        spotter = ISpotter(_spotter);
        liquidation_engine = ILiquidationEngine(_liquidation_engine);
        collateral_type = _collateral_type;
        boost = RAY;
    }

    // --- Synchronization ---
    modifier not_stopped(uint256 level) {
        require(stopped < level, "stopped");
        _;
    }

    // --- Administration ---
    // file
    function set(bytes32 key, uint256 val) external auth lock {
        if (key == "boost") {
            boost = val;
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
            revert("unrecognized param");
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
            revert("unrecognized param");
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
        price = Math.rdiv(val * 1e9, spotter.par());
    }

    // kick - start an auction
    // note: trusts the caller to transfer collateral to the contract
    // The starting price `starting_price` is obtained as follows:
    //
    //     starting_price = val * boost / par
    //
    // Where `val` is the collateral's unitary value in USD, `boost` is a
    // multiplicative factor to increase the starting price, and `par` is a
    // reference per BEI.
    function start(
        // tab [rad] - debt
        uint256 coin_amount,
        // lot [wad] - collateral
        uint256 collateral_amount,
        // user - address that will receive any leftover collaterl
        address user,
        // keeper - address that will receive incentive
        address keeper
    ) external auth lock not_stopped(1) returns (uint256 id) {
        require(coin_amount > 0, "0 coin amount");
        require(collateral_amount > 0, "0 collateral amount");
        require(user != address(0), "0 address user");
        id = ++last_auction_id;

        active.push(id);

        ICollateralAuction.Sale storage sale = sales[id];
        sale.pos = active.length - 1;
        sale.coin_amount = coin_amount;
        sale.collateral_amount = collateral_amount;
        sale.user = user;
        sale.start_time = uint96(block.timestamp);

        uint256 starting_price = Math.rmul(get_price(), boost);
        require(starting_price > 0, "zero starting price");
        sale.starting_price = starting_price;

        // incentive to start auction
        uint256 fee;
        if (flat_fee > 0 || fee_rate > 0) {
            // rad + rad * wad / wad
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
        ICollateralAuction.Sale storage sale = sales[id];
        address user = sale.user;
        uint96 start_time = sale.start_time;
        uint256 starting_price = sale.starting_price;

        require(user != address(0), "not running auction");

        // Check that auction needs reset
        // and compute current price [ray]
        (bool done,) = status(start_time, starting_price);
        require(done, "cannot reset");

        uint256 coin_amount = sale.coin_amount;
        uint256 collateral_amount = sale.collateral_amount;
        sale.start_time = uint96(block.timestamp);

        uint256 price = get_price();
        starting_price = Math.rmul(price, boost);
        require(starting_price > 0, "0 starting price");
        sale.starting_price = starting_price;

        // incentive to redo auction
        uint256 fee;
        if (flat_fee > 0 || fee_rate > 0) {
            if (
                coin_amount >= min_coin && collateral_amount * price >= min_coin
            ) {
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
        // id - Auction id
        uint256 id,
        // amt [wad] - Upper limit on amount of collateral to buy
        uint256 max_collateral,
        // max [ray] - Maximum acceptable price (BEI / collateral)
        uint256 max_price,
        // who - Receiver of collateral and external call address
        address receiver,
        // Data to pass in external call; if length 0, no call is done
        bytes calldata data
    ) external lock not_stopped(3) {
        ICollateralAuction.Sale storage sale = sales[id];
        address user = sale.user;
        uint96 start_time = sale.start_time;

        require(user != address(0), "not running auction");

        uint256 price;
        {
            bool done;
            (done, price) = status(start_time, sale.starting_price);
            // Check that auction doesn't need reset
            require(!done, "needs reset");
        }

        // Ensure price is acceptable to buyer
        require(max_price >= price, "price > max");

        uint256 collateral_amount = sale.collateral_amount;
        uint256 coin_amount = sale.coin_amount;
        // BEI needed to buy a slice of this sale
        uint256 owe;
        {
            // Purchase as much as possible, up to max_collateral
            // slice <= collateral_amount
            uint256 slice = Math.min(collateral_amount, max_collateral);

            // BEI needed to buy a slice of this sale
            // rad = wad * ray
            // owe = amount collateral * BEI / collateral
            owe = slice * price;

            // owe > coin amount                         -> set own = coin amount and recalculate slice
            // owe < coin amount && slice < col amount -> ?
            // Don't collect more than coin_amount of BEI
            if (owe > coin_amount) {
                // Total debt will be paid
                // owe' <= owe
                owe = coin_amount;
                // Adjust slice
                // slice' = owe' / price <= owe / price = slice <= collateral_amount
                // wad = rad / ray
                slice = owe / price;
            } else if (owe < coin_amount && slice < collateral_amount) {
                // If owe = coin amount or slice = collateral_amount -> auction completed -> dust doesn't matter
                if (coin_amount - owe < min_coin) {
                    // safe as owe < coin_amount
                    // If coin_amount <= min_coin, buyers have to take the entire collateral_amount.
                    require(coin_amount > min_coin, "no partial purchase");
                    // Adjust amount to pay
                    // coin amount - min coin < owe
                    owe = coin_amount - min_coin;
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
            sale.coin_amount = coin_amount;
            sale.collateral_amount = collateral_amount;
        }

        emit Take(
            id, max_collateral, price, owe, coin_amount, collateral_amount, user
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
        ICollateralAuction.Sale memory sale = sales[id];

        bool done;
        (done, price) = status(sale.start_time, sale.starting_price);

        needs_redo = sale.user != address(0) && done;
        collateral_amount = sale.collateral_amount;
        coin_amount = sale.coin_amount;
    }

    // Internally returns boolean for if an auction needs a redo
    function status(uint96 start_time, uint256 starting_price)
        internal
        view
        returns (bool done, uint256 price)
    {
        // price = BEI / collateral [ray]
        price = calc.price(starting_price, block.timestamp - start_time);
        done = (
            block.timestamp - start_time > max_duration
                || Math.rdiv(price, starting_price) < min_delta_price_ratio
        );
    }

    // Public function to update the cached dust*chop value.
    // upchost
    function update_min_coin() external {
        ICDPEngine.Collateral memory col =
            ICDPEngine(cdp_engine).collaterals(collateral_type);
        min_coin =
            Math.wmul(col.min_debt, liquidation_engine.penalty(collateral_type));
    }

    // Cancel an auction during ES or via governance action.
    function yank(uint256 id) external auth lock {
        ICollateralAuction.Sale memory sale = sales[id];
        require(sale.user != address(0), "not running auction");
        // liquidation_engine.digs(collateral_type, sales[id].coin_amount);
        cdp_engine.transfer_collateral(
            collateral_type, address(this), msg.sender, sale.collateral_amount
        );
        _remove(id);
        emit Yank(id);
    }
}
