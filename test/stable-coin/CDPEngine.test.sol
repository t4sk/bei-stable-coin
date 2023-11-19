// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {ICDPEngine} from "../../src/interfaces/ICDPEngine.sol";
import "../../src/lib/Math.sol";
import {CDPEngine} from "../../src/stable-coin/CDPEngine.sol";

contract CDPEngineTest is Test {
    CDPEngine private cdp_engine;

    bytes32 private constant COL_TYPE = bytes32(uint256(1));

    function setUp() public {
        cdp_engine = new CDPEngine();
    }

    function setup_cdp_engine() private {
        cdp_engine.init(COL_TYPE);
        cdp_engine.set("sys_max_debt", 1000 * RAD);
        cdp_engine.set(COL_TYPE, "max_debt", 100 * RAD);
        cdp_engine.set(COL_TYPE, "spot", 10 * RAY);
        cdp_engine.set(COL_TYPE, "min_debt", RAD);
    }

    function setup_cdp_access(address cdp, address gem_src, address coin_dst)
        private
    {
        vm.prank(cdp);
        cdp_engine.allow_account_modification(address(this));
        vm.prank(gem_src);
        cdp_engine.allow_account_modification(address(this));
        vm.prank(coin_dst);
        cdp_engine.allow_account_modification(address(this));
    }

    function get_collateral(bytes32 col_type)
        private
        returns (ICDPEngine.Collateral memory)
    {
        return ICDPEngine(address(cdp_engine)).collaterals(col_type);
    }

    function get_position(bytes32 col_type, address cdp)
        private
        returns (ICDPEngine.Position memory)
    {
        return ICDPEngine(address(cdp_engine)).positions(col_type, cdp);
    }

    function get_delta_coin(bytes32 col_type, int256 delta_debt)
        private
        returns (int256)
    {
        ICDPEngine.Collateral memory c =
            ICDPEngine(address(cdp_engine)).collaterals(col_type);
        return Math.mul(c.rate, delta_debt);
    }

    function test_constructor() public {
        assertTrue(cdp_engine.authorized(address(this)));
        assertTrue(cdp_engine.is_live());
    }

    function test_init() public {
        vm.expectRevert("not authorized");
        vm.prank(address(1));
        cdp_engine.init(COL_TYPE);

        cdp_engine.init(COL_TYPE);
        ICDPEngine.Collateral memory col = get_collateral(COL_TYPE);
        assertEq(col.rate, RAY);

        vm.expectRevert("already initialized");
        cdp_engine.init(COL_TYPE);
    }

    function test_set_auth() public {
        vm.expectRevert("not authorized");
        vm.prank(address(1));
        cdp_engine.set("sys_max_debt", 0);

        vm.expectRevert("not authorized");
        vm.prank(address(1));
        cdp_engine.set(COL_TYPE, "spot", 0);
    }

    function test_set_invalid_param() public {
        vm.expectRevert("invalid param");
        cdp_engine.set("x", 0);

        vm.expectRevert("invalid param");
        cdp_engine.set(COL_TYPE, "x", 0);
    }

    function test_set() public {
        cdp_engine.set("sys_max_debt", 100);
        assertEq(cdp_engine.sys_max_debt(), 100);

        ICDPEngine.Collateral memory col;

        cdp_engine.set(COL_TYPE, "spot", 100);
        col = get_collateral(COL_TYPE);
        assertEq(col.spot, 100);

        cdp_engine.set(COL_TYPE, "max_debt", 200);
        col = get_collateral(COL_TYPE);
        assertEq(col.max_debt, 200);

        cdp_engine.set(COL_TYPE, "min_debt", 300);
        col = get_collateral(COL_TYPE);
        assertEq(col.min_debt, 300);
    }

    function test_set_stopped() public {
        cdp_engine.stop();
        vm.expectRevert("stopped");
        cdp_engine.set("sys_max_debt", 0);

        vm.expectRevert("stopped");
        cdp_engine.set(COL_TYPE, "spot", 0);
    }

    function test_stop() public {
        vm.expectRevert("not authorized");
        vm.prank(address(1));
        cdp_engine.stop();

        assertEq(cdp_engine.is_live(), true);
        cdp_engine.stop();
        assertEq(cdp_engine.is_live(), false);
    }

    function test_modify_collateral_balance() public {
        address src = address(1);

        vm.expectRevert("not authorized");
        vm.prank(address(1));
        cdp_engine.modify_collateral_balance(COL_TYPE, src, 100);

        uint256 bal0;
        uint256 bal1;

        bal0 = cdp_engine.gem(COL_TYPE, src);
        cdp_engine.modify_collateral_balance(COL_TYPE, src, 100);
        bal1 = cdp_engine.gem(COL_TYPE, src);
        assertEq(bal1 - bal0, 100);

        bal0 = cdp_engine.gem(COL_TYPE, src);
        cdp_engine.modify_collateral_balance(COL_TYPE, src, -10);
        bal1 = cdp_engine.gem(COL_TYPE, src);
        assertEq(bal0 - bal1, 10);
    }

    function test_transfer_collataeral() public {
        address src = address(1);
        address dst = address(2);

        cdp_engine.modify_collateral_balance(COL_TYPE, src, 100);

        vm.expectRevert("not authorized");
        cdp_engine.transfer_collateral(COL_TYPE, src, dst, 100);

        vm.prank(src);
        cdp_engine.transfer_collateral(COL_TYPE, src, dst, 10);
        assertEq(cdp_engine.gem(COL_TYPE, src), 90);
        assertEq(cdp_engine.gem(COL_TYPE, dst), 10);

        vm.prank(src);
        cdp_engine.allow_account_modification(address(this));
        cdp_engine.transfer_collateral(COL_TYPE, src, dst, 10);
        assertEq(cdp_engine.gem(COL_TYPE, src), 80);
        assertEq(cdp_engine.gem(COL_TYPE, dst), 20);
    }

    function test_transfer_coin() public {
        address src = address(1);
        address dst = address(2);

        cdp_engine.mint(src, src, 100);

        vm.expectRevert("not authorized");
        cdp_engine.transfer_coin(src, dst, 100);

        vm.prank(src);
        cdp_engine.transfer_coin(src, dst, 10);
        assertEq(cdp_engine.coin(src), 90);
        assertEq(cdp_engine.coin(dst), 10);

        vm.prank(src);
        cdp_engine.allow_account_modification(address(this));
        cdp_engine.transfer_coin(src, dst, 10);
        assertEq(cdp_engine.coin(src), 80);
        assertEq(cdp_engine.coin(dst), 20);
    }

    function test_modify_cdp_revert() public {
        address cdp = address(1);
        address gem_src = address(2);
        address coin_dst = address(3);

        // Test - collateral not initialized //
        vm.expectRevert("collateral not initialized");
        cdp_engine.modify_cdp({
            col_type: COL_TYPE,
            cdp: cdp,
            gem_src: gem_src,
            coin_dst: coin_dst,
            delta_col: 0,
            delta_debt: 0
        });

        setup_cdp_engine();

        // Test - delta debt > max //
        vm.expectRevert("delta debt > max");
        cdp_engine.modify_cdp({
            col_type: COL_TYPE,
            cdp: cdp,
            gem_src: gem_src,
            coin_dst: coin_dst,
            delta_col: 0,
            delta_debt: int256(100 * WAD + 1)
        });

        // Test - undercollateralized //
        vm.expectRevert("undercollateralized");
        cdp_engine.modify_cdp({
            col_type: COL_TYPE,
            cdp: cdp,
            gem_src: gem_src,
            coin_dst: coin_dst,
            delta_col: int256(WAD),
            delta_debt: int256(11 * WAD + 1)
        });

        // Test - not allowed cdp //
        vm.expectRevert("not allowed to modify cdp");
        cdp_engine.modify_cdp({
            col_type: COL_TYPE,
            cdp: cdp,
            gem_src: gem_src,
            coin_dst: coin_dst,
            delta_col: int256(WAD),
            delta_debt: int256(WAD)
        });

        vm.prank(cdp);
        cdp_engine.allow_account_modification(address(this));

        // Test - not allowed collateral src //
        vm.expectRevert("not allowed to modify gem src");
        cdp_engine.modify_cdp({
            col_type: COL_TYPE,
            cdp: cdp,
            gem_src: gem_src,
            coin_dst: coin_dst,
            delta_col: int256(WAD),
            delta_debt: int256(WAD)
        });

        vm.prank(gem_src);
        cdp_engine.allow_account_modification(address(this));

        // Test - not allowed coin dst //
        cdp_engine.modify_collateral_balance(COL_TYPE, gem_src, int256(WAD));
        cdp_engine.modify_cdp({
            col_type: COL_TYPE,
            cdp: cdp,
            gem_src: gem_src,
            coin_dst: coin_dst,
            delta_col: int256(WAD),
            delta_debt: int256(WAD)
        });

        vm.expectRevert("not allowed to modify coin dst");
        cdp_engine.modify_cdp({
            col_type: COL_TYPE,
            cdp: cdp,
            gem_src: gem_src,
            coin_dst: coin_dst,
            delta_col: 0,
            delta_debt: -int256(WAD)
        });

        vm.prank(coin_dst);
        cdp_engine.allow_account_modification(address(this));

        // Test - dust //
        vm.expectRevert("debt < dust");
        cdp_engine.modify_cdp({
            col_type: COL_TYPE,
            cdp: cdp,
            gem_src: gem_src,
            coin_dst: coin_dst,
            delta_col: 0,
            delta_debt: -int256(WAD) + 1
        });

        // Test - stopped //
        cdp_engine.stop();
        vm.expectRevert("stopped");
        cdp_engine.modify_cdp({
            col_type: COL_TYPE,
            cdp: cdp,
            gem_src: gem_src,
            coin_dst: coin_dst,
            delta_col: 0,
            delta_debt: 0
        });
    }

    function test_modify_cdp() public {
        address cdp = address(1);
        address gem_src = address(2);
        address coin_dst = address(3);

        setup_cdp_engine();
        setup_cdp_access({cdp: cdp, gem_src: gem_src, coin_dst: coin_dst});

        cdp_engine.modify_collateral_balance(
            COL_TYPE, gem_src, int256(10 * WAD)
        );

        // delta_col, delta_debt
        int256[2][8] memory tests = [
            [int256(0), int256(0)],
            [int256(WAD), int256(0)],
            [int256(0), int256(WAD)],
            [int256(WAD), int256(WAD)],
            [-int256(WAD), int256(0)],
            [int256(0), -int256(WAD)],
            [int256(WAD), int256(0)],
            [-int256(WAD), int256(WAD)]
        ];

        for (uint256 i = 0; i < tests.length; i++) {
            int256 delta_col = tests[i][0];
            int256 delta_debt = tests[i][1];

            ICDPEngine.Position memory pos0 = get_position(COL_TYPE, cdp);
            ICDPEngine.Collateral memory col0 = get_collateral(COL_TYPE);
            uint256 gem0 = cdp_engine.gem(COL_TYPE, gem_src);
            uint256 coin0 = cdp_engine.coin(coin_dst);

            cdp_engine.modify_cdp({
                col_type: COL_TYPE,
                cdp: cdp,
                gem_src: gem_src,
                coin_dst: coin_dst,
                delta_col: delta_col,
                delta_debt: delta_debt
            });

            ICDPEngine.Position memory pos1 = get_position(COL_TYPE, cdp);
            ICDPEngine.Collateral memory col1 = get_collateral(COL_TYPE);
            uint256 gem1 = cdp_engine.gem(COL_TYPE, gem_src);
            uint256 coin1 = cdp_engine.coin(coin_dst);

            assertEq(pos1.collateral, Math.add(pos0.collateral, delta_col));
            assertEq(pos1.debt, Math.add(pos0.debt, delta_debt));
            assertEq(col1.debt, Math.add(col0.debt, delta_debt));
            assertEq(gem1, Math.sub(gem0, delta_col));
            assertEq(
                coin1, Math.add(coin0, get_delta_coin(COL_TYPE, delta_debt))
            );
        }
    }

    function test_grab() public {
        address cdp = address(1);
        address gem_dst = address(2);
        address debt_dst = address(3);

        setup_cdp_engine();
        setup_cdp_access({cdp: cdp, gem_src: cdp, coin_dst: cdp});

        cdp_engine.modify_collateral_balance(COL_TYPE, cdp, int256(10 * WAD));
        cdp_engine.modify_cdp({
            col_type: COL_TYPE,
            cdp: cdp,
            gem_src: cdp,
            coin_dst: cdp,
            delta_col: int256(WAD),
            delta_debt: int256(2 * WAD)
        });

        vm.expectRevert("not authorized");
        vm.prank(address(1));
        cdp_engine.grab({
            col_type: COL_TYPE,
            cdp: cdp,
            gem_dst: gem_dst,
            debt_dst: debt_dst,
            delta_col: 0,
            delta_debt: 0
        });

        int256 delta_coin = get_delta_coin(COL_TYPE, -int256(2 * WAD));

        ICDPEngine.Position memory pos0 = get_position(COL_TYPE, cdp);
        ICDPEngine.Collateral memory col0 = get_collateral(COL_TYPE);
        uint256 g0 = cdp_engine.gem(COL_TYPE, gem_dst);
        uint256 d0 = cdp_engine.unbacked_debts(debt_dst);
        uint256 s0 = cdp_engine.sys_unbacked_debt();
        cdp_engine.grab({
            col_type: COL_TYPE,
            cdp: cdp,
            gem_dst: gem_dst,
            debt_dst: debt_dst,
            delta_col: -int256(WAD),
            delta_debt: -int256(2 * WAD)
        });
        ICDPEngine.Position memory pos1 = get_position(COL_TYPE, cdp);
        ICDPEngine.Collateral memory col1 = get_collateral(COL_TYPE);
        uint256 g1 = cdp_engine.gem(COL_TYPE, gem_dst);
        uint256 d1 = cdp_engine.unbacked_debts(debt_dst);
        uint256 s1 = cdp_engine.sys_unbacked_debt();

        assertEq(pos1.collateral, pos0.collateral - WAD);
        assertEq(pos1.debt, pos0.debt - 2 * WAD);
        assertEq(col1.debt, col0.debt - 2 * WAD);
        assertEq(g1, g0 + WAD);
        assertEq(d1, d0 + uint256(-delta_coin));
        assertEq(s1, s0 + uint256(-delta_coin));
    }

    function test_mint() public {
        address debt_dst = address(1);
        address coin_dst = address(2);

        vm.expectRevert("not authorized");
        vm.prank(debt_dst);
        cdp_engine.mint(debt_dst, coin_dst, 100);

        cdp_engine.mint(debt_dst, coin_dst, 100);
        assertEq(cdp_engine.unbacked_debts(debt_dst), 100);
        assertEq(cdp_engine.coin(coin_dst), 100);
        assertEq(cdp_engine.sys_unbacked_debt(), 100);
        assertEq(cdp_engine.sys_debt(), 100);
    }

    function test_burn() public {
        address src = address(1);
        cdp_engine.mint(src, src, 100);

        vm.prank(src);
        cdp_engine.burn(10);

        assertEq(cdp_engine.unbacked_debts(src), 90);
        assertEq(cdp_engine.coin(src), 90);
        assertEq(cdp_engine.sys_unbacked_debt(), 90);
        assertEq(cdp_engine.sys_debt(), 90);
    }

    function test_sync() public {
        address coin_dst = address(1);

        vm.expectRevert("not authorized");
        vm.prank(coin_dst);
        cdp_engine.sync(COL_TYPE, coin_dst, 100);

        // TODO: test with col.debt > 0
        cdp_engine.sync(COL_TYPE, coin_dst, 100);

        cdp_engine.stop();
        vm.expectRevert("stopped");
        cdp_engine.sync(COL_TYPE, coin_dst, 100);
    }
}
