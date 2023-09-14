// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../lib/Math.sol";
import "../lib/Auth.sol";
import "../lib/Pause.sol";
import "../lib/AccountApprovals.sol";

contract Vat is Auth, Pause, AccountApprovals {
    // Ilk
    struct CollateralType {
        // Art - Total debt issued for this collateral
        uint256 debt; // wad
        // rate - Accumulated rates
        uint256 rate; // ray
        // spot - Price with safety margin
        uint256 spot; // ray
        // line - Debt ceiling
        uint256 ceiling; // rad
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

    // ilks
    mapping(bytes32 => CollateralType) public cols;
    // urns - collateral type => account => Vault
    mapping(bytes32 => mapping(address => Vault)) public vaults;
    // collateral type => account => balance (wad)
    mapping(bytes32 => mapping(address => uint256)) public gem;
    // account => dai balance (rad)
    mapping(address => uint256) public dai;
    // sin - account => debt balance (rad)
    mapping(address => uint256) public debts;

    // Total DAI issued (rad)
    uint256 public globalDebt;
    // Total Unbacked Dai (rad)
    uint256 public globalUnbackedDebt;
    // Total Debt Ceiling (rad)
    uint256 public globalDebtCeiling;

    constructor() {
        live = true;
    }

    // --- Administration ---
    function init(bytes32 colType) external auth {
        require(cols[colType].rate == 0, "already init");
        cols[colType].rate = RAY;
    }

    // file
    function set(bytes32 name, uint256 data) external auth notStopped {
        if (name == "globalDebtCeiling") {
            globalDebtCeiling = data;
        } else {
            revert("unrecognized param");
        }
    }

    function set(bytes32 colType, bytes32 name, uint256 data)
        external
        auth
        notStopped
    {
        if (name == "spot") {
            cols[colType].spot = data;
        } else if (name == "ceiling") {
            cols[colType].ceiling = data;
        } else if (name == "floor") {
            cols[colType].floor = data;
        } else {
            revert("unrecognized param");
        }
    }

    // cage
    function stop() external auth {
        _stop();
    }

    // --- Fungibility ---
    // slip
    function modifyCollateralBalance(bytes32 colType, address user, int256 wad)
        external
    {
        gem[colType][user] = Math.add(gem[colType][user], wad);
    }

    // flux
    function transferCollateral(
        bytes32 colType,
        address src,
        address dst,
        uint256 wad
    ) external {
        require(canModifyAccount(src, msg.sender), "not authorized");
        gem[colType][src] -= wad;
        gem[colType][dst] += wad;
    }

    // move
    function transferDai(address src, address dst, uint256 rad) external {
        require(canModifyAccount(src, msg.sender), "not authorized");
        dai[src] -= rad;
        dai[dst] += rad;
    }
    // --- CDP Manipulation ---
    // --- CDP Fungibility ---
    // --- Settlement ---
    // --- Rates ---

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
        CollateralType memory col = cols[colType];
        require(col.rate != 0, "collateral not initialized");

        vault.collateral = Math.add(vault.collateral, deltaCol);
        vault.debt = Math.add(vault.debt, deltaDebt);
        col.debt = Math.add(col.debt, deltaDebt);

        int256 dRate = Math.mul(col.rate, deltaDebt);
        uint256 vaultDebt = col.rate * vault.debt;
        // TODO: why?
        globalDebt = Math.add(globalDebt, dRate);

        // int dtab = _mul(ilk.rate, dart);
        // uint tab = _mul(ilk.rate, urn.art);
        // debt     = _add(debt, dtab);

        gem[colType][src] = Math.sub(gem[colType][src], deltaCol);
        dai[dst] = Math.add(dai[dst], dRate);

        vaults[colType][vaultAddr] = vault;
        cols[colType] = col;
    }
}
