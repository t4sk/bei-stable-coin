// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IVat} from "../interfaces/IVat.sol";
import {ICollateralAuction} from "../interfaces/ICollateralAuction.sol";
import {Auth} from "../lib/Auth.sol";
import {Pause} from "../lib/Pause.sol";

contract LiquidationEngine is Auth, Pause {
    IVat public immutable vat;

    constructor(address _vat) {
        vat = IVat(_vat);
    }

    function liquidate(bytes32 colType, address vault, address kpr)
        external
        notStopped
        returns (uint256 id)
    {
        // Vault memory v = vat.vaults(colType, vault);
        //     colType memory milk = ilks[colType];
        //     uint256 dart;
        //     uint256 rate;
        //     uint256 dust;
        //     {
        //         uint256 spot;
        //         (,rate, spot,, dust) = vat.ilks(colType);
        //         require(spot > 0 && mul(ink, spot) < mul(art, rate), "Dog/not-unsafe");

        //         // Get the minimum value between:
        //         // 1) Remaining space in the general Hole
        //         // 2) Remaining space in the collateral hole
        //         require(Hole > Dirt && milk.hole > milk.dirt, "Dog/liquidation-limit-hit");
        //         uint256 room = min(Hole - Dirt, milk.hole - milk.dirt);

        //         // uint256.max()/(RAD*WAD) = 115,792,089,237,316
        //         dart = min(art, mul(room, WAD) / rate / milk.chop);

        //         // Partial liquidation edge case logic
        //         if (art > dart) {
        //             if (mul(art - dart, rate) < dust) {

        //                 // If the leftover Vault would be dusty, just liquidate it entirely.
        //                 // This will result in at least one of dirt_i > hole_i or Dirt > Hole becoming true.
        //                 // The amount of excess will be bounded above by ceiling(dust_i * chop_i / WAD).
        //                 // This deviation is assumed to be small compared to both hole_i and Hole, so that
        //                 // the extra amount of target DAI over the limits intended is not of economic concern.
        //                 dart = art;
        //             } else {

        //                 // In a partial liquidation, the resulting auction should also be non-dusty.
        //                 require(mul(dart, rate) >= dust, "Dog/dusty-auction-from-partial-liquidation");
        //             }
        //         }
        //     }

        //     uint256 dink = mul(ink, dart) / art;

        //     require(dink > 0, "Dog/null-auction");
        //     require(dart <= 2**255 && dink <= 2**255, "Dog/overflow");

        //     vat.grab(
        //         colType, vault, milk.clip, address(vow), -int256(dink), -int256(dart)
        //     );

        //     uint256 due = mul(dart, rate);
        //     vow.fess(due);

        //     {   // Avoid stack too deep
        //         // This calcuation will overflow if dart*rate exceeds ~10^14
        //         uint256 tab = mul(due, milk.chop) / WAD;
        //         Dirt = add(Dirt, tab);
        //         ilks[colType].dirt = add(milk.dirt, tab);

        //         id = ClipperLike(milk.clip).kick({
        //             tab: tab,
        //             lot: dink,
        //             usr: vault,
        //             kpr: kpr
        //         });
        //     }

        //     emit Liquidate(colType, vault, dink, dart, due, milk.clip, id);
    }
}
