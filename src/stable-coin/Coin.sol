// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import {Auth} from "../lib/Auth.sol";

contract Coin is Auth {
    event Approval(address indexed src, address indexed spender, uint256 wad);
    event Transfer(address indexed src, address indexed dst, uint256 wad);

    string public constant name = "Stable coin";
    string public constant symbol = "COIN";
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function transfer(address dst, uint256 wad) external returns (bool) {
        return transferFrom(msg.sender, dst, wad);
    }

    function transferFrom(address src, address dst, uint256 wad)
        public
        returns (bool)
    {
        if (
            src != msg.sender && allowance[src][msg.sender] != type(uint256).max
        ) {
            allowance[src][msg.sender] -= wad;
        }

        balanceOf[src] -= wad;
        balanceOf[dst] += wad;

        emit Transfer(src, dst, wad);
        return true;
    }

    function mint(address user, uint256 wad) external auth {
        balanceOf[user] += wad;
        totalSupply += wad;
        emit Transfer(address(0), user, wad);
    }

    function burn(address user, uint256 wad) external {
        if (
            user != msg.sender
                && allowance[user][msg.sender] != type(uint256).max
        ) {
            allowance[user][msg.sender] -= wad;
        }

        balanceOf[user] -= wad;
        totalSupply -= wad;

        emit Transfer(user, address(0), wad);
    }

    function approve(address user, uint256 wad) external returns (bool) {
        allowance[msg.sender][user] = wad;
        emit Approval(msg.sender, user, wad);
        return true;
    }

    function push(address usr, uint256 amount) external {
        transferFrom(msg.sender, usr, amount);
    }

    function pull(address usr, uint256 amount) external {
        transferFrom(usr, msg.sender, amount);
    }

    function move(address src, address dst, uint256 amount) external {
        transferFrom(src, dst, amount);
    }
}
