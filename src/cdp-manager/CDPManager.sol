// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./SafeHandler.sol";

contract CDPManager {
    address public immutable cdp_engine;
    uint256 public cdp_id;

    struct List {
        uint256 prev;
        uint256 next;
    }

    // CDP id => safe handler
    mapping(uint256 => address) public safes;
    // CDP id => owner
    mapping(uint256 => address) public owners;
    // CDP id => collateral type
    mapping(uint256 => bytes32) public cols;

    // CDP id => List
    mapping(uint256 => List) public list;
    // Owner => first CDP id
    mapping(address => uint256) public first;
    // Owner => last CDP id
    mapping(address => uint256) public last;
    // Owner => CDP count
    mapping(address => uint256) public count;

    constructor(address _cdp_engine) {
        cdp_engine = _cdp_engine;
    }

    function open(bytes32 col_type, address user) public returns (uint256) {
        require(user != address(0), "user = 0 address");

        uint256 id = cdp_id + 1;
        cdp_id = id;

        safes[id] = address(new SafeHandler(cdp_engine));
        owners[id] = user;
        cols[id] = col_type;

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
