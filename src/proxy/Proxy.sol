// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IAuthority {
    function canCall(address src, address dst, bytes4 sig)
        external
        view
        returns (bool);
}

contract Proxy {
    address public owner;
    address public authority;

    event SetOwner(address indexed owner);
    event SetAuthority(address indexed authority);

    constructor(address owner_) {
        owner = owner_;
        emit SetOwner(owner_);
    }

    receive() external payable {}

    modifier auth() {
        require(
            msg.sender == owner
                || authority != address(0)
                    && IAuthority(authority).canCall(msg.sender, address(this), msg.sig),
            "not authorized"
        );
        _;
    }

    function setOwner(address owner_) external auth {
        owner = owner_;
        emit SetOwner(owner_);
    }

    function setAuthority(address authority_) external auth {
        authority = authority_;
        emit SetAuthority(authority_);
    }

    function execute(address target, bytes calldata data)
        external
        payable
        auth
        returns (bytes memory res)
    {
        require(target != address(0), "target = 0 address");
        bool ok;
        (ok, res) = target.delegatecall(data);
        require(ok, "execute failed");
    }
}
