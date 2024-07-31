// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.24;

abstract contract CircuitBreaker {
    event Stop();

    bool public is_live;

    modifier live() {
        require(is_live, "stopped");
        _;
    }

    constructor() {
        is_live = true;
    }

    // cage
    function _stop() internal {
        require(is_live, "stopped");
        is_live = false;
        emit Stop();
    }
}
