// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IVat} from "../interfaces/IVat.sol";
import {IVow} from "../interfaces/IVow.sol";
import {ICollateralAuctionHouse} from
    "../interfaces/ICollateralAuctionHouse.sol";
import "../lib/Math.sol";
import {Auth} from "../lib/Auth.sol";
import {Pause} from "../lib/Pause.sol";

// Dog
contract LiquidationEngine is Auth, Pause {
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

    IVat public immutable vat;
    mapping(bytes32 => CollateralType) public cols;
    // vow
    IVow public vow;
    // Hole
    // Max DAI needed to cover debt+fees of active auctions [rad]
    uint256 public max;
    // Dirt
    // Amount DAI needed to cover debt+fees of active auctions [rad]
    uint256 public total;

    constructor(address _vat) {
        vat = IVat(_vat);
    }

    function liquidate(bytes32 colType, address vault, address keeper)
        external
        notStopped
        returns (uint256 id)
    {
        IVat.Vault memory v = vat.vaults(colType, vault);
        IVat.CollateralType memory c = vat.cols(colType);
        CollateralType memory col = cols[colType];
        uint256 deltaDebt;
        {
            require(
                c.spot > 0 && v.collateral * c.spot < v.debt * c.rate,
                "not unsafe"
            );

            // Get the minimum value between:
            // 1) Remaining space in the general Hole
            // 2) Remaining space in the collateral hole
            require(
                max > total && col.max > col.amount, "Dog/liquidation-limit-hit"
            );
            uint256 room = Math.min(max - total, col.max - col.amount);

            // uint256.max()/(RAD*WAD) = 115,792,089,237,316
            deltaDebt = Math.min(v.debt, room * WAD / c.rate / col.penalty);

            // Partial liquidation edge case logic
            if (v.debt > deltaDebt) {
                if ((v.debt - deltaDebt) * c.rate < c.floor) {
                    // If the leftover Vault would be dusty, just liquidate it entirely.
                    // This will result in at least one of dirt_i > hole_i or Dirt > Hole becoming true.
                    // The amount of excess will be bounded above by ceiling(dust_i * chop_i / WAD).
                    // This deviation is assumed to be small compared to both hole_i and Hole, so that
                    // the extra amount of target DAI over the limits intended is not of economic concern.
                    deltaDebt = v.debt;
                } else {
                    // In a partial liquidation, the resulting auction should also be non-dusty.
                    require(
                        deltaDebt * c.rate >= c.floor,
                        "dusty auction from partial liquidation"
                    );
                }
            }
        }

        uint256 deltaCol = (v.collateral * deltaDebt) / v.debt;

        require(deltaCol > 0, "null-auction");
        require(deltaDebt <= 2 ** 255 && deltaCol <= 2 ** 255, "overflow");

        vat.grab({
            colType: colType,
            src: vault,
            dst: col.auction,
            debtDst: address(vow),
            deltaCol: -int256(deltaCol),
            deltaDebt: -int256(deltaDebt)
        });

        uint256 due = deltaDebt * c.rate;
        vow.pushDebtToQueue(due);

        {
            // Avoid stack too deep
            // This calcuation will overflow if deltaDebt*rate exceeds ~10^14
            // tab: the target DAI to raise from the auction (debt + stability fees + liquidation penalty) [rad]
            uint256 targetDai = due * col.penalty / WAD;
            total += targetDai;
            cols[colType].amount += targetDai;

            id = ICollateralAuctionHouse(col.auction).startAuction({
                tab: targetDai,
                // lot: the amount of collateral available for purchase [wad]
                lot: deltaCol,
                user: vault,
                keeper: keeper
            });
        }
    }

    // digs
    function removeDaiFromAuction(bytes32 collateral_type, uint256 rad)
        external
        auth
    {
        total -= rad;
        cols[collateral_type].amount -= rad;
        // emit Digs(ilk, rad);
    }
}
