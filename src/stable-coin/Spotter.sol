// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import {ISafeEngine} from "../interfaces/ISafeEngine.sol";
import {IPriceFeed} from "../interfaces/IPriceFeed.sol";
import {ISpotter} from "../interfaces/ISpotter.sol";
import "../lib/Math.sol";
import {Auth} from "../lib/Auth.sol";
import {CircuitBreaker} from "../lib/CircuitBreaker.sol";

// TODO: rename?
contract Spotter is Auth, CircuitBreaker {
    event Poke(bytes32 col_type, uint256 val, uint256 spot);

    // ilks
    mapping(bytes32 => ISpotter.Collateral) public collaterals;

    ISafeEngine public immutable safe_engine;
    // par - value of BEI in the reference asset (e.g. $1 per BEI)
    uint256 public par; // ref per BEI [ray]

    constructor(address _safe_engine) {
        safe_engine = ISafeEngine(_safe_engine);
        par = RAY;
    }

    // file
    function set(bytes32 col_type, bytes32 key, address addr) external auth live {
        if (key == "price_feed") {
            collaterals[col_type].price_feed = IPriceFeed(addr);
        } else {
            revert("invalid param");
        }
    }

    function set(bytes32 key, uint256 val) external auth live {
        if (key == "par") {
            par = val;
        } else {
            revert("invalid param");
        }
    }

    function set(bytes32 col_type, bytes32 key, uint256 val) external auth live {
        if (key == "liquidation_ratio") {
            collaterals[col_type].liquidation_ratio = val;
        } else {
            revert("invalid param");
        }
    }

    function poke(bytes32 col_type) external {
        (uint256 val, bool ok) = IPriceFeed(collaterals[col_type].price_feed).peek();
        // TODO: should require ok?
        uint256 spot = ok
            // TODO: what?
            ? Math.rdiv(Math.rdiv(val * 10 ** 9, par), collaterals[col_type].liquidation_ratio)
            : 0;
        safe_engine.set(col_type, "spot", spot);
        emit Poke(col_type, val, spot);
    }

    function stop() external auth {
        _stop();
    }
}
