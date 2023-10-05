// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IVat} from "../interfaces/IVat.sol";
import {IDebtEngine} from "../interfaces/IDebtEngine.sol";
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
    mapping(bytes32 => CollateralType) public colTypes;
    // vow
    IDebtEngine public debtEngine;
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
        CollateralType memory col = colTypes[colType];
        // TODO: what is dart?
        uint256 dart;
        {
            // (, rate, spot,, dust) = vat.colTypes(colType);
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
            uint256 diff = Math.min(max - total, col.max - col.amount);

            // uint256.max()/(RAD*WAD) = 115,792,089,237,316
            dart = Math.min(v.debt, diff * WAD / c.rate / col.penalty);

            // Partial liquidation edge case logic
            if (v.debt > dart) {
                if ((v.debt - dart) * c.rate < c.floor) {
                    // If the leftover Vault would be dusty, just liquidate it entirely.
                    // This will result in at least one of dirt_i > hole_i or Dirt > Hole becoming true.
                    // The amount of excess will be bounded above by ceiling(dust_i * chop_i / WAD).
                    // This deviation is assumed to be small compared to both hole_i and Hole, so that
                    // the extra amount of target DAI over the limits intended is not of economic concern.
                    dart = v.debt;
                } else {
                    // In a partial liquidation, the resulting auction should also be non-dusty.
                    require(
                        dart * c.rate >= c.floor,
                        "dusty auction from partial liquidation"
                    );
                }
            }
        }

        // TODO: what is dink?
        uint256 dink = (v.collateral * dart) / v.debt;

        require(dink > 0, "null-auction");
        require(dart <= 2 ** 255 && dink <= 2 ** 255, "overflow");

        vat.grab(
            colType,
            vault,
            col.auction,
            address(debtEngine),
            -int256(dink),
            -int256(dart)
        );

        uint256 due = dart * c.rate;
        debtEngine.pushDebtToQueue(due);

        {
            // Avoid stack too deep
            // This calcuation will overflow if dart*rate exceeds ~10^14
            // TODO: what is tab?
            uint256 tab = due * col.penalty / WAD;
            total += tab;
            colTypes[colType].amount += tab;

            id = ICollateralAuctionHouse(col.auction).startAuction({
                tab: tab,
                lot: dink,
                user: vault,
                keeper: keeper
            });
        }

        // emit Liquidate(colType, vault, dink, dart, due, col.auction, id);
    }
}
