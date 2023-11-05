// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IVat} from "../interfaces/IVat.sol";
import {ICoin} from "../interfaces/ICoin.sol";
import {RAY} from "../lib/Math.sol";
import {Auth} from "../lib/Auth.sol";
import {CircuitBreaker} from "../lib/CircuitBreaker.sol";

contract CoinJoin is Auth, CircuitBreaker {
    event Join(address indexed user, uint256 wad);
    event Exit(address indexed user, uint256 wad);

    IVat public immutable vat;
    ICoin public immutable dai;

    constructor(address _vat, address _dai) {
        vat = IVat(_vat);
        dai = ICoin(_dai);
    }

    // cage
    function stop() external auth {
        _stop();
    }

    function join(address user, uint256 wad) external {
        vat.transfer_coin(address(this), user, wad * RAY);
        dai.burn(msg.sender, wad);
        emit Join(user, wad);
    }

    function exit(address user, uint256 wad) external {
        require(live, "not live");
        vat.transfer_coin(msg.sender, address(this), wad * RAY);
        dai.mint(user, wad);
        emit Exit(user, wad);
    }
}
