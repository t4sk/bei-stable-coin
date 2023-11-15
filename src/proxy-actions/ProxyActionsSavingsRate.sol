// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import {ICoinJoin} from "../interfaces/ICoinJoin.sol";
import {ISafeEngine} from "../interfaces/ISafeEngine.sol";
import {IPot} from "../interfaces/IPot.sol";
import "../lib/Math.sol";
import {Common} from "./Common.sol";

// DssProxyActionsDsr
contract ProxyActionsSavingsRate is Common {
    function join(address coin_join, address pot, uint256 wad) public {
        ISafeEngine safe_engine =
            ISafeEngine(ICoinJoin(coin_join).safe_engine());
        // Executes drip to get the chi rate updated to rho == now,
        // otherwise join will fail
        uint256 chi = IPot(pot).drip();
        // Joins wad amount to the safe_engine balance
        coin_join_join(coin_join, address(this), wad);
        // Approves the pot to take out BEI from the proxy's balance in the safe_engine
        if (!safe_engine.can(address(this), address(pot))) {
            safe_engine.allow_account_modification(pot);
        }
        // Joins the pie value (equivalent to the BEI wad amount) in the pot
        IPot(pot).join(wad * RAY / chi);
    }

    function exit(address coin_join, address pot, uint256 wad) public {
        ISafeEngine safe_engine =
            ISafeEngine(ICoinJoin(coin_join).safe_engine());
        // Executes drip to count the savings accumulated until this moment
        uint256 chi = IPot(pot).drip();
        // Calculates the pie value in the pot equivalent to the BEI wad amount
        uint256 pie = wad * RAY / chi;
        // Exits BEI from the pot
        IPot(pot).exit(pie);
        // Checks the actual balance of BEI in the safe_engine after the pot exit
        uint256 bal = safe_engine.coin(address(this));
        // Allows adapter to access to proxy's BEI balance in the safe_engine
        if (!safe_engine.can(address(this), address(coin_join))) {
            safe_engine.allow_account_modification(coin_join);
        }
        // It is necessary to check if due rounding the exact wad amount can be exited by the adapter.
        // Otherwise it will do the maximum BEI balance in the safe_engine
        ICoinJoin(coin_join).exit(
            msg.sender, bal >= wad * RAY ? wad : bal / RAY
        );
    }

    function exit_all(address coin_join, address pot) public {
        ISafeEngine safe_engine =
            ISafeEngine(ICoinJoin(coin_join).safe_engine());
        // Executes drip to count the savings accumulated until this moment
        uint256 chi = IPot(pot).drip();
        // Gets the total pie belonging to the proxy address
        uint256 pie = IPot(pot).pie(address(this));
        // Exits BEI from the pot
        IPot(pot).exit(pie);
        // Allows adapter to access to proxy's BEI balance in the safe_engine
        if (!safe_engine.can(address(this), address(coin_join))) {
            safe_engine.allow_account_modification(coin_join);
        }
        // Exits the BEI amount corresponding to the value of pie
        ICoinJoin(coin_join).exit(msg.sender, chi * pie / RAY);
    }
}
