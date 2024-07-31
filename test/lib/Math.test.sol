// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../../src/lib/Math.sol";

contract MathTest is Test {
    function bound_int(int256 y) private pure returns (int256) {
        return y == type(int256).min ? y + 1 : y;
    }

    function test_min(uint256 x, uint256 y) public {
        assertEq(Math.min(x, y), x <= y ? x : y);
    }

    function test_max(uint256 x, uint256 y) public {
        assertEq(Math.max(x, y), x <= y ? y : x);
    }

    function test_add(uint256 x, int256 y) public {
        x = bound(x, 0, 2 ** 255);
        y = bound_int(y);
        x = y >= 0 ? x : Math.max(x, uint256(-y));
        assertEq(Math.add(x, y), y >= 0 ? x + uint256(y) : x - uint256(-y));
    }

    function test_sub(uint256 x, int256 y) public {
        x = bound(x, 0, 2 ** 255);
        y = bound_int(y);
        x = y <= 0 ? x : Math.max(x, uint256(y));
        assertEq(Math.sub(x, y), y >= 0 ? x - uint256(y) : x + uint256(-y));
    }

    function test_mul(uint256 x, int256 y) public {
        x = bound(x, 0, 2 ** 255 - 1);

        // Check overflow
        int256 z;
        unchecked {
            z = int256(x) * y;
        }

        if (y != 0 && z / y != int256(x)) {
            vm.expectRevert();
        }

        z = Math.mul(x, y);
        assertEq(z, int256(x) * y);
    }
}
