pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {ICDPEngine} from "../../src/interfaces/ICDPEngine.sol";
import {IJug} from "../../src/interfaces/IJug.sol";
import "../../src/lib/Math.sol";
import {Pot} from "../../src/stable-coin/Pot.sol";

contract MockCDPEngine {
    mapping(address => uint256) public coin;
    mapping(address => uint256) public unbacked_debts;

    function transfer_coin(address src, address dst, uint256 rad) external {
        coin[src] -= rad;
        coin[dst] += rad;
    }

    function mint(address debt_dst, address coin_dst, uint256 rad) external {
        unbacked_debts[debt_dst] += rad;
        coin[coin_dst] += rad;
    }
}

contract PotTest is Test {
    MockCDPEngine private cdp_engine;
    address private constant debt_engine = address(1);
    Pot private pot;

    function setUp() public {
        cdp_engine = new MockCDPEngine();
        pot = new Pot(address(cdp_engine));
    }

    function test_collect_stability_fee() public {
        //
    }

    function test_join_exit() public {
        //
    }
}
