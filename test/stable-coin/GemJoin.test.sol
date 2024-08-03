// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {Gem} from "../Gem.sol";
import "../../src/lib/Math.sol";
import {CDPEngine} from "../../src/stable-coin/CDPEngine.sol";
import {GemJoin} from "../../src/stable-coin/GemJoin.sol";

contract GemJoinTest is Test {
    CDPEngine private cdp_engine;
    GemJoin private gem_join;
    Gem private gem;

    bytes32 private constant COL_TYPE = bytes32(uint256(1));

    function setUp() public {
        cdp_engine = new CDPEngine();
        gem = new Gem("gem", "GEM", 18);
        gem_join = new GemJoin(address(cdp_engine), COL_TYPE, address(gem));

        cdp_engine.grant_auth(address(gem_join));

        gem.mint(address(this), 1e18);
        gem.approve(address(gem_join), type(uint256).max);
    }

    function test_join() public {
        uint256 wad = 1e18;
        gem_join.join(address(this), wad);

        assertEq(gem.balanceOf(address(gem_join)), wad);
        assertEq(cdp_engine.gem(COL_TYPE, address(this)), wad);
    }

    function test_exit() public {
        uint256 wad = 1e18;
        gem_join.join(address(this), wad);

        address gem_dst = address(1);
        gem_join.exit(gem_dst, wad);

        assertEq(gem.balanceOf(address(gem_join)), 0);
        assertEq(gem.balanceOf(gem_dst), wad);
        assertEq(cdp_engine.gem(COL_TYPE, address(this)), 0);
    }
}
