// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../interfaces/IVat.sol";
import "../lib/Math.sol";
import "../lib/Auth.sol";

contract Jug is Auth {
    struct CollateralType {
        // Per second stability fee
        uint256 fee;
        uint256 updatedAt;
    }

    mapping(bytes32 => CollateralType) public collateralTypes;
    IVat public immutable vat;
    address public vow;
    // Global stability fee
    uint256 public base;

    constructor(address _vat) {
        vat = IVat(_vat);
    }

    function _diff(uint256 x, uint256 y) internal pure returns (int256 z) {
        z = int256(x) - int256(y);
        require(int256(x) >= 0 && int256(y) >= 0);
    }

    function init(bytes32 colType) external auth {
        CollateralType storage col = collateralTypes[colType];
        require(col.fee == 0, "already initialized");
        col.fee = RAY;
        col.updatedAt = block.timestamp;
    }

    // file
    function modifyParams(bytes32 colType, bytes32 name, uint256 data)
        external
        auth
    {
        require(
            block.timestamp == collateralTypes[colType].updatedAt,
            "update time != now"
        );
        if (name == "fee") {
            collateralTypes[colType].fee = data;
        } else {
            revert("Unrecognized name");
        }
    }

    function modifyParams(bytes32 name, uint256 data) external auth {
        if (name == "base") {
            base = data;
        } else {
            revert("Unrecognized name");
        }
    }

    function modifyParams(bytes32 name, address data) external auth {
        if (name == "vow") {
            vow = data;
        } else {
            revert("Unrecognized name");
        }
    }

    // TODO: fee

    // drip
    function drip(bytes32 colType) external returns (uint256 rate) {
        CollateralType storage col = collateralTypes[colType];

        require(
            block.timestamp >= col.updatedAt, "block timestamp < update time"
        );
        (, uint256 prev) = vat.collateralTypes(colType);
        rate = Math.rpow(base + col.fee, block.timestamp - col.updatedAt, RAY)
            * prev / RAY;
        // TODO: ?
        vat.updateRate(colType, vow, _diff(rate, prev));
        col.updatedAt = block.timestamp;
    }
}
