// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

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

    function test_add_auth_unauthorized() public {
        vm.expectRevert("not authorized");
        address user = address(1);
        vm.prank(user);
        auth.add_auth(user);
    }

    function test_add_auth() public {
        address user = address(1);
        auth.add_auth(user);
        assertTrue(auth.authorized(user));
    }

    function test_remove_auth_unauthorized() public {
        vm.expectRevert("not authorized");
        address user = address(1);
        vm.prank(user);
        auth.remove_auth(user);
    }

    function test_remove_auth() public {
        address user = address(1);
        auth.add_auth(user);

        auth.remove_auth(user);
        assertTrue(!auth.authorized(user));
   }
}
