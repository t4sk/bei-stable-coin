// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../../src/lib/Math.sol";
import {Gem} from "../Gem.sol";
import {CDPEngine} from "../../src/stable-coin/CDPEngine.sol";
import {DebtAuction} from "../../src/stable-coin/DebtAuction.sol";
import {SurplusAuction} from "../../src/stable-coin/SurplusAuction.sol";
import {DSEngine} from "../../src/stable-coin/DSEngine.sol";

// TODO: test
contract DSEngineTest is Test {
    Gem private gem;
    Gem private gov;
    CDPEngine private cdp_engine;
    DebtAuction private debt_auction;
    SurplusAuction private surplus_auction;
    DSEngine private ds_engine;

    function setUp() public {
        gem = new Gem("gem", "GEM", 18);
        gov = new Gem("gov", "GOV", 18);
        cdp_engine = new CDPEngine();
        debt_auction = new DebtAuction(address(cdp_engine), address(gem));
        surplus_auction = new SurplusAuction(address(cdp_engine), address(gov));

        ds_engine = new DSEngine(
            address(cdp_engine), address(surplus_auction), address(debt_auction)
        );
    }
}
