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
    uint256 public last_cdp_id;
    // urns
    // cdp id => CDPHandler
    mapping(uint256 => address) public positions;
    // list
    // cdp id => prev & next cdp ids (double linked list)
    mapping(uint256 => ICDPManager.List) public list;
    // owns
    // cdp id => owner of cdp
    mapping(uint256 => address) public owner_of;
    // ilks
    // cdp id => collateral types
    mapping(uint256 => bytes32) public collaterals;

    // first
    // owner => first cdp id
    mapping(address => uint256) public first;
    // last
    // owner => last cdp id
    mapping(address => uint256) public last;
    // count
    // owner => amount of cdp handlers
    mapping(address => uint256) public count;

    // cdpCan - permission to modify cdp by addr
    // owner => cdp id => addr => allowed
    mapping(address => mapping(uint256 => mapping(address => bool))) public
        cdp_can;

    // urnCan
    // CDPHandler => addr => allowed
    mapping(address => mapping(address => bool)) public cdp_handler_can;

    // cdpAllowed - msg.sender is cdp owner or cdp owner has given permission to msg.sender
    modifier cdp_allowed(uint256 cdp_id) {
        address owner = owner_of[cdp_id];
        require(
            msg.sender == owner || cdp_can[owner][cdp_id][msg.sender],
            "cdp not allowed"
        );
        _;
    }

    // urnAllowed
    modifier cdp_handler_allowed(address user) {
        require(
            msg.sender == user || cdp_handler_can[user][msg.sender],
            "cdp handler not allowed"
        );
        _;
    }

    constructor(address _cdp_engine) {
        cdp_engine = _cdp_engine;
    }

    // cdpAllow
    // Allow / disallow user to manage the cdp.
    function allow_cdp(uint256 cdp_id, address user, bool ok)
        public
        cdp_allowed(cdp_id)
    {
        cdp_can[owner_of[cdp_id]][cdp_id][user] = ok;
    }

    // urnAllow
    // Allow / disallow user to quit to msg.sender's cdp handler.
    function allow_cdp_handler(address user, bool ok) public {
        cdp_handler_can[msg.sender][user] = ok;
    }

    // open
    // Open a new cdp for a given user address.
    function open(bytes32 col_type, address user) public returns (uint256) {
        require(user != address(0), "user = zero address");

        // increment and then assign to var
        uint256 id = ++last_cdp_id;

        positions[id] = address(new CDPHandler(cdp_engine));
        owner_of[id] = user;
        collaterals[id] = col_type;

        // TODO: learn doubly linked list algo
        // Add new cdp to double linked list and pointers
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
    // Give the cdp ownership to a dst address.
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
    // Modify cdp keeping the generated BEI or collateral freed in the cdp address.
    function modify_cdp(uint256 cdp_id, int256 delta_col, int256 delta_debt)
        public
        cdp_allowed(cdp_id)
    {
        address cdp = positions[cdp_id];
        ICDPEngine(cdp_engine).modify_cdp({
            col_type: collaterals[cdp_id],
            cdp: cdp,
            gem_src: cdp,
            coin_dst: cdp,
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

    // Quit the system, migrating the cdp_id (collateral, debt) to a different dst cdp handler
    function quit(uint256 cdp_id, address cdp_dst)
        public
        cdp_allowed(cdp_id)
        cdp_handler_allowed(cdp_dst)
    {
        bytes32 col_type = collaterals[cdp_id];
        address cdp = positions[cdp_id];

        ICDPEngine.Position memory pos =
            ICDPEngine(cdp_engine).positions(col_type, cdp);

        ICDPEngine(cdp_engine).fork({
            col_type: col_type,
            cdp_src: cdp,
            cdp_dst: cdp_dst,
            delta_col: Math.to_int(pos.collateral),
            delta_debt: Math.to_int(pos.debt)
        });
    }

    // Import a position from cdp_src cdp handler to the cdp handler owned by cdp_id
    function enter(address cdp_src, uint256 cdp_id)
        public
        cdp_handler_allowed(cdp_src)
        cdp_allowed(cdp_id)
    {
        bytes32 col_type = collaterals[cdp_id];

        ICDPEngine.Position memory pos =
            ICDPEngine(cdp_engine).positions(col_type, cdp_src);

        ICDPEngine(cdp_engine).fork({
            col_type: col_type,
            cdp_src: cdp_src,
            cdp_dst: positions[cdp_id],
            delta_col: Math.to_int(pos.collateral),
            delta_debt: Math.to_int(pos.debt)
        });
    }

    // Move a position from cdp_src cdp handler to the cdp_dst cdp handler
    function shift(uint256 cdp_src, uint256 cdp_dst)
        public
        cdp_allowed(cdp_src)
        cdp_allowed(cdp_dst)
    {
        require(
            collaterals[cdp_src] == collaterals[cdp_dst],
            "not matching collaterals"
        );
        ICDPEngine.Position memory pos = ICDPEngine(cdp_engine).positions(
            collaterals[cdp_src], positions[cdp_src]
        );
        ICDPEngine(cdp_engine).fork({
            col_type: collaterals[cdp_src],
            cdp_src: positions[cdp_src],
            cdp_dst: positions[cdp_dst],
            delta_col: Math.to_int(pos.collateral),
            delta_debt: Math.to_int(pos.debt)
        });
    }
}
