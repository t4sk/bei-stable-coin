// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {ISpotter} from "../../src/interfaces/ISpotter.sol";
import "../../src/lib/Math.sol";
import {Spotter} from "../../src/stable-coin/Spotter.sol";

contract MockCDPEngine {
    uint256 public spot;

    function set(bytes32 col_type, bytes32 k, uint256 v) external {
        spot = v;
    }
}

contract MockPriceFeed {
    function peek() external returns (uint256 val, bool ok) {
        // 1 ETH = 2000 USD
        return (2000 * WAD, true);
    }
}

contract SpotterTest is Test {
    MockCDPEngine private cdp_engine;
    MockPriceFeed private price_feed;
    Spotter private spotter;
    bytes32 constant COL_TYPE = bytes32(uint256(1));

    function setUp() public {
        cdp_engine = new MockCDPEngine();
        price_feed = new MockPriceFeed();
        spotter = new Spotter(address(cdp_engine));
    }

    function get_collateral(bytes32 col_type)
        private
        view
        returns (ISpotter.Collateral memory)
    {
        return ISpotter(address(spotter)).collaterals(col_type);
    }

    function test_constructor() public {
        assertEq(spotter.authorized(address(this)), true);
        assertEq(spotter.is_live(), true);
        assertEq(address(spotter.cdp_engine()), address(cdp_engine));
        assertEq(spotter.par(), RAY);
    }

    function test_set() public {
        vm.expectRevert("not authorized");
        vm.prank(address(1));
        spotter.set("par", 0);

        vm.expectRevert("not authorized");
        vm.prank(address(1));
        spotter.set(COL_TYPE, "price_feed", address(price_feed));

        vm.expectRevert("not authorized");
        vm.prank(address(1));
        spotter.set(COL_TYPE, "liquidation_ratio", 0);

        spotter.set("par", 1);
        assertEq(spotter.par(), 1);

        ISpotter.Collateral memory col;
        spotter.set(COL_TYPE, "price_feed", address(1));
        col = get_collateral(COL_TYPE);
        assertEq(col.price_feed, address(1));

        spotter.set(COL_TYPE, "liquidation_ratio", 1);
        col = get_collateral(COL_TYPE);
        assertEq(col.liquidation_ratio, 1);

        spotter.stop();
        vm.expectRevert("stopped");
        spotter.set("par", 0);

        vm.expectRevert("stopped");
        spotter.set(COL_TYPE, "price_feed", address(price_feed));

        vm.expectRevert("stopped");
        spotter.set(COL_TYPE, "liquidation_ratio", 0);
    }

    function test_poke() public {
        uint256 liquidation_ratio = 145 * RAY / 100;
        (uint256 val,) = price_feed.peek();
        uint256 spot =
            Math.rdiv(Math.rdiv(val * 1e9, spotter.par()), liquidation_ratio);
        assertGt(spot, 0);

        spotter.set(COL_TYPE, "price_feed", address(price_feed));
        spotter.set(COL_TYPE, "liquidation_ratio", liquidation_ratio);

        spotter.poke(COL_TYPE);
        assertEq(cdp_engine.spot(), spot);
    }

    function test_stop() public {
        vm.expectRevert("not authorized");
        vm.prank(address(1));
        spotter.stop();

        spotter.stop();
        assertEq(spotter.is_live(), false);
    }
}
