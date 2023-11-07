// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Auth} from "../lib/Auth.sol";
import "../lib/Math.sol";

// Abacus
contract LinearDecrease is Auth {
    // --- Data ---
    // tau
    // Seconds after auction start when the price reaches zero [seconds]
    uint256 public duration;

    // --- Administration ---
    // file
    function set(bytes32 key, uint256 val) external auth {
        if (key == "duration") {
            duration = val;
        } else {
            revert("invalid param");
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
        // TODO: top is RAY?
        return Math.rmul(top, (duration - dt) * RAY / duration);
    }
}

// TODO:
contract StairstepExponentialDecrease is Auth {}

// TODO:
contract ExponentialDecrease is Auth {}
