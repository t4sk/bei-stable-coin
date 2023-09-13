// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

abstract contract Stop {
    event Stop();

    bool public live;

    modifier notStopped() {
        require(live, "stopped");
        _;
    }

    // cage
    function _stop() internal {
        live = false;
        emit Stop();
    }
}
