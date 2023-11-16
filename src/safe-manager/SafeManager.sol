// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import {ISafeEngine} from "../interfaces/ISafeEngine.sol";
import {ISafeManager} from "../interfaces/ISafeManager.sol";
import "../lib/Math.sol";
import {SafeHandler} from "./SafeHandler.sol";

// DssCdpManager
contract SafeManager {
    event NewSafe(
        address indexed user, address indexed owner, uint256 indexed safe_id
    );

    // vat
    address public immutable safe_engine;
    // cdpi
    uint256 public last_safe_id;
    // urns
    // safe id => SafeHandler
    mapping(uint256 => address) public safes;
    // list
    // safe id => prev & next safe ids (double linked list)
    mapping(uint256 => ISafeManager.List) public list;
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
    // SafeHandler => addr => allowed
    mapping(address => mapping(address => bool)) public safe_handler_can;

    // cdpAllowed - msg.sender is safe owner or safe owner has given permission to msg.sender
    modifier safe_allowed(uint256 safe_id) {
        address owner = owner_of[safe_id];
        require(
            msg.sender == owner || safe_can[owner][safe_id][msg.sender],
            "safe not allowed"
        );
        _;
    }

    // TODO: wat dis?
    // urnAllowed
    modifier safe_handler_allowed(address user) {
        require(
            msg.sender == user || safe_handler_can[user][msg.sender],
            "safe handler not allowed"
        );
        _;
    }

    constructor(address _safe_engine) {
        safe_engine = _safe_engine;
    }

    // cdpAllow
    // Allow / disallow user to manage the safe.
    function allow_safe(uint256 safe_id, address user, bool ok)
        public
        safe_allowed(safe_id)
    {
        safe_can[owner_of[safe_id]][safe_id][user] = ok;
    }

    // urnAllow
    // Allow / disallow user to quit to msg.sender's safe handler.
    function allow_safe_handler(address user, bool ok) public {
        safe_handler_can[msg.sender][user] = ok;
    }

    // open
    // Open a new safe for a given user address.
    function open(bytes32 col_type, address user) public returns (uint256) {
        require(user != address(0), "user = zero address");

        // increment and then assign to var
        uint256 id = ++last_safe_id;

        safes[id] = address(new SafeHandler(safe_engine));
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

        emit NewSafe(msg.sender, user, id);
        return id;
    }

    // give
    // Give the safe ownership to a dst address.
    function give(uint256 safe_id, address dst) public safe_allowed(safe_id) {
        require(dst != address(0), "dst = 0 address");
        require(dst != owner_of[safe_id], "dst is already owner");

        // TODO: learn doubly linked list algo
        // Remove transferred safe_id from double linked list of origin user and pointers
        if (list[safe_id].prev != 0) {
            // Set the next pointer of the prev safe_id (if exists) to the next of the transferred one
            list[list[safe_id].prev].next = list[safe_id].next;
        }
        if (list[safe_id].next != 0) {
            // If wasn't the last one
            list[list[safe_id].next].prev = list[safe_id].prev; // Set the prev pointer of the next safe_id to the prev of the transferred one
        } else {
            // If was the last one
            last[owner_of[safe_id]] = list[safe_id].prev; // Update last pointer of the owner
        }
        if (first[owner_of[safe_id]] == safe_id) {
            // If was the first one
            first[owner_of[safe_id]] = list[safe_id].next; // Update first pointer of the owner
        }
        count[owner_of[safe_id]] -= 1;

        // Transfer ownership
        owner_of[safe_id] = dst;

        // Add transferred safe_id to double linked list of destiny user and pointers
        list[safe_id].prev = last[dst];
        list[safe_id].next = 0;
        if (last[dst] != 0) {
            list[last[dst]].next = safe_id;
        }
        if (first[dst] == 0) {
            first[dst] = safe_id;
        }
        last[dst] = safe_id;
        count[dst] += 1;
    }

    // frob
    // Modify safe keeping the generated BEI or collateral freed in the safe address.
    function modify_safe(uint256 safe_id, int256 delta_col, int256 delta_debt)
        public
        safe_allowed(safe_id)
    {
        address safe = safes[safe_id];
        ISafeEngine(safe_engine).modify_safe({
            col_type: collaterals[safe_id],
            safe: safe,
            col_src: safe,
            coin_dst: safe,
            delta_col: delta_col,
            delta_debt: delta_debt
        });
    }

    // flux
    // Transfer wad amount of safe_id collateral from the safe_id address to a dst address.
    function transfer_collateral(uint256 safe_id, address dst, uint256 wad)
        public
        safe_allowed(safe_id)
    {
        ISafeEngine(safe_engine).transfer_collateral(
            collaterals[safe_id], safes[safe_id], dst, wad
        );
    }

    // flux
    // Transfer wad amount of any type of collateral (col_type) from the safe_id address to a dst address.
    // This function has the purpose to take away collateral from the system that doesn't correspond to the safe_id but was sent there wrongly.
    function transfer_collateral(
        bytes32 col_type,
        uint256 safe_id,
        address dst,
        uint256 wad
    ) public safe_allowed(safe_id) {
        ISafeEngine(safe_engine).transfer_collateral(
            col_type, safes[safe_id], dst, wad
        );
    }

    // move
    // Transfer wad amount of BEI from the safe_id address to a dst address.
    function transfer_coin(uint256 safe_id, address dst, uint256 rad)
        public
        safe_allowed(safe_id)
    {
        ISafeEngine(safe_engine).transfer_coin(safes[safe_id], dst, rad);
    }

    // Quit the system, migrating the safe_id (collateral, debt) to a different dst safe handler
    function quit(uint256 safe_id, address dst)
        public
        safe_allowed(safe_id)
        safe_handler_allowed(dst)
    {
        bytes32 col_type = collaterals[safe_id];
        address safe = safes[safe_id];

        ISafeEngine.Safe memory s =
            ISafeEngine(safe_engine).safes(col_type, safe);

        ISafeEngine(safe_engine).fork({
            col_type: col_type,
            src: safe,
            dst: dst,
            delta_col: Math.to_int(s.collateral),
            delta_debt: Math.to_int(s.debt)
        });
    }

    // Import a position from src safe handler to the safe handler owned by safe_id
    function enter(address src, uint256 safe_id)
        public
        safe_handler_allowed(src)
        safe_allowed(safe_id)
    {
        bytes32 col_type = collaterals[safe_id];

        ISafeEngine.Safe memory s =
            ISafeEngine(safe_engine).safes(col_type, src);

        ISafeEngine(safe_engine).fork({
            col_type: col_type,
            src: src,
            dst: safes[safe_id],
            delta_col: Math.to_int(s.collateral),
            delta_debt: Math.to_int(s.debt)
        });
    }

    // Move a position from safe_src safe handler to the safe_dst safe handler
    function shift(uint256 safe_src, uint256 safe_dst)
        public
        safe_allowed(safe_src)
        safe_allowed(safe_dst)
    {
        require(
            collaterals[safe_src] == collaterals[safe_dst],
            "not matching collaterals"
        );
        ISafeEngine.Safe memory s = ISafeEngine(safe_engine).safes(
            collaterals[safe_src], safes[safe_src]
        );
        ISafeEngine(safe_engine).fork({
            col_type: collaterals[safe_src],
            src: safes[safe_src],
            dst: safes[safe_dst],
            delta_col: Math.to_int(s.collateral),
            delta_debt: Math.to_int(s.debt)
        });
    }
}
