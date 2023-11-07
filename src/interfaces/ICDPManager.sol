// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

interface ICDPManager {
    function cdp_engine() external view returns (address);
    function safes(uint256) external view returns (address);
    function cols(uint256) external view returns (bytes32);
    function open(bytes32, address) external returns (uint256);
    // frob
    function modify_safe(uint256 safe, int256 deltaCollateral, int256 deltaDebt)
        external;
    function move(uint256 cdp, address dst, uint256 rad) external;
}
