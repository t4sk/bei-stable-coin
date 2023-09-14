// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IVat} from "../interfaces/IVat.sol";
import {IDai} from "../interfaces/IDai.sol";
import {RAY} from "../lib/Math.sol";

contract DaiJoin {
    event AddAuthorization(address indexed user);
    event RemoveAuthorization(address indexed user);
    event Join(address indexed user, uint256 wad);
    event Exit(address indexed user, uint256 wad);
    event Pause();

    IVat public immutable vat;
    IDai public immutable dai;
    bool public live;

    // wards
    mapping(address => bool) public authorized;

    modifier auth() {
        require(authorized[msg.sender], "not authorized");
        _;
    }

    constructor(address _vat, address _dai) {
        authorized[msg.sender] = true;
        live = true;
        vat = IVat(_vat);
        dai = IDai(_dai);
        emit AddAuthorization(msg.sender);
    }

    // rely
    function addAuthorization(address user) external auth {
        authorized[user] = true;
        emit AddAuthorization(user);
    }

    // deny
    function remoteAuthorization(address user) external auth {
        authorized[user] = false;
        emit RemoveAuthorization(user);
    }

    // cage
    function stop() external auth {
        live = false;
        emit Pause();
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
