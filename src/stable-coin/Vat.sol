// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IVat} from "../interfaces/IVat.sol";
import "../lib/Math.sol";
import "../lib/Auth.sol";
import "../lib/Pause.sol";
import "../lib/AccountAuth.sol";

/*
dink: change in collateral.
dart: change in debt.
*/

// CDP Engine
contract Vat is Auth, Pause, AccountAuth {
    // ilks
    mapping(bytes32 => IVat.CollateralType) public cols;
    // urns - collateral type => account => safe
    mapping(bytes32 => mapping(address => IVat.Safe)) public safes;
    // collateral type => account => balance (wad)
    mapping(bytes32 => mapping(address => uint256)) public gem;
    // account => coin balance (rad)
    mapping(address => uint256) public coin;
    // sin - account => debt balance (rad)
    mapping(address => uint256) public debts;

    // debt- Total coin issued (rad)
    uint256 public global_debt;
    // vice -Total unbacked coin (rad)
    uint256 public global_unbacked_debt;
    // Line - Total debt ceiling (rad)
    uint256 public global_debt_ceiling;

    // --- Administration ---
    function init(bytes32 col_type) external auth {
        require(cols[col_type].rate == 0, "already init");
        cols[col_type].rate = RAY;
    }

    // file
    function set(bytes32 key, uint256 val) external auth notStopped {
        if (key == "global_debt_ceiling") {
            global_debt_ceiling = val;
        } else {
            revert("unrecognized param");
        }
    }

    function set(bytes32 col_type, bytes32 key, uint256 val)
        external
        auth
        notStopped
    {
        if (key == "spot") {
            cols[col_type].spot = val;
        } else if (key == "ceiling") {
            cols[col_type].ceiling = val;
        } else if (key == "floor") {
            cols[col_type].floor = val;
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
    function modify_collateral_balance(
        bytes32 col_type,
        address user,
        int256 wad
    ) external auth {
        gem[col_type][user] = Math.add(gem[col_type][user], wad);
    }

    // flux: transfer collateral between users.
    function transfer_collateral(
        bytes32 col_type,
        address src,
        address dst,
        uint256 wad
    ) external {
        require(can_modify_account(src, msg.sender), "not authorized");
        gem[col_type][src] -= wad;
        gem[col_type][dst] += wad;
    }

    // move: transfer stablecoin between users.
    function transfer_coin(address src, address dst, uint256 rad) external {
        require(can_modify_account(src, msg.sender), "not authorized");
        coin[src] -= rad;
        coin[dst] += rad;
    }

    // --- CDP Manipulation ---
    // frob: modify a safe.
    //     lock: transfer collateral into a safe.
    //     free: transfer collateral from a safe.
    //     draw: increase safe debt, creating coin.
    //     wipe: decrease safe debt, destroying coin.
    // frob(i, u, v, w, dink, dart) - modify a safe
    // - modify the safe of user u
    // - using gem from user v
    // - and creating coin for user w
    // dink: change in collateral.
    // dart: change in debt.
    function modify_safe(
        bytes32 col_type,
        address safe_addr,
        address col_src,
        address debt_dst,
        int256 delta_col,
        int256 delta_debt
    ) external notStopped {
        IVat.Safe memory safe = safes[col_type][safe_addr];
        IVat.CollateralType memory col = cols[col_type];
        require(col.rate != 0, "collateral not init");

        safe.collateral = Math.add(safe.collateral, delta_col);
        safe.debt = Math.add(safe.debt, delta_debt);
        col.debt = Math.add(col.debt, delta_debt);

        // delta_debt = delta coin / col.rate
        // delta coin = col.rate * delta_debt
        int256 delta_coin = Math.mul(col.rate, delta_debt);
        // total coin + compound interest that the safe owes to protocol
        uint256 total_coin = col.rate * safe.debt;
        global_debt = Math.add(global_debt, delta_coin);

        // either debt has decreased, or debt ceilings are not exceeded
        require(
            delta_debt <= 0
                || (
                    col.debt * col.rate <= col.ceiling
                        && global_debt <= global_debt_ceiling
                ),
            "ceiling exceeded"
        );
        // safe is either less risky than before, or it is safe
        require(
            (delta_debt <= 0 && delta_col >= 0)
                || total_coin <= safe.collateral * col.spot,
            "not safe"
        );

        // safe is either more safe, or the owner consents
        require(
            (delta_debt <= 0 && delta_col >= 0)
                || can_modify_account(safe_addr, msg.sender),
            "not allowed safe addr"
        );
        // collateral src consents
        require(
            delta_col <= 0 || can_modify_account(col_src, msg.sender),
            "not allowed collateral src"
        );
        // debt dst consents
        require(
            delta_debt >= 0 || can_modify_account(debt_dst, msg.sender),
            "not allowed debt dst"
        );

        // safe has no debt, or a non-dusty amount
        require(safe.debt == 0 || total_coin >= col.floor, "Vat/dust");

        gem[col_type][col_src] = Math.sub(gem[col_type][col_src], delta_col);
        coin[debt_dst] = Math.add(coin[debt_dst], delta_coin);

        safes[col_type][safe_addr] = safe;
        cols[col_type] = col;
    }

    // --- CDP Fungibility ---
    // fork: to split a safe - binary approval or splitting/merging safes.
    //    dink: amount of collateral to exchange.
    //    dart: amount of stablecoin debt to exchange.
    function fork(
        bytes32 col_type,
        address src,
        address dst,
        int256 delta_col,
        int256 delta_debt
    ) external {
        IVat.Safe storage u = safes[col_type][src];
        IVat.Safe storage v = safes[col_type][dst];
        IVat.CollateralType storage col = cols[col_type];

        u.collateral = Math.sub(u.collateral, delta_col);
        u.debt = Math.sub(u.debt, delta_debt);
        v.collateral = Math.add(v.collateral, delta_col);
        v.debt = Math.add(v.debt, delta_debt);

        uint256 u_total_coin = u.debt * col.rate;
        uint256 v_total_coin = v.debt * col.rate;

        // both sides consent
        require(
            can_modify_account(src, msg.sender)
                && can_modify_account(dst, msg.sender),
            "not allowed"
        );

        // both sides safe
        require(u_total_coin <= u.collateral * col.spot, "not safe src");
        require(v_total_coin <= v.collateral * col.spot, "not safe dst");

        // both sides non-dusty
        require(u_total_coin >= col.floor || u.debt == 0, "dust src");
        require(v_total_coin >= col.floor || v.debt == 0, "dust dst");
    }

    // --- CDP Confiscation ---
    // grab: liquidate a safe.
    // grab(i, u, v, w, dink, dart)
    // - modify the safe of user u
    // - give gem to user v
    // - create sin for user w
    // grab is the means by which safes are liquidated,
    // transferring debt from the safe to a users sin balance.
    function grab(
        bytes32 col_type,
        address src,
        address col_dst,
        address debt_dst,
        int256 delta_col,
        int256 delta_debt
    ) external auth {
        IVat.Safe storage safe = safes[col_type][src];
        IVat.CollateralType storage col = cols[col_type];

        safe.collateral = Math.add(safe.collateral, delta_col);
        safe.debt = Math.add(safe.debt, delta_debt);
        col.debt = Math.add(col.debt, delta_debt);

        int256 delta_coin = Math.mul(col.rate, delta_debt);

        gem[col_type][col_dst] = Math.sub(gem[col_type][col_dst], delta_col);
        debts[debt_dst] = Math.sub(debts[debt_dst], delta_coin);
        global_unbacked_debt = Math.sub(global_unbacked_debt, delta_coin);
    }

    // --- Settlement ---
    // heal: create / destroy equal quantities of stablecoin and system debt (vice).
    function burn(uint256 rad) external {
        debts[msg.sender] -= rad;
        coin[msg.sender] -= rad;
        global_unbacked_debt -= rad;
        global_debt -= rad;
    }

    // suck: mint unbacked stablecoin (accounted for with vice).
    function mint(address debt_dst, address coin_dst, uint256 rad)
        external
        auth
    {
        debts[debt_dst] += rad;
        coin[coin_dst] += rad;
        global_unbacked_debt += rad;
        global_debt += rad;
    }

    // --- Rates ---
    // fold: modify the debt multiplier, creating / destroying corresponding debt.
    function update_rate(bytes32 col_type, address coin_dst, int256 delta_rate)
        external
        auth
        notStopped
    {
        IVat.CollateralType storage col = cols[col_type];
        // old total debt = col.debt * col.rate
        // new total debt = col.debt * (col.rate + delta_rate)
        col.rate = Math.add(col.rate, delta_rate);
        int256 delta_debt = Math.mul(col.debt, delta_rate);
        coin[coin_dst] = Math.add(coin[coin_dst], delta_debt);
        global_debt = Math.add(global_debt, delta_debt);
    }
}
