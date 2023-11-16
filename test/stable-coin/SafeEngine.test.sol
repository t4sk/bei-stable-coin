// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {ISafeEngine} from "../../src/interfaces/ISafeEngine.sol";
import "../../src/lib/Math.sol";
import {SafeEngine} from "../../src/stable-coin/SafeEngine.sol";

contract SafeEngineTest is Test {
    SafeEngine private safe_engine;

    bytes32 private constant COL_TYPE = bytes32(uint256(1));

    function setUp() public {
        safe_engine = new SafeEngine();
    }

    function get_collateral(bytes32 col_type)
        internal
        returns (ISafeEngine.Collateral memory)
    {
        return ISafeEngine(address(safe_engine)).collaterals(col_type);
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
        ISafeEngine.Collateral memory col = get_collateral(COL_TYPE);
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

        ISafeEngine.Collateral memory col;

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

    function test_modify_safe() public {
        address safe = address(1);
        address col_src = address(2);
        address coin_dst = address(3);
        int256 delta_col = 0;
        int256 delta_debt = 0;

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
        safe_engine.modify_safe({
            col_type: COL_TYPE,
            safe: safe,
            col_src: col_src,
            coin_dst: coin_dst,
            delta_col: 0,
            delta_debt: 0
        });

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

        // TODO: test
        safe_engine.sync(COL_TYPE, coin_dst, 100);

        safe_engine.stop();
        vm.expectRevert("stopped");
        safe_engine.sync(COL_TYPE, coin_dst, 100);
    }
}
