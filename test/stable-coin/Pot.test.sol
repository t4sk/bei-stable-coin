pragma solidity 0.8.24;

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
    address private constant ds_engine = address(1);
    Pot private pot;
    address[] private users = [address(11), address(12)];

    function setUp() public {
        cdp_engine = new MockCDPEngine();
        pot = new Pot(address(cdp_engine));
        // about 5% per year
        pot.set("ds_engine", ds_engine);
        pot.set("savings_rate", 1000000001547125957863212448);

        for (uint256 i = 0; i < users.length; i++) {
            cdp_engine.mint(users[i], users[i], RAD);
        }
    }

    function test_join_collect_exit() public {
        uint256 rate_acc;
        uint256 wad;

        pot.collect_stability_fee();
        rate_acc = pot.rate_acc();
        wad = RAD / rate_acc;

        for (uint256 i = 0; i < users.length; i++) {
            vm.prank(users[i]);
            pot.join(wad);
            assertEq(pot.pie(users[i]), wad);
        }
        assertEq(pot.total_pie(), users.length * wad);

        skip(100);

        pot.collect_stability_fee();
        rate_acc = pot.rate_acc();

        for (uint256 i = 0; i < users.length; i++) {
            vm.prank(users[i]);
            pot.exit(wad);
            assertEq(pot.pie(users[i]), 0);
            assertGt(cdp_engine.coin(users[i]), RAD);
        }
        assertEq(pot.total_pie(), 0);
    }
}
