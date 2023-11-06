// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ICoinJoin} from "../interfaces/ICoinJoin.sol";
import {IGemJoin} from "../interfaces/IGemJoin.sol";
import {ICDPManager} from "../interfaces/ICDPManager.sol";
import {ICDPEngine} from "../interfaces/ICDPEngine.sol";
import {IJug} from "../interfaces/IJug.sol";
import {Math, WAD, RAY, RAD} from "../lib/Math.sol";

contract Common {
    function daiJoin_join(address adapter, address account, uint256 wad) public {
        ICoinJoin(adapter).coin().transferFrom(msg.sender, address(this), wad);
        ICoinJoin(adapter).coin().approve(adapter, wad);
        ICoinJoin(adapter).join(account, wad);
    }
}

contract ProxyActions is Common {
    function open(address manager, bytes32 collateral_type, address user) public returns (uint256 cdp) {
        cdp = ICDPManager(manager).open(collateral_type, user);
    }

    function gemJoin_join(address adapter, address safe, uint256 amount, bool isTransferFrom) public {
        if (isTransferFrom) {
            IGemJoin(adapter).gem().transferFrom(msg.sender, address(this), amount);
            IGemJoin(adapter).gem().approve(adapter, amount);
        }
        IGemJoin(adapter).join(safe, amount);
    }

    function to18Decimals(address gemJoin, uint256 amount) internal returns (uint256 wad) {
        // For those collaterals that have less than 18 decimals precision we need to do the conversion before passing to frob function
        // Adapters will automatically handle the difference of precision
        wad = amount * 10 ** (18 - IGemJoin(gemJoin).dec());
    }

    // _getDrawDart
    function getDeltaDebt(address cdp_engine, address jug, address safe, bytes32 collateral_type, uint256 wad)
        internal
        returns (int256 deltaDebt)
    {
        // Updates stability fee rate
        uint256 rate = IJug(jug).drip(collateral_type);

        // Gets DAI balance of the safe in the cdp_engine
        uint256 dai = ICDPEngine(cdp_engine).coin(safe);

        // TODO:?
        // If there was already enough DAI in the cdp_engine balance,
        // just exits it without adding more debt
        if (dai < wad * RAY) {
            // Calculates the needed delta debt so together with the existing dai
            // in the cdp_engine is enough to exit wad amount of DAI tokens
            deltaDebt = Math.to_int((wad * RAY - dai) / rate);
            // This is neeeded due lack of precision.
            // It might need to sum an extra delta debt wei (for the given DAI wad amount)
            deltaDebt = uint256(deltaDebt) * rate < wad * RAY ? deltaDebt - 1 : deltaDebt;
        }
    }

    // Transfer rad amount of DAI from cdp to dst
    function move(address manager, uint256 cdp, address dst, uint256 rad) public {
        ICDPManager(manager).move(cdp, dst, rad);
    }

    function frob(address manager, uint256 cdp, int256 deltaCollateral, int256 deltaDebt) public {
        ICDPManager(manager).modify_safe(cdp, deltaCollateral, deltaDebt);
    }

    // Lock collateral, generate debt and send DAI to msg.sender
    function lockGemAndDraw(
        address manager,
        address jug,
        address gemJoin,
        address daiJoin,
        uint256 cdp,
        uint256 amount,
        uint256 wad,
        bool isTransferFrom
    ) public {
        address safe = ICDPManager(manager).safes(cdp);
        address cdp_engine = ICDPManager(manager).cdp_engine();
        bytes32 collateral_type = ICDPManager(manager).cols(cdp);

        gemJoin_join(gemJoin, safe, amount, isTransferFrom);
        // Locks token amount into the CDP and generates debt
        // frob(manager, cdp, to_int(to18Decimals(gemJoin, amount)), _getDrawDart(cdp_engine, jug, urn, ilk, wadD));
        // // Moves the DAI amount (balance in the cdp_engine in rad) to proxy's address
        move(manager, cdp, address(this), Math.to_rad(wad));
        // // Allows adapter to access to proxy's DAI balance in the cdp_engine
        // if (VatLike(cdp_engine).can(address(this), address(daiJoin)) == 0) {
        //     VatLike(cdp_engine).hope(daiJoin);
        // }
        // Exits DAI to the user's wallet as a token
        ICoinJoin(daiJoin).exit(msg.sender, wad);
    }

    function openLockGemAndDraw(
        address manager,
        address jug,
        address gemJoin,
        address daiJoin,
        bytes32 collateral_type,
        uint256 amount,
        uint256 wad,
        bool isTransferFrom
    ) public returns (uint256 cdp) {
        cdp = open(manager, collateral_type, address(this));
        lockGemAndDraw(manager, jug, gemJoin, daiJoin, cdp, amount, wad, isTransferFrom);
    }
}
