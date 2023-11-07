// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

interface ICollateralAuction {
    function collateral_type() external view returns (bytes32);
    // TODO: rename inputs
    function start(uint256 coin_to_raise, uint256 collateral_to_sell, address user, address keeper)
        external
        returns (uint256);
}
