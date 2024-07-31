// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.24;

// Dog
interface ILiquidationEngine {
    // chop
    function penalty(bytes32 col_type) external returns (uint256);
    // digs
    function remove_coin_from_auction(bytes32 col_type, uint256 rad) external;
}
