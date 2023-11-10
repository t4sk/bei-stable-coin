// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

contract Proxy {
    address public owner;

    event SetOwner(address indexed owner);

    modifier auth() {
        require(msg.sender == owner, "not authorized");
        _;
    }

    constructor(address _owner) {
        owner = _owner;
        emit SetOwner(_owner);
    }

    receive() external payable {}

    function set_owner(address _owner) external auth {
        owner = _owner;
        emit SetOwner(_owner);
    }

    function execute(address target, bytes calldata data)
        external
        payable
        auth
        returns (bytes memory res)
    {
        bool ok;
        (ok, res) = target.delegatecall(data);
        require(ok, "execute failed");
    }
}
