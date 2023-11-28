// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "../../src/lib/Math.sol";
import {LinearDecrease} from "../../src/stable-coin/AuctionPriceCalculator.sol";

contract AuctionPriceCalculator is Test {
    LinearDecrease private calc;

    function setUp() public {
        calc = new LinearDecrease();
        calc.set("duration", 3600);
    }

    function test_price() public {
        assertEq(calc.price(RAY, 0), RAY);
        assertEq(calc.price(RAY, 1800), RAY / 2);
        assertEq(calc.price(RAY, 3600), 0);
    }
}
