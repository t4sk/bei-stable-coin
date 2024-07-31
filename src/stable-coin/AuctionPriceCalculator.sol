// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.24;

import {Auth} from "../lib/Auth.sol";
import "../lib/Math.sol";

// Abacus
contract LinearDecrease is Auth {
    // --- Data ---
    // tau [seconds] - Seconds after auction start when the price reaches zero
    uint256 public duration;

    // --- Administration ---
    // file
    function set(bytes32 key, uint256 val) external auth {
        if (key == "duration") {
            duration = val;
        } else {
            revert("unrecognized param");
        }
    }

    // Price calculation when price is decreased linearly in proportion to time:
    // tau: The number of seconds after the start of the auction where the price will hit 0
    // top: Initial price
    // dur: current seconds since the start of the auction
    //
    // Returns y = top * ((tau - dur) / tau)
    //
    // Note the internal call to mul multiples by RAY, thereby ensuring that the rmul calculation
    // which utilizes top and tau (RAY values) is also a RAY value.
    function price(uint256 top, uint256 dt) external view returns (uint256) {
        if (duration <= dt) {
            return 0;
        }
        return Math.rmul(top, (duration - dt) * RAY / duration);
    }
}

contract StairstepExponentialDecrease is Auth {
    // --- Data ---
    // step [seconds] - Length of time between price drops
    uint256 public step;
    // cut [ray] - Per-step multiplicative factor
    uint256 public cut;

    // --- Administration ---
    // file
    function set(bytes32 key, uint256 val) external auth {
        if (key == "cut") {
            require(
                (cut = val) <= RAY, "StairstepExponentialDecrease/cut-gt-RAY"
            );
        } else if (key == "step") {
            step = val;
        } else {
            revert("unrecognized param");
        }
    }

    // top: initial price
    // dur: seconds since the auction has started
    // step: seconds between a price drop
    // cut: cut encodes the percentage to decrease per step.
    //   For efficiency, the values is set as (1 - (% value / 100)) * RAY
    //   So, for a 1% decrease per step, cut would be (1 - 0.01) * RAY
    //
    // returns: top * (cut ^ dur)
    //
    //
    function price(uint256 top, uint256 dt) external view returns (uint256) {
        return Math.rmul(top, Math.rpow(cut, dt / step, RAY));
    }
}

// TODO:
contract ExponentialDecrease is Auth {}
