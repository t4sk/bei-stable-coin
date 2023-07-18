// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./SafeHandler.sol";

contract CdpManager {
    address public immutable vat;
    uint256 public cdpId;

    // CDP id => safe handler
    mapping(uint256 => address) public safes;
    // CDP id => owner
    mapping(uint256 => address) public owners;
    // CDP id => collateral type
    mapping(uint256 => bytes32) public collateralTypes;

    constructor(address _vat) {
        vat = _vat;
    }

    function open(bytes32 collateralType, address user)
        public
        returns (uint256 id)
    {
        require(user != address(0), "user = 0 address");

        uint256 id = cdpId + 1;
        safes[id] = address(new SafeHandler(vat));
    }
}
