// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

interface ISpotter {
    // Ilk
    struct Collateral {
        // pip
        address price_feed;
        // mat [ray]
        uint256 liquidation_ratio;
    }

    // par - reference per BEI
    function par() external returns (uint256);
    function collaterals(bytes32) external returns (Collateral memory);
}
