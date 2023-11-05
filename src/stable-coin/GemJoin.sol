// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IVat} from "../interfaces/IVat.sol";
import {IGem} from "../interfaces/IGem.sol";
import {Auth} from "../lib/Auth.sol";
import {CircuitBreaker} from "../lib/CircuitBreaker.sol";

contract GemJoin is Auth, CircuitBreaker {
    event Join(address indexed user, uint256 wad);
    event Exit(address indexed user, uint256 wad);

    IVat public immutable vat;
    // ilk
    bytes32 public immutable collateralType;
    IGem public immutable gem;
    // decimals
    uint256 public immutable dec;

    constructor(address _vat, bytes32 _collateralType, address _gem) {
        vat = IVat(_vat);
        collateralType = _collateralType;
        gem = IGem(_gem);
        dec = gem.decimals();
    }

    // cage
    function stop() external auth {
        _stop();
    }

    function join(address user, uint256 wad) external {
        require(live, "not live");
        // wad <= 2**255 - 1
        require(int256(wad) >= 0, "overflow");
        vat.modify_collateral_balance(collateralType, user, int256(wad));
        require(gem.transferFrom(msg.sender, address(this), wad), "transfer failed");
        emit Join(user, wad);
    }

    function exit(address user, uint256 wad) external {
        require(wad <= 2 ** 255, "overflow");
        vat.modify_collateral_balance(collateralType, msg.sender, -int256(wad));
        require(gem.transfer(user, wad), "transfer failed");
        emit Exit(user, wad);
    }
}
