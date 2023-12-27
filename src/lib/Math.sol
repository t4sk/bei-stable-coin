// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

uint256 constant WAD = 10 ** 18;
uint256 constant RAY = 10 ** 27;
uint256 constant RAD = 10 ** 45;

library Math {
    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x <= y ? x : y;
    }

    function max(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x >= y ? x : y;
    }

    function add(uint256 x, int256 y) internal pure returns (uint256 z) {
        // int256 = -2 ** 255 to 2 ** 255 - 1
        // overflow for -y if y = -2 ** 255
        z = y >= 0 ? x + uint256(y) : x - uint256(-y);
    }

    function sub(uint256 x, int256 y) internal pure returns (uint256 z) {
        z = y >= 0 ? x - uint256(y) : x + uint256(-y);
    }

    function mul(uint256 x, int256 y) internal pure returns (int256 z) {
        // x < 2 ** 255
        require(int256(x) >= 0, "x > max int256");
        z = int256(x) * y;
    }

    function diff(uint256 x, uint256 y) internal pure returns (int256 z) {
        require(int256(x) >= 0 && int256(y) >= 0);
        z = int256(x) - int256(y);
    }

    function to_rad(uint256 wad) internal pure returns (uint256 rad) {
        rad = wad * RAY;
    }

    function wmul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x * y / WAD;
    }

    function rmul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x * y / RAY;
    }

    function rdiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x * RAY / y;
    }

    function rpow(uint256 x, uint256 n, uint256 b)
        internal
        pure
        returns (uint256 z)
    {
        assembly {
            switch x
            // x = 0
            case 0 {
                switch n
                // n = 0 --> x**n = 0**0 --> 1
                case 0 { z := b }
                // n > 0 --> x**n = 0**n --> 0
                default { z := 0 }
            }
            default {
                switch mod(n, 2)
                // x > 0 and n is even --> z = 1
                case 0 { z := b }
                // x > 0 and n is odd --> z = x
                default { z := x }

                let half := div(b, 2) // for rounding.
                // n = n / 2, while n > 0, n = n / 2
                for { n := div(n, 2) } n { n := div(n, 2) } {
                    let xx := mul(x, x)
                    // Check overflow? revert if xx / x != x
                    if iszero(eq(div(xx, x), x)) { revert(0, 0) }
                    // Round (xx + half) / b
                    let xxRound := add(xx, half)
                    // Check overflow - revert if xxRound < xx
                    if lt(xxRound, xx) { revert(0, 0) }
                    x := div(xxRound, b)
                    // if n % 2 == 1
                    if mod(n, 2) {
                        let zx := mul(z, x)
                        // revert if x != 0 and zx / x != z
                        if and(iszero(iszero(x)), iszero(eq(div(zx, x), z))) {
                            revert(0, 0)
                        }
                        // Round (zx + half) / b
                        let zxRound := add(zx, half)
                        // Check overflow - revert if zxRound < zx
                        if lt(zxRound, zx) { revert(0, 0) }
                        z := div(zxRound, b)
                    }
                }
            }
        }
    }
}
