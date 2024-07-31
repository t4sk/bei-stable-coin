// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.24;

contract Auth {
    event AddAuthorization(address indexed user);
    event RemoveAuthorization(address indexed user);

    // wards
    mapping(address => bool) public authorized;

    modifier auth() {
        require(authorized[msg.sender], "not authorized");
        _;
    }

    constructor() {
        authorized[msg.sender] = true;
        emit AddAuthorization(msg.sender);
    }

    // rely
    function add_auth(address user) external auth {
        authorized[user] = true;
        emit AddAuthorization(user);
    }

    // deny
    function remove_auth(address user) external auth {
        authorized[user] = false;
        emit RemoveAuthorization(user);
    }
}
