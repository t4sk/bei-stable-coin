// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {Auth} from "../../src/lib/Auth.sol";

contract AuthTest is Test {
    Auth private auth;

    function setUp() public {
        auth = new Auth();
    }

    function test_constructor() public {
        assertTrue(auth.authorized(address(this)));
    }

    function test_grant_auth_unauthorized() public {
        vm.expectRevert("not authorized");
        address user = address(1);
        vm.prank(user);
        auth.grant_auth(user);
    }

    function test_grant_auth() public {
        address user = address(1);
        auth.grant_auth(user);
        assertTrue(auth.authorized(user));
    }

    function test_deny_auth_unauthorized() public {
        vm.expectRevert("not authorized");
        address user = address(1);
        vm.prank(user);
        auth.deny_auth(user);
    }

    function test_deny_auth() public {
        address user = address(1);
        auth.grant_auth(user);

        auth.deny_auth(user);
        assertTrue(!auth.authorized(user));
    }
}
