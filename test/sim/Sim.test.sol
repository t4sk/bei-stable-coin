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
// cdp-manager
import {CDPManager} from "../../src/cdp-manager/CDPManager.sol";
// proxy
import {Proxy} from "../../src/proxy/Proxy.sol";
import {ProxyActions} from "../../src/proxy-actions/ProxyActions.sol";
import {ProxyActionsSavingsRate} from
    "../../src/proxy-actions/ProxyActionsSavingsRate.sol";

bytes32 constant COL_TYPE = bytes32(uint256(1));

contract Sim is Test {
    Gem private gem;
    GemJoin private gem_join;
    Coin private coin;
    CoinJoin private coin_join;
    CDPEngine private cdp_engine;
    Jug private jug;
    address[] private users = [address(11), address(12), address(13)];
    CDPManager private cdp_manager;
    Proxy[] private proxies;
    ProxyActions private proxy_actions;
    // TODO: test
    ProxyActionsSavingsRate private proxy_actions_savings_rate;

    function setUp() public {
        gem = new Gem("gem", "GEM", 18);
        coin = new Coin();

        cdp_engine = new CDPEngine();
        gem_join = new GemJoin(address(cdp_engine), COL_TYPE, address(gem));
        coin_join = new CoinJoin(address(cdp_engine), address(coin));
        jug = new Jug(address(cdp_engine));

        cdp_engine.add_auth(address(gem_join));
        coin.add_auth(address(coin_join));

        cdp_engine.init(COL_TYPE);

        // Proxy setup
        cdp_manager = new CDPManager(address(cdp_engine));
        proxy_actions = new ProxyActions();
        proxy_actions_savings_rate = new ProxyActionsSavingsRate();

        for (uint256 i = 0; i < users.length; i++) {
            proxies.push(new Proxy(users[i]));
        }

        // Mint gem
        for (uint256 i = 0; i < users.length; i++) {
            gem.mint(users[i], 10000 * WAD);
            vm.prank(users[i]);
            gem.approve(address(proxies[i]), type(uint256).max);
        }
    }

    function test() public {
        uint256 col_amount = WAD;
        uint256 coin_wad = WAD;
        vm.prank(users[0]);
        bytes memory res = proxies[0].execute(
            address(proxy_actions),
            abi.encodeCall(
                proxy_actions.open_lock_gem_and_borrow,
                (
                    address(cdp_manager),
                    address(jug),
                    address(gem_join),
                    address(coin_join),
                    COL_TYPE,
                    col_amount,
                    coin_wad,
                    true
                )
            )
        );
        uint256 cdp_id = abi.decode(res, (uint256));
    }
}
