// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ICDPEngine} from "../interfaces/ICDPEngine.sol";
import "../lib/Math.sol";
import "../lib/Auth.sol";

/*
The primary function of the Jug smart contract is to accumulate stability fees
for a particular collateral type whenever its drip() method is called.
*/
contract Jug is Auth {
    struct CollateralType {
        // Per second stability fee
        // duty - Collateral-specific, per-second stability fee contribution [ray]
        uint256 fee;
        // rho - Time of last drip [unix epoch time]
        uint256 updated_at;
    }

    mapping(bytes32 => CollateralType) public cols;
    // CDP engine
    ICDPEngine public immutable cdp_engine;
    // Debt engine
    address public debt_engine;
    // base - Global per-second stability fee [ray]
    uint256 public base_fee;

    constructor(address _cdp_engine) {
        cdp_engine = ICDPEngine(_cdp_engine);
    }

    // --- Administration ---
    function init(bytes32 col_type) external auth {
        CollateralType storage col = cols[col_type];
        require(col.fee == 0, "already initialized");
        col.fee = RAY;
        col.updated_at = block.timestamp;
    }

    // file
    function set(bytes32 col_type, bytes32 key, uint256 data) external auth {
        require(block.timestamp == cols[col_type].updated_at, "update time != now");
        if (key == "fee") {
            cols[col_type].fee = data;
        } else {
            revert("Unrecognized key");
        }
    }

    function set(bytes32 key, uint256 data) external auth {
        if (key == "base_fee") {
            base_fee = data;
        } else {
            revert("Unrecognized key");
        }
    }

    function set(bytes32 key, address data) external auth {
        if (key == "debt_engine") {
            debt_engine = data;
        } else {
            revert("Unrecognized key");
        }
    }

    // --- Stability Fee Collection ---
    // drip
    function drip(bytes32 col_type) external returns (uint256 rate) {
        CollateralType storage col = cols[col_type];
        require(block.timestamp >= col.updated_at, "now < last update");
        ICDPEngine.CollateralType memory c = cdp_engine.cols(col_type);
        rate = Math.rmul(Math.rpow(base_fee + col.fee, block.timestamp - col.updated_at, RAY), c.rate);
        cdp_engine.update_rate(col_type, debt_engine, Math.diff(rate, c.rate));
        col.updated_at = block.timestamp;
    }
}
