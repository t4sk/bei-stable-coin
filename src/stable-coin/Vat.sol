// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../lib/Math.sol";
import "../lib/Auth.sol";
import "../lib/Pause.sol";
import "../lib/AccountApprovals.sol";

contract Vat is Auth, Pause, AccountApprovals {
    // Ilk
    struct CollateralType {
        // Art: total normalized stablecoin debt.
        uint256 debt; // wad
        // rate: stablecoin debt multiplier (accumulated stability fees).
        uint256 rate; // ray
        // spot: collateral price with safety margin, i.e. the maximum stablecoin allowed per unit of collateral.
        uint256 spot; // ray
        // line: the debt ceiling for a specific collateral type.
        uint256 ceiling; // rad
        // dust: the debt floor for a specific collateral type.
        uint256 floor; // rad
    }

    // Urn
    struct Vault {
        // ink: collateral balance.
        uint256 collateral; // wad
        // art: normalized outstanding stablecoin debt.
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

    // debt- Total DAI issued (rad)
    uint256 public globalDebt;
    // vice -Total Unbacked Dai (rad)
    uint256 public globalUnbackedDebt;
    // line - Total Debt Ceiling (rad)
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
    // slip: modify a user's collateral balance.
    function modifyCollateralBalance(bytes32 colType, address user, int256 wad)
        external
        auth
    {
        gem[colType][user] = Math.add(gem[colType][user], wad);
    }

    // flux: transfer collateral between users.
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

    // move: transfer stablecoin between users.
    function transferDai(address src, address dst, uint256 rad) external {
        require(canModifyAccount(src, msg.sender), "not authorized");
        dai[src] -= rad;
        dai[dst] += rad;
    }

    // --- CDP Manipulation ---
    // frob: modify a Vault.
    //     lock: transfer collateral into a Vault.
    //     free: transfer collateral from a Vault.
    //     draw: increase Vault debt, creating Dai.
    //     wipe: decrease Vault debt, destroying Dai.
    //     dink: change in collateral.
    //     dart: change in debt.
    function modifyVault(
        bytes32 colType,
        address vaultAddr,
        address src,
        address dst,
        int256 deltaCol,
        int256 deltaDebt
    ) external notStopped {
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

    // --- CDP Fungibility ---
    //fork: to split a Vault - binary approval or splitting/merging Vaults.
    //    dink: amount of collateral to exchange.
    //    dart: amount of stablecoin debt to exchange.
    // --- CDP Confiscation ---
    // grab: liquidate a Vault.

    // --- Settlement ---
    // heal: create / destroy equal quantities of stablecoin and system debt (vice).
    function settle(uint256 rad) external {
        address account = msg.sender;
        debts[account] = debts[account] - rad;
        dai[account] = dai[account] - rad;
        globalUnbackedDebt = globalUnbackedDebt - rad;
        globalDebt = globalDebt - rad;
    }

    // suck: mint unbacked stablecoin (accounted for with vice).
    function mint(address debtDst, address coinDst, uint256 rad)
        external
        auth
    {
        debts[debtDst] = debts[debtDst] + rad;
        dai[coinDst] = dai[coinDst] + rad;
        globalUnbackedDebt = globalUnbackedDebt + rad;
        globalDebt = globalDebt + rad;
    }

    // --- Rates ---
    // fold: modify the debt multiplier, creating / destroying corresponding debt.
    function updateRate(bytes32 colType, address dst, int256 rate)
        external
        auth
        notStopped
    {
        CollateralType storage col = cols[colType];
        col.rate = Math.add(col.rate, rate);
        int256 delta = Math.mul(col.debt, rate);
        dai[dst] = Math.add(dai[dst], delta);
        globalDebt = Math.add(globalDebt, delta);
    }
}
