// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IDaiJoin} from "../interfaces/IDaiJoin.sol";
import {IGemJoin} from "../interfaces/IGemJoin.sol";
import {ICdpManager} from "../interfaces/ICdpManager.sol";
import {Math} from "../lib/Math.sol";

contract Common {
    function daiJoin_join(address adapter, address account, uint256 wad)
        public
    {
        IDaiJoin(adapter).dai().transferFrom(msg.sender, address(this), wad);
        IDaiJoin(adapter).dai().approve(adapter, wad);
        IDaiJoin(adapter).join(account, wad);
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

    // Transfer rad amount of DAI from cdp to dst
    function move(address manager, uint256 cdp, address dst, uint256 rad)
        public
    {
        IManager(manager).move(cdp, dst, rad);
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
        address feeCollector,
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
        // frob(manager, cdp, toInt(convertTo18(gemJoin, amtC)), _getDrawDart(vat, jug, urn, ilk, wadD));
        // // Moves the DAI amount (balance in the vat in rad) to proxy's address
        move(manager, cdp, address(this), Math.toRad(wad));
        // // Allows adapter to access to proxy's DAI balance in the vat
        // if (VatLike(vat).can(address(this), address(daiJoin)) == 0) {
        //     VatLike(vat).hope(daiJoin);
        // }
        // Exits DAI to the user's wallet as a token
        IDaiJoin(daiJoin).exit(msg.sender, wad);
    }

    function openLockGemAndDraw(
        address manager,
        address feeCollector,
        address gemJoin,
        address daiJoin,
        bytes32 collateralType,
        uint256 amount,
        uint256 wad,
        bool isTransferFrom
    ) public returns (uint256 cdp) {
        cdp = open(manager, collateralType, address(this));
        lockGemAndDraw(
            manager,
            feeCollector,
            gemJoin,
            daiJoin,
            cdp,
            amount,
            wad,
            isTransferFrom
        );
    }
}
