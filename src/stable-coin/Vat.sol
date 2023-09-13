// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../lib/Math.sol";
import "../lib/Auth.sol";
import "../lib/Stop.sol";

contract Vat is Auth, Stop {
    // Ilk
    struct CollateralType {
        // Art - Total debt issued for this collateral
        uint256 debt; // wad
        // rate - Accumulated rates
        uint256 rate; // ray
        // spot - Price with safety margin
        uint256 spot; // ray
        // line - Debt ceiling
        uint256 ceil; // rad
        // dust - Debt floor
        uint256 floor; // rad
    }
    // Urn
    struct Vault {
        // ink
        uint256 collateral; // wad
        // art
        uint256 debt; // wad
    }

    // account => caller => can modify account
    mapping(address => mapping(address => bool)) public can;

    // ilks
    mapping(bytes32 => CollateralType) public colTypes;
    // urns - collateral type => account => Vault
    mapping(bytes32 => mapping(address => Vault)) public vaults;
    // collateral type => account => balance (wad)
    mapping(bytes32 => mapping(address => uint256)) public gem;
    // account => dai balance (rad)
    mapping(address => uint256) public dai;
    // sin - account => debt balance (rad)
    mapping(address => uint256) public debts;


    // Total DAI issued
    uint256 public debt;

    constructor() {
        live = true;
    }

    // cage
    function stop() external auth {
        _stop();
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

    // frob
    function modifyVault(
        bytes32 colType,
        address vaultAddr,
        address src,
        address dst,
        int256 deltaCol,
        int256 deltaDebt
    ) external {
        require(live, "not live");

        Vault memory vault = vaults[colType][vaultAddr];
        CollateralType memory col = colTypes[colType];
        require(col.rate != 0, "collateral not initialized");

        vault.collateral = Math.add(vault.collateral, deltaCol);
        vault.debt = Math.add(vault.debt, deltaDebt);
        col.debt = Math.add(col.debt, deltaDebt);

        int256 dRate = Math.mul(col.rate, deltaDebt);
        uint256 vaultDebt = col.rate * vault.debt;
        // TODO: why?
        debt = Math.add(debt, dRate);

        // int dtab = _mul(ilk.rate, dart);
        // uint tab = _mul(ilk.rate, urn.art);
        // debt     = _add(debt, dtab);

        gem[colType][src] = Math.sub(gem[colType][src], deltaCol);
        dai[dst] = Math.add(dai[dst], dRate);

        vaults[colType][vaultAddr] = vault;
        colTypes[colType] = col;
    }
}
