// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.24;

import "../lib/Math.sol";
import {Auth} from "../lib/Auth.sol";
import {AccessControl} from "../lib/AccessControl.sol";

// TODO:
contract EmergencyShutdown is Auth, AccessControl {}
