// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IVat} from "./IVat.sol";
import {ICoin} from "./ICoin.sol";

interface ICoinJoin {
    function vat() external returns (IVat);
    function coin() external returns (ICoin);
    function join(address, uint256) external payable;
    function exit(address, uint256) external;
}
