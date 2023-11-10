// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

contract Account {
    // can
    // owner => user => can modify account
    mapping(address => mapping(address => bool)) public can;

    // hope
    function allow_account_modification(address user) external {
        can[msg.sender][user] = true;
    }

    // nope
    function deny_account_modification(address user) external {
        can[msg.sender][user] = false;
    }

    // wish
    function can_modify_account(address owner, address user) public view returns (bool) {
        return owner == user || can[owner][user];
    }
}
