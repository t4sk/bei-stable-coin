// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ICDPEngine} from "../interfaces/ICDPEngine.sol";
import {IDebtEngine} from "../interfaces/IDebtEngine.sol";
import {ICollateralAuction} from "../interfaces/ICollateralAuction.sol";
import "../lib/Math.sol";
import {Auth} from "../lib/Auth.sol";
import {CircuitBreaker} from "../lib/CircuitBreaker.sol";

// Dog
contract LiquidationEngine is Auth, CircuitBreaker {
    event Liquidate(
        bytes32 indexed col_type,
        address indexed safe,
        uint256 delta_col,
        uint256 delta_debt,
        uint256 due,
        address auction,
        uint256 indexed id
    );
    event Remove(bytes32 col_type, uint256 rad);

    struct CollateralType {
        // clip - Address of collateral auction house
        address auction;
        // chop - Liquidation penalty [wad]
        uint256 penalty;
        // hole - Max DAI needed to cover debt+fees of active auctions per collateral [rad]
        uint256 max;
        // dirt - Amountt of DAI needed to cover debt+fees of active auctions per collateral [rad]
        uint256 amount;
    }

    ICDPEngine public immutable cdp_engine;
    mapping(bytes32 => CollateralType) public cols;
    // debt_engine
    IDebtEngine public debt_engine;
    // Hole
    // Max DAI needed to cover debt+fees of active auctions [rad]
    uint256 public max;
    // Dirt
    // Amount DAI needed to cover debt+fees of active auctions [rad]
    uint256 public total;

    constructor(address _cdp_engine) {
        cdp_engine = ICDPEngine(_cdp_engine);
    }

    // --- Administration ---
    // file
    function set(bytes32 key, address val) external auth {
        if (key == "debt_engine") {
            debt_engine = IDebtEngine(val);
        } else {
            revert("set invalid param");
        }
    }

    function set(bytes32 key, uint256 val) external auth {
        if (key == "max") {
            max = val;
        } else {
            revert("invalid param");
        }
    }

    function set(bytes32 col_type, bytes32 key, uint256 val) external auth {
        if (key == "penalty") {
            require(val >= WAD, "penalty < WAD");
            cols[col_type].penalty = val;
        } else if (key == "max") {
            cols[col_type].max = val;
        } else {
            revert("invalid param");
        }
    }

    function set(bytes32 col_type, bytes32 key, address auction) external auth {
        if (key == "auction") {
            require(col_type == ICollateralAuction(auction).collateral_type(), "col type != auction col type");
            cols[col_type].auction = auction;
        } else {
            revert("invalid param");
        }
    }

    // --- CDP Liquidation: all bark and no bite ---
    //
    // Liquidate a Vault and start a Dutch auction to sell its collateral for DAI.
    //
    // The third argument is the address that will receive the liquidation reward, if any.
    //
    // The entire Vault will be liquidated except when the target amount of DAI to be raised in
    // the resulting auction (debt of Vault + liquidation penalty) causes either Dirt to exceed
    // Hole or ilk.dirt to exceed ilk.hole by an economically significant amount. In that
    // case, a partial liquidation is performed to respect the global and per-ilk limits on
    // outstanding DAI target. The one exception is if the resulting auction would likely
    // have too little collateral to be interesting to Keepers (debt taken from Vault < ilk.dust),
    // in which case the function reverts.
    function liquidate(bytes32 col_type, address safe, address keeper) external not_stopped returns (uint256 id) {
        ICDPEngine.Safe memory s = cdp_engine.safes(col_type, safe);
        ICDPEngine.CollateralType memory c = cdp_engine.cols(col_type);
        CollateralType memory col = cols[col_type];
        uint256 delta_debt;
        {
            require(c.spot > 0 && s.collateral * c.spot < s.debt * c.rate, "not unsafe");

            // Get the minimum value between:
            // 1) Remaining space in the general Hole
            // 2) Remaining space in the collateral hole
            require(max > total && col.max > col.amount, "liquidation limit");
            uint256 room = Math.min(max - total, col.max - col.amount);

            // TODO: why divide by penalty?
            // uint256.max()/(RAD*WAD) = 115,792,089,237,316
            delta_debt = Math.min(s.debt, room * WAD / c.rate / col.penalty);

            // Partial liquidation edge case logic
            if (s.debt > delta_debt) {
                if ((s.debt - delta_debt) * c.rate < c.floor) {
                    // If the leftover s would be dusty, just liquidate it entirely.
                    // This will result in at least one of dirt_i > hole_i or Dirt > Hole becoming true.
                    // The amount of excess will be bounded above by ceiling(dust_i * chop_i / WAD).
                    // This deviation is assumed to be small compared to both hole_i and Hole, so that
                    // the extra amount of target DAI over the limits intended is not of economic concern.
                    delta_debt = s.debt;
                } else {
                    // In a partial liquidation, the resulting auction should also be non-dusty.
                    require(delta_debt * c.rate >= c.floor, "dusty auction from partial liquidation");
                }
            }
        }

        uint256 delta_col = (s.collateral * delta_debt) / s.debt;

        require(delta_col > 0, "null-auction");
        require(delta_debt <= 2 ** 255 && delta_col <= 2 ** 255, "overflow");

        // NOTE: collateral sent to aution, debt sent to debt engine
        cdp_engine.grab({
            col_type: col_type,
            src: safe,
            col_dst: col.auction,
            debt_dst: address(debt_engine),
            delta_col: -int256(delta_col),
            delta_debt: -int256(delta_debt)
        });

        uint256 due = delta_debt * c.rate;
        debt_engine.push_debt_to_queue(due);

        {
            // Avoid stack too deep
            // This calcuation will overflow if delta_debt*rate exceeds ~10^14
            uint256 target_coin_amount = due * col.penalty / WAD;
            total += target_coin_amount;
            cols[col_type].amount += target_coin_amount;

            id = ICollateralAuction(col.auction).start_auction({
                // tab: the target DAI to raise from the auction (debt + stability fees + liquidation penalty) [rad]
                // TODO: what is tab?
                tab: target_coin_amount,
                // lot: the amount of collateral available for purchase [wad]
                lot: delta_col,
                user: safe,
                keeper: keeper
            });
        }

        emit Liquidate(col_type, safe, delta_col, delta_debt, due, col.auction, id);
    }

    // digs
    function remove_coin_from_auction(bytes32 col_type, uint256 rad) external auth {
        total -= rad;
        cols[col_type].amount -= rad;
        emit Remove(col_type, rad);
    }

    // cage
    function stop() external auth {
        _stop();
    }
}
