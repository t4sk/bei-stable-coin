// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

interface ISafeEngine {
    // Ilk: a collateral type.
    struct CollateralType {
        // Art: total normalized stablecoin debt.
        uint256 debt; // wad
        // rate: stablecoin debt multiplier (accumulated stability fees).
        uint256 rate; // ray
        // spot: collateral price with safety margin, i.e. the maximum stablecoin allowed per unit of collateral.
        uint256 spot; // ray
        // line: the debt ceiling for a specific collateral type.
        uint256 max_debt; // rad
        // dust: the debt floor for a specific collateral type.
        uint256 min_debt; // rad
    }

    // Urn: a specific safe.
    struct Safe {
        // ink: collateral balance.
        uint256 collateral; // wad
        // art: normalized outstanding stablecoin debt.
        uint256 debt; // wad
    }

    function coin(address safe) external view returns (uint256);
    function debts(address account) external view returns (uint256);
    function safes(bytes32 col_type, address safe)
        external
        view
        returns (Safe memory);
    // ilks
    function cols(bytes32 col_type)
        external
        view
        returns (CollateralType memory);
    // rely
    function add_auth(address user) external;
    // deny
    function remove_auth(address user) external;
    // wards
    function authorized(address owner, address user)
        external
        view
        returns (bool);
    // hope
    function allow_account_modification(address user) external;
    // nope
    function deny_account_modification(address user) external;
    // wish
    function can_modify_account(address account, address user)
        external
        view
        returns (bool);
    // file
    function set(bytes32 key, uint256 val) external;
    function set(bytes32 col_type, bytes32 key, uint256 val) external;
    // slip
    function modify_collateral_balance(
        bytes32 col_type,
        address user,
        int256 wad
    ) external;
    // flux
    function transfer_collateral(
        bytes32 col_type,
        address src,
        address dst,
        uint256 wad
    ) external;
    // move
    function transfer_coin(address src, address dst, uint256 rad) external;
    function fork(
        bytes32 col_type,
        address src,
        address dst,
        int256 delta_col,
        int256 delta_debt
    ) external;
    function grab(
        bytes32 col_type,
        address src,
        address col_dst,
        address debt_dst,
        int256 delta_col,
        int256 delta_debt
    ) external;
    // suck
    function mint(address debt_dst, address coin_dst, uint256 rad) external;
    // heal
    function burn(uint256 rad) external;
    // fold
    function update_rate(bytes32 col_type, address debt_engine, int256 rate)
        external;
}
