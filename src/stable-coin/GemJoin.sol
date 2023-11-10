// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import {ISafeEngine} from "../interfaces/ISafeEngine.sol";
import {IGem} from "../interfaces/IGem.sol";
import {Auth} from "../lib/Auth.sol";
import {CircuitBreaker} from "../lib/CircuitBreaker.sol";

contract GemJoin is Auth, CircuitBreaker {
    event Join(address indexed user, uint256 wad);
    event Exit(address indexed user, uint256 wad);

    // vat
    ISafeEngine public immutable safe_engine;
    // ilk
    bytes32 public immutable collateral_type;
    // gem
    IGem public immutable gem;
    // dec
    uint8 public immutable decimals;

    constructor(address _safe_engine, bytes32 _collateral_type, address _gem) {
        safe_engine = ISafeEngine(_safe_engine);
        collateral_type = _collateral_type;
        gem = IGem(_gem);
        decimals = gem.decimals();
    }

    // cage
    function stop() external auth {
        _stop();
    }

    function join(address user, uint256 wad) external live {
        // wad <= 2**255 - 1
        require(int256(wad) >= 0, "overflow");
        safe_engine.modify_collateral_balance(collateral_type, user, int256(wad));
        require(gem.transferFrom(msg.sender, address(this), wad), "transfer failed");
        emit Join(user, wad);
    }

    function exit(address user, uint256 wad) external {
        require(wad <= 2 ** 255, "overflow");
        safe_engine.modify_collateral_balance(collateral_type, msg.sender, -int256(wad));
        require(gem.transfer(user, wad), "transfer failed");
        emit Exit(user, wad);
    }
}
