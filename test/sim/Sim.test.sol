// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {Gem} from "../Gem.sol";
import {ICDPEngine} from "../../src/interfaces/ICDPEngine.sol";
import {ICollateralAuction} from "../../src/interfaces/ICollateralAuction.sol";
// stable-coin
import "../../src/lib/Math.sol";
import {CDPEngine} from "../../src/stable-coin/CDPEngine.sol";
import {Coin} from "../../src/stable-coin/Coin.sol";
import {CoinJoin} from "../../src/stable-coin/CoinJoin.sol";
import {GemJoin} from "../../src/stable-coin/GemJoin.sol";
import {Spotter} from "../../src/stable-coin/Spotter.sol";
import {Jug} from "../../src/stable-coin/Jug.sol";
import {DebtEngine} from "../../src/stable-coin/DebtEngine.sol";
import {SurplusAuction} from "../../src/stable-coin/SurplusAuction.sol";
import {DebtAuction} from "../../src/stable-coin/DebtAuction.sol";
import {LiquidationEngine} from "../../src/stable-coin/LiquidationEngine.sol";
import {CollateralAuction} from "../../src/stable-coin/CollateralAuction.sol";
import {StairstepExponentialDecrease} from
    "../../src/stable-coin/AuctionPriceCalculator.sol";

bytes32 constant COL_TYPE = bytes32(uint256(1));

contract PriceFeed {
    // wad
    uint256 public spot;

    function set(uint256 val) external {
        spot = val;
    }

    function peek() external returns (uint256 val, bool ok) {
        return (spot, true);
    }
}

