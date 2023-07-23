// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

contract Dai {
    event AddAuthorization(address indexed user);
    event RemoveAuthorization(address indexed user);
    event Approval(address indexed src, address indexed spender, uint256 wad);
    event Transfer(address indexed src, address indexed dst, uint256 wad);

    // wards
    mapping(address => bool) public authorized;

    string public constant name = "DAI stablecoin";
    string public constant symbol = "DAI";
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    modifier auth() {
        require(authorized[msg.sender], "not authorized");
        _;
    }

    constructor() {
        authorized[msg.sender] = true;
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

    // Alias
    function push(address user, uint256 wad) external {
        transferFrom(msg.sender, user, wad);
    }

    function pull(address user, uint256 wad) external {
        transferFrom(user, msg.sender, wad);
    }

    function move(address src, address dst, uint256 wad) external {
        transferFrom(src, dst, wad);
    }
}
