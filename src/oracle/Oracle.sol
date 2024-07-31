// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.24;

import {Auth} from "../lib/Auth.sol";
import "../lib/Math.sol";

// DSValue
interface IDSValue {
    function peek() external view returns (bytes32, bool);
}

// OSM - Oracle security module
// Deployed contracts are called PIP_ETH, PIP_WBTC, etc...
contract Oracle is Auth {
    bool public stopped;

    modifier not_stopped() {
        require(!stopped, "stopped");
        _;
    }

    // src - source of oracle's value
    address public src;
    uint16 constant ONE_HOUR = uint16(3600);
    // hop - wait duration for next poke
    uint16 public hop = ONE_HOUR;
    // zzz - timestamp in the past that is a multiple of hop
    uint64 public prev_hop_timestamp;

    struct Feed {
        uint128 val;
        bool has_value;
    }

    Feed public cur;
    // nxt
    Feed public next;

    // Whitelisted contracts, set by an auth
    // bud
    mapping(address => bool) public whitelisted;

    // toll
    modifier only_whitelisted() {
        require(whitelisted[msg.sender], "not whitelisted");
        _;
    }

    event LogValue(bytes32 val);

    constructor(address _src) public {
        src = _src;
    }

    function stop() external auth {
        stopped = true;
    }

    function start() external auth {
        stopped = false;
    }

    function change(address _src) external auth {
        src = _src;
    }

    // prev - calculate timestamp in the past that is a multiple of hop
    function prev(uint256 timestamp) internal view returns (uint64) {
        require(hop != 0, "hop is 0");
        return uint64(timestamp - (timestamp % hop));
    }

    // step - update hop
    function step(uint16 _hop) external auth {
        require(_hop > 0, "hop is 0");
        hop = _hop;
    }

    function void() external auth {
        cur = next = Feed(0, false);
        stopped = true;
    }

    function pass() public view returns (bool ok) {
        return block.timestamp >= (prev_hop_timestamp + uint64(hop));
    }

    function poke() external not_stopped {
        require(pass(), "not passed");
        (bytes32 val, bool ok) = IDSValue(src).peek();
        if (ok) {
            cur = next;
            next = Feed(uint128(uint256(val)), true);
            prev_hop_timestamp = prev(block.timestamp);
            emit LogValue(bytes32(uint256(cur.val)));
        }
    }

    function peek() external view only_whitelisted returns (bytes32, bool) {
        return (bytes32(uint256(cur.val)), cur.has_value);
    }

    function peep() external view only_whitelisted returns (bytes32, bool) {
        return (bytes32(uint256(next.val)), next.has_value);
    }

    function read() external view only_whitelisted returns (bytes32) {
        require(cur.has_value, "no current value");
        return (bytes32(uint256(cur.val)));
    }

    // kiss
    function add_whitelist(address a) external auth {
        require(a != address(0), "address = 0");
        whitelisted[a] = true;
    }

    // diss
    function remove_whitelist(address a) external auth {
        whitelisted[a] = false;
    }

    // kiss
    function add_whitelist(address[] calldata a) external auth {
        for (uint256 i = 0; i < a.length; i++) {
            require(a[i] != address(0), "address = 0");
            whitelisted[a[i]] = true;
        }
    }

    // diss
    function remove_whitelist(address[] calldata a) external auth {
        for (uint256 i = 0; i < a.length; i++) {
            whitelisted[a[i]] = false;
        }
    }
}