contract Sim is Test {
    Gem private mkr;
    Gem private gem;
    GemJoin private gem_join;
    Coin private coin;
    CoinJoin private coin_join;
    CDPEngine private cdp_engine;
    Spotter private spotter;
    Jug private jug;
    DebtEngine private debt_engine;
    SurplusAuction private surplus_auction;
    DebtAuction private debt_auction;
    LiquidationEngine private liquidation_engine;
    CollateralAuction private collateral_auction;
    StairstepExponentialDecrease private stairstep_exp_dec;
    PriceFeed private price_feed;
    address private constant keeper = address(111);
    address[] private users = [address(11), address(12), address(13)];

    function setUp() public {
        mkr = new Gem("MKR", "MKR", 18);
        gem = new Gem("gem", "GEM", 18);
        coin = new Coin();

        cdp_engine = new CDPEngine();
        gem_join = new GemJoin(address(cdp_engine), COL_TYPE, address(gem));
        coin_join = new CoinJoin(address(cdp_engine), address(coin));
        spotter = new Spotter(address(cdp_engine));
        jug = new Jug(address(cdp_engine));

        debt_auction = new DebtAuction(address(cdp_engine), address(mkr));
        surplus_auction = new SurplusAuction(address(cdp_engine), address(mkr));
        debt_engine = new DebtEngine(
            address(cdp_engine), address(surplus_auction), address(debt_auction)
        );
        liquidation_engine = new LiquidationEngine(address(cdp_engine));
        collateral_auction = new CollateralAuction(
            address(cdp_engine),
            address(spotter),
            address(liquidation_engine),
            COL_TYPE
        );
        stairstep_exp_dec = new StairstepExponentialDecrease();

        price_feed = new PriceFeed();

        cdp_engine.add_auth(address(gem_join));
        cdp_engine.add_auth(address(jug));
        cdp_engine.add_auth(address(spotter));
        cdp_engine.add_auth(address(liquidation_engine));
        cdp_engine.add_auth(address(collateral_auction));
        debt_engine.add_auth(address(liquidation_engine));
        collateral_auction.add_auth(address(liquidation_engine));
        coin.add_auth(address(coin_join));

        cdp_engine.init(COL_TYPE);
        cdp_engine.set("sys_max_debt", 1e9 * RAD);
        cdp_engine.set(COL_TYPE, "max_debt", 1e6 * RAD);
        cdp_engine.set(COL_TYPE, "min_debt", 10 * RAD);
        cdp_engine.set(COL_TYPE, "spot", 1000 * RAY);

        jug.set("debt_engine", address(debt_engine));
        jug.init(COL_TYPE);
        jug.set(COL_TYPE, "fee", 1000000001622535724756171269);

        spotter.set(COL_TYPE, "price_feed", address(price_feed));
        spotter.set(COL_TYPE, "liquidation_ratio", 145 * RAY / 100);

        liquidation_engine.set("debt_engine", address(debt_engine));
        liquidation_engine.set("max_coin", 1e6 * RAD);
        liquidation_engine.set(COL_TYPE, "max_coin", 1e5 * RAD);
        // TODO: what is liquidation penalty
        liquidation_engine.set(COL_TYPE, "penalty", 1.13 * 1e18);
        liquidation_engine.set(COL_TYPE, "auction", address(collateral_auction));

        collateral_auction.set("boost", 1.1 * 1e27);
        collateral_auction.set("max_duration", 7200);
        collateral_auction.set("min_delta_price_ratio", 0.45 * 1e27);
        collateral_auction.set("fee_rate", 0.001 * 1e18);
        collateral_auction.set("flat_fee", 250 * RAD);

        stairstep_exp_dec.set("cut", 0.99 * 1e27);
        stairstep_exp_dec.set("step", 90);

        price_feed.set(1000 * WAD);

        // Mint gem
        for (uint256 i = 0; i < users.length; i++) {
            gem.mint(users[i], 10000 * WAD);
            vm.prank(users[i]);
            gem.approve(address(gem_join), type(uint256).max);

            vm.prank(users[i]);
            coin.approve(address(coin_join), type(uint256).max);
        }
    }

    function get_borrow_delta_debt(
        address cdp,
        bytes32 col_type,
        uint256 coin_wad
    ) internal returns (int256 delta_debt) {
        uint256 rate = jug.collect_stability_fee(col_type);
        uint256 coin_bal = cdp_engine.coin(cdp);
        if (coin_wad * RAY > coin_bal) {
            delta_debt = Math.to_int((coin_wad * RAY - coin_bal) / rate);
            delta_debt = uint256(delta_debt) * rate < coin_wad * RAY
                ? delta_debt - 1
                : delta_debt;
        }
    }

    function get_repay_delta_debt(
        uint256 coin_rad,
        address cdp,
        bytes32 col_type
    ) internal view returns (int256 delta_debt_wad) {
        ICDPEngine.Collateral memory c = get_collateral(col_type);
        ICDPEngine.Position memory pos = get_position(col_type, cdp);
        // wad
        delta_debt_wad = Math.to_int(coin_rad / c.rate_acc);
        delta_debt_wad = uint256(delta_debt_wad) <= pos.debt
            ? -delta_debt_wad
            : -Math.to_int(pos.debt);
    }

    function get_repay_all_coin_wad(address user, address cdp, bytes32 col_type)
        internal
        view
        returns (uint256 coin_wad)
    {
        ICDPEngine.Collateral memory c = get_collateral(col_type);
        ICDPEngine.Position memory pos = get_position(col_type, cdp);
        uint256 coin_bal = cdp_engine.coin(user);
        uint256 rad = pos.debt * c.rate_acc - coin_bal;
        coin_wad = rad / RAY;
        coin_wad = coin_wad * RAY < rad ? coin_wad + 1 : coin_wad;
    }

    function get_collateral(bytes32 col_type)
        internal
        view
        returns (ICDPEngine.Collateral memory)
    {
        return ICDPEngine(address(cdp_engine)).collaterals(col_type);
    }

    function get_position(bytes32 col_type, address cdp)
        internal
        view
        returns (ICDPEngine.Position memory)
    {
        return ICDPEngine(address(cdp_engine)).positions(col_type, cdp);
    }

    function get_sale(uint256 sale_id)
        internal
        view
        returns (ICollateralAuction.Sale memory)
    {
        return ICollateralAuction(address(collateral_auction)).sales(sale_id);
    }

    function borrow(
        bytes32 col_type,
        address user,
        uint256 col_wad,
        uint256 coin_wad
    ) internal {
        // Lock gem
        vm.startPrank(user);
        gem_join.join(user, col_wad);

        cdp_engine.modify_cdp({
            col_type: col_type,
            cdp: user,
            gem_src: user,
            coin_dst: user,
            delta_col: int256(col_wad),
            delta_debt: 0
        });

        // Borrow
        int256 delta_debt = get_borrow_delta_debt(user, col_type, coin_wad);
        cdp_engine.modify_cdp({
            col_type: col_type,
            cdp: user,
            gem_src: user,
            coin_dst: user,
            delta_col: 0,
            delta_debt: delta_debt
        });
        cdp_engine.allow_account_modification(address(coin_join));
        coin_join.exit(user, coin_wad);
        vm.stopPrank();
    }

    function repay_all(bytes32 col_type, address user) internal {
        uint256 repay_all_coin_wad =
            get_repay_all_coin_wad(user, user, col_type);

        uint256 pos_debt = get_position(col_type, user).debt;

        vm.startPrank(user);
        coin_join.join(user, repay_all_coin_wad);
        cdp_engine.modify_cdp({
            col_type: col_type,
            cdp: user,
            gem_src: user,
            coin_dst: user,
            delta_col: 0,
            delta_debt: -int256(pos_debt)
        });
        vm.stopPrank();
    }

    function test_repay_all() public {
        uint256 col_wad = WAD;
        uint256 coin_wad = 100 * WAD;
        borrow(COL_TYPE, users[0], col_wad, coin_wad);

        uint256 coin_bal = coin.balanceOf(users[0]);
        assertEq(coin_bal, coin_wad, "coin balance");

        // Increase stability fee
        skip(7 * 24 * 3600);
        jug.collect_stability_fee(COL_TYPE);

        address user = users[0];

        uint256 repay_all_coin_wad =
            get_repay_all_coin_wad(user, user, COL_TYPE);

        // TODO: how to circulate coin without this mint?
        // TODO: borrow -> stability fee -> collect stability fee -> debt engine -> ?
        // Need extra coin to pay stability fee
        coin.mint(user, repay_all_coin_wad - coin_wad);
        cdp_engine.mint(
            address(coin_join),
            address(coin_join),
            (repay_all_coin_wad - coin_wad) * RAY
        );

        repay_all(COL_TYPE, user);
        assertEq(get_position(COL_TYPE, user).debt, 0, "debt");
    }

    function test_liquidation() public {
        uint256 col_wad = WAD;
        uint256 coin_wad = 100 * WAD;
        borrow(COL_TYPE, users[0], col_wad, coin_wad);

        price_feed.set(10 * WAD);
        spotter.poke(COL_TYPE);
        collateral_auction.update_min_coin();

        uint256 sale_id =
            liquidation_engine.liquidate(COL_TYPE, users[0], keeper);

        ICollateralAuction.Sale memory sale = get_sale(sale_id);
        console.log("HERE", sale.coin_amount, sale.collateral_amount);
    }

    // TODO: test repay partial
    // TODO: test debt auction
    // TODO: test surplus auction
    // TODO: test Rates module
}
