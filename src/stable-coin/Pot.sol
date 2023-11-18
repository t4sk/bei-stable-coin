// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import {ICDPEngine} from "../interfaces/ICDPEngine.sol";
import {Auth} from "../lib/Auth.sol";
import {CircuitBreaker} from "../lib/CircuitBreaker.sol";
import "../lib/Math.sol";

/*
Pot is the core of the BEI Savings Rate. 
It allows users to deposit BEI and activate the BEI Savings Rate and 
earning savings on their BEI.  The DSR is set by Maker Governance, and will 
typically be less than the base stability fee to remain sustainable. 
The purpose of Pot is to offer another incentive for holding BEI.
*/
contract Pot is Auth, CircuitBreaker {
    // pie = sum(coin / chi)
    // Normalised savings BEI [wad]
    mapping(address => uint256) public pie;
    // Pie
    // Total normalised savings BEI [wad]
    uint256 public total_pie;
    // dsr
    // BEI savings rate [ray]
    uint256 public savings_rate;
    // chi
    // Rate accumulator [ray]
    uint256 public chi;

    ICDPEngine public safe_engine; // CDP Engine
    address public debt_engine; // Debt Engine
    // rho
    uint256 public updated_at; // Time of last drip [unix epoch time]
    // drip - performs stability fee collection for a specific
    //        collateral type when it is called

    constructor(address _safe_engine) {
        safe_engine = ICDPEngine(_safe_engine);
        savings_rate = RAY;
        chi = RAY;
        updated_at = block.timestamp;
    }

    // --- Administration ---
    // file
    function set(bytes32 key, uint256 val) external auth live {
        require(block.timestamp == updated_at, "updated_at != now");
        if (key == "savings_rate") {
            savings_rate = val;
        } else {
            revert("invalid param");
        }
    }

    // file
    function set(bytes32 key, address addr) external auth {
        if (key == "debt_engine") {
            debt_engine = addr;
        } else {
            revert("invalid param");
        }
    }

    // cage
    function stop() external auth {
        _stop();
        savings_rate = RAY;
    }

    // --- Savings Rate Accumulation ---
    function drip() external returns (uint256) {
        require(block.timestamp >= updated_at, "now < updated_at");
        uint256 tmp = Math.rmul(
            Math.rpow(savings_rate, block.timestamp - updated_at, RAY), chi
        );
        uint256 delta_chi = tmp - chi;
        chi = tmp;
        updated_at = block.timestamp;
        // prev total = chi * total
        // new  total = new chi * total
        // mint = new total - prev total = (new chi - chi) * total
        safe_engine.mint(debt_engine, address(this), total_pie * delta_chi);
        return tmp;
    }

    // --- Savings BEI Management ---
    function join(uint256 wad) external {
        require(block.timestamp == updated_at, "updated_at != now");
        // TODO: check math for multiple deposits
        pie[msg.sender] += wad;
        total_pie += wad;
        safe_engine.transfer_coin(msg.sender, address(this), chi * wad);
    }

    function exit(uint256 wad) external {
        pie[msg.sender] -= wad;
        total_pie -= wad;
        safe_engine.transfer_coin(address(this), msg.sender, chi * wad);
    }
}
