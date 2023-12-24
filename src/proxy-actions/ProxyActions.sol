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
    function to_wad(address gem_join, uint256 amount)
        internal
        returns (uint256 wad)
    {
        wad = amount * 10 ** (18 - IGemJoin(gem_join).decimals());
    }

    // _getDrawDart -> wad
    function get_borrow_delta_debt(
        address cdp_engine,
        address jug,
        address cdp,
        bytes32 col_type,
        uint256 coin_wad
    ) internal returns (int256 delta_debt) {
        // Updates stability fee rate
        uint256 rate = IJug(jug).collect_stability_fee(col_type);

        // Gets BEI balance of the cdp in the cdp_engine
        uint256 coin_bal = ICDPEngine(cdp_engine).coin(cdp);

        // If there was already enough BEI in the cdp_engine balance,
        // just exits it without adding more debt
        if (coin_wad * RAY > coin_bal) {
            // Calculates the needed delta debt so together with the existing BEI
            // in the cdp_engine is enough to exit wad amount of BEI tokens
            delta_debt = Math.to_int((coin_wad * RAY - coin_bal) / rate);
            // This is needed due lack of precision.
            // It might need to sum an extra delta debt wei (for the given BEI wad amount)
            delta_debt = uint256(delta_debt) * rate < coin_wad * RAY
                ? delta_debt - 1
                : delta_debt;
        }
    }

    // _getWipeDart -> wad
    function get_repay_delta_debt(
        address cdp_engine,
        uint256 coin_rad,
        address cdp,
        bytes32 col_type
    ) internal view returns (int256 delta_debt_wad) {
        // Gets actual rate from the cdp_engine
        ICDPEngine.Collateral memory c =
            ICDPEngine(cdp_engine).collaterals(col_type);
        // Gets actual debt value of the cdp
        ICDPEngine.Position memory pos =
            ICDPEngine(cdp_engine).positions(col_type, cdp);

        // Uses the whole coin_rad balance in the cdp_engine to reduce the debt
        delta_debt_wad = Math.to_int(coin_rad / c.rate_acc);
        // Checks the calculated delta_debt_wad is not higher than cdp.debt (total debt),
        // otherwise uses its value
        delta_debt_wad = uint256(delta_debt_wad) <= pos.debt
            ? -delta_debt_wad
            : -Math.to_int(pos.debt);
    }

    // _getWipeAllWad
    function get_repay_all_coin_wad(
        address cdp_engine,
        address user,
        address cdp,
        bytes32 col_type
    ) internal view returns (uint256 coin_wad) {
        // Gets actual rate from the cdp_engine
        ICDPEngine.Collateral memory c =
            ICDPEngine(cdp_engine).collaterals(col_type);
        // Gets actual debt value of the cdp
        ICDPEngine.Position memory pos =
            ICDPEngine(cdp_engine).positions(col_type, cdp);
        // Gets actual coin amount in the cdp
        uint256 coin_bal = ICDPEngine(cdp_engine).coin(user);

        uint256 rad = pos.debt * c.rate_acc - coin_bal;
        coin_wad = rad / RAY;

        // If the rad precision has some dust, it will need to request for 1 extra coin_wad wei
        coin_wad = coin_wad * RAY < rad ? coin_wad + 1 : coin_wad;
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
        uint256 gem_amount,
        bool is_transfer_from
    ) public {
        if (is_transfer_from) {
            IGem gem = IGem(IGemJoin(gem_join).gem());
            gem.transferFrom(msg.sender, address(this), gem_amount);
            gem.approve(gem_join, gem_amount);
        }
        IGemJoin(gem_join).join(cdp, gem_amount);
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
        uint256 gem_amount,
        bool is_tranfer_from
    ) public {
        // Takes token amount from user's wallet and joins into the cdp_engine
        gem_join_join(gem_join, address(this), gem_amount, is_tranfer_from);
        // Locks token amount into the CDP
        ICDPEngine(ICDPManager(cdp_manager).cdp_engine()).modify_cdp({
            col_type: ICDPManager(cdp_manager).collaterals(cdp_id),
            cdp: ICDPManager(cdp_manager).positions(cdp_id),
            gem_src: address(this),
            coin_dst: address(this),
            delta_col: Math.to_int(to_wad(gem_join, gem_amount)),
            delta_debt: 0
        });
    }

    // safeLockGem
    function safe_lock_gem(
        address cdp_manager,
        address gem_join,
        uint256 cdp_id,
        uint256 gem_amount,
        bool is_tranfer_from,
        address owner
    ) public {
        require(
            ICDPManager(cdp_manager).owner_of(cdp_id) == owner, "owner mismatch"
        );
        lock_gem(cdp_manager, gem_join, cdp_id, gem_amount, is_tranfer_from);
    }

    // freeETH
    function free_eth(
        address cdp_manager,
        address eth_join,
        uint256 cdp_id,
        uint256 eth_amount
    ) public {
        // Unlocks WETH amount from the CDP
        modify_cdp({
            cdp_manager: cdp_manager,
            cdp_id: cdp_id,
            delta_col: -Math.to_int(eth_amount),
            delta_debt: 0
        });
        // Moves the amount from the CDP cdp to proxy's address
        transfer_collateral(cdp_manager, cdp_id, address(this), eth_amount);
        // Exits WETH amount to proxy address as a token
        IGemJoin(eth_join).exit(address(this), eth_amount);
        // Converts WETH to ETH
        IWETH(address(IGemJoin(eth_join).gem())).withdraw(eth_amount);
        // Sends ETH back to the user's wallet
        payable(msg.sender).transfer(eth_amount);
    }

    // freeGem
    function free_gem(
        address cdp_manager,
        address gem_join,
        uint256 cdp_id,
        uint256 gem_amount
    ) public {
        uint256 wad = to_wad(gem_join, gem_amount);
        // Unlocks token amount from the CDP
        modify_cdp(cdp_manager, cdp_id, -Math.to_int(wad), 0);
        // Moves the amount from the CDP cdp to proxy's address
        transfer_collateral(cdp_manager, cdp_id, address(this), wad);
        // Exits token amount to the user's wallet as a token
        IGemJoin(gem_join).exit(msg.sender, gem_amount);
    }

    // exitETH
    function exit_eth(
        address cdp_manager,
        address eth_join,
        uint256 cdp_id,
        uint256 eth_amount
    ) public {
        // Moves the amount from the CDP cdp to proxy's address
        transfer_collateral(cdp_manager, cdp_id, address(this), eth_amount);
        // Exits WETH amount to proxy address as a token
        IGemJoin(eth_join).exit(address(this), eth_amount);
        // Converts WETH to ETH
        IWETH(address(IGemJoin(eth_join).gem())).withdraw(eth_amount);
        // Sends ETH back to the user's wallet
        payable(msg.sender).transfer(eth_amount);
    }

    // exitGem
    function exit_gem(
        address cdp_manager,
        address gem_join,
        uint256 cdp_id,
        uint256 gem_amount
    ) public {
        // Moves the gem_amount from the CDP cdp to proxy's address
        transfer_collateral(
            cdp_manager, cdp_id, address(this), to_wad(gem_join, gem_amount)
        );
        // Exits token gem_amount to the user's wallet as a token
        IGemJoin(gem_join).exit(msg.sender, gem_amount);
    }

    // draw
    function borrow(
        address cdp_manager,
        address jug,
        address coin_join,
        uint256 cdp_id,
        uint256 coin_wad
    ) public {
        address cdp = ICDPManager(cdp_manager).positions(cdp_id);
        address cdp_engine = ICDPManager(cdp_manager).cdp_engine();
        bytes32 col_type = ICDPManager(cdp_manager).collaterals(cdp_id);
        // Generates debt in the CDP
        modify_cdp({
            cdp_manager: cdp_manager,
            cdp_id: cdp_id,
            delta_col: 0,
            delta_debt: get_borrow_delta_debt({
                cdp_engine: cdp_engine,
                jug: jug,
                cdp: cdp,
                col_type: col_type,
                coin_wad: coin_wad
            })
        });
        // Moves the BEI amount (balance in the cdp_engine in rad) to proxy's address
        transfer_coin(cdp_manager, cdp_id, address(this), Math.to_rad(coin_wad));
        // Allows adapter to access to proxy's BEI balance in the cdp_engine
        if (!ICDPEngine(cdp_engine).can(address(this), address(coin_join))) {
            ICDPEngine(cdp_engine).allow_account_modification(coin_join);
        }
        // Exits BEI to the user's wallet as a token
        ICoinJoin(coin_join).exit(msg.sender, coin_wad);
    }

    // wipe
    function repay(
        address cdp_manager,
        address coin_join,
        uint256 cdp_id,
        uint256 coin_wad
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
            coin_join_join(coin_join, cdp, coin_wad);
            // Paybacks debt to the CDP
            modify_cdp({
                cdp_manager: cdp_manager,
                cdp_id: cdp_id,
                delta_col: 0,
                delta_debt: get_repay_delta_debt({
                    cdp_engine: cdp_engine,
                    coin_rad: ICDPEngine(cdp_engine).coin(cdp),
                    cdp: cdp,
                    col_type: col_type
                })
            });
        } else {
            // Joins BEI amount into the cdp_engine
            coin_join_join(coin_join, address(this), coin_wad);
            // Paybacks debt to the CDP
            ICDPEngine(cdp_engine).modify_cdp({
                col_type: col_type,
                cdp: cdp,
                gem_src: address(this),
                coin_dst: address(this),
                delta_col: 0,
                delta_debt: get_repay_delta_debt({
                    cdp_engine: cdp_engine,
                    coin_rad: coin_wad * RAY,
                    cdp: cdp,
                    col_type: col_type
                })
            });
        }
    }

    // safeWipe
    function safe_repay(
        address cdp_manager,
        address coin_join,
        uint256 cdp_id,
        uint256 coin_wad,
        address owner
    ) public {
        require(
            ICDPManager(cdp_manager).owner_of(cdp_id) == owner, "owner mismatch"
        );
        repay(cdp_manager, coin_join, cdp_id, coin_wad);
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
                get_repay_all_coin_wad(cdp_engine, cdp, cdp, col_type)
            );
            // Paybacks debt to the CDP
            modify_cdp({
                cdp_manager: cdp_manager,
                cdp_id: cdp_id,
                delta_col: 0,
                delta_debt: -int256(pos.debt)
            });
        } else {
            // Joins BEI amount into the cdp_engine
            coin_join_join(
                coin_join,
                address(this),
                get_repay_all_coin_wad(cdp_engine, address(this), cdp, col_type)
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
            ICDPManager(cdp_manager).owner_of(cdp_id) == owner, "owner mismatch"
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
        uint256 coin_wad
    ) public payable {
        address cdp = ICDPManager(cdp_manager).positions(cdp_id);
        address cdp_engine = ICDPManager(cdp_manager).cdp_engine();
        bytes32 col_type = ICDPManager(cdp_manager).collaterals(cdp_id);
        // Receives ETH amount, converts it to WETH and joins it into the cdp_engine
        eth_join_join(eth_join, cdp);
        // Locks WETH amount into the CDP and generates debt
        modify_cdp({
            cdp_manager: cdp_manager,
            cdp_id: cdp_id,
            delta_col: Math.to_int(msg.value),
            delta_debt: get_borrow_delta_debt({
                cdp_engine: cdp_engine,
                jug: jug,
                cdp: cdp,
                col_type: col_type,
                coin_wad: coin_wad
            })
        });
        // Moves the BEI amount (balance in the cdp_engine in rad) to proxy's address
        transfer_coin({
            cdp_manager: cdp_manager,
            cdp_id: cdp_id,
            dst: address(this),
            rad: Math.to_rad(coin_wad)
        });
        // Allows adapter to access to proxy's BEI balance in the cdp_engine
        if (!ICDPEngine(cdp_engine).can(address(this), address(coin_join))) {
            ICDPEngine(cdp_engine).allow_account_modification(coin_join);
        }
        // Exits BEI to the user's wallet as a token
        ICoinJoin(coin_join).exit(msg.sender, coin_wad);
    }

    // openLockETHAndDraw
    function open_lock_eth_and_borrow(
        address cdp_manager,
        address jug,
        address eth_join,
        address coin_join,
        bytes32 col_type,
        uint256 coin_wad
    ) public payable returns (uint256 cdp_id) {
        cdp_id = open(cdp_manager, col_type, address(this));
        lock_eth_and_borrow(
            cdp_manager, jug, eth_join, coin_join, cdp_id, coin_wad
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
        uint256 coin_wad,
        bool is_tranfer_from
    ) public {
        address cdp = ICDPManager(cdp_manager).positions(cdp_id);
        address cdp_engine = ICDPManager(cdp_manager).cdp_engine();
        bytes32 col_type = ICDPManager(cdp_manager).collaterals(cdp_id);
        // Takes token amount from user's wallet and joins into the cdp_engine
        gem_join_join(gem_join, cdp, col_amount, is_tranfer_from);
        // Locks token amount into the CDP and generates debt
        modify_cdp({
            cdp_manager: cdp_manager,
            cdp_id: cdp_id,
            delta_col: Math.to_int(to_wad(gem_join, col_amount)),
            delta_debt: get_borrow_delta_debt({
                cdp_engine: cdp_engine,
                jug: jug,
                cdp: cdp,
                col_type: col_type,
                coin_wad: coin_wad
            })
        });

        // Moves the BEI amount (balance in the cdp_engine in rad) to proxy's address
        transfer_coin({
            cdp_manager: cdp_manager,
            cdp_id: cdp_id,
            dst: address(this),
            rad: Math.to_rad(coin_wad)
        });
        // Allows adapter to access to proxy's BEI balance in the cdp_engine
        if (!ICDPEngine(cdp_engine).can(address(this), address(coin_join))) {
            ICDPEngine(cdp_engine).allow_account_modification(coin_join);
        }
        // Exits BEI to the user's wallet as a token
        ICoinJoin(coin_join).exit(msg.sender, coin_wad);
    }

    // openLockGemAndDraw
    function open_lock_gem_and_borrow(
        address cdp_manager,
        address jug,
        address gem_join,
        address coin_join,
        bytes32 col_type,
        uint256 col_amount,
        uint256 coin_wad,
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
            coin_wad,
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
    //     uint256 coin_wad
    // ) public returns (address bag, uint256 cdp_id) {
    //     // Creates bag (if doesn't exist) to hold GNT
    //     bag = GNTJoinLike(gntJoin).bags(address(this));
    //     if (bag == address(0)) {
    //         bag = makeGemBag(gntJoin);
    //     }
    //     // Transfer funds to the funds which previously were sent to the proxy
    //     IGem(IGemJoin(gntJoin).gem()).transfer(bag, col_amount);
    //     cdp_id = open_lock_gem_and_draw(
    //         cdp_manager, jug, gntJoin, coin_join, col_type, col_amount, coin_wad, false
    //     );
    // }

    // wipeAndFreeETH
    function repay_and_free_eth(
        address cdp_manager,
        address eth_join,
        address coin_join,
        uint256 cdp_id,
        uint256 col_wad,
        uint256 coin_wad
    ) public {
        address cdp = ICDPManager(cdp_manager).positions(cdp_id);
        address cdp_engine = ICDPManager(cdp_manager).cdp_engine();
        // Joins BEI amount into the cdp_engine
        coin_join_join(coin_join, cdp, coin_wad);
        // Paybacks debt to the CDP and unlocks WETH amount from it
        modify_cdp({
            cdp_manager: cdp_manager,
            cdp_id: cdp_id,
            delta_col: -Math.to_int(col_wad),
            delta_debt: get_repay_delta_debt({
                cdp_engine: cdp_engine,
                coin_rad: ICDPEngine(cdp_engine).coin(cdp),
                cdp: cdp,
                col_type: ICDPManager(cdp_manager).collaterals(cdp_id)
            })
        });
        // Moves the amount from the CDP to proxy's address
        transfer_collateral({
            cdp_manager: cdp_manager,
            cdp_id: cdp_id,
            dst: address(this),
            wad: col_wad
        });
        // Exits WETH amount to proxy address as a token
        IGemJoin(eth_join).exit(address(this), col_wad);
        // Converts WETH to ETH
        IWETH(address(IGemJoin(eth_join).gem())).withdraw(col_wad);
        // Sends ETH back to the user's wallet
        payable(msg.sender).transfer(col_wad);
    }

    // wipeAllAndFreeETH
    function repay_all_and_free_eth(
        address cdp_manager,
        address eth_join,
        address coin_join,
        uint256 cdp_id,
        uint256 col_wad
    ) public {
        address cdp_engine = ICDPManager(cdp_manager).cdp_engine();
        address cdp = ICDPManager(cdp_manager).positions(cdp_id);
        bytes32 col_type = ICDPManager(cdp_manager).collaterals(cdp_id);
        ICDPEngine.Position memory pos =
            ICDPEngine(cdp_engine).positions(col_type, cdp);

        // Joins BEI amount into the cdp_engine
        coin_join_join(
            coin_join,
            cdp,
            get_repay_all_coin_wad(cdp_engine, cdp, cdp, col_type)
        );
        // Paybacks debt to the CDP and unlocks WETH amount from it
        modify_cdp({
            cdp_manager: cdp_manager,
            cdp_id: cdp_id,
            delta_col: -Math.to_int(col_wad),
            delta_debt: -int256(pos.debt)
        });
        // Moves the amount from the CDP cdp to proxy's address
        transfer_collateral(cdp_manager, cdp_id, address(this), col_wad);
        // Exits WETH amount to proxy address as a token
        IGemJoin(eth_join).exit(address(this), col_wad);
        // Converts WETH to ETH
        IWETH(address(IGemJoin(eth_join).gem())).withdraw(col_wad);
        // Sends ETH back to the user's wallet
        payable(msg.sender).transfer(col_wad);
    }

    // wipeAndFreeGem
    function repay_and_free_gem(
        address cdp_manager,
        address gem_join,
        address coin_join,
        uint256 cdp_id,
        uint256 col_amount,
        uint256 coin_wad
    ) public {
        address cdp = ICDPManager(cdp_manager).positions(cdp_id);
        // Joins BEI amount into the cdp_engine
        coin_join_join(coin_join, cdp, coin_wad);
        uint256 col_wad = to_wad(gem_join, col_amount);
        // Paybacks debt to the CDP and unlocks token amount from it
        modify_cdp({
            cdp_manager: cdp_manager,
            cdp_id: cdp_id,
            delta_col: -Math.to_int(col_wad),
            delta_debt: get_repay_delta_debt({
                cdp_engine: ICDPManager(cdp_manager).cdp_engine(),
                coin_rad: ICDPEngine(ICDPManager(cdp_manager).cdp_engine()).coin(cdp),
                cdp: cdp,
                col_type: ICDPManager(cdp_manager).collaterals(cdp_id)
            })
        });
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
            coin_join,
            cdp,
            get_repay_all_coin_wad(cdp_engine, cdp, cdp, col_type)
        );
        uint256 col_wad = to_wad(gem_join, col_amount);
        // Paybacks debt to the CDP and unlocks token amount from it
        modify_cdp({
            cdp_manager: cdp_manager,
            cdp_id: cdp_id,
            delta_col: -Math.to_int(col_wad),
            delta_debt: -int256(pos.debt)
        });
        // Moves the amount from the CDP cdp to proxy's address
        transfer_collateral({
            cdp_manager: cdp_manager,
            cdp_id: cdp_id,
            dst: address(this),
            wad: col_wad
        });
        // Exits token amount to the user's wallet as a token
        IGemJoin(gem_join).exit(msg.sender, col_amount);
    }
}
