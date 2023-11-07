// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

abstract contract CircuitBreaker {
    event Stop();

    bool public live;

    modifier not_stopped() {
        require(live, "stopped");
        _;
    }

    constructor() {
        live = true;
    }

    // cage
    function _stop() internal {
        require(live, "not live");
        live = false;
        emit Stop();
    }
}
