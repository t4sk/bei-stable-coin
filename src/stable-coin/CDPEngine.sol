// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import {ICDPEngine} from "../interfaces/ICDPEngine.sol";
import "../lib/Math.sol";
import {Auth} from "../lib/Auth.sol";
import {CircuitBreaker} from "../lib/CircuitBreaker.sol";
import {AccessControl} from "../lib/AccessControl.sol";

// Vat - CDP Engine
contract CDPEngine is Auth, CircuitBreaker, AccessControl {
    // ilks
    mapping(bytes32 => ICDPEngine.Collateral) public collaterals;
    // TODO: rename safe to CDP?
    // urns - collateral type => account => safe
    mapping(bytes32 => mapping(address => ICDPEngine.Position)) public safes;
    // gem - collateral type => account => balance [wad]
    mapping(bytes32 => mapping(address => uint256)) public gem;
    // dai - account => coin balance [rad]
    mapping(address => uint256) public coin;
    // sin - account => debt balance [rad]
    mapping(address => uint256) public debts;

    // debt - total coin issued [rad]
    uint256 public sys_debt;
    // vice - total unbacked coin [rad]
    uint256 public sys_unbacked_debt;
    // Line - total debt ceiling [rad]
    uint256 public sys_max_debt;

    // --- Administration ---
    function init(bytes32 col_type) external auth {
        require(collaterals[col_type].rate == 0, "already initialized");
        collaterals[col_type].rate = RAY;
    }

    // file
    function set(bytes32 key, uint256 val) external auth live {
        if (key == "sys_max_debt") {
            sys_max_debt = val;
        } else {
            revert("invalid param");
        }
    }

    function set(bytes32 col_type, bytes32 key, uint256 val)
        external
        auth
        live
    {
        if (key == "spot") {
            collaterals[col_type].spot = val;
        } else if (key == "max_debt") {
            collaterals[col_type].max_debt = val;
        } else if (key == "min_debt") {
            collaterals[col_type].min_debt = val;
        } else {
            revert("invalid param");
        }
    }

    // cage
    function stop() external auth {
        _stop();
    }

    // --- Fungibility ---
    // slip - modify a user's collateral balance.
    function modify_collateral_balance(
        bytes32 col_type,
        address src,
        int256 wad
    ) external auth {
        gem[col_type][src] = Math.add(gem[col_type][src], wad);
    }

    // flux - transfer collateral between users.
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

    // move - transfer stablecoin between users.
    function transfer_coin(address src, address dst, uint256 rad) external {
        require(can_modify_account(src, msg.sender), "not authorized");
        coin[src] -= rad;
        coin[dst] += rad;
    }

    // --- CDP Manipulation ---
    // frob - modify a safe.
    // frob(i, u, v, w, dink, dart) - modify a safe
    // - modify the safe of user u
    // - using gem from user v
    // - and creating coin for user w
    // dink: change in amount of collateral
    // dart: change in amount of debt
    // TODO: rename to modify_cdp?
    function modify_cdp(
        bytes32 col_type,
        address safe,
        address col_src,
        address coin_dst,
        int256 delta_col,
        int256 delta_debt
    ) external live {
        ICDPEngine.Position memory pos = safes[col_type][safe];
        ICDPEngine.Collateral memory col = collaterals[col_type];
        require(col.rate != 0, "collateral not initialized");

        pos.collateral = Math.add(pos.collateral, delta_col);
        pos.debt = Math.add(pos.debt, delta_debt);
        col.debt = Math.add(col.debt, delta_debt);

        // delta_debt = delta_coin / col.rate
        // delta_coin [rad] = col.rate * delta_debt
        int256 delta_coin = Math.mul(col.rate, delta_debt);
        // coin balance + compound interest that the safe owes to protocol
        // debt [rad]
        uint256 coin_debt = col.rate * pos.debt;
        sys_debt = Math.add(sys_debt, delta_coin);

        // either debt has decreased, or debt ceilings are not exceeded
        require(
            delta_debt <= 0
                || (col.debt * col.rate <= col.max_debt && sys_debt <= sys_max_debt),
            "delta debt > max"
        );
        // safe is either less risky than before, or it is safe
        require(
            (delta_debt <= 0 && delta_col >= 0)
                || coin_debt <= pos.collateral * col.spot,
            "undercollateralized"
        );
        // safe is either more safe, or the owner consent
        require(
            (delta_debt <= 0 && delta_col >= 0)
                || can_modify_account(safe, msg.sender),
            "not allowed to modify safe"
        );
        // collateral src consent
        require(
            delta_col <= 0 || can_modify_account(col_src, msg.sender),
            "not allowed to modify collateral src"
        );
        // coin dst consent
        require(
            delta_debt >= 0 || can_modify_account(coin_dst, msg.sender),
            "not allowed to modify coin dst"
        );

        // safe has no debt, or a non-dusty amount
        require(pos.debt == 0 || coin_debt >= col.min_debt, "debt < dust");

        gem[col_type][col_src] = Math.sub(gem[col_type][col_src], delta_col);
        coin[coin_dst] = Math.add(coin[coin_dst], delta_coin);

        safes[col_type][safe] = pos;
        collaterals[col_type] = col;
    }

    // --- CDP Fungibility ---
    // fork - to split a safe - binary approval or splitting/merging safes.
    //    dink: amount of collateral to exchange.
    //    dart: amount of stablecoin debt to exchange.
    function fork(
        bytes32 col_type,
        address src,
        address dst,
        int256 delta_col,
        int256 delta_debt
    ) external {
        ICDPEngine.Position storage u = safes[col_type][src];
        ICDPEngine.Position storage v = safes[col_type][dst];
        ICDPEngine.Collateral storage col = collaterals[col_type];

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
        require(u_total_coin >= col.min_debt || u.debt == 0, "dust src");
        require(v_total_coin >= col.min_debt || v.debt == 0, "dust dst");
    }

    // --- CDP Confiscation ---
    // grab - liquidate a safe.
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
        ICDPEngine.Position storage safe = safes[col_type][src];
        ICDPEngine.Collateral storage col = collaterals[col_type];

        // TODO: flip operations? add -> sub
        safe.collateral = Math.add(safe.collateral, delta_col);
        safe.debt = Math.add(safe.debt, delta_debt);
        col.debt = Math.add(col.debt, delta_debt);

        int256 delta_coin = Math.mul(col.rate, delta_debt);

        gem[col_type][col_dst] = Math.sub(gem[col_type][col_dst], delta_col);
        debts[debt_dst] = Math.sub(debts[debt_dst], delta_coin);
        sys_unbacked_debt = Math.sub(sys_unbacked_debt, delta_coin);
    }

    // --- Settlement ---
    // heal - create / destroy equal quantities of stablecoin and system debt (vice).
    function burn(uint256 rad) external {
        debts[msg.sender] -= rad;
        coin[msg.sender] -= rad;
        sys_unbacked_debt -= rad;
        sys_debt -= rad;
    }

    // suck - mint unbacked stablecoin (accounted for with vice).
    function mint(address debt_dst, address coin_dst, uint256 rad)
        external
        auth
    {
        debts[debt_dst] += rad;
        coin[coin_dst] += rad;
        sys_unbacked_debt += rad;
        sys_debt += rad;
    }

    // --- Rates ---
    // fold - modify the debt multiplier, creating / destroying corresponding debt.
    function sync(bytes32 col_type, address coin_dst, int256 delta_rate)
        external
        auth
        live
    {
        ICDPEngine.Collateral storage col = collaterals[col_type];
        // old total debt = col.debt * col.rate
        // new total debt = col.debt * (col.rate + delta_rate)
        col.rate = Math.add(col.rate, delta_rate);
        int256 delta_debt = Math.mul(col.debt, delta_rate);
        coin[coin_dst] = Math.add(coin[coin_dst], delta_debt);
        sys_debt = Math.add(sys_debt, delta_debt);
    }
}
