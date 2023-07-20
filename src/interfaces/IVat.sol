// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IVat {
    // can
    function isAuthorized(address owner, address user)
        external
        view
        returns (bool);
    // hope
    function addAuthorization(address user) external;
    // nope
    function removeAuthorization(address user) external;

    // TODO: rename
    // modify a user's collateral balance
    function slip(bytes32, address, int256) external;
    // TODO: rename
    // transfer stablecoin between users
    function move(address, address, uint256) external;
}
