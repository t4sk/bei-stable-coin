// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./SafeHandler.sol";

contract CdpManager {
    address public immutable vat;
    uint256 public cdpId;

    struct List {
        uint256 prev;
        uint256 next;
    }

    // CDP id => vault handler
    mapping(uint256 => address) public vaults;
    // CDP id => owner
    mapping(uint256 => address) public owners;
    // CDP id => collateral type
    mapping(uint256 => bytes32) public collateralTypes;

    // CDP id => List
    mapping(uint256 => List) public list;
    // Owner => first CDP id
    mapping(address => uint256) public first;
    // Owner => last CDP id
    mapping(address => uint256) public last;
    // Owner => CDP count
    mapping(address => uint256) public count;

    constructor(address _vat) {
        vat = _vat;
    }

    function open(bytes32 collateralType, address user)
        public
        returns (uint256)
    {
        require(user != address(0), "user = 0 address");

        uint256 id = cdpId + 1;
        cdpId = id;

        vaults[id] = address(new SafeHandler(vat));
        owners[id] = user;
        collateralTypes[id] = collateralType;

        // Add new CDP to double linked list
        if (first[user] == 0) {
            first[user] = id;
        }
        if (last[user] != 0) {
            list[id].prev = last[user];
            list[last[user]].next = id;
        }
        last[user] = id;
        count[user] += 1;

        // Open 1st time
        // first = 1
        // last  = 1

        // Open 2nd time
        // first = 1
        // list[2].prev = 1
        // list[1].next = 2
        // last = 2

        // Open 3rd time
        // first = 1
        // list[3].prev = 2
        // list[2].next = 3
        // last = 3

        return id;
    }
}
