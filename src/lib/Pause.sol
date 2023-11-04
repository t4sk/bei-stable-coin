// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

abstract contract Pause {
    event Stop();

    bool public live;

    modifier notStopped() {
        require(live, "stopped");
        _;
    }

    constructor() {
        live = true;
    }

    // cage
    function _stop() internal {
        live = false;
        emit Stop();
    }
}
