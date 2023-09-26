// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IVat} from "../interfaces/IVat.sol";
import {IDai} from "../interfaces/IDai.sol";
import {RAY} from "../lib/Math.sol";
import "../lib/Auth.sol";
import "../lib/Pause.sol";

contract DaiJoin is Auth, Pause {
    event Join(address indexed user, uint256 wad);
    event Exit(address indexed user, uint256 wad);

    IVat public immutable vat;
    IDai public immutable dai;

    constructor(address _vat, address _dai) {
        vat = IVat(_vat);
        dai = IDai(_dai);
    }

    // cage
    function stop() external auth {
        _stop();
    }

    function join(address user, uint256 wad) external {
        vat.transferDai(address(this), user, wad * RAY);
        dai.burn(msg.sender, wad);
        emit Join(user, wad);
    }

    function exit(address user, uint256 wad) external {
        require(live, "not live");
        vat.transferDai(msg.sender, address(this), wad * RAY);
        dai.mint(user, wad);
        emit Exit(user, wad);
    }
}
