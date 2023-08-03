// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../lib/Math.sol";

contract Vat {
    event AddAuthorization(address indexed user);
    event RemoveAuthorization(address indexed user);
    event Stop();

    // Ilk
    struct CollateralType {
        // Art - Total debt issued for this collateral
        uint256 debt; // wad
        // rate - Accumulated rates
        uint256 rate; // ray
        // spot - Price with safety margin
        uint256 spot; // ray
        // line - Debt ceiling
        uint256 line; // rad
        // dust - Debt floor
        uint256 dust; // rad
    }
    // Urn

    struct Safe {
        // ink
        uint256 collateral; // wad
        // art
        uint256 debt; // wad
    }

    // wards
    mapping(address => bool) public authorized;
    bool public live;
    // collateral type => account => balance (wad)
    mapping(bytes32 => mapping(address => uint256)) public gem;
    // account => dai balance (rad)
    mapping(address => uint256) public dai;

    // account => caller => can modify account
    mapping(address => mapping(address => bool)) public can;

    mapping(bytes32 => CollateralType) public collateralTypes;
    // collateral type => account => Safe
    mapping(bytes32 => mapping(address => Safe)) public safes;

    // Total DAI issued
    uint256 public debt;

    modifier auth() {
        require(authorized[msg.sender], "not authorized");
        _;
    }

    constructor() {
        authorized[msg.sender] = true;
        live = true;
    }

    // rely
    function addAuthorization(address user) external auth {
        authorized[user] = true;
        emit AddAuthorization(user);
    }

    // deny
    function remoteAuthorization(address user) external auth {
        authorized[user] = false;
        emit RemoveAuthorization(user);
    }

    // cage
    function stop() external auth {
        live = false;
        emit Stop();
    }

    // hope
    function approveAccountModification(address user) external {
        can[msg.sender][user] = true;
    }

    // nope
    function denyAccountModification(address user) external {
        can[msg.sender][user] = false;
    }

    // wish
    function canModifyAccount(address account, address user)
        internal
        view
        returns (bool)
    {
        return account == user || can[account][user];
    }

    // slip
    function modifyCollateralBalance(
        bytes32 collateralType,
        address user,
        int256 wad
    ) external {
        gem[collateralType][user] = Math.add(gem[collateralType][user], wad);
    }

    // move
    function transferInternalCoins(address src, address dst, uint256 rad)
        external
    {
        require(canModifyAccount(src, msg.sender), "not authorized");
        dai[src] -= rad;
        dai[dst] += rad;
    }

    // frob
    function modifySafe(
        bytes32 collateralType,
        address safeAddr,
        address collateralSource,
        address debtDestination,
        int256 deltaCollateral,
        int256 deltaDebt
    ) external {
        require(live, "not live");

        Safe memory safe = safes[collateralType][safeAddr];
        CollateralType memory col = collateralTypes[collateralType];
        require(col.rate != 0, "collateral not initialized");

        safe.collateral = Math.add(safe.collateral, deltaCollateral);
        safe.debt = Math.add(safe.debt, deltaDebt);
        col.debt = Math.add(col.debt, deltaDebt);

        int256 dRate = Math.mul(col.rate, deltaDebt);
        uint256 userDebt = col.rate * safe.debt;
        // TODO: why?
        debt = Math.add(debt, dRate);

        // int dtab = _mul(ilk.rate, dart);
        // uint tab = _mul(ilk.rate, urn.art);
        // debt     = _add(debt, dtab);
    }
}
