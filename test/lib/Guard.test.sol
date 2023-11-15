// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {Guard} from "../../src/lib/Guard.sol";

contract TestGuard is Guard {
    function call() lock public {
        (bool ok, ) = msg.sender.call("");
        require(ok, "failed");
    }
}

contract GuardTest is Test {
    TestGuard private g;
    uint private n;
    uint private count;

    function setUp() public {
        g = new TestGuard();
    }

    fallback() external {
        if (count < n) {
            count += 1;
            g.call();
        }
    }

    function test_lock() public {
        g.call();

        n = 1;
        vm.expectRevert();
        g.call();
    }
}