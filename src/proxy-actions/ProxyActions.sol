// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import {IWETH} from "../interfaces/IWETH.sol";
import {IGem} from "../interfaces/IGem.sol";
import {ICoin} from "../interfaces/ICoin.sol";
import {ICoinJoin} from "../interfaces/ICoinJoin.sol";
import {IGemJoin} from "../interfaces/IGemJoin.sol";
import {IAccount} from "../interfaces/IAccount.sol";
import {ISafeManager} from "../interfaces/ISafeManager.sol";
import {ISafeEngine} from "../interfaces/ISafeEngine.sol";
import {IJug} from "../interfaces/IJug.sol";
import "../lib/Math.sol";
import {Common} from "./Common.sol";

contract ProxyActions is Common {
    function to_18_dec(address gem_join, uint256 amount)
        internal
        returns (uint256 wad)
    {
        wad = amount * 10 ** (18 - IGemJoin(gem_join).decimals());
    }

    // _get_add_delta_debt
    function _get_add_delta_debt(
        address safe_engine,
        address jug,
        address safe,
        bytes32 col_type,
        uint256 wad
    ) internal returns (int256 delta_debt) {
        // TODO: why drip?
        // Updates stability fee rate
        uint256 rate = IJug(jug).drip(col_type);

        // Gets DAI balance of the safe in the safe_engine
        uint256 coin_bal = ISafeEngine(safe_engine).coin(safe);

        // If there was already enough DAI in the safe_engine balance,
        // just exits it without adding more debt
        if (coin_bal < wad * RAY) {
            // Calculates the needed delta debt so together with the existing dai
            // in the safe_engine is enough to exit wad amount of DAI tokens
            delta_debt = Math.to_int((wad * RAY - coin_bal) / rate);
            // TODO: wat dis?
            // This is needed due lack of precision.
            // It might need to sum an extra delta debt wei (for the given DAI wad amount)
            delta_debt = uint256(delta_debt) * rate < wad * RAY
                ? delta_debt - 1
                : delta_debt;
        }
    }

    // _get_remove_delta_debt
    function _get_remove_delta_debt(
        address safe_engine,
        // TODO: wad, ray or rad?
        uint256 coin_amount,
        address safe,
        bytes32 col_type
    ) internal view returns (int256 delta_debt) {
        // Gets actual rate from the safe_engine
        ISafeEngine.Collateral memory c =
            ISafeEngine(safe_engine).collaterals(col_type);
        // Gets actual debt value of the safe
        ISafeEngine.Safe memory s =
            ISafeEngine(safe_engine).safes(col_type, safe);

        // Uses the whole coin_amount balance in the safe_engine to reduce the debt
        delta_debt = Math.to_int(coin_amount / c.rate);
        // Checks the calculated delta_debt is not higher than safe.debt (total debt),
        // otherwise uses its value
        delta_debt =
            uint256(delta_debt) <= s.debt ? -delta_debt : -Math.to_int(s.debt);
    }

    // _get_remove_all_debt
    function _get_remove_all_debt(
        address safe_engine,
        address user,
        address safe,
        bytes32 col_type
    ) internal view returns (uint256 wad) {
        // Gets actual rate from the safe_engine
        ISafeEngine.Collateral memory c =
            ISafeEngine(safe_engine).collaterals(col_type);
        // Gets actual debt value of the safe
        ISafeEngine.Safe memory s =
            ISafeEngine(safe_engine).safes(col_type, safe);
        // Gets actual coin amount in the safe
        uint256 coin_bal = ISafeEngine(safe_engine).coin(user);

        uint256 rad = s.debt * c.rate - coin_bal;
        wad = rad / RAY;

        // If the rad precision has some dust, it will need to request for 1 extra wad wei
        wad = wad * RAY < rad ? wad + 1 : wad;
    }

    function transfer(address gem, address dst, uint256 amount) public {
        IGem(gem).transfer(dst, amount);
    }

    function eth_join_join(address gem_join, address safe) public payable {
        IWETH weth = IWETH(address(IGemJoin(gem_join).gem()));
        // Wraps ETH in WETH
        weth.deposit{value: msg.value}();
        // Approves adapter to take the WETH amount
        weth.approve(address(gem_join), msg.value);
        // Joins WETH collateral into the safe_engine
        IGemJoin(gem_join).join(safe, msg.value);
    }

    function gem_join_join(
        address gem_join,
        address safe,
        uint256 amount,
        bool is_transfer_from
    ) public {
        if (is_transfer_from) {
            IGem gem = IGemJoin(gem_join).gem();
            gem.transferFrom(msg.sender, address(this), amount);
            gem.approve(gem_join, amount);
        }
        IGemJoin(gem_join).join(safe, amount);
    }

    // hope
    function allow_account_modification(address acc, address user) public {
        IAccount(acc).allow_account_modification(user);
    }

    // nope
    function deny_account_modification(address acc, address user) public {
        IAccount(acc).deny_account_modification(user);
    }

    function open(address safe_manager, bytes32 col_type, address user)
        public
        returns (uint256 safe_id)
    {
        safe_id = ISafeManager(safe_manager).open(col_type, user);
    }

    // TODO: wat dis?
    function give(address safe_manager, uint256 safe_id, address user) public {
        ISafeManager(safe_manager).give(safe_id, user);
    }

    // TODO:
    // function giveToProxy(
    //     address proxyRegistry,
    //     address safe_manager,
    //     uint safe_id,
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
    //         // We want to avoid creating a proxy for a contract address that might not be able to handle proxies, then losing the safe_id
    //         require(csize == 0, "Dst-is-a-contract");
    //         // Creates the proxy for the dst address
    //         proxy = ProxyRegistryLike(proxyRegistry).build(dst);
    //     }
    //     // Transfers safe_id to the dst proxy
    //     give(safe_manager, safe_id, proxy);
    // }

    // cdpAllow
    function allow_safe(
        address safe_manager,
        uint256 safe_id,
        address user,
        bool ok
    ) public {
        ISafeManager(safe_manager).allow_safe(safe_id, user, ok);
    }

    // urnAllow
    function allow_safe_handler(address safe_manager, address user, bool ok)
        public
    {
        ISafeManager(safe_manager).allow_safe_handler(user, ok);
    }

    // flux
    function transfer_collateral(
        address safe_manager,
        uint256 safe_id,
        address dst,
        uint256 wad
    ) public {
        ISafeManager(safe_manager).transfer_collateral(safe_id, dst, wad);
    }

    // move
    function transfer_coin(
        address safe_manager,
        uint256 safe_id,
        address dst,
        uint256 rad
    ) public {
        ISafeManager(safe_manager).transfer_coin(safe_id, dst, rad);
    }

    // frob
    function modify_safe(
        address safe_manager,
        uint256 safe_id,
        int256 delta_col,
        int256 delta_debt
    ) public {
        ISafeManager(safe_manager).modify_safe(safe_id, delta_col, delta_debt);
    }

    function quit(address safe_manager, uint256 safe_id, address dst) public {
        ISafeManager(safe_manager).quit(safe_id, dst);
    }

    function enter(address safe_manager, address src, uint256 safe_id) public {
        ISafeManager(safe_manager).enter(src, safe_id);
    }

    function shift(address safe_manager, uint256 safe_src, uint256 safe_dst)
        public
    {
        ISafeManager(safe_manager).shift(safe_src, safe_dst);
    }

    // TODO: wat dis?
    // function makeGemBag(
    //     address gem_join
    // ) public returns (address bag) {
    //     bag = GNTJoinLike(gem_join).make(address(this));
    // }

    function lock_eth(address safe_manager, address eth_join, uint256 safe_id)
        public
        payable
    {
        // Receives ETH amount, converts it to WETH and joins it into the safe_engine
        eth_join_join(eth_join, address(this));
        // Locks WETH amount into the CDP
        ISafeEngine(ISafeManager(safe_manager).safe_engine()).modify_safe({
            col_type: ISafeManager(safe_manager).collaterals(safe_id),
            safe: ISafeManager(safe_manager).safes(safe_id),
            col_src: address(this),
            debt_dst: address(this),
            delta_col: Math.to_int(msg.value),
            delta_debt: 0
        });
    }

    function safe_lock_eth(
        address safe_manager,
        address eth_join,
        uint256 safe_id,
        address owner
    ) public payable {
        require(
            ISafeManager(safe_manager).owner_of(safe_id) == owner,
            "owner missmatch"
        );
        lock_eth(safe_manager, eth_join, safe_id);
    }

    function lock_gem(
        address safe_manager,
        address gem_join,
        uint256 safe_id,
        uint256 amt,
        bool is_tranfer_from
    ) public {
        // Takes token amount from user's wallet and joins into the safe_engine
        gem_join_join(gem_join, address(this), amt, is_tranfer_from);
        // Locks token amount into the CDP
        ISafeEngine(ISafeManager(safe_manager).safe_engine()).modify_safe({
            col_type: ISafeManager(safe_manager).collaterals(safe_id),
            safe: ISafeManager(safe_manager).safes(safe_id),
            col_src: address(this),
            debt_dst: address(this),
            delta_col: Math.to_int(to_18_dec(gem_join, amt)),
            delta_debt: 0
        });
    }

    function safe_lock_gem(
        address safe_manager,
        address gem_join,
        uint256 safe_id,
        uint256 amt,
        bool is_tranfer_from,
        address owner
    ) public {
        require(
            ISafeManager(safe_manager).owner_of(safe_id) == owner,
            "owner missmatch"
        );
        lock_gem(safe_manager, gem_join, safe_id, amt, is_tranfer_from);
    }

    function free_eth(
        address safe_manager,
        address eth_join,
        uint256 safe_id,
        uint256 wad
    ) public {
        // Unlocks WETH amount from the CDP
        modify_safe(safe_manager, safe_id, -Math.to_int(wad), 0);
        // Moves the amount from the CDP safe to proxy's address
        transfer_collateral(safe_manager, safe_id, address(this), wad);
        // Exits WETH amount to proxy address as a token
        IGemJoin(eth_join).exit(address(this), wad);
        // Converts WETH to ETH
        IWETH(address(IGemJoin(eth_join).gem())).withdraw(wad);
        // Sends ETH back to the user's wallet
        payable(msg.sender).transfer(wad);
    }

    function free_gem(
        address safe_manager,
        address gem_join,
        uint256 safe_id,
        uint256 amt
    ) public {
        uint256 wad = to_18_dec(gem_join, amt);
        // Unlocks token amount from the CDP
        modify_safe(safe_manager, safe_id, -Math.to_int(wad), 0);
        // Moves the amount from the CDP safe to proxy's address
        transfer_collateral(safe_manager, safe_id, address(this), wad);
        // Exits token amount to the user's wallet as a token
        IGemJoin(gem_join).exit(msg.sender, amt);
    }

    function exit_eth(
        address safe_manager,
        address eth_join,
        uint256 safe_id,
        uint256 wad
    ) public {
        // Moves the amount from the CDP safe to proxy's address
        transfer_collateral(safe_manager, safe_id, address(this), wad);

        // Exits WETH amount to proxy address as a token
        IGemJoin(eth_join).exit(address(this), wad);
        // Converts WETH to ETH
        IWETH(address(IGemJoin(eth_join).gem())).withdraw(wad);
        // Sends ETH back to the user's wallet
        payable(msg.sender).transfer(wad);
    }

    function exit_gem(
        address safe_manager,
        address gem_join,
        uint256 safe_id,
        uint256 amt
    ) public {
        // Moves the amount from the CDP safe to proxy's address
        transfer_collateral(
            safe_manager, safe_id, address(this), to_18_dec(gem_join, amt)
        );
        // Exits token amount to the user's wallet as a token
        IGemJoin(gem_join).exit(msg.sender, amt);
    }

    // draw
    // TODO: rename
    function draw(
        address safe_manager,
        address jug,
        address coin_join,
        uint256 safe_id,
        uint256 wad
    ) public {
        address safe = ISafeManager(safe_manager).safes(safe_id);
        address safe_engine = ISafeManager(safe_manager).safe_engine();
        bytes32 col_type = ISafeManager(safe_manager).collaterals(safe_id);
        // Generates debt in the CDP
        modify_safe(
            safe_manager,
            safe_id,
            0,
            _get_add_delta_debt(safe_engine, jug, safe, col_type, wad)
        );
        // Moves the DAI amount (balance in the safe_engine in rad) to proxy's address
        transfer_coin(safe_manager, safe_id, address(this), Math.to_rad(wad));
        // Allows adapter to access to proxy's DAI balance in the safe_engine
        if (!ISafeEngine(safe_engine).can(address(this), address(coin_join))) {
            ISafeEngine(safe_engine).allow_account_modification(coin_join);
        }
        // Exits DAI to the user's wallet as a token
        ICoinJoin(coin_join).exit(msg.sender, wad);
    }

    // wipe
    // TODO: rename
    function wipe(
        address safe_manager,
        address coin_join,
        uint256 safe_id,
        uint256 wad
    ) public {
        address safe_engine = ISafeManager(safe_manager).safe_engine();
        address safe = ISafeManager(safe_manager).safes(safe_id);
        bytes32 col_type = ISafeManager(safe_manager).collaterals(safe_id);

        address owner = ISafeManager(safe_manager).owner_of(safe_id);
        if (
            owner == address(this)
                || ISafeManager(safe_manager).safe_can(
                    owner, safe_id, address(this)
                )
        ) {
            // Joins DAI amount into the safe_engine
            coin_join_join(coin_join, safe, wad);
            // Paybacks debt to the CDP
            modify_safe(
                safe_manager,
                safe_id,
                0,
                _get_remove_delta_debt(
                    safe_engine,
                    ISafeEngine(safe_engine).coin(safe),
                    safe,
                    col_type
                )
            );
        } else {
            // Joins DAI amount into the safe_engine
            coin_join_join(coin_join, address(this), wad);
            // Paybacks debt to the CDP
            ISafeEngine(safe_engine).modify_safe({
                col_type: col_type,
                safe: safe,
                col_src: address(this),
                debt_dst: address(this),
                delta_col: 0,
                delta_debt: _get_remove_delta_debt(
                    safe_engine, wad * RAY, safe, col_type
                    )
            });
        }
    }

    function safe_wipe(
        address safe_manager,
        address coin_join,
        uint256 safe_id,
        uint256 wad,
        address owner
    ) public {
        require(
            ISafeManager(safe_manager).owner_of(safe_id) == owner,
            "owner-missmatch"
        );
        wipe(safe_manager, coin_join, safe_id, wad);
    }

    function wipe_all(address safe_manager, address coin_join, uint256 safe_id)
        public
    {
        address safe_engine = ISafeManager(safe_manager).safe_engine();
        address safe = ISafeManager(safe_manager).safes(safe_id);
        bytes32 col_type = ISafeManager(safe_manager).collaterals(safe_id);
        ISafeEngine.Safe memory s =
            ISafeEngine(safe_engine).safes(col_type, safe);

        address owner = ISafeManager(safe_manager).owner_of(safe_id);
        if (
            owner == address(this)
                || ISafeManager(safe_manager).safe_can(
                    owner, safe_id, address(this)
                )
        ) {
            // Joins DAI amount into the safe_engine
            coin_join_join(
                coin_join,
                safe,
                _get_remove_all_debt(safe_engine, safe, safe, col_type)
            );
            // Paybacks debt to the CDP
            modify_safe(safe_manager, safe_id, 0, -int256(s.debt));
        } else {
            // Joins DAI amount into the safe_engine
            coin_join_join(
                coin_join,
                address(this),
                _get_remove_all_debt(safe_engine, address(this), safe, col_type)
            );
            // Paybacks debt to the CDP
            ISafeEngine(safe_engine).modify_safe({
                col_type: col_type,
                safe: safe,
                col_src: address(this),
                debt_dst: address(this),
                delta_col: 0,
                delta_debt: -int256(s.debt)
            });
        }
    }

    function safe_wipe_all(
        address safe_manager,
        address coin_join,
        uint256 safe_id,
        address owner
    ) public {
        require(
            ISafeManager(safe_manager).owner_of(safe_id) == owner,
            "owner-missmatch"
        );
        wipe_all(safe_manager, coin_join, safe_id);
    }

    // lockETHAndDraw
    function lock_eth_and_draw(
        address safe_manager,
        address jug,
        address eth_join,
        address coin_join,
        uint256 safe_id,
        uint256 wadD
    ) public payable {
        address safe = ISafeManager(safe_manager).safes(safe_id);
        address safe_engine = ISafeManager(safe_manager).safe_engine();
        bytes32 col_type = ISafeManager(safe_manager).collaterals(safe_id);
        // Receives ETH amount, converts it to WETH and joins it into the safe_engine
        eth_join_join(eth_join, safe);
        // Locks WETH amount into the CDP and generates debt
        modify_safe(
            safe_manager,
            safe_id,
            Math.to_int(msg.value),
            _get_add_delta_debt(safe_engine, jug, safe, col_type, wadD)
        );
        // Moves the DAI amount (balance in the safe_engine in rad) to proxy's address
        transfer_coin(safe_manager, safe_id, address(this), Math.to_rad(wadD));
        // Allows adapter to access to proxy's DAI balance in the safe_engine
        if (!ISafeEngine(safe_engine).can(address(this), address(coin_join))) {
            ISafeEngine(safe_engine).allow_account_modification(coin_join);
        }
        // Exits DAI to the user's wallet as a token
        ICoinJoin(coin_join).exit(msg.sender, wadD);
    }

    // openLockETHAndDraw
    function open_lock_eth_and_draw(
        address safe_manager,
        address jug,
        address eth_join,
        address coin_join,
        bytes32 col_type,
        uint256 wadD
    ) public payable returns (uint256 safe_id) {
        safe_id = open(safe_manager, col_type, address(this));
        lock_eth_and_draw(safe_manager, jug, eth_join, coin_join, safe_id, wadD);
    }

    function lock_gem_and_draw(
        address safe_manager,
        address jug,
        address gem_join,
        address coin_join,
        uint256 safe_id,
        uint256 amtC,
        uint256 wadD,
        bool is_tranfer_from
    ) public {
        address safe = ISafeManager(safe_manager).safes(safe_id);
        address safe_engine = ISafeManager(safe_manager).safe_engine();
        bytes32 col_type = ISafeManager(safe_manager).collaterals(safe_id);
        // Takes token amount from user's wallet and joins into the safe_engine
        gem_join_join(gem_join, safe, amtC, is_tranfer_from);
        // Locks token amount into the CDP and generates debt
        modify_safe(
            safe_manager,
            safe_id,
            Math.to_int(to_18_dec(gem_join, amtC)),
            _get_add_delta_debt(safe_engine, jug, safe, col_type, wadD)
        );
        // Moves the DAI amount (balance in the safe_engine in rad) to proxy's address
        transfer_coin(safe_manager, safe_id, address(this), Math.to_rad(wadD));
        // Allows adapter to access to proxy's DAI balance in the safe_engine
        if (!ISafeEngine(safe_engine).can(address(this), address(coin_join))) {
            ISafeEngine(safe_engine).allow_account_modification(coin_join);
        }
        // Exits DAI to the user's wallet as a token
        ICoinJoin(coin_join).exit(msg.sender, wadD);
    }

    function open_lock_gem_and_draw(
        address safe_manager,
        address jug,
        address gem_join,
        address coin_join,
        bytes32 col_type,
        uint256 amtC,
        uint256 wadD,
        bool is_tranfer_from
    ) public returns (uint256 safe_id) {
        safe_id = open(safe_manager, col_type, address(this));
        lock_gem_and_draw(
            safe_manager,
            jug,
            gem_join,
            coin_join,
            safe_id,
            amtC,
            wadD,
            is_tranfer_from
        );
    }

    // TODO:
    // function openLockGNTAndDraw(
    //     address safe_manager,
    //     address jug,
    //     address gntJoin,
    //     address coin_join,
    //     bytes32 col_type,
    //     uint256 amtC,
    //     uint256 wadD
    // ) public returns (address bag, uint256 safe_id) {
    //     // Creates bag (if doesn't exist) to hold GNT
    //     bag = GNTJoinLike(gntJoin).bags(address(this));
    //     if (bag == address(0)) {
    //         bag = makeGemBag(gntJoin);
    //     }
    //     // Transfer funds to the funds which previously were sent to the proxy
    //     IGem(IGemJoin(gntJoin).gem()).transfer(bag, amtC);
    //     safe_id = open_lock_gem_and_draw(
    //         safe_manager, jug, gntJoin, coin_join, col_type, amtC, wadD, false
    //     );
    // }

    function wipe_and_free_eth(
        address safe_manager,
        address eth_join,
        address coin_join,
        uint256 safe_id,
        uint256 wadC,
        uint256 wadD
    ) public {
        address safe = ISafeManager(safe_manager).safes(safe_id);
        address safe_engine = ISafeManager(safe_manager).safe_engine();
        // Joins DAI amount into the safe_engine
        coin_join_join(coin_join, safe, wadD);
        // Paybacks debt to the CDP and unlocks WETH amount from it
        modify_safe(
            safe_manager,
            safe_id,
            -Math.to_int(wadC),
            _get_remove_delta_debt(
                safe_engine,
                ISafeEngine(safe_engine).coin(safe),
                safe,
                ISafeManager(safe_manager).collaterals(safe_id)
            )
        );
        // Moves the amount from the CDP safe to proxy's address
        transfer_collateral(safe_manager, safe_id, address(this), wadC);
        // Exits WETH amount to proxy address as a token
        IGemJoin(eth_join).exit(address(this), wadC);
        // Converts WETH to ETH
        IWETH(address(IGemJoin(eth_join).gem())).withdraw(wadC);
        // Sends ETH back to the user's wallet
        payable(msg.sender).transfer(wadC);
    }

    function wipe_all_and_free_eth(
        address safe_manager,
        address eth_join,
        address coin_join,
        uint256 safe_id,
        uint256 wadC
    ) public {
        address safe_engine = ISafeManager(safe_manager).safe_engine();
        address safe = ISafeManager(safe_manager).safes(safe_id);
        bytes32 col_type = ISafeManager(safe_manager).collaterals(safe_id);
        ISafeEngine.Safe memory s =
            ISafeEngine(safe_engine).safes(col_type, safe);

        // Joins DAI amount into the safe_engine
        coin_join_join(
            coin_join,
            safe,
            _get_remove_all_debt(safe_engine, safe, safe, col_type)
        );
        // Paybacks debt to the CDP and unlocks WETH amount from it
        modify_safe(safe_manager, safe_id, -Math.to_int(wadC), -int256(s.debt));
        // Moves the amount from the CDP safe to proxy's address
        transfer_collateral(safe_manager, safe_id, address(this), wadC);
        // Exits WETH amount to proxy address as a token
        IGemJoin(eth_join).exit(address(this), wadC);
        // Converts WETH to ETH
        IWETH(address(IGemJoin(eth_join).gem())).withdraw(wadC);
        // Sends ETH back to the user's wallet
        payable(msg.sender).transfer(wadC);
    }

    // wipeAndFreeGem
    function wipe_and_free_gem(
        address safe_manager,
        address gem_join,
        address coin_join,
        uint256 safe_id,
        uint256 amtC,
        uint256 wadD
    ) public {
        address safe = ISafeManager(safe_manager).safes(safe_id);
        // Joins DAI amount into the safe_engine
        coin_join_join(coin_join, safe, wadD);
        uint256 wadC = to_18_dec(gem_join, amtC);
        // Paybacks debt to the CDP and unlocks token amount from it
        modify_safe(
            safe_manager,
            safe_id,
            -Math.to_int(wadC),
            _get_remove_delta_debt(
                ISafeManager(safe_manager).safe_engine(),
                ISafeEngine(ISafeManager(safe_manager).safe_engine()).coin(safe),
                safe,
                ISafeManager(safe_manager).collaterals(safe_id)
            )
        );
        // Moves the amount from the CDP safe to proxy's address
        transfer_collateral(safe_manager, safe_id, address(this), wadC);
        // Exits token amount to the user's wallet as a token
        IGemJoin(gem_join).exit(msg.sender, amtC);
    }

    // wipeAllAndFreeGem
    function wipe_all_and_free_gem(
        address safe_manager,
        address gem_join,
        address coin_join,
        uint256 safe_id,
        uint256 amtC
    ) public {
        address safe_engine = ISafeManager(safe_manager).safe_engine();
        address safe = ISafeManager(safe_manager).safes(safe_id);
        bytes32 col_type = ISafeManager(safe_manager).collaterals(safe_id);
        ISafeEngine.Safe memory s =
            ISafeEngine(safe_engine).safes(col_type, safe);

        // Joins DAI amount into the safe_engine
        coin_join_join(
            coin_join,
            safe,
            _get_remove_all_debt(safe_engine, safe, safe, col_type)
        );
        uint256 wadC = to_18_dec(gem_join, amtC);
        // Paybacks debt to the CDP and unlocks token amount from it
        modify_safe(safe_manager, safe_id, -Math.to_int(wadC), -int256(s.debt));
        // Moves the amount from the CDP safe to proxy's address
        transfer_collateral(safe_manager, safe_id, address(this), wadC);
        // Exits token amount to the user's wallet as a token
        IGemJoin(gem_join).exit(msg.sender, amtC);
    }
}
