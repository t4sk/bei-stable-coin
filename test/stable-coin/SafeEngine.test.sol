// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {ICDPEngine} from "../../src/interfaces/ICDPEngine.sol";
import "../../src/lib/Math.sol";
import {SafeEngine} from "../../src/stable-coin/SafeEngine.sol";

contract SafeEngineTest is Test {
    SafeEngine private safe_engine;

    bytes32 private constant COL_TYPE = bytes32(uint256(1));

    function setUp() public {
        safe_engine = new SafeEngine();
    }

    function get_collateral(bytes32 col_type)
        private
        returns (ICDPEngine.Collateral memory)
    {
        return ICDPEngine(address(safe_engine)).collaterals(col_type);
    }

    function get_safe(bytes32 col_type, address safe)
        private
        returns (ICDPEngine.Safe memory)
    {
        return ICDPEngine(address(safe_engine)).safes(col_type, safe);
    }

    function test_constructor() public {
        assertTrue(safe_engine.authorized(address(this)));
        assertTrue(safe_engine.is_live());
    }

    function test_init() public {
        vm.expectRevert("not authorized");
        vm.prank(address(1));
        safe_engine.init(COL_TYPE);

        safe_engine.init(COL_TYPE);
        ICDPEngine.Collateral memory col = get_collateral(COL_TYPE);
        assertEq(col.rate, RAY);

        vm.expectRevert("already initialized");
        safe_engine.init(COL_TYPE);
    }

    function test_set_auth() public {
        vm.expectRevert("not authorized");
        vm.prank(address(1));
        safe_engine.set("sys_max_debt", 0);

        vm.expectRevert("not authorized");
        vm.prank(address(1));
        safe_engine.set(COL_TYPE, "spot", 0);
    }

    function test_set_invalid_param() public {
        vm.expectRevert("invalid param");
        safe_engine.set("x", 0);

        vm.expectRevert("invalid param");
        safe_engine.set(COL_TYPE, "x", 0);
    }

    function test_set() public {
        safe_engine.set("sys_max_debt", 100);
        assertEq(safe_engine.sys_max_debt(), 100);

        ICDPEngine.Collateral memory col;

        safe_engine.set(COL_TYPE, "spot", 100);
        col = get_collateral(COL_TYPE);
        assertEq(col.spot, 100);

        safe_engine.set(COL_TYPE, "max_debt", 200);
        col = get_collateral(COL_TYPE);
        assertEq(col.max_debt, 200);

        safe_engine.set(COL_TYPE, "min_debt", 300);
        col = get_collateral(COL_TYPE);
        assertEq(col.min_debt, 300);
    }

    function test_set_stopped() public {
        safe_engine.stop();
        vm.expectRevert("stopped");
        safe_engine.set("sys_max_debt", 0);

        vm.expectRevert("stopped");
        safe_engine.set(COL_TYPE, "spot", 0);
    }

    function test_stop() public {
        vm.expectRevert("not authorized");
        vm.prank(address(1));
        safe_engine.stop();

        assertEq(safe_engine.is_live(), true);
        safe_engine.stop();
        assertEq(safe_engine.is_live(), false);
    }

    function test_modify_collateral_balance() public {
        address src = address(1);

        vm.expectRevert("not authorized");
        vm.prank(address(1));
        safe_engine.modify_collateral_balance(COL_TYPE, src, 100);

        uint256 bal0;
        uint256 bal1;

        bal0 = safe_engine.gem(COL_TYPE, src);
        safe_engine.modify_collateral_balance(COL_TYPE, src, 100);
        bal1 = safe_engine.gem(COL_TYPE, src);
        assertEq(bal1 - bal0, 100);

        bal0 = safe_engine.gem(COL_TYPE, src);
        safe_engine.modify_collateral_balance(COL_TYPE, src, -10);
        bal1 = safe_engine.gem(COL_TYPE, src);
        assertEq(bal0 - bal1, 10);
    }

    function test_transfer_collataeral() public {
        address src = address(1);
        address dst = address(2);

        safe_engine.modify_collateral_balance(COL_TYPE, src, 100);

        vm.expectRevert("not authorized");
        safe_engine.transfer_collateral(COL_TYPE, src, dst, 100);

        vm.prank(src);
        safe_engine.transfer_collateral(COL_TYPE, src, dst, 10);
        assertEq(safe_engine.gem(COL_TYPE, src), 90);
        assertEq(safe_engine.gem(COL_TYPE, dst), 10);

        vm.prank(src);
        safe_engine.allow_account_modification(address(this));
        safe_engine.transfer_collateral(COL_TYPE, src, dst, 10);
        assertEq(safe_engine.gem(COL_TYPE, src), 80);
        assertEq(safe_engine.gem(COL_TYPE, dst), 20);
    }

    function test_transfer_coin() public {
        address src = address(1);
        address dst = address(2);

        safe_engine.mint(src, src, 100);

        vm.expectRevert("not authorized");
        safe_engine.transfer_coin(src, dst, 100);

        vm.prank(src);
        safe_engine.transfer_coin(src, dst, 10);
        assertEq(safe_engine.coin(src), 90);
        assertEq(safe_engine.coin(dst), 10);

        vm.prank(src);
        safe_engine.allow_account_modification(address(this));
        safe_engine.transfer_coin(src, dst, 10);
        assertEq(safe_engine.coin(src), 80);
        assertEq(safe_engine.coin(dst), 20);
    }

    function test_modify_safe_revert() public {
        address safe = address(1);
        address col_src = address(2);
        address coin_dst = address(3);

        // Test - collateral not initialized //
        vm.expectRevert("collateral not initialized");
        safe_engine.modify_safe({
            col_type: COL_TYPE,
            safe: safe,
            col_src: col_src,
            coin_dst: coin_dst,
            delta_col: 0,
            delta_debt: 0
        });

        safe_engine.init(COL_TYPE);
        safe_engine.set("sys_max_debt", 1000 * RAD);
        safe_engine.set(COL_TYPE, "max_debt", 100 * RAD);
        safe_engine.set(COL_TYPE, "spot", 11 * RAY);
        safe_engine.set(COL_TYPE, "min_debt", RAD);

        // Test - delta debt > max //
        vm.expectRevert("delta debt > max");
        safe_engine.modify_safe({
            col_type: COL_TYPE,
            safe: safe,
            col_src: col_src,
            coin_dst: coin_dst,
            delta_col: 0,
            delta_debt: int256(100 * WAD + 1)
        });

        // Test - undercollateralized //
        vm.expectRevert("undercollateralized");
        safe_engine.modify_safe({
            col_type: COL_TYPE,
            safe: safe,
            col_src: col_src,
            coin_dst: coin_dst,
            delta_col: int256(WAD),
            delta_debt: int256(11 * WAD + 1)
        });

        // Test - not allowed safe //
        vm.expectRevert("not allowed to modify safe");
        safe_engine.modify_safe({
            col_type: COL_TYPE,
            safe: safe,
            col_src: col_src,
            coin_dst: coin_dst,
            delta_col: int256(WAD),
            delta_debt: int256(WAD)
        });

        vm.prank(safe);
        safe_engine.allow_account_modification(address(this));

        // Test - not allowed collateral src //
        vm.expectRevert("not allowed to modify collateral src");
        safe_engine.modify_safe({
            col_type: COL_TYPE,
            safe: safe,
            col_src: col_src,
            coin_dst: coin_dst,
            delta_col: int256(WAD),
            delta_debt: int256(WAD)
        });

        vm.prank(col_src);
        safe_engine.allow_account_modification(address(this));

        // Test - not allowed coin dst //
        safe_engine.modify_collateral_balance(COL_TYPE, col_src, int256(WAD));
        safe_engine.modify_safe({
            col_type: COL_TYPE,
            safe: safe,
            col_src: col_src,
            coin_dst: coin_dst,
            delta_col: int256(WAD),
            delta_debt: int256(WAD)
        });

        vm.expectRevert("not allowed to modify coin dst");
        safe_engine.modify_safe({
            col_type: COL_TYPE,
            safe: safe,
            col_src: col_src,
            coin_dst: coin_dst,
            delta_col: 0,
            delta_debt: -int256(WAD)
        });

        vm.prank(coin_dst);
        safe_engine.allow_account_modification(address(this));

        // Test - dust //
        vm.expectRevert("debt < dust");
        safe_engine.modify_safe({
            col_type: COL_TYPE,
            safe: safe,
            col_src: col_src,
            coin_dst: coin_dst,
            delta_col: 0,
            delta_debt: -int256(WAD) + 1
        });

        // Test - stopped //
        safe_engine.stop();
        vm.expectRevert("stopped");
        safe_engine.modify_safe({
            col_type: COL_TYPE,
            safe: safe,
            col_src: col_src,
            coin_dst: coin_dst,
            delta_col: 0,
            delta_debt: 0
        });
    }

    function test_modify_safe() public {
        address safe = address(1);
        address col_src = address(2);
        address coin_dst = address(3);

        safe_engine.init(COL_TYPE);
        safe_engine.set("sys_max_debt", 1000 * RAD);
        safe_engine.set(COL_TYPE, "max_debt", 100 * RAD);
        safe_engine.set(COL_TYPE, "spot", 10 * RAY);
        safe_engine.set(COL_TYPE, "min_debt", RAD);

        vm.prank(safe);
        safe_engine.allow_account_modification(address(this));
        vm.prank(col_src);
        safe_engine.allow_account_modification(address(this));
        vm.prank(coin_dst);
        safe_engine.allow_account_modification(address(this));

        safe_engine.modify_collateral_balance(
            COL_TYPE, col_src, int256(10 * WAD)
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

            ICDPEngine.Safe memory s0 = get_safe(COL_TYPE, safe);
            ICDPEngine.Collateral memory col0 = get_collateral(COL_TYPE);
            uint256 gem0 = safe_engine.gem(COL_TYPE, col_src);
            uint256 coin0 = safe_engine.coin(coin_dst);

            safe_engine.modify_safe({
                col_type: COL_TYPE,
                safe: safe,
                col_src: col_src,
                coin_dst: coin_dst,
                delta_col: delta_col,
                delta_debt: delta_debt
            });

            ICDPEngine.Safe memory s1 = get_safe(COL_TYPE, safe);
            ICDPEngine.Collateral memory col1 = get_collateral(COL_TYPE);
            uint256 gem1 = safe_engine.gem(COL_TYPE, col_src);
            uint256 coin1 = safe_engine.coin(coin_dst);

            assertEq(s1.collateral, Math.add(s0.collateral, delta_col));
            assertEq(s1.debt, Math.add(s0.debt, delta_debt));
            assertEq(col1.debt, Math.add(col0.debt, delta_debt));
            assertEq(gem1, Math.sub(gem0, delta_col));
            assertEq(coin1, Math.add(coin0, Math.mul(col0.rate, delta_debt)));
        }
    }

    function test_mint() public {
        address debt_dst = address(1);
        address coin_dst = address(1);

        vm.expectRevert("not authorized");
        vm.prank(debt_dst);
        safe_engine.mint(debt_dst, coin_dst, 100);

        safe_engine.mint(debt_dst, coin_dst, 100);
        assertEq(safe_engine.debts(debt_dst), 100);
        assertEq(safe_engine.coin(coin_dst), 100);
        assertEq(safe_engine.sys_unbacked_debt(), 100);
        assertEq(safe_engine.sys_debt(), 100);
    }

    function test_burn() public {
        address src = address(1);
        safe_engine.mint(src, src, 100);

        vm.prank(src);
        safe_engine.burn(10);

        assertEq(safe_engine.debts(src), 90);
        assertEq(safe_engine.coin(src), 90);
        assertEq(safe_engine.sys_unbacked_debt(), 90);
        assertEq(safe_engine.sys_debt(), 90);
    }

    function test_sync() public {
        address coin_dst = address(1);

        vm.expectRevert("not authorized");
        vm.prank(coin_dst);
        safe_engine.sync(COL_TYPE, coin_dst, 100);

        // TODO: test with col.debt > 0
        safe_engine.sync(COL_TYPE, coin_dst, 100);

        safe_engine.stop();
        vm.expectRevert("stopped");
        safe_engine.sync(COL_TYPE, coin_dst, 100);
    }
}
