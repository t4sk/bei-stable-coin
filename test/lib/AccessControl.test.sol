// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {AccessControl} from "../../src/lib/AccessControl.sol";

contract AccessControlTest is Test {
    AccessControl private ac;

    function setUp() public {
        ac = new AccessControl();
    }

    function test_allow_account_modification() public {
        address user = address(1);
        assertEq(ac.can(address(this), user), false);

        ac.allow_account_modification(user);
        assertEq(ac.can(address(this), user), true);
    }

    function test_deny_account_modification() public {
        address user = address(1);
        ac.allow_account_modification(user);
        assertEq(ac.can(address(this), user), true);

        ac.deny_account_modification(user);
        assertEq(ac.can(address(this), user), false);
    }

    function test_can_modify_account() public {
        address[2] memory users = [address(1), address(2)];

        assertEq(ac.can_modify_account(address(this), address(this)), true);

        ac.allow_account_modification(users[0]);
        assertEq(ac.can_modify_account(address(this), users[0]), true);
        assertEq(ac.can_modify_account(address(this), users[1]), false);
    }

    function test_fuzz_can_modify_account(address user_0, address user_1)
        public
    {
        vm.assume(user_0 != user_1);

        assertEq(ac.can_modify_account(user_0, user_0), true);
        assertEq(ac.can_modify_account(user_1, user_1), true);

        vm.prank(user_0);
        ac.allow_account_modification(user_1);

        assertEq(ac.can_modify_account(user_0, user_0), true);
        assertEq(ac.can_modify_account(user_0, user_1), true);
        assertEq(ac.can_modify_account(user_1, user_1), true);
        assertEq(ac.can_modify_account(user_1, user_0), false);

        vm.prank(user_0);
        ac.deny_account_modification(user_1);

        assertEq(ac.can_modify_account(user_0, user_0), true);
        assertEq(ac.can_modify_account(user_0, user_1), false);
        assertEq(ac.can_modify_account(user_1, user_1), true);
        assertEq(ac.can_modify_account(user_1, user_0), false);
    }
}
