// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../../src/lib/Math.sol";
import {ICDPEngine} from "../../src/interfaces/ICDPEngine.sol";
import {LiquidationEngine} from "../../src/stable-coin/LiquidationEngine.sol";

contract MockCdpEngine {
    mapping(bytes32 => ICDPEngine.Collateral) public collaterals;
    mapping(bytes32 => mapping(address => ICDPEngine.Position)) public positions;

    function set_col(
        bytes32 col_type,
        uint256 debt,
        uint256 rate_acc,
        uint256 spot,
        uint256 max_debt,
        uint256 min_debt
    ) external {
        collaterals[col_type] = ICDPEngine.Collateral({
            debt: debt,
            rate_acc: rate_acc,
            spot: spot,
            max_debt: max_debt,
            min_debt: min_debt
        });
    }

    function set_pos(
        bytes32 col_type,
        address cdp,
        uint256 col_amount,
        uint256 debt
    ) external {
        positions[col_type][cdp] =
            ICDPEngine.Position({collateral: col_amount, debt: debt});
    }

    function grab(
        bytes32 col_type,
        address cdp,
        address gem_dst,
        address debt_dst,
        int256 delta_col,
        int256 delta_debt
    ) external {}
}

contract MockDSEngine {
    function push_debt_to_queue(uint256 debt) external {}
}

contract MockCollateralAuction {
    bytes32 public constant collateral_type = bytes32(uint256(1));

    function start(
        uint256 coin_amount,
        uint256 collateral_amount,
        address user,
        address keeper
    ) external returns (uint256 id) {}
}

contract LiquidationEngineTest is Test {
    MockCdpEngine private cdp_engine;
    MockDSEngine private ds_engine;
    MockCollateralAuction private auction;
    LiquidationEngine private liquidation_engine;

    bytes32 private constant COL_TYPE = bytes32(uint256(1));
    address private constant CDP = address(11);
    address private constant KEEPER = address(12);
    // collateral
    uint256 private constant SPOT = 99 * RAY;
    uint256 private constant RATE_ACC = RAY;
    // position
    uint256 private constant DEBT = 100 * WAD;
    uint256 private constant COL_AMOUNT = WAD;

    function setUp() public {
        cdp_engine = new MockCdpEngine();
        ds_engine = new MockDSEngine();
        liquidation_engine = new LiquidationEngine(address(cdp_engine));
        auction = new MockCollateralAuction();

        liquidation_engine.set("ds_engine", address(ds_engine));
        liquidation_engine.set("max", 1000 * RAD);
        liquidation_engine.set(COL_TYPE, "max", 1000 * RAD);
        liquidation_engine.set(COL_TYPE, "penalty", WAD);
        liquidation_engine.set(COL_TYPE, "auction", address(auction));

        cdp_engine.set_col({
            col_type: COL_TYPE,
            debt: DEBT,
            rate_acc: RATE_ACC,
            spot: SPOT,
            max_debt: 1000 * RAD,
            min_debt: RAD
        });

        cdp_engine.set_pos({
            col_type: COL_TYPE,
            cdp: CDP,
            col_amount: COL_AMOUNT,
            debt: DEBT
        });
    }

    function test_liquidation() public {
        liquidation_engine.liquidate(COL_TYPE, CDP, KEEPER);
    }
}
