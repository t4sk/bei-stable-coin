// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IVat} from "../interfaces/IVat.sol";
import "../interfaces/IPriceFeed.sol";
import "../lib/Math.sol";
import "../lib/Auth.sol";
import "../lib/Pause.sol";

struct CollateralType {
    IPriceFeed priceFeed;
    // mat
    // TODO: what?
    uint256 liquidationRatio;
}

contract Spot is Auth, Pause {
    event Poke(bytes32 colType, uint256 val, uint256 spot);

    mapping(bytes32 => CollateralType) public cols;

    IVat public immutable vat;
    // TODO: what is par?
    uint256 public par; // ref per dai [ray]

    constructor(address _vat) {
        live = true;
        vat = IVat(_vat);
        par = RAY;
    }

    // file
    function set(bytes32 colType, bytes32 name, address priceFeed)
        external
        auth
        notStopped
    {
        if (name == "priceFeed") {
            cols[colType].priceFeed = IPriceFeed(priceFeed);
        } else {
            revert("unrecognized param");
        }
    }

    function set(bytes32 colType, bytes32 name, uint256 data)
        external
        auth
        notStopped
    {
        if (name == "liquidationRatio") {
            cols[colType].liquidationRatio = data;
        } else {
            revert("unrecognized param");
        }
    }

    function set(bytes32 name, uint256 data) external auth notStopped {
        if (name == "par") {
            par = data;
        } else {
            revert("unrecognized param");
        }
    }

    function poke(bytes32 colType) external {
        (uint256 val, bool ok) = cols[colType].priceFeed.peek();
        uint256 spot = ok
            // TODO: what?
            ? Math.rdiv(
                Math.rdiv(val * 10 ** 9, par), cols[colType].liquidationRatio
            )
            : 0;
        vat.modifyParam(colType, "spot", spot);
        emit Poke(colType, val, spot);
    }

    function stop() external auth {
        _stop();
    }
}
