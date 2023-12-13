// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {Gem} from "../Gem.sol";
// stable-coin
import "../../src/lib/Math.sol";
import {CDPEngine} from "../../src/stable-coin/CDPEngine.sol";
import {Coin} from "../../src/stable-coin/Coin.sol";
import {CoinJoin} from "../../src/stable-coin/CoinJoin.sol";
import {GemJoin} from "../../src/stable-coin/GemJoin.sol";
import {Jug} from "../../src/stable-coin/Jug.sol";
import {DebtEngine} from "../../src/stable-coin/DebtEngine.sol";
import {SurplusAuction} from "../../src/stable-coin/SurplusAuction.sol";
import {DebtAuction} from "../../src/stable-coin/DebtAuction.sol";

bytes32 constant COL_TYPE = bytes32(uint256(1));

contract Sim is Test {
    Gem private mkr;
    Gem private gem;
    GemJoin private gem_join;
    Coin private coin;
    CoinJoin private coin_join;
    CDPEngine private cdp_engine;
    Jug private jug;
    DebtEngine private debt_engine;
    SurplusAuction private surplus_auction;
    DebtAuction private debt_auction;
    address[] private users = [address(11), address(12), address(13)];

    function setUp() public {
        mkr = new Gem("MKR", "MKR", 18);
        gem = new Gem("gem", "GEM", 18);
        coin = new Coin();

        cdp_engine = new CDPEngine();
        gem_join = new GemJoin(address(cdp_engine), COL_TYPE, address(gem));
        coin_join = new CoinJoin(address(cdp_engine), address(coin));
        jug = new Jug(address(cdp_engine));

        debt_auction = new DebtAuction(
            address(cdp_engine),
            address(mkr)
        );
        surplus_auction = new SurplusAuction(
            address(cdp_engine),
            address(mkr)
        );
        debt_engine = new DebtEngine(
            address(cdp_engine),
            address(surplus_auction),
            address(debt_auction)
        );

        cdp_engine.add_auth(address(gem_join));
        cdp_engine.add_auth(address(jug));
        coin.add_auth(address(coin_join));

        cdp_engine.init(COL_TYPE);
        cdp_engine.set("sys_max_debt", 1e9 * RAD);
        cdp_engine.set(COL_TYPE, "max_debt", 1e6 * RAD);
        cdp_engine.set(COL_TYPE, "min_debt", 100 * RAD);
        cdp_engine.set(COL_TYPE, "spot", 1000 * RAY);

        jug.set("debt_engine", address(debt_engine));
        jug.init(COL_TYPE);
        jug.set(COL_TYPE, "fee", 1000000001622535724756171269);

        // Mint gem
        for (uint256 i = 0; i < users.length; i++) {
            gem.mint(users[i], 10000 * WAD);
            vm.prank(users[i]);
            gem.approve(address(gem_join), type(uint256).max);
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

    function test() public {
        uint256 col_amount = WAD;
        uint256 coin_wad = 100 * WAD;

        // Lock gem
        vm.startPrank(users[0]);
        gem_join.join(users[0], col_amount);

        cdp_engine.modify_cdp({
            col_type: COL_TYPE,
            cdp: users[0],
            gem_src: users[0],
            coin_dst: users[0],
            delta_col: int256(col_amount),
            delta_debt: 0
        });

        // Borrow
        int256 delta_debt = get_borrow_delta_debt(
            users[0],
            COL_TYPE,
            coin_wad
        );
        cdp_engine.modify_cdp({
            col_type: COL_TYPE,
            cdp: users[0],
            gem_src: users[0],
            coin_dst: users[0],
            delta_col: 0,
            delta_debt: delta_debt
        });
        cdp_engine.allow_account_modification(address(coin_join));
        coin_join.exit(users[0], coin_wad);
        vm.stopPrank();
    }
}
