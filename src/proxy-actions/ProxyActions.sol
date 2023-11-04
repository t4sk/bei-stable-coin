// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ICoinJoin} from "../interfaces/ICoinJoin.sol";
import {IGemJoin} from "../interfaces/IGemJoin.sol";
import {ICdpManager} from "../interfaces/ICdpManager.sol";
import {IVat} from "../interfaces/IVat.sol";
import {IJug} from "../interfaces/IJug.sol";
import {Math, WAD, RAY, RAD} from "../lib/Math.sol";

contract Common {
    function daiJoin_join(address adapter, address account, uint256 wad)
        public
    {
        ICoinJoin(adapter).dai().transferFrom(msg.sender, address(this), wad);
        ICoinJoin(adapter).dai().approve(adapter, wad);
        ICoinJoin(adapter).join(account, wad);
    }
}

contract ProxyActions is Common {
    function open(address manager, bytes32 collateralType, address user)
        public
        returns (uint256 cdp)
    {
        cdp = ICdpManager(manager).open(collateralType, user);
    }

    function gemJoin_join(
        address adapter,
        address vault,
        uint256 amount,
        bool isTransferFrom
    ) public {
        if (isTransferFrom) {
            IGemJoin(adapter).gem().transferFrom(
                msg.sender, address(this), amount
            );
            IGemJoin(adapter).gem().approve(adapter, amount);
        }
        IGemJoin(adapter).join(vault, amount);
    }

    function to18Decimals(address gemJoin, uint256 amount)
        internal
        returns (uint256 wad)
    {
        // For those collaterals that have less than 18 decimals precision we need to do the conversion before passing to frob function
        // Adapters will automatically handle the difference of precision
        wad = amount * 10 ** (18 - IGemJoin(gemJoin).dec());
    }

    // _getDrawDart
    function getDeltaDebt(
        address vat,
        address jug,
        address vault,
        bytes32 collateralType,
        uint256 wad
    ) internal returns (int256 deltaDebt) {
        // Updates stability fee rate
        uint256 rate = IJug(jug).drip(collateralType);

        // Gets DAI balance of the vault in the vat
        uint256 dai = IVat(vat).dai(vault);

        // TODO:?
        // If there was already enough DAI in the vat balance,
        // just exits it without adding more debt
        if (dai < wad * RAY) {
            // Calculates the needed delta debt so together with the existing dai
            // in the vat is enough to exit wad amount of DAI tokens
            deltaDebt = Math.to_int((wad * RAY - dai) / rate);
            // This is neeeded due lack of precision.
            // It might need to sum an extra delta debt wei (for the given DAI wad amount)
            deltaDebt = uint256(deltaDebt) * rate < wad * RAY
                ? deltaDebt - 1
                : deltaDebt;
        }
    }

    // Transfer rad amount of DAI from cdp to dst
    function move(address manager, uint256 cdp, address dst, uint256 rad)
        public
    {
        ICdpManager(manager).move(cdp, dst, rad);
    }

    function frob(
        address manager,
        uint256 cdp,
        int256 deltaCollateral,
        int256 deltaDebt
    ) public {
        ICdpManager(manager).modifyVault(cdp, deltaCollateral, deltaDebt);
    }

    // Lock collateral, generate debt and send DAI to msg.sender
    function lockGemAndDraw(
        address manager,
        address jug,
        address gemJoin,
        address daiJoin,
        uint256 cdp,
        uint256 amount,
        uint256 wad,
        bool isTransferFrom
    ) public {
        address vault = ICdpManager(manager).vaults(cdp);
        address vat = ICdpManager(manager).vat();
        bytes32 collateralType = ICdpManager(manager).collateralTypes(cdp);

        gemJoin_join(gemJoin, vault, amount, isTransferFrom);
        // Locks token amount into the CDP and generates debt
        // frob(manager, cdp, to_int(to18Decimals(gemJoin, amount)), _getDrawDart(vat, jug, urn, ilk, wadD));
        // // Moves the DAI amount (balance in the vat in rad) to proxy's address
        move(manager, cdp, address(this), Math.to_rad(wad));
        // // Allows adapter to access to proxy's DAI balance in the vat
        // if (VatLike(vat).can(address(this), address(daiJoin)) == 0) {
        //     VatLike(vat).hope(daiJoin);
        // }
        // Exits DAI to the user's wallet as a token
        ICoinJoin(daiJoin).exit(msg.sender, wad);
    }

    function openLockGemAndDraw(
        address manager,
        address jug,
        address gemJoin,
        address daiJoin,
        bytes32 collateralType,
        uint256 amount,
        uint256 wad,
        bool isTransferFrom
    ) public returns (uint256 cdp) {
        cdp = open(manager, collateralType, address(this));
        lockGemAndDraw(
            manager, jug, gemJoin, daiJoin, cdp, amount, wad, isTransferFrom
        );
    }
}
