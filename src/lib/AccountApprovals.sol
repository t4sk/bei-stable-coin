// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

contract AccountApprovals {
    // can
    // account => caller => can modify account
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
    function can_modify_account(address account, address user)
        internal
        view
        returns (bool)
    {
        return account == user || can[account][user];
    }
}
