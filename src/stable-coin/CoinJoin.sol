// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import {ISafeEngine} from "../interfaces/ISafeEngine.sol";
import {ICoin} from "../interfaces/ICoin.sol";
import "../lib/Math.sol";
import {Auth} from "../lib/Auth.sol";
import {CircuitBreaker} from "../lib/CircuitBreaker.sol";

contract CoinJoin is Auth, CircuitBreaker {
    event Join(address indexed user, uint256 wad);
    event Exit(address indexed user, uint256 wad);

    // vat
    ISafeEngine public immutable safe_engine;
    // dai
    ICoin public immutable coin;

    constructor(address _safe_engine, address _coin) {
        safe_engine = ISafeEngine(_safe_engine);
        coin = ICoin(_coin);
    }

    // cage
    function stop() external auth {
        _stop();
    }

    function join(address user, uint256 wad) external {
        safe_engine.transfer_coin(address(this), user, wad * RAY);
        coin.burn(msg.sender, wad);
        emit Join(user, wad);
    }

    function exit(address user, uint256 wad) external live {
        safe_engine.transfer_coin(msg.sender, address(this), wad * RAY);
        coin.mint(user, wad);
        emit Exit(user, wad);
    }
}
