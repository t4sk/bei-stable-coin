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
    // slip
    function modifyCollateralBalance(
        bytes32 collateralType,
        address user,
        int256 wad
    ) external;
    // move - transfer stable coins
    function transferInternalCoins(address src, address dst, uint256 rad)
        external;
}
