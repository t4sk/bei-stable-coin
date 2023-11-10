// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

interface IAccount {
    // can
    function can(address account, address caller)
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
}
