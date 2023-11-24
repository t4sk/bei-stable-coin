// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {ICDPEngine} from "../../src/interfaces/ICDPEngine.sol";
import {IJug} from "../../src/interfaces/IJug.sol";
import "../../src/lib/Math.sol";
import {Jug} from "../../src/stable-coin/Jug.sol";

contract MockCDPEngine {
    mapping(bytes32 => ICDPEngine.Collateral) public collaterals;

    constructor(bytes32 col_type) {
        collaterals[col_type] = ICDPEngine.Collateral({
            debt: 0,
            rate_acc: 1109285099002409304767524639,
            spot: 0,
            max_debt: 0,
            min_debt: 0
        });
    }

    function get_collateral(bytes32 col_type)
        external
        view
        returns (ICDPEngine.Collateral memory)
    {
        return collaterals[col_type];
    }

    function update_rate_acc(
        bytes32 col_type,
        address coin_dst,
        int256 delta_rate_acc
    ) external {}
}

contract JugTest is Test {
    MockCDPEngine private cdp_engine;
    Jug private jug;
    bytes32 private constant COL_TYPE = bytes32(uint256(1));

    function setUp() public {
        cdp_engine = new MockCDPEngine(COL_TYPE);
        jug = new Jug(address(cdp_engine));
    }

    function test_collect_stability_fee() public {
        jug.init(COL_TYPE);
        // About 5% per year
        uint256 fee = 1000000001622535724756171269;
        jug.set(COL_TYPE, "fee", fee);

        ICDPEngine.Collateral memory c0 = cdp_engine.get_collateral(COL_TYPE);
        uint256 rate;
        rate = jug.collect_stability_fee(COL_TYPE);
        assertEq(rate, c0.rate_acc);

        skip(10);

        rate = jug.collect_stability_fee(COL_TYPE);
        assertGt(rate, c0.rate_acc);
        assertEq(rate, Math.rmul(Math.rpow(fee, 10, RAY), c0.rate_acc));
    }
}
