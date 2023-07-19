// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IVat} from "../interfaces/IVat.sol";
import {IGem} from "../interfaces/IGem.sol";

contract GemJoin {
    event AddAuthorization(address indexed user);
    event RemoveAuthorization(address indexed user);
    event Stop();
    event Join(address indexed user, uint256 wad);
    event Exit(address indexed user, uint256 wad);

    IVat public immutable vat;
    // ilk
    bytes32 public immutable collateralType;
    IGem public immutable gem;
    // decimals
    uint256 public immutable dec;
    bool public live;

    // wards
    mapping(address => bool) public authorized;

    modifier auth() {
        require(authorized[msg.sender], "not authorized");
        _;
    }

    constructor(address _vat, bytes32 _collateralType, address _gem) {
        authorized[msg.sender] = true;
        live = true;
        vat = IVat(_vat);
        collateralType = _collateralType;
        gem = IGem(_gem);
        dec = gem.decimals();
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
        emit Stop();
    }

    function join(address user, uint256 wad) external {
        require(live, "not live");
        // TODO: what?
        require(int256(wad) >= 0, "overflow");
        vat.slip(collateralType, user, int256(wad));
        require(
            gem.transferFrom(msg.sender, address(this), wad), "transfer failed"
        );
        emit Join(user, wad);
    }

    function exit(address user, uint256 wad) external {
        require(wad <= 2 ** 255, "overflow");
        vat.slip(collateralType, msg.sender, -int256(wad));
        require(gem.transfer(user, wad), "transfer failed");
        emit Exit(user, wad);
    }
}
