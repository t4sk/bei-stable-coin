// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ICDPEngine} from "../interfaces/ICDPEngine.sol";

contract SafeHandler {
    constructor(address cdp_engine) {
        ICDPEngine(cdp_engine).add_auth(msg.sender);
    }
}
