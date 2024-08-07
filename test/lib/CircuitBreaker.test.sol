// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {CircuitBreaker} from "../../src/lib/CircuitBreaker.sol";

contract TestCircuitBreaker is CircuitBreaker {
    function stop() public {
        _stop();
    }

    function call() public not_stopped {}
}

contract CircuitBreakerTest is Test {
    TestCircuitBreaker private cb;

    function setUp() public {
        cb = new TestCircuitBreaker();
    }

    function test_live() public {
        assertEq(cb.live(), true);
        cb.call();

        cb.stop();
        assertEq(cb.live(), false);

        vm.expectRevert("stopped");
        cb.call();
    }
}
