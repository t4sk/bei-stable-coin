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

    ISafeEngine public immutable safe_engine;
    ICoin public immutable dai;

    constructor(address _cdp_engine, address _dai) {
        safe_engine = ISafeEngine(_cdp_engine);
        dai = ICoin(_dai);
    }

    // cage
    function stop() external auth {
        _stop();
    }

    function join(address user, uint256 wad) external {
        safe_engine.transfer_coin(address(this), user, wad * RAY);
        dai.burn(msg.sender, wad);
        emit Join(user, wad);
    }

    function exit(address user, uint256 wad) external live {
        safe_engine.transfer_coin(msg.sender, address(this), wad * RAY);
        dai.mint(user, wad);
        emit Exit(user, wad);
    }
}
