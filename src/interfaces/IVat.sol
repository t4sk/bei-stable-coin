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
}
