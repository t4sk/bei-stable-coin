// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.24;

interface ISpotter {
    // Ilk
    struct Collateral {
        // pip
        address price_feed;
        // mat [ray]
        uint256 liquidation_ratio;
    }

    // par [ray] - value of BEI in the reference asset (e.g. $1 per BEI)
    function par() external returns (uint256);
    function collaterals(bytes32 col_type)
        external
        view
        returns (Collateral memory);
}
