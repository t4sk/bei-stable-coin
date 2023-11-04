// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IVat} from "./IVat.sol";
import {IGem} from "./IGem.sol";

interface ICoinJoin {
    function vat() external returns (IVat);
    function dai() external returns (IGem);
    function join(address, uint256) external payable;
    function exit(address, uint256) external;
}
