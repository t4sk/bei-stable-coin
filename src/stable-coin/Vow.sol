// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IVat} from "../interfaces/IVat.sol";
import {IDebtAuctionHouse} from "../interfaces/IDebtAuctionHouse.sol";
import {ISurplusAuctionHouse} from "../interfaces/ISurplusAuctionHouse.sol";
import {Math} from "../lib/Math.sol";
import {Auth} from "../lib/Auth.sol";
import {Pause} from "../lib/Pause.sol";

// TODO:
// Vow - Debt engine
contract Vow is Auth, Pause {
    IVat public immutable vat;
    // flapper
    ISurplusAuctionHouse public surplusAuctionHouse;
    // flopper
    IDebtAuctionHouse public debtAuctionHouse;

    // sin (mapping timestamp => rad)
    mapping(uint256 => uint256) public debtQueue; // debt queue
    // Sin
    uint256 public totalQueuedDebt; // Queued debt            [rad]
    // Ash
    uint256 public totalDebtOnAuction; // On-auction debt        [rad]

    // wait
    uint256 public popDebtDelay; // Flop delay             [seconds]
    // dump [wad]
    // Amount of protocol tokens to be minted post-auction
    uint256 public debtAuctionInitialLotSize;
    // sump [rad]
    // Amount of debt sold in one debt auction (initial coin bid for debtAuctionInitialLotSize protocol tokens)
    uint256 public debtAcutionBidSize;

    // bump [rad]
    // Amount of surplus stability fees sold in one surplus auction
    uint256 public surplusLotSize;
    // hump [rad]
    // Amount of stability fees that need to accrue in this contract before any surplus auction can start
    uint256 public surplusBuffer;

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

    // fess
    /**
     * @notice Push bad debt into a queue
     * @dev Debt is locked in a queue to give the system enough time to auction collateral
     *      and gather surplus
     */
    function pushDebtToQueue(uint256 debt) external auth {
        debtQueue[block.timestamp] += debt;
        totalQueuedDebt += debt;
    }

    // flog - Pop from debt-queue
    /**
     * @notice Pop a block of bad debt from the debt queue
     */
    function popDebtFromQueue(uint256 timestamp) external {
        require(
            timestamp + popDebtDelay <= block.timestamp, "wait not finished"
        );
        totalQueuedDebt -= debtQueue[timestamp];
        debtQueue[timestamp] = 0;
    }

    // heal - Debt settlement
    /**
     * @notice Destroy an equal amount of coins and bad debt
     * @dev We can only destroy debt that is not locked in the queue and also not in a debt auction
     *
     */
    function settleDebt(uint256 rad) external {
        require(rad <= vat.dai(address(this)), "insufficient surplus");
        require(
            rad
                <= vat.debts(address(this)) - totalQueuedDebt - totalDebtOnAuction,
            "insufficient debt"
        );
        vat.burn(rad);
    }

    // kiss
    /**
     * @notice Use surplus coins to destroy debt that was in a debt auction
     *
     */
    function cancelAuctionedDebtWithSurplus(uint256 rad) external {
        require(rad <= totalDebtOnAuction, "not enough debt on auction");
        require(rad <= vat.dai(address(this)), "insufficient surplus");
        totalDebtOnAuction -= rad;
        vat.burn(rad);
    }

    // Debt auction
    /**
     * @notice Start a debt auction (print protocol tokens in exchange for coins so that the
     *         system can be recapitalized)
     * @dev We can only auction debt that is not already being auctioned and is not locked in the debt queue
     *
     */
    function startDebtAuction() external returns (uint256 id) {
        require(
            debtAcutionBidSize
                <= vat.debts(address(this)) - totalQueuedDebt - totalDebtOnAuction,
            "insufficient debt"
        );
        require(vat.dai(address(this)) == 0, "surplus not zero");
        totalDebtOnAuction += debtAcutionBidSize;
        id = debtAuctionHouse.startAuction(
            address(this), debtAuctionInitialLotSize, debtAcutionBidSize
        );
    }

    // Surplus auction
    /**
     * @notice Start a surplus auction
     * @dev We can only auction surplus if we wait at least 'surplusAuctionDelay' seconds since the last
     *      surplus auction trigger, if we keep enough surplus in the buffer and if there is no bad debt left to burn
     *
     */
    function startSurplusAuction() external returns (uint256 id) {
        require(
            vat.dai(address(this))
                >= vat.debts(address(this)) + surplusLotSize + surplusBuffer,
            "insufficient surplus"
        );
        require(
            vat.debts(address(this)) - totalQueuedDebt - totalDebtOnAuction == 0,
            "debt not zero"
        );
        id = surplusAuctionHouse.startAuction(surplusLotSize, 0);
    }

    function stop() external auth {
        _stop();
        totalQueuedDebt = 0;
        totalDebtOnAuction = 0;
        surplusAuctionHouse.stop(vat.dai(address(surplusAuctionHouse)));
        debtAuctionHouse.stop();
        vat.burn(Math.min(vat.dai(address(this)), vat.debts(address(this))));
    }
}
