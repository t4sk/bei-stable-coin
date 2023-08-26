pragma solidity 0.8.18;

contract Math {
    function test(uint x, uint n, uint b) public pure returns (uint z) {
        assembly {
            z := x



            // n = 3,  x = x*x, z = z*x

            // n = 5,  (x = x*x, (x = x*x, z = z*x))
            // n = 6,  ((x = x*x, x = z*x), x = x*x)
            // n = 7,  ((x = x*x, x = z*x), (x = x*x, x = z*x))

            // n = 0,  z = b
            // n = 1,  z = x
            // n = 2,  z = b, x = x*x, z = z*x
            // n = 3,  z = x, x = x*x, z = z*x
            // n = 4,  z = b, x = x*x | x = x*x, z = z*x
            // n = 5,  z = x, x = x*x | x = x*x, z = z*x
            // n = 6,  z = b, x = x*x, z = z*x | x = x*x, z = z*x
            // n = 7,  z = x, x = x*x, z = z*x | x = x*x, z = z*x
            // n = 8,  z = b, x = x*x | x = x*x | x = x*x, z = z*x
            // n = 16, z = b, x = x*x | x = x*x | x = x*x | x = x*x, z = z*x

            for { n := div(n, 2) } n { n := div(n, 2) } {
                let xx := mul(x, x)
                x := div(xx, b)
            }
        }
    }

    // let, if, switch, revert, loop, gas cost of iszero and not, math overflow check (add, mul)
    function my_rpow(uint x, uint n, uint b) public pure returns (uint z) {
        assembly {
            switch x
            // x = 0
            case 0 {
                switch n
                case 0 {
                    // 0**0
                    z := b
                }
                default {
                    // 0**n, n > 0
                    z := 0
                }
            }
            // x > 0
            default {
                switch mod(n, 2)
                // even
                case 0 {
                    z := b
                }
                // odd
                default {
                    z := x
                }
                let half := div(b, 2)
                for { n := div(n, 2) } n { n := div(n, 2)} {
                    let xx := mul(x, x)
                    // Check overflow? revert if xx / x != x
                    if iszero(eq(div(xx, x), x)) { revert(0, 0) }
                    let xxRound := add(xx, half)
                    // Check overflow - revert if xxRound < xx
                    if lt(xxRound, xx) { revert(0, 0) }
                    // x = 3, b = 10
                    // (9 + 5) / 10 = 14 / 10 = 1
                    // 9 / 10 = 0
                    x := div(xxRound, b)
                    // if n % 2 == 1
                    if mod(n, 2) {
                        let zx := mul(z, x)
                        // revert if x != 0 and zx / x != z
                        if and(iszero(iszero(x)), iszero(eq(div(zx, x), z))) { revert(0, 0) }
                        let zxRound := add(zx, half)
                        // Check overflow - revert if zxRound < zx
                        if lt(zxRound, zx) { revert(0, 0) }
                        z := div(zxRound, b)
                    }
                }
            }
        }
    }

    function rpow(uint x, uint n, uint b) public pure returns (uint z) {
      assembly {
        switch x case 0 {switch n case 0 {z := b} default {z := 0}}
        default {
          switch mod(n, 2) case 0 { z := b } default { z := x }
          let half := div(b, 2)  // for rounding.
          for { n := div(n, 2) } n { n := div(n,2) } {
            let xx := mul(x, x)
            if iszero(eq(div(xx, x), x)) { revert(0,0) }
            let xxRound := add(xx, half)
            if lt(xxRound, xx) { revert(0,0) }
            x := div(xxRound, b)
            if mod(n,2) {
              let zx := mul(z, x)
              if and(iszero(iszero(x)), iszero(eq(div(zx, x), z))) { revert(0,0) }
              let zxRound := add(zx, half)
              if lt(zxRound, zx) { revert(0,0) }
              z := div(zxRound, b)
            }
          }
        }
      }
    }

    function forLoop(uint n) public pure returns (uint i) {
        // 1188 gas for n = 10
        // assembly {
        //     for { let k := n } k { k := sub(k, 1) } {
        //         i := add(i, 1)
        //     }
        // }

        // 4902 gas
        for (uint k = n; k > 0; k -= 1) {
            i += 1;
        }
    }

    function whileLoop(uint n) public pure returns (uint i) {
        assembly {
            for {} n {} {
                n := sub(n, 1)
                i := add(i, 1)
            }
        }
    }
}
