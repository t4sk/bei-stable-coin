// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.24;

import {ICoin} from "../interfaces/ICoin.sol";
import {ICoinJoin} from "../interfaces/ICoinJoin.sol";

contract Common {
    function coin_join_join(address adapter, address user, uint256 wad) public {
        ICoin coin = ICoin(ICoinJoin(adapter).coin());
        coin.transferFrom(msg.sender, address(this), wad);
        coin.approve(adapter, wad);
        ICoinJoin(adapter).join(user, wad);
    }
}
