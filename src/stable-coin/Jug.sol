// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import {ISafeEngine} from "../interfaces/ISafeEngine.sol";
import "../lib/Math.sol";
import "../lib/Auth.sol";

// TODO: dynamic fee where jug fee < stability fee
/*
The primary function of the Jug smart contract is to accumulate stability fees
for a particular collateral type whenever its drip() method is called.
*/
contract Jug is Auth {
    // Ilk
    struct Collateral {
        // Per second stability fee
        // duty - Collateral-specific, per-second stability fee contribution [ray]
        uint256 fee;
        // rho - Time of last drip [unix epoch time]
        uint256 updated_at;
    }

    // ilks
    mapping(bytes32 => Collateral) public collaterals;
    // vat
    ISafeEngine public immutable safe_engine;
    // vow
    address public debt_engine;
    // base - Global per-second stability fee [ray]
    uint256 public base_fee;

    constructor(address _safe_engine) {
        safe_engine = ISafeEngine(_safe_engine);
    }

    // --- Administration ---
    function init(bytes32 col_type) external auth {
        Collateral storage col = collaterals[col_type];
        require(col.fee == 0, "already initialized");
        col.fee = RAY;
        col.updated_at = block.timestamp;
    }

    // file
    function set(bytes32 col_type, bytes32 key, uint256 val) external auth {
        require(block.timestamp == collaterals[col_type].updated_at, "update time != now");
        if (key == "fee") {
            collaterals[col_type].fee = val;
        } else {
            revert("invalid param");
        }
    }

    function set(bytes32 key, uint256 val) external auth {
        if (key == "base_fee") {
            base_fee = val;
        } else {
            revert("invalid param");
        }
    }

    function set(bytes32 key, address val) external auth {
        if (key == "debt_engine") {
            debt_engine = val;
        } else {
            revert("invalid param");
        }
    }

    // --- Stability Fee Collection ---
    // drip
    function drip(bytes32 col_type) external returns (uint256 rate) {
        Collateral storage col = collaterals[col_type];
        require(block.timestamp >= col.updated_at, "now < last update");
        ISafeEngine.Collateral memory c = safe_engine.collaterals(col_type);
        rate =
            Math.rmul(Math.rpow(base_fee + col.fee, block.timestamp - col.updated_at, RAY), c.rate);
        safe_engine.sync(col_type, debt_engine, Math.diff(rate, c.rate));
        col.updated_at = block.timestamp;
    }
}
