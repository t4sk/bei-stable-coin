// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

contract AccountApprovals {
    // can
    // account => caller => can modify account
    mapping(address => mapping(address => bool)) public can;

    // hope
    function approveAccountModification(address user) external {
        can[msg.sender][user] = true;
    }

    // nope
    function denyAccountModification(address user) external {
        can[msg.sender][user] = false;
    }

    // wish
    function canModifyAccount(address account, address user)
        internal
        view
        returns (bool)
    {
        return account == user || can[account][user];
    }
}
