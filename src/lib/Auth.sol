// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.24;

contract Auth {
    event GrantAuthorization(address indexed user);
    event DenyAuthorization(address indexed user);

    // wards
    mapping(address => bool) public authorized;

    modifier auth() {
        require(authorized[msg.sender], "not authorized");
        _;
    }

    constructor() {
        authorized[msg.sender] = true;
        emit GrantAuthorization(msg.sender);
    }

    // rely
    function grant_auth(address user) external auth {
        authorized[user] = true;
        emit GrantAuthorization(user);
    }

    // deny
    function deny_auth(address user) external auth {
        authorized[user] = false;
        emit DenyAuthorization(user);
    }
}
