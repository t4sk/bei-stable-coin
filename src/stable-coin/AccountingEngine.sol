// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IVat} from "../interfaces/IVat.sol";
import {IDebtAuctionHouse} from "../interfaces/IDebtAuctionHouse.sol";
import {ISurplusAuctionHouse} from "../interfaces/ISurplusAuctionHouse.sol";
import {Auth} from "../lib/Auth.sol";
import {Pause} from "../lib/Pause.sol";

contract AccountingEngine is Auth, Pause {
    IVat public immutable vat;
    // flapper
    ISurplusAuctionHouse public surplusAuctionHouse;
    // flopper
    IDebtAuctionHouse public debtAuctionHouse;

    // sin
    mapping(uint256 => uint256) public debtQueue; // debt queue
    // Sin
    uint256 public totalQueuedDebt; // Queued debt            [rad]
    // Ash
    uint256 public totalDebtOnAuction; // On-auction debt        [rad]

    // wait
    uint256 public popDebtDelay; // Flop delay             [seconds]
    // dump
    uint256 public dump; // Flop initial lot size  [wad]
    // sump
    uint256 public sump; // Flop fixed bid size    [rad]

    // bump
    uint256 public bump; // Flap fixed lot size    [rad]
    // hump
    uint256 public hump; // Surplus buffer         [rad]

    constructor(
        address _vat,
        address _surplusAuctionHouse,
        address _debtAuctionHouse
    ) {
        vat = IVat(_vat);
        surplusAuctionHouse = ISurplusAuctionHouse(_surplusAuctionHouse);
        debtAuctionHouse = IDebtAuctionHouse(_debtAuctionHouse);
        vat.approveAccountModification(_surplusAuctionHouse);
    }

    // function file(bytes32 what, uint data) external auth {
    //     if (what == "wait") wait = data;
    //     else if (what == "bump") bump = data;
    //     else if (what == "sump") sump = data;
    //     else if (what == "dump") dump = data;
    //     else if (what == "hump") hump = data;
    //     else revert("Vow/file-unrecognized-param");
    // }

    // function file(bytes32 what, address data) external auth {
    //     if (what == "flapper") {
    //         vat.nope(address(flapper));
    //         flapper = FlapLike(data);
    //         vat.hope(data);
    //     }
    //     else if (what == "flopper") flopper = FlopLike(data);
    //     else revert("Vow/file-unrecognized-param");
    // }

    // function fess(uint tab) external auth {
    //     sin[now] = add(sin[now], tab);
    //     Sin = add(Sin, tab);
    // }
    // // Pop from debt-queue
    // function flog(uint era) external {
    //     require(add(era, wait) <= now, "Vow/wait-not-finished");
    //     Sin = sub(Sin, sin[era]);
    //     sin[era] = 0;
    // }

    // // Debt settlement
    // function heal(uint rad) external {
    //     require(rad <= vat.dai(address(this)), "Vow/insufficient-surplus");
    //     require(rad <= sub(sub(vat.sin(address(this)), Sin), Ash), "Vow/insufficient-debt");
    //     vat.heal(rad);
    // }
    // function kiss(uint rad) external {
    //     require(rad <= Ash, "Vow/not-enough-ash");
    //     require(rad <= vat.dai(address(this)), "Vow/insufficient-surplus");
    //     Ash = sub(Ash, rad);
    //     vat.heal(rad);
    // }

    // // Debt auction
    // function flop() external returns (uint id) {
    //     require(sump <= sub(sub(vat.sin(address(this)), Sin), Ash), "Vow/insufficient-debt");
    //     require(vat.dai(address(this)) == 0, "Vow/surplus-not-zero");
    //     Ash = add(Ash, sump);
    //     id = flopper.kick(address(this), dump, sump);
    // }
    // // Surplus auction
    // function flap() external returns (uint id) {
    //     require(vat.dai(address(this)) >= add(add(vat.sin(address(this)), bump), hump), "Vow/insufficient-surplus");
    //     require(sub(sub(vat.sin(address(this)), Sin), Ash) == 0, "Vow/debt-not-zero");
    //     id = flapper.kick(bump, 0);
    // }

    // function cage() external auth {
    //     require(live == 1, "Vow/not-live");
    //     live = 0;
    //     Sin = 0;
    //     Ash = 0;
    //     flapper.cage(vat.dai(address(flapper)));
    //     flopper.cage();
    //     vat.heal(min(vat.dai(address(this)), vat.sin(address(this))));
    // }
}
