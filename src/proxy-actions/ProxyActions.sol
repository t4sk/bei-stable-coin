// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IDaiJoin} from "../interfaces/IDaiJoin.sol";
import {ICdpManager} from "../interfaces/ICdpManager.sol";


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
        // lockGemAndDraw();
    }

    function openLockETHAndDraw(
        address manager,
        address feeCollector,
        address ethJoin,
        address daiJoin,
        bytes32 collateralType,
        uint256 wad
    ) public payable returns (uint256 cdp) {
        // cdp = open(manager, collateralType, address(this));
        // lockGemAndDraw(manager, feeCollector, )
    }
}
