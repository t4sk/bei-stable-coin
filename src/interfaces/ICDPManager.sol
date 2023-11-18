// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

interface ICDPManager {
    struct List {
        uint256 prev;
        uint256 next;
    }

    // vat
    function cdp_engine() external view returns (address);
    // cdpi
    function last_cdp_id() external view returns (uint256);
    // urns
    function positions(uint256 cdp_id) external view returns (address);
    // list
    function list(uint256 cdp_id) external view returns (List memory);
    // owns
    function owner_of(uint256 cdp_id) external view returns (address);
    // ilks
    function collaterals(uint256 cdp_id) external view returns (bytes32);

    // first
    function first(address owner) external view returns (uint256);
    // last
    function last(address owner) external view returns (uint256);
    // count
    function count(address owner) external view returns (uint256);

    // cdpCan - permission to modify cdp by addr
    function cdp_can(address owner, uint256 cdp_id, address user)
        external
        view
        returns (bool);
    // urnCan
    function cdp_handler_can(address owner, address user)
        external
        view
        returns (bool);
    // cdpAllow
    function allow_cdp(uint256 cdp_id, address user, bool ok) external;
    // urnAllow
    function allow_cdp_handler(address user, bool ok) external;

    // open
    function open(bytes32 col_type, address user)
        external
        returns (uint256 id);
    // give
    function give(uint256 cdp_id, address dst) external;
    // frob
    function modify_cdp(uint256 cdp_id, int256 delta_col, int256 delta_debt)
        external;
    // flux
    function transfer_collateral(uint256 cdp_id, address dst, uint256 wad)
        external;
    // flux
    function transfer_collateral(
        bytes32 col_type,
        uint256 cdp_id,
        address dst,
        uint256 wad
    ) external;
    // move
    function transfer_coin(uint256 cdp_id, address dst, uint256 rad) external;
    // quit
    function quit(uint256 cdp_id, address cdp_dst) external;
    // enter
    function enter(address cdp_src, uint256 cdp_id) external;
    function shift(uint256 cdp_src, uint256 cdp_dst) external;
}
