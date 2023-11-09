// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

interface ISafeEngine {
    // Ilk: a collateral type
    struct Collateral {
        // Art [wad] total normalized stablecoin debt
        uint256 debt;
        // rate [ray] stablecoin debt multiplier (accumulated stability fees)
        uint256 rate;
        // spot [ray] collateral price with safety margin,
        //            i.e. the maximum stablecoin allowed per unit of collateral
        uint256 spot;
        // line [rad] debt ceiling for a specific collateral type
        uint256 max_debt;
        // dust [rad] debt floor for a specific collateral type
        uint256 min_debt;
    }

    // Urn: a specific vault (CDP)
    struct Safe {
        // ink [wad] collateral balance
        uint256 collateral;
        // art [wad] normalized outstanding stablecoin debt
        uint256 debt;
    }

    // ilks
    function cols(bytes32 col_type) external view returns (Collateral memory);
    // urns
    function safes(bytes32 col_type, address account)
        external
        view
        returns (Safe memory);
    // gem [wad]
    function gem(bytes32 col_type, address account)
        external
        view
        returns (uint256);
    // dai [rad]
    function coin(address account) external view returns (uint256);
    // sin [rad]
    function debts(address account) external view returns (uint256);
    // debt [rad]
    function total_debt() external view returns (uint256);
    // vice [rad]
    function total_unbacked_debt() external view returns (uint256);
    // Line [rad]
    function max_total_debt() external view returns (uint256);

    // rely
    function add_auth(address user) external;
    // deny
    function remove_auth(address user) external;
    // wards
    function authorized(address user) external view returns (bool);

    // hope
    function allow_account_modification(address user) external;
    // nope
    function deny_account_modification(address user) external;
    // wish
    function can_modify_account(address account, address user)
        external
        view
        returns (bool);

    // --- Administration ---
    function init(bytes32 col_type) external;
    // file
    function set(bytes32 key, uint256 val) external;
    function set(bytes32 col_type, bytes32 key, uint256 val) external;
    // cage
    function stop() external;

    // --- Fungibility ---
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

    // --- CDP Manipulation ---
    // frob
    function modify_safe(
        bytes32 col_type,
        address safe,
        address col_src,
        address debt_dst,
        int256 delta_col,
        int256 delta_debt
    ) external;

    // --- CDP Fungibility ---
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

    // --- Settlement ---
    // heal
    function burn(uint256 rad) external;
    // suck
    function mint(address debt_dst, address coin_dst, uint256 rad) external;

    // --- Rates ---
    // fold
    function sync(bytes32 col_type, address coin_dst, int256 delta_rate)
        external;
}
