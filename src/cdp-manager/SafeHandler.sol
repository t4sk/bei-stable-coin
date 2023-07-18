// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IVat} from "../interfaces/IVat.sol";

contract SafeHandler {
    constructor(address vat) {
        IVat(vat).addAuthorization(msg.sender);
    }
}
