// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IVat} from "../interfaces/IVat.sol";
import "../lib/Math.sol";
import "../lib/Auth.sol";
import "../lib/Pause.sol";
import "../lib/AccountApprovals.sol";

/*
dink: change in collateral.
dart: change in debt.
*/

// CDP Engine
contract Vat is Auth, Pause, AccountApprovals {
    // ilks
    mapping(bytes32 => IVat.CollateralType) public cols;
    // urns - collateral type => account => Vault
    mapping(bytes32 => mapping(address => IVat.Vault)) public vaults;
    // collateral type => account => balance (wad)
    mapping(bytes32 => mapping(address => uint256)) public gem;
    // account => dai balance (rad)
    mapping(address => uint256) public dai;
    // sin - account => debt balance (rad)
    mapping(address => uint256) public debts;

    // debt- Total DAI issued (rad)
    uint256 public globalDebt;
    // vice -Total unbacked Dai (rad)
    uint256 public globalUnbackedDebt;
    // Line - Total debt ceiling (rad)
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

    // TODO: - study how proxy action calls frob
    // --- CDP Manipulation ---
    // frob: modify a Vault.
    //     lock: transfer collateral into a Vault.
    //     free: transfer collateral from a Vault.
    //     draw: increase Vault debt, creating Dai.
    //     wipe: decrease Vault debt, destroying Dai.
    // frob(i, u, v, w, dink, dart) - modify a Vault
    // - modify the Vault of user u
    // - using gem from user v
    // - and creating dai for user w
    // dink: change in collateral.
    // dart: change in debt.
    function modifyVault(
        bytes32 colType,
        address vaultAddr,
        address colSrc,
        address debtDst,
        int256 deltaCol,
        int256 deltaDebt
    ) external notStopped {
        IVat.Vault memory vault = vaults[colType][vaultAddr];
        IVat.CollateralType memory col = cols[colType];
        require(col.rate != 0, "collateral not init");

        vault.collateral = Math.add(vault.collateral, deltaCol);
        vault.debt = Math.add(vault.debt, deltaDebt);
        col.debt = Math.add(col.debt, deltaDebt);

        // deltaDebt = delta dai / col.rate
        // delta dai = col.rate * deltaDebt
        int256 deltaDai = Math.mul(col.rate, deltaDebt);
        // total dai + compound interest that the vault owes to protocol
        uint256 totalDai = col.rate * vault.debt;
        globalDebt = Math.add(globalDebt, deltaDai);

        // either debt has decreased, or debt ceilings are not exceeded
        require(
            deltaDebt <= 0
                || (
                    col.debt * col.rate <= col.ceiling
                        && globalDebt <= globalDebtCeiling
                ),
            "ceiling exceeded"
        );
        // vault is either less risky than before, or it is safe
        require(
            (deltaDebt <= 0 && deltaCol >= 0)
                || totalDai <= vault.collateral * col.spot,
            "not safe"
        );

        // vault is either more safe, or the owner consents
        require(
            (deltaDebt <= 0 && deltaCol >= 0)
                || canModifyAccount(vaultAddr, msg.sender),
            "not allowed vault addr"
        );
        // collateral src consents
        require(
            deltaCol <= 0 || canModifyAccount(colSrc, msg.sender),
            "not allowed collateral src"
        );
        // debt dst consents
        require(
            deltaDebt >= 0 || canModifyAccount(debtDst, msg.sender),
            "not allowed debt dst"
        );

        // vault has no debt, or a non-dusty amount
        require(vault.debt == 0 || totalDai >= col.floor, "Vat/dust");

        gem[colType][colSrc] = Math.sub(gem[colType][colSrc], deltaCol);
        dai[debtDst] = Math.add(dai[debtDst], deltaDai);

        vaults[colType][vaultAddr] = vault;
        cols[colType] = col;
    }

    // --- CDP Fungibility ---
    // fork: to split a Vault - binary approval or splitting/merging Vaults.
    //    dink: amount of collateral to exchange.
    //    dart: amount of stablecoin debt to exchange.
    function fork(
        bytes32 colType,
        address src,
        address dst,
        int256 deltaCol,
        int256 deltaDebt
    ) external {
        IVat.Vault storage u = vaults[colType][src];
        IVat.Vault storage v = vaults[colType][dst];
        IVat.CollateralType storage col = cols[colType];

        u.collateral = Math.sub(u.collateral, deltaCol);
        u.debt = Math.sub(u.debt, deltaDebt);
        v.collateral = Math.add(v.collateral, deltaCol);
        v.debt = Math.add(v.debt, deltaDebt);

        uint256 uTotalDai = u.debt * col.rate;
        uint256 vTotalDai = v.debt * col.rate;

        // both sides consent
        require(
            canModifyAccount(src, msg.sender)
                && canModifyAccount(dst, msg.sender),
            "not allowed"
        );

        // both sides safe
        require(uTotalDai <= u.collateral * col.spot, "not safe src");
        require(vTotalDai <= v.collateral * col.spot, "not safe dst");

        // both sides non-dusty
        require(uTotalDai >= col.floor || u.debt == 0, "dust src");
        require(vTotalDai >= col.floor || v.debt == 0, "dust dst");
    }

    // --- CDP Confiscation ---
    // grab: liquidate a Vault.
    // grab(i, u, v, w, dink, dart)
    // - modify the Vault of user u
    // - give gem to user v
    // - create sin for user w
    // grab is the means by which Vaults are liquidated,
    // transferring debt from the Vault to a users sin balance.
    function grab(
        bytes32 colType,
        address src,
        address colDst,
        address debtDst,
        int256 deltaCol,
        int256 deltaDebt
    ) external auth {
        IVat.Vault storage vault = vaults[colType][src];
        IVat.CollateralType storage col = cols[colType];

        vault.collateral = Math.add(vault.collateral, deltaCol);
        vault.debt = Math.add(vault.debt, deltaDebt);
        col.debt = Math.add(col.debt, deltaDebt);

        int256 deltaDai = Math.mul(col.rate, deltaDebt);

        gem[colType][colDst] = Math.sub(gem[colType][colDst], deltaCol);
        debts[debtDst] = Math.sub(debts[debtDst], deltaDai);
        globalUnbackedDebt = Math.sub(globalUnbackedDebt, deltaDai);
    }

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
    function updateRate(bytes32 colType, address dst, int256 deltaRate)
        external
        auth
        notStopped
    {
        IVat.CollateralType storage col = cols[colType];
        col.rate = Math.add(col.rate, deltaRate);
        // old total debe = col.debt * col.rate
        // new total debt = col.debt * (col.rate + deltaRate)
        int256 deltaDebt = Math.mul(col.debt, deltaRate);
        dai[dst] = Math.add(dai[dst], deltaDebt);
        globalDebt = Math.add(globalDebt, deltaDebt);
    }
}
