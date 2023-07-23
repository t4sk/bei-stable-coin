// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../lib/Math.sol";

contract Vat {
    event AddAuthorization(address indexed user);
    event RemoveAuthorization(address indexed user);
    event Stop();

    // wards
    mapping(address => bool) public authorized;
    bool public live;
    // collateral type => account => balance (wad)
    mapping(bytes32 => mapping(address => uint256)) public gem;
    // account => dai balance (rad)
    mapping(address => uint256) public dai;

    // account => caller => can modify account
    mapping(address => mapping(address => bool)) public can;

    modifier auth() {
        require(authorized[msg.sender], "not authorized");
        _;
    }

    constructor() {
        authorized[msg.sender] = true;
        live = true;
    }

    // rely
    function addAuthorization(address user) external auth {
        authorized[user] = true;
        emit AddAuthorization(user);
    }

    // deny
    function remoteAuthorization(address user) external auth {
        authorized[user] = false;
        emit RemoveAuthorization(user);
    }

    // cage
    function stop() external auth {
        live = false;
        emit Stop();
    }

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

    // slip
    function modifyCollateralBalance(
        bytes32 collateralType,
        address user,
        int256 wad
    ) external {
        gem[collateralType][user] = Math.add(gem[collateralType][user], wad);
    }

    // move
    function transferInternalCoins(address src, address dst, uint256 rad)
        external
    {
        require(canModifyAccount(src, msg.sender), "not authorized");
        dai[src] -= rad;
        dai[dst] += rad;
    }
}
