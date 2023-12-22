// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

interface ICollateralAuction {
    struct Sale {
        // pos - Index in active array
        uint256 pos;
        // tab [rad] - Amount of coin to raise
        uint256 coin_amount;
        // lot [wad] - Amount of collateral to sell
        uint256 collateral_amount;
        // usr - Liquidated CDP
        address user;
        // tick - Auction start time
        uint96 start_time;
        // top [ray] - Starting price
        uint256 starting_price;
    }

    function sales(uint256 sale_id) external view returns (Sale memory);
    function collateral_type() external view returns (bytes32);
    function start(
        uint256 coin_amount,
        uint256 collateral_amount,
        address user,
        address keeper
    ) external returns (uint256);
}
