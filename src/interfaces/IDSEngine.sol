// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.24;

// vow
interface IDSEngine {
    // vat
    function cdp_engine() external view returns (address);
    // flapper
    function surplus_auction() external view returns (address);
    // flopper
    function debt_auction() external view returns (address);
    // sin
    function debt_queue(uint256 timestamp) external view returns (uint256);
    // Sin
    function total_debt_on_queue() external view returns (uint256);
    // Ash
    function total_debt_on_debt_auction() external view returns (uint256);
    // wait
    function pop_debt_delay() external view returns (uint256);
    // dump
    function debt_auction_lot_size() external view returns (uint256);
    // sump
    function debt_auction_bid_size() external view returns (uint256);
    // bump
    function surplus_auction_lot_size() external view returns (uint256);
    // hump
    function surplus_buffer() external view returns (uint256);
    // fess
    function push_debt_to_queue(uint256 debt) external;
    // flog
    function pop_debt_from_queue(uint256 timestamp) external;
    // heal
    function settle_debt(uint256 rad) external;
    // kiss
    function decrease_auction_debt(uint256 rad) external;
    // flop
    function start_debt_auction() external returns (uint256 id);
    // flap
    function start_surplus_auction() external returns (uint256 id);
    // cage
    function stop() external;
}
