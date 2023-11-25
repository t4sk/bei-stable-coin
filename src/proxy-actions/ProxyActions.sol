// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import {IWETH} from "../interfaces/IWETH.sol";
import {IGem} from "../interfaces/IGem.sol";
import {ICoin} from "../interfaces/ICoin.sol";
import {ICoinJoin} from "../interfaces/ICoinJoin.sol";
import {IGemJoin} from "../interfaces/IGemJoin.sol";
import {IAccessControl} from "../interfaces/IAccessControl.sol";
import {ICDPManager} from "../interfaces/ICDPManager.sol";
import {ICDPEngine} from "../interfaces/ICDPEngine.sol";
import {IJug} from "../interfaces/IJug.sol";
import "../lib/Math.sol";
import {Common} from "./Common.sol";

contract ProxyActions is Common {
    // convertTo18
    function to_18_dec(address gem_join, uint256 amount)
        internal
        returns (uint256 wad)
    {
        wad = amount * 10 ** (18 - IGemJoin(gem_join).decimals());
    }

    // _getDrawDart
    function _get_borrow_delta_debt(
        address cdp_engine,
        address jug,
        address cdp,
        bytes32 col_type,
        uint256 wad
    ) internal returns (int256 delta_debt) {
        // Updates stability fee rate
        uint256 rate = IJug(jug).collect_stability_fee(col_type);

        // Gets BEI balance of the cdp in the cdp_engine
        uint256 coin_bal = ICDPEngine(cdp_engine).coin(cdp);

        // If there was already enough BEI in the cdp_engine balance,
        // just exits it without adding more debt
        if (wad * RAY > coin_bal) {
            // Calculates the needed delta debt so together with the existing BEI
            // in the cdp_engine is enough to exit wad amount of BEI tokens
            delta_debt = Math.to_int((wad * RAY - coin_bal) / rate);
            // TODO: wat dis?
            // This is needed due lack of precision.
            // It might need to sum an extra delta debt wei (for the given BEI wad amount)
            delta_debt = uint256(delta_debt) * rate < wad * RAY
                ? delta_debt - 1
                : delta_debt;
        }
    }

    // _getWipeDart
    function _get_repay_delta_debt(
        address cdp_engine,
        // TODO: wad, ray or rad?
        uint256 coin_amount,
        address cdp,
        bytes32 col_type
    ) internal view returns (int256 delta_debt) {
        // Gets actual rate from the cdp_engine
        ICDPEngine.Collateral memory c =
            ICDPEngine(cdp_engine).collaterals(col_type);
        // Gets actual debt value of the cdp
        ICDPEngine.Position memory pos =
            ICDPEngine(cdp_engine).positions(col_type, cdp);

        // Uses the whole coin_amount balance in the cdp_engine to reduce the debt
        delta_debt = Math.to_int(coin_amount / c.rate_acc);
        // Checks the calculated delta_debt is not higher than cdp.debt (total debt),
        // otherwise uses its value
        delta_debt = uint256(delta_debt) <= pos.debt
            ? -delta_debt
            : -Math.to_int(pos.debt);
    }

    // _getWipeAllWad
    function _get_repay_all_debt(
        address cdp_engine,
        address user,
        address cdp,
        bytes32 col_type
    ) internal view returns (uint256 wad) {
        // Gets actual rate from the cdp_engine
        ICDPEngine.Collateral memory c =
            ICDPEngine(cdp_engine).collaterals(col_type);
        // Gets actual debt value of the cdp
        ICDPEngine.Position memory pos =
            ICDPEngine(cdp_engine).positions(col_type, cdp);
        // Gets actual coin amount in the cdp
        uint256 coin_bal = ICDPEngine(cdp_engine).coin(user);

        uint256 rad = pos.debt * c.rate_acc - coin_bal;
        wad = rad / RAY;

        // If the rad precision has some dust, it will need to request for 1 extra wad wei
        wad = wad * RAY < rad ? wad + 1 : wad;
    }

    function transfer(address gem, address dst, uint256 amount) public {
        IGem(gem).transfer(dst, amount);
    }

    // ethJoin_join
    function eth_join_join(address gem_join, address cdp) public payable {
        IWETH weth = IWETH(address(IGemJoin(gem_join).gem()));
        // Wraps ETH in WETH
        weth.deposit{value: msg.value}();
        // Approves adapter to take the WETH amount
        weth.approve(address(gem_join), msg.value);
        // Joins WETH collateral into the cdp_engine
        IGemJoin(gem_join).join(cdp, msg.value);
    }

    // gemJoin_join
    function gem_join_join(
        address gem_join,
        address cdp,
        uint256 amount,
        bool is_transfer_from
    ) public {
        if (is_transfer_from) {
            IGem gem = IGem(IGemJoin(gem_join).gem());
            gem.transferFrom(msg.sender, address(this), amount);
            gem.approve(gem_join, amount);
        }
        IGemJoin(gem_join).join(cdp, amount);
    }

    // hope
    function allow_account_modification(address acc, address user) public {
        IAccessControl(acc).allow_account_modification(user);
    }

    // nope
    function deny_account_modification(address acc, address user) public {
        IAccessControl(acc).deny_account_modification(user);
    }

    function open(address cdp_manager, bytes32 col_type, address user)
        public
        returns (uint256 cdp_id)
    {
        cdp_id = ICDPManager(cdp_manager).open(col_type, user);
    }

    // TODO: wat dis?
    function give(address cdp_manager, uint256 cdp_id, address user) public {
        ICDPManager(cdp_manager).give(cdp_id, user);
    }

    // TODO:
    // function giveToProxy(
    //     address proxyRegistry,
    //     address cdp_manager,
    //     uint cdp_id,
    //     address dst
    // ) public {
    //     // Gets actual proxy address
    //     address proxy = ProxyRegistryLike(proxyRegistry).proxies(dst);
    //     // Checks if the proxy address already existed and dst address is still the owner
    //     if (proxy == address(0) || ProxyLike(proxy).owner() != dst) {
    //         uint csize;
    //         assembly {
    //             csize := extcodesize(dst)
    //         }
    //         // We want to avoid creating a proxy for a contract address that might not be able to handle proxies, then losing the cdp_id
    //         require(csize == 0, "Dst-is-a-contract");
    //         // Creates the proxy for the dst address
    //         proxy = ProxyRegistryLike(proxyRegistry).build(dst);
    //     }
    //     // Transfers cdp_id to the dst proxy
    //     give(cdp_manager, cdp_id, proxy);
    // }

    // cdpAllow
    function allow_cdp(
        address cdp_manager,
        uint256 cdp_id,
        address user,
        bool ok
    ) public {
        ICDPManager(cdp_manager).allow_cdp(cdp_id, user, ok);
    }

    // urnAllow
    function allow_cdp_handler(address cdp_manager, address user, bool ok)
        public
    {
        ICDPManager(cdp_manager).allow_cdp_handler(user, ok);
    }

    // flux
    function transfer_collateral(
        address cdp_manager,
        uint256 cdp_id,
        address dst,
        uint256 wad
    ) public {
        ICDPManager(cdp_manager).transfer_collateral(cdp_id, dst, wad);
    }

    // move
    function transfer_coin(
        address cdp_manager,
        uint256 cdp_id,
        address dst,
        // TODO: check units
        uint256 rad
    ) public {
        ICDPManager(cdp_manager).transfer_coin(cdp_id, dst, rad);
    }

    // frob
    function modify_cdp(
        address cdp_manager,
        uint256 cdp_id,
        int256 delta_col,
        int256 delta_debt
    ) public {
        ICDPManager(cdp_manager).modify_cdp(cdp_id, delta_col, delta_debt);
    }

    function quit(address cdp_manager, uint256 cdp_id, address dst) public {
        ICDPManager(cdp_manager).quit(cdp_id, dst);
    }

    function enter(address cdp_manager, address src, uint256 cdp_id) public {
        ICDPManager(cdp_manager).enter(src, cdp_id);
    }

    function shift(address cdp_manager, uint256 cdp_src, uint256 cdp_dst)
        public
    {
        ICDPManager(cdp_manager).shift(cdp_src, cdp_dst);
    }

    // TODO: wat dis?
    // function makeGemBag(
    //     address gem_join
    // ) public returns (address bag) {
    //     bag = GNTJoinLike(gem_join).make(address(this));
    // }

    // lockETH
    function lock_eth(address cdp_manager, address eth_join, uint256 cdp_id)
        public
        payable
    {
        // Receives ETH amount, converts it to WETH and joins it into the cdp_engine
        eth_join_join(eth_join, address(this));
        // TODO: why 2 ways to call modify_cdp -> from CDPManager and directly to CDPEngine
        // Locks WETH amount into the CDP
        ICDPEngine(ICDPManager(cdp_manager).cdp_engine()).modify_cdp({
            col_type: ICDPManager(cdp_manager).collaterals(cdp_id),
            cdp: ICDPManager(cdp_manager).positions(cdp_id),
            gem_src: address(this),
            coin_dst: address(this),
            delta_col: Math.to_int(msg.value),
            delta_debt: 0
        });
    }

    // safeLockETH
    function safe_lock_eth(
        address cdp_manager,
        address eth_join,
        uint256 cdp_id,
        address owner
    ) public payable {
        require(
            ICDPManager(cdp_manager).owner_of(cdp_id) == owner, "owner mismatch"
        );
        lock_eth(cdp_manager, eth_join, cdp_id);
    }

    // lockGem
    function lock_gem(
        address cdp_manager,
        address gem_join,
        uint256 cdp_id,
        uint256 amount,
        bool is_tranfer_from
    ) public {
        // Takes token amount from user's wallet and joins into the cdp_engine
        gem_join_join(gem_join, address(this), amount, is_tranfer_from);
        // Locks token amount into the CDP
        ICDPEngine(ICDPManager(cdp_manager).cdp_engine()).modify_cdp({
            col_type: ICDPManager(cdp_manager).collaterals(cdp_id),
            cdp: ICDPManager(cdp_manager).positions(cdp_id),
            gem_src: address(this),
            coin_dst: address(this),
            delta_col: Math.to_int(to_18_dec(gem_join, amount)),
            delta_debt: 0
        });
    }

    // safeLockGem
    function safe_lock_gem(
        address cdp_manager,
        address gem_join,
        uint256 cdp_id,
        uint256 amount,
        bool is_tranfer_from,
        address owner
    ) public {
        require(
            ICDPManager(cdp_manager).owner_of(cdp_id) == owner, "owner mismatch"
        );
        lock_gem(cdp_manager, gem_join, cdp_id, amount, is_tranfer_from);
    }

    // freeETH
    function free_eth(
        address cdp_manager,
        address eth_join,
        uint256 cdp_id,
        uint256 wad
    ) public {
        // Unlocks WETH amount from the CDP
        modify_cdp(cdp_manager, cdp_id, -Math.to_int(wad), 0);
        // Moves the amount from the CDP cdp to proxy's address
        transfer_collateral(cdp_manager, cdp_id, address(this), wad);
        // Exits WETH amount to proxy address as a token
        IGemJoin(eth_join).exit(address(this), wad);
        // Converts WETH to ETH
        IWETH(address(IGemJoin(eth_join).gem())).withdraw(wad);
        // Sends ETH back to the user's wallet
        payable(msg.sender).transfer(wad);
    }

    // freeGem
    function free_gem(
        address cdp_manager,
        address gem_join,
        uint256 cdp_id,
        uint256 amount
    ) public {
        uint256 wad = to_18_dec(gem_join, amount);
        // Unlocks token amount from the CDP
        modify_cdp(cdp_manager, cdp_id, -Math.to_int(wad), 0);
        // Moves the amount from the CDP cdp to proxy's address
        transfer_collateral(cdp_manager, cdp_id, address(this), wad);
        // Exits token amount to the user's wallet as a token
        IGemJoin(gem_join).exit(msg.sender, amount);
    }

    // exitETH
    function exit_eth(
        address cdp_manager,
        address eth_join,
        uint256 cdp_id,
        uint256 wad
    ) public {
        // Moves the amount from the CDP cdp to proxy's address
        transfer_collateral(cdp_manager, cdp_id, address(this), wad);
        // Exits WETH amount to proxy address as a token
        IGemJoin(eth_join).exit(address(this), wad);
        // Converts WETH to ETH
        IWETH(address(IGemJoin(eth_join).gem())).withdraw(wad);
        // Sends ETH back to the user's wallet
        payable(msg.sender).transfer(wad);
    }

    // exitGem
    function exit_gem(
        address cdp_manager,
        address gem_join,
        uint256 cdp_id,
        uint256 amount
    ) public {
        // Moves the amount from the CDP cdp to proxy's address
        transfer_collateral(
            cdp_manager, cdp_id, address(this), to_18_dec(gem_join, amount)
        );
        // Exits token amount to the user's wallet as a token
        IGemJoin(gem_join).exit(msg.sender, amount);
    }

    // draw
    function borrow(
        address cdp_manager,
        address jug,
        address coin_join,
        uint256 cdp_id,
        uint256 wad
    ) public {
        address cdp = ICDPManager(cdp_manager).positions(cdp_id);
        address cdp_engine = ICDPManager(cdp_manager).cdp_engine();
        bytes32 col_type = ICDPManager(cdp_manager).collaterals(cdp_id);
        // Generates debt in the CDP
        modify_cdp(
            cdp_manager,
            cdp_id,
            0,
            _get_borrow_delta_debt(cdp_engine, jug, cdp, col_type, wad)
        );
        // Moves the BEI amount (balance in the cdp_engine in rad) to proxy's address
        transfer_coin(cdp_manager, cdp_id, address(this), Math.to_rad(wad));
        // Allows adapter to access to proxy's BEI balance in the cdp_engine
        if (!ICDPEngine(cdp_engine).can(address(this), address(coin_join))) {
            ICDPEngine(cdp_engine).allow_account_modification(coin_join);
        }
        // Exits BEI to the user's wallet as a token
        ICoinJoin(coin_join).exit(msg.sender, wad);
    }

    // wipe
    function repay(
        address cdp_manager,
        address coin_join,
        uint256 cdp_id,
        uint256 wad
    ) public {
        address cdp_engine = ICDPManager(cdp_manager).cdp_engine();
        address cdp = ICDPManager(cdp_manager).positions(cdp_id);
        bytes32 col_type = ICDPManager(cdp_manager).collaterals(cdp_id);

        address owner = ICDPManager(cdp_manager).owner_of(cdp_id);
        if (
            owner == address(this)
                || ICDPManager(cdp_manager).cdp_can(owner, cdp_id, address(this))
        ) {
            // Joins BEI amount into the cdp_engine
            coin_join_join(coin_join, cdp, wad);
            // Paybacks debt to the CDP
            modify_cdp(
                cdp_manager,
                cdp_id,
                0,
                _get_repay_delta_debt(
                    cdp_engine, ICDPEngine(cdp_engine).coin(cdp), cdp, col_type
                )
            );
        } else {
            // Joins BEI amount into the cdp_engine
            coin_join_join(coin_join, address(this), wad);
            // Paybacks debt to the CDP
            ICDPEngine(cdp_engine).modify_cdp({
                col_type: col_type,
                cdp: cdp,
                gem_src: address(this),
                coin_dst: address(this),
                delta_col: 0,
                delta_debt: _get_repay_delta_debt(
                    cdp_engine, wad * RAY, cdp, col_type
                    )
            });
        }
    }

    // safeWipe
    function safe_repay(
        address cdp_manager,
        address coin_join,
        uint256 cdp_id,
        uint256 wad,
        address owner
    ) public {
        require(
            ICDPManager(cdp_manager).owner_of(cdp_id) == owner,
            "owner-missmatch"
        );
        repay(cdp_manager, coin_join, cdp_id, wad);
    }

    // wipeAll
    function repay_all(address cdp_manager, address coin_join, uint256 cdp_id)
        public
    {
        address cdp_engine = ICDPManager(cdp_manager).cdp_engine();
        address cdp = ICDPManager(cdp_manager).positions(cdp_id);
        bytes32 col_type = ICDPManager(cdp_manager).collaterals(cdp_id);
        ICDPEngine.Position memory pos =
            ICDPEngine(cdp_engine).positions(col_type, cdp);

        address owner = ICDPManager(cdp_manager).owner_of(cdp_id);
        if (
            owner == address(this)
                || ICDPManager(cdp_manager).cdp_can(owner, cdp_id, address(this))
        ) {
            // Joins BEI amount into the cdp_engine
            coin_join_join(
                coin_join,
                cdp,
                _get_repay_all_debt(cdp_engine, cdp, cdp, col_type)
            );
            // Paybacks debt to the CDP
            modify_cdp(cdp_manager, cdp_id, 0, -int256(pos.debt));
        } else {
            // Joins BEI amount into the cdp_engine
            coin_join_join(
                coin_join,
                address(this),
                _get_repay_all_debt(cdp_engine, address(this), cdp, col_type)
            );
            // Paybacks debt to the CDP
            ICDPEngine(cdp_engine).modify_cdp({
                col_type: col_type,
                cdp: cdp,
                gem_src: address(this),
                coin_dst: address(this),
                delta_col: 0,
                delta_debt: -int256(pos.debt)
            });
        }
    }

    // safeWipeAll
    function safe_repay_all(
        address cdp_manager,
        address coin_join,
        uint256 cdp_id,
        address owner
    ) public {
        require(
            ICDPManager(cdp_manager).owner_of(cdp_id) == owner,
            "owner-missmatch"
        );
        repay_all(cdp_manager, coin_join, cdp_id);
    }

    // lockETHAndDraw
    function lock_eth_and_borrow(
        address cdp_manager,
        address jug,
        address eth_join,
        address coin_join,
        uint256 cdp_id,
        uint256 coin_amount
    ) public payable {
        address cdp = ICDPManager(cdp_manager).positions(cdp_id);
        address cdp_engine = ICDPManager(cdp_manager).cdp_engine();
        bytes32 col_type = ICDPManager(cdp_manager).collaterals(cdp_id);
        // Receives ETH amount, converts it to WETH and joins it into the cdp_engine
        eth_join_join(eth_join, cdp);
        // Locks WETH amount into the CDP and generates debt
        modify_cdp(
            cdp_manager,
            cdp_id,
            Math.to_int(msg.value),
            _get_borrow_delta_debt(cdp_engine, jug, cdp, col_type, coin_amount)
        );
        // Moves the BEI amount (balance in the cdp_engine in rad) to proxy's address
        transfer_coin(
            cdp_manager, cdp_id, address(this), Math.to_rad(coin_amount)
        );
        // Allows adapter to access to proxy's BEI balance in the cdp_engine
        if (!ICDPEngine(cdp_engine).can(address(this), address(coin_join))) {
            ICDPEngine(cdp_engine).allow_account_modification(coin_join);
        }
        // Exits BEI to the user's wallet as a token
        ICoinJoin(coin_join).exit(msg.sender, coin_amount);
    }

    // openLockETHAndDraw
    function open_lock_eth_and_borrow(
        address cdp_manager,
        address jug,
        address eth_join,
        address coin_join,
        bytes32 col_type,
        uint256 coin_amount
    ) public payable returns (uint256 cdp_id) {
        cdp_id = open(cdp_manager, col_type, address(this));
        lock_eth_and_borrow(
            cdp_manager, jug, eth_join, coin_join, cdp_id, coin_amount
        );
    }

    // lockGemAndDraw
    function lock_gem_and_borrow(
        address cdp_manager,
        address jug,
        address gem_join,
        address coin_join,
        uint256 cdp_id,
        uint256 col_amount,
        uint256 coin_amount,
        bool is_tranfer_from
    ) public {
        address cdp = ICDPManager(cdp_manager).positions(cdp_id);
        address cdp_engine = ICDPManager(cdp_manager).cdp_engine();
        bytes32 col_type = ICDPManager(cdp_manager).collaterals(cdp_id);
        // Takes token amount from user's wallet and joins into the cdp_engine
        gem_join_join(gem_join, cdp, col_amount, is_tranfer_from);
        // Locks token amount into the CDP and generates debt
        modify_cdp(
            cdp_manager,
            cdp_id,
            Math.to_int(to_18_dec(gem_join, col_amount)),
            _get_borrow_delta_debt(cdp_engine, jug, cdp, col_type, coin_amount)
        );
        // Moves the BEI amount (balance in the cdp_engine in rad) to proxy's address
        transfer_coin(
            cdp_manager, cdp_id, address(this), Math.to_rad(coin_amount)
        );
        // Allows adapter to access to proxy's BEI balance in the cdp_engine
        if (!ICDPEngine(cdp_engine).can(address(this), address(coin_join))) {
            ICDPEngine(cdp_engine).allow_account_modification(coin_join);
        }
        // Exits BEI to the user's wallet as a token
        ICoinJoin(coin_join).exit(msg.sender, coin_amount);
    }

    // openLockGemAndDraw
    function open_lock_gem_and_borrow(
        address cdp_manager,
        address jug,
        address gem_join,
        address coin_join,
        bytes32 col_type,
        uint256 col_amount,
        uint256 coin_amount,
        bool is_tranfer_from
    ) public returns (uint256 cdp_id) {
        cdp_id = open(cdp_manager, col_type, address(this));
        lock_gem_and_borrow(
            cdp_manager,
            jug,
            gem_join,
            coin_join,
            cdp_id,
            col_amount,
            coin_amount,
            is_tranfer_from
        );
    }

    // TODO:
    // function openLockGNTAndDraw(
    //     address cdp_manager,
    //     address jug,
    //     address gntJoin,
    //     address coin_join,
    //     bytes32 col_type,
    //     uint256 col_amount,
    //     uint256 coin_amount
    // ) public returns (address bag, uint256 cdp_id) {
    //     // Creates bag (if doesn't exist) to hold GNT
    //     bag = GNTJoinLike(gntJoin).bags(address(this));
    //     if (bag == address(0)) {
    //         bag = makeGemBag(gntJoin);
    //     }
    //     // Transfer funds to the funds which previously were sent to the proxy
    //     IGem(IGemJoin(gntJoin).gem()).transfer(bag, col_amount);
    //     cdp_id = open_lock_gem_and_draw(
    //         cdp_manager, jug, gntJoin, coin_join, col_type, col_amount, coin_amount, false
    //     );
    // }

    // wipeAndFreeETH
    function repay_and_free_eth(
        address cdp_manager,
        address eth_join,
        address coin_join,
        uint256 cdp_id,
        uint256 col_amount,
        uint256 coin_amount
    ) public {
        address cdp = ICDPManager(cdp_manager).positions(cdp_id);
        address cdp_engine = ICDPManager(cdp_manager).cdp_engine();
        // Joins BEI amount into the cdp_engine
        coin_join_join(coin_join, cdp, coin_amount);
        // Paybacks debt to the CDP and unlocks WETH amount from it
        modify_cdp(
            cdp_manager,
            cdp_id,
            -Math.to_int(col_amount),
            _get_repay_delta_debt(
                cdp_engine,
                ICDPEngine(cdp_engine).coin(cdp),
                cdp,
                ICDPManager(cdp_manager).collaterals(cdp_id)
            )
        );
        // Moves the amount from the CDP cdp to proxy's address
        transfer_collateral(cdp_manager, cdp_id, address(this), col_amount);
        // Exits WETH amount to proxy address as a token
        IGemJoin(eth_join).exit(address(this), col_amount);
        // Converts WETH to ETH
        IWETH(address(IGemJoin(eth_join).gem())).withdraw(col_amount);
        // Sends ETH back to the user's wallet
        payable(msg.sender).transfer(col_amount);
    }

    // wipeAllAndFreeETH
    function repay_all_and_free_eth(
        address cdp_manager,
        address eth_join,
        address coin_join,
        uint256 cdp_id,
        uint256 col_amount
    ) public {
        address cdp_engine = ICDPManager(cdp_manager).cdp_engine();
        address cdp = ICDPManager(cdp_manager).positions(cdp_id);
        bytes32 col_type = ICDPManager(cdp_manager).collaterals(cdp_id);
        ICDPEngine.Position memory pos =
            ICDPEngine(cdp_engine).positions(col_type, cdp);

        // Joins BEI amount into the cdp_engine
        coin_join_join(
            coin_join, cdp, _get_repay_all_debt(cdp_engine, cdp, cdp, col_type)
        );
        // Paybacks debt to the CDP and unlocks WETH amount from it
        modify_cdp(
            cdp_manager, cdp_id, -Math.to_int(col_amount), -int256(pos.debt)
        );
        // Moves the amount from the CDP cdp to proxy's address
        transfer_collateral(cdp_manager, cdp_id, address(this), col_amount);
        // Exits WETH amount to proxy address as a token
        IGemJoin(eth_join).exit(address(this), col_amount);
        // Converts WETH to ETH
        IWETH(address(IGemJoin(eth_join).gem())).withdraw(col_amount);
        // Sends ETH back to the user's wallet
        payable(msg.sender).transfer(col_amount);
    }

    // wipeAndFreeGem
    function repay_and_free_gem(
        address cdp_manager,
        address gem_join,
        address coin_join,
        uint256 cdp_id,
        uint256 col_amount,
        uint256 coin_amount
    ) public {
        address cdp = ICDPManager(cdp_manager).positions(cdp_id);
        // Joins BEI amount into the cdp_engine
        coin_join_join(coin_join, cdp, coin_amount);
        uint256 col_wad = to_18_dec(gem_join, col_amount);
        // Paybacks debt to the CDP and unlocks token amount from it
        modify_cdp(
            cdp_manager,
            cdp_id,
            -Math.to_int(col_wad),
            _get_repay_delta_debt(
                ICDPManager(cdp_manager).cdp_engine(),
                ICDPEngine(ICDPManager(cdp_manager).cdp_engine()).coin(cdp),
                cdp,
                ICDPManager(cdp_manager).collaterals(cdp_id)
            )
        );
        // Moves the amount from the CDP cdp to proxy's address
        transfer_collateral(cdp_manager, cdp_id, address(this), col_wad);
        // Exits token amount to the user's wallet as a token
        IGemJoin(gem_join).exit(msg.sender, col_amount);
    }

    // wipeAllAndFreeGem
    function repay_all_and_free_gem(
        address cdp_manager,
        address gem_join,
        address coin_join,
        uint256 cdp_id,
        uint256 col_amount
    ) public {
        address cdp_engine = ICDPManager(cdp_manager).cdp_engine();
        address cdp = ICDPManager(cdp_manager).positions(cdp_id);
        bytes32 col_type = ICDPManager(cdp_manager).collaterals(cdp_id);
        ICDPEngine.Position memory pos =
            ICDPEngine(cdp_engine).positions(col_type, cdp);

        // Joins BEI amount into the cdp_engine
        coin_join_join(
            coin_join, cdp, _get_repay_all_debt(cdp_engine, cdp, cdp, col_type)
        );
        uint256 col_wad = to_18_dec(gem_join, col_amount);
        // Paybacks debt to the CDP and unlocks token amount from it
        modify_cdp(
            cdp_manager, cdp_id, -Math.to_int(col_wad), -int256(pos.debt)
        );
        // Moves the amount from the CDP cdp to proxy's address
        transfer_collateral(cdp_manager, cdp_id, address(this), col_wad);
        // Exits token amount to the user's wallet as a token
        IGemJoin(gem_join).exit(msg.sender, col_amount);
    }
}
