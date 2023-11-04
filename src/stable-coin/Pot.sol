// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IVat} from "../interfaces/IVat.sol";
import {Auth} from "../lib/Auth.sol";
import {Pause} from "../lib/Pause.sol";
import {RAY, Math} from "../lib/Math.sol";

/*
Pot is the core of the Dai Savings Rate. 
It allows users to deposit dai and activate the Dai Savings Rate and 
earning savings on their dai.  The DSR is set by Maker Governance, and will 
typically be less than the base stability fee to remain sustainable. 
The purpose of Pot is to offer another incentive for holding Dai.
*/
contract Pot is Auth, Pause {
    // pie
    mapping(address => uint256) public balances; // Normalised savings Dai [wad]
    // Pie
    uint256 public total; // Total normalised savings Dai [wad]
    // dsr
    uint256 public dsr; // Dai savings rate [ray]
    // chi
    uint256 public chi; // Rate accumulator [ray]

    IVat public vat; // CDP Engine
    address public vow; // Debt Engine
    // rho
    uint256 public updated_at; // Time of last drip [unix epoch time]
    // drip - performs stability fee collection for a specific
    //        collateral type when it is called

    constructor(address _vat) {
        vat = IVat(_vat);
        dsr = RAY;
        chi = RAY;
        updated_at = block.timestamp;
    }

    // --- Administration ---
    // file
    function set(bytes32 key, uint256 val) external auth not_stopped {
        require(block.timestamp == updated_at, "updated_at != now");
        if (key == "dsr") {
            dsr = val;
        } else {
            revert("invalid param");
        }
    }

    // file
    function set(bytes32 key, address addr) external auth {
        if (key == "vow") {
            vow = addr;
        } else {
            revert("invalid param");
        }
    }

    // cage
    function stop() external auth {
        _stop();
        dsr = RAY;
    }

    // --- Savings Rate Accumulation ---
    function drip() external returns (uint256) {
        require(block.timestamp >= updated_at, "now < updated_at");
        uint256 tmp = Math.rmul(Math.rpow(dsr, block.timestamp - updated_at, RAY), chi);
        uint256 delta_chi = tmp - chi;
        chi = tmp;
        updated_at = block.timestamp;
        // prev total = chi * total
        // new  total = new chi * total
        // mint = new total - prev total = (new chi - chi) * total
        vat.mint(vow, address(this), total * delta_chi);
        return tmp;
    }

    // --- Savings Dai Management ---
    function join(uint256 wad) external {
        require(block.timestamp == updated_at, "updated_at != now");
        balances[msg.sender] += wad;
        total += wad;
        vat.transfer_coin(msg.sender, address(this), chi * wad);
    }

    function exit(uint256 wad) external {
        balances[msg.sender] -= wad;
        total -= wad;
        vat.transfer_coin(address(this), msg.sender, chi * wad);
    }
}
