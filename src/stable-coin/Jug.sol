// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.24;

import {ICDPEngine} from "../interfaces/ICDPEngine.sol";
import "../lib/Math.sol";
import {Auth} from "../lib/Auth.sol";

/*
The primary function of the Jug smart contract is to accumulate stability fees
for a particular collateral type whenever its collect_stability_fee() method is called.
*/
contract Jug is Auth {
    // Ilk
    struct Collateral {
        // Per second stability fee
        // duty [ray] - Collateral-specific, per-second stability fee contribution
        uint256 fee;
        // rho - Time of last collect_stability_fee [unix epoch time]
        uint256 updated_at;
    }

    // ilks
    mapping(bytes32 => Collateral) public collaterals;
    // vat
    ICDPEngine public immutable cdp_engine;
    // vow
    address public ds_engine;
    // base [ray] - Global per-second stability fee
    uint256 public base_fee;

    constructor(address _cdp_engine) {
        cdp_engine = ICDPEngine(_cdp_engine);
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
        require(
            block.timestamp == collaterals[col_type].updated_at,
            "update time != now"
        );
        if (key == "fee") {
            collaterals[col_type].fee = val;
        } else {
            revert("unrecognized param");
        }
    }

    function set(bytes32 key, uint256 val) external auth {
        if (key == "base_fee") {
            base_fee = val;
        } else {
            revert("unrecognized param");
        }
    }

    function set(bytes32 key, address val) external auth {
        if (key == "ds_engine") {
            ds_engine = val;
        } else {
            revert("unrecognized param");
        }
    }

    // --- Stability Fee Collection ---
    // drip
    function collect_stability_fee(bytes32 col_type)
        external
        returns (uint256 rate)
    {
        Collateral storage col = collaterals[col_type];
        require(col.updated_at <= block.timestamp, "now < last update");
        ICDPEngine.Collateral memory c = cdp_engine.collaterals(col_type);
        rate = Math.rmul(
            Math.rpow(base_fee + col.fee, block.timestamp - col.updated_at, RAY),
            c.rate_acc
        );
        cdp_engine.update_rate_acc(
            col_type, ds_engine, Math.diff(rate, c.rate_acc)
        );
        col.updated_at = block.timestamp;
    }
}
