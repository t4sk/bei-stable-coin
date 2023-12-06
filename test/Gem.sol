// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

contract Gem {
    event Approval(address indexed src, address indexed spender, uint256 wad);
    event Transfer(address indexed src, address indexed dst, uint256 wad);

    string public name;
    string public symbol;
    uint8 public immutable decimals;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _sym, uint8 _dec) {
        name = _name;
        symbol = _sym;
        decimals = _dec;
    }

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

    function mint(address dst, uint256 wad) external {
        balanceOf[dst] += wad;
        totalSupply += wad;
        emit Transfer(address(0), dst, wad);
    }

    function burn(address src, uint256 wad) external {
        if (
            src != msg.sender && allowance[src][msg.sender] != type(uint256).max
        ) {
            allowance[src][msg.sender] -= wad;
        }

        balanceOf[src] -= wad;
        totalSupply -= wad;

        emit Transfer(src, address(0), wad);
    }

    function approve(address spender, uint256 wad) external returns (bool) {
        allowance[msg.sender][spender] = wad;
        emit Approval(msg.sender, spender, wad);
        return true;
    }

    function push(address dst, uint256 wad) external {
        transferFrom(msg.sender, dst, wad);
    }

    function pull(address src, uint256 wad) external {
        transferFrom(src, msg.sender, wad);
    }

    function move(address src, address dst, uint256 wad) external {
        transferFrom(src, dst, wad);
    }
}
