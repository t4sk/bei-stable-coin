// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IVat {
    // Ilk: a collateral type.
    struct CollateralType {
        // Art: total normalized stablecoin debt.
        uint256 debt; // wad
        // rate: stablecoin debt multiplier (accumulated stability fees).
        uint256 rate; // ray
        // spot: collateral price with safety margin, i.e. the maximum stablecoin allowed per unit of collateral.
        uint256 spot; // ray
        // line: the debt ceiling for a specific collateral type.
        // TODO: rename to debt_ceiling?
        uint256 ceiling; // rad
        // dust: the debt floor for a specific collateral type.
        // TODO: rename to min_debt?
        uint256 floor; // rad
    }

    // Urn: a specific Vault.
    struct Vault {
        // ink: collateral balance.
        uint256 collateral; // wad
        // art: normalized outstanding stablecoin debt.
        uint256 debt; // wad
    }

    function dai(address vault) external view returns (uint256);
    function debts(address account) external view returns (uint256);
    function vaults(bytes32 colType, address vault)
        external
        view
        returns (Vault memory);
    // ilks
    function cols(bytes32 colType)
        external
        view
        returns (CollateralType memory);
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
    // flux
    function transferCollateral(
        bytes32 colType,
        address src,
        address dst,
        uint256 wad
    ) external;
    // move
    function transferDai(address src, address dst, uint256 rad) external;
    // fold
    // TODO: what is vow?, rate?
    function updateRate(bytes32 collateralType, address vow, int256 rate)
        external;

    // file
    function modifyParam(bytes32, bytes32, uint256) external;

    // hope
    function approveAccountModification(address user) external;
    // nope
    function denyAccountModification(address user) external;
    function settle(uint256 rad) external;
    function grab(
        bytes32 colType,
        address src,
        address dst,
        address debtDst,
        int256 deltaCol,
        int256 deltaDebt
    ) external;
}
