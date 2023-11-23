// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import {ICDPEngine} from "../interfaces/ICDPEngine.sol";
import {IPriceFeed} from "../interfaces/IPriceFeed.sol";
import {ISpotter} from "../interfaces/ISpotter.sol";
import "../lib/Math.sol";
import {Auth} from "../lib/Auth.sol";
import {CircuitBreaker} from "../lib/CircuitBreaker.sol";

contract Spotter is Auth, CircuitBreaker {
    event Poke(bytes32 col_type, uint256 val, uint256 spot);

    // ilks
    mapping(bytes32 => ISpotter.Collateral) public collaterals;

    ICDPEngine public immutable cdp_engine;
    // par [ray] - value of BEI in the reference asset (e.g. $1 per BEI)
    uint256 public par;

    constructor(address _cdp_engine) {
        cdp_engine = ICDPEngine(_cdp_engine);
        par = RAY;
    }

    // file
    function set(bytes32 key, uint256 val) external auth live {
        if (key == "par") {
            par = val;
        } else {
            revert("invalid param");
        }
    }

    function set(bytes32 col_type, bytes32 key, address addr)
        external
        auth
        live
    {
        if (key == "price_feed") {
            collaterals[col_type].price_feed = addr;
        } else {
            revert("invalid param");
        }
    }

    function set(bytes32 col_type, bytes32 key, uint256 val)
        external
        auth
        live
    {
        if (key == "liquidation_ratio") {
            collaterals[col_type].liquidation_ratio = val;
        } else {
            revert("invalid param");
        }
    }

    function poke(bytes32 col_type) external {
        (uint256 val, bool ok) =
            IPriceFeed(collaterals[col_type].price_feed).peek();
        // NOTE: spot = liquidation price
        //            = val * 1e9 * par / liquidation_ratio
        uint256 spot = ok
            ? Math.rdiv(
                Math.rdiv(val * 1e9, par), collaterals[col_type].liquidation_ratio
            )
            : 0;
        cdp_engine.set(col_type, "spot", spot);
        emit Poke(col_type, val, spot);
    }

    function stop() external auth {
        _stop();
    }
}
