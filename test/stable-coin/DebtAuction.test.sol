// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../../src/lib/Math.sol";
import {Gem} from "../Gem.sol";
import {DebtAuction} from "../../src/stable-coin/DebtAuction.sol";

contract MockCDPEngine {
    function transfer_coin(address src, address dst, uint256 rad) external {}
}

contract MockDebtEngine {
    function total_debt_on_debt_auction() external view returns (uint256) {
        return 0;
    }

    function decrease_auction_debt(uint256 rad) external {}
}

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

    function test_auction() public {
        uint256 lot = WAD;
        uint256 bid = RAD;
        uint256 id = auction.start(address(debt_engine), lot, bid);

        lot = lot * 95 / 100;
        auction.bid(id, lot, bid);

        skip(auction.bid_duration() + 1);

        auction.claim(id);
    }
}
