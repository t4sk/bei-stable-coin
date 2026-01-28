// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../../src/lib/Math.sol";
import {CDPEngine} from "../../src/stable-coin/CDPEngine.sol";
import {CoinJoin} from "../../src/stable-coin/CoinJoin.sol";
import {Coin} from "../../src/stable-coin/Coin.sol";

contract CoinJoinTest is Test {
    CDPEngine private cdp_engine;
    CoinJoin private coin_join;
    Coin private coin;

    function setUp() public {
        cdp_engine = new CDPEngine();
        coin = new Coin();
        coin_join = new CoinJoin(address(cdp_engine), address(coin));

        coin.grant_auth(address(coin_join));

        cdp_engine.mint({
            debt_dst: address(0), coin_dst: address(this), rad: 1e45
        });

        cdp_engine.allow_account_modification(address(coin_join));
    }

    function test_exit() public {
        uint256 wad = 1e18;
        address coin_dst = address(1);
        coin_join.exit(coin_dst, wad);

        assertEq(coin.balanceOf(coin_dst), wad);
        assertEq(cdp_engine.coin(address(this)), 0);
        assertEq(cdp_engine.coin(address(coin_join)), wad * RAY);
    }

    function test_join() public {
        uint256 wad = 1e18;
        coin_join.exit(address(this), wad);

        coin.approve(address(coin_join), type(uint256).max);

        address coin_dst = address(1);
        coin_join.join(coin_dst, wad);

        assertEq(coin.balanceOf(address(this)), 0);
        assertEq(cdp_engine.coin(coin_dst), wad * RAY);
        assertEq(cdp_engine.coin(address(coin_join)), 0);
    }
}
