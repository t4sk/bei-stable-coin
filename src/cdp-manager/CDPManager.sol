// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import {ICDPEngine} from "../interfaces/ICDPEngine.sol";
import {ICDPManager} from "../interfaces/ICDPManager.sol";
import "../lib/Math.sol";
import {CDPHandler} from "./CDPHandler.sol";

// DssCdpManager
contract CDPManager {
    event OpenCDP(
        address indexed user, address indexed owner, uint256 indexed cdp_id
    );

    // vat
    address public immutable cdp_engine;
    // cdpi
    uint256 public last_safe_id;
    // urns
    // safe id => CDPHandler
    mapping(uint256 => address) public positions;
    // list
    // safe id => prev & next safe ids (double linked list)
    mapping(uint256 => ICDPManager.List) public list;
    // owns
    // safe id => owner of safe
    mapping(uint256 => address) public owner_of;
    // ilks
    // safe id => collateral types
    mapping(uint256 => bytes32) public collaterals;

    // first
    // owner => first safe id
    mapping(address => uint256) public first;
    // last
    // owner => last safe id
    mapping(address => uint256) public last;
    // count
    // owner => amount of safe handlers
    mapping(address => uint256) public count;

    // cdpCan - permission to modify safe by addr
    // owner => safe id => addr => allowed
    mapping(address => mapping(uint256 => mapping(address => bool))) public
        safe_can;

    // urnCan
    // CDPHandler => addr => allowed
    mapping(address => mapping(address => bool)) public safe_handler_can;

    // cdpAllowed - msg.sender is safe owner or safe owner has given permission to msg.sender
    modifier cdp_allowed(uint256 cdp_id) {
        address owner = owner_of[cdp_id];
        require(
            msg.sender == owner || safe_can[owner][cdp_id][msg.sender],
            "safe not allowed"
        );
        _;
    }

    // TODO: wat dis?
    // urnAllowed
    modifier cdp_handler_allowed(address user) {
        require(
            msg.sender == user || safe_handler_can[user][msg.sender],
            "safe handler not allowed"
        );
        _;
    }

    constructor(address _safe_engine) {
        cdp_engine = _safe_engine;
    }

    // cdpAllow
    // Allow / disallow user to manage the safe.
    function allow_cdp(uint256 cdp_id, address user, bool ok)
        public
        cdp_allowed(cdp_id)
    {
        safe_can[owner_of[cdp_id]][cdp_id][user] = ok;
    }

    // urnAllow
    // Allow / disallow user to quit to msg.sender's safe handler.
    function allow_cdp_handler(address user, bool ok) public {
        safe_handler_can[msg.sender][user] = ok;
    }

    // open
    // Open a new safe for a given user address.
    function open(bytes32 col_type, address user) public returns (uint256) {
        require(user != address(0), "user = zero address");

        // increment and then assign to var
        uint256 id = ++last_safe_id;

        positions[id] = address(new CDPHandler(cdp_engine));
        owner_of[id] = user;
        collaterals[id] = col_type;

        // TODO: learn doubly linked list algo
        // Add new safe to double linked list and pointers
        if (first[user] == 0) {
            first[user] = id;
        }
        if (last[user] != 0) {
            list[id].prev = last[user];
            list[last[user]].next = id;
        }
        last[user] = id;
        count[user] += 1;

        emit OpenCDP(msg.sender, user, id);
        return id;
    }

    // give
    // Give the safe ownership to a dst address.
    function give(uint256 cdp_id, address dst) public cdp_allowed(cdp_id) {
        require(dst != address(0), "dst = 0 address");
        require(dst != owner_of[cdp_id], "dst is already owner");

        // TODO: learn doubly linked list algo
        // Remove transferred cdp_id from double linked list of origin user and pointers
        if (list[cdp_id].prev != 0) {
            // Set the next pointer of the prev cdp_id (if exists) to the next of the transferred one
            list[list[cdp_id].prev].next = list[cdp_id].next;
        }
        if (list[cdp_id].next != 0) {
            // If wasn't the last one
            list[list[cdp_id].next].prev = list[cdp_id].prev; // Set the prev pointer of the next cdp_id to the prev of the transferred one
        } else {
            // If was the last one
            last[owner_of[cdp_id]] = list[cdp_id].prev; // Update last pointer of the owner
        }
        if (first[owner_of[cdp_id]] == cdp_id) {
            // If was the first one
            first[owner_of[cdp_id]] = list[cdp_id].next; // Update first pointer of the owner
        }
        count[owner_of[cdp_id]] -= 1;

        // Transfer ownership
        owner_of[cdp_id] = dst;

        // Add transferred cdp_id to double linked list of destiny user and pointers
        list[cdp_id].prev = last[dst];
        list[cdp_id].next = 0;
        if (last[dst] != 0) {
            list[last[dst]].next = cdp_id;
        }
        if (first[dst] == 0) {
            first[dst] = cdp_id;
        }
        last[dst] = cdp_id;
        count[dst] += 1;
    }

    // frob
    // Modify safe keeping the generated BEI or collateral freed in the safe address.
    function modify_cdp(uint256 cdp_id, int256 delta_col, int256 delta_debt)
        public
        cdp_allowed(cdp_id)
    {
        address safe = positions[cdp_id];
        ICDPEngine(cdp_engine).modify_cdp({
            col_type: collaterals[cdp_id],
            safe: safe,
            col_src: safe,
            coin_dst: safe,
            delta_col: delta_col,
            delta_debt: delta_debt
        });
    }

    // flux
    // Transfer wad amount of cdp_id collateral from the cdp_id address to a dst address.
    function transfer_collateral(uint256 cdp_id, address dst, uint256 wad)
        public
        cdp_allowed(cdp_id)
    {
        ICDPEngine(cdp_engine).transfer_collateral(
            collaterals[cdp_id], positions[cdp_id], dst, wad
        );
    }

    // flux
    // Transfer wad amount of any type of collateral (col_type) from the cdp_id address to a dst address.
    // This function has the purpose to take away collateral from the system that doesn't correspond to the cdp_id but was sent there wrongly.
    function transfer_collateral(
        bytes32 col_type,
        uint256 cdp_id,
        address dst,
        uint256 wad
    ) public cdp_allowed(cdp_id) {
        ICDPEngine(cdp_engine).transfer_collateral(
            col_type, positions[cdp_id], dst, wad
        );
    }

    // move
    // Transfer wad amount of BEI from the cdp_id address to a dst address.
    function transfer_coin(uint256 cdp_id, address dst, uint256 rad)
        public
        cdp_allowed(cdp_id)
    {
        ICDPEngine(cdp_engine).transfer_coin(positions[cdp_id], dst, rad);
    }

    // Quit the system, migrating the cdp_id (collateral, debt) to a different dst safe handler
    function quit(uint256 cdp_id, address dst)
        public
        cdp_allowed(cdp_id)
        cdp_handler_allowed(dst)
    {
        bytes32 col_type = collaterals[cdp_id];
        address safe = positions[cdp_id];

        ICDPEngine.Position memory pos =
            ICDPEngine(cdp_engine).positions(col_type, safe);

        ICDPEngine(cdp_engine).fork({
            col_type: col_type,
            src: safe,
            dst: dst,
            delta_col: Math.to_int(pos.collateral),
            delta_debt: Math.to_int(pos.debt)
        });
    }

    // Import a position from src safe handler to the safe handler owned by cdp_id
    function enter(address src, uint256 cdp_id)
        public
        cdp_handler_allowed(src)
        cdp_allowed(cdp_id)
    {
        bytes32 col_type = collaterals[cdp_id];

        ICDPEngine.Position memory pos =
            ICDPEngine(cdp_engine).positions(col_type, src);

        ICDPEngine(cdp_engine).fork({
            col_type: col_type,
            src: src,
            dst: positions[cdp_id],
            delta_col: Math.to_int(pos.collateral),
            delta_debt: Math.to_int(pos.debt)
        });
    }

    // Move a position from safe_src safe handler to the safe_dst safe handler
    function shift(uint256 safe_src, uint256 safe_dst)
        public
        cdp_allowed(safe_src)
        cdp_allowed(safe_dst)
    {
        require(
            collaterals[safe_src] == collaterals[safe_dst],
            "not matching collaterals"
        );
        ICDPEngine.Position memory pos = ICDPEngine(cdp_engine).positions(
            collaterals[safe_src], positions[safe_src]
        );
        ICDPEngine(cdp_engine).fork({
            col_type: collaterals[safe_src],
            src: positions[safe_src],
            dst: positions[safe_dst],
            delta_col: Math.to_int(pos.collateral),
            delta_debt: Math.to_int(pos.debt)
        });
    }
}
