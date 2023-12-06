// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "../../src/lib/Math.sol";
import {Gem} from "../Gem.sol";
import {DebtAuction} from "../../src/stable-coin/DebtAuction.sol";

contract MockCDPEngine {}

contract MockDebtEngine {}

contract DebtAuctionTest is Test {
    MockCDPEngine private cdp_engine;
    MockDebtEngine private debt_engine;
    Gem private gem;
    DebtAuction private auction;

    function setUp() public {
        cdp_engine = new MockCDPEngine();
        debt_engine = new MockDebtEngine();
        gem = new Gem("gem", "GEM", 18);
        auction = new DebtAuction(address(cdp_engine), address(gem));
    }

    function test_auction() public {}
}
