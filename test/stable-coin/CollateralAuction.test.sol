// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {ISpotter} from "../../src/interfaces/ISpotter.sol";
import "../../src/lib/Math.sol";
import {CollateralAuction} from "../../src/stable-coin/CollateralAuction.sol";

contract MockCDPEngine {
    mapping(address => uint256) public coin;
    mapping(address => uint256) public unbacked_debts;
    mapping(bytes32 => mapping(address => uint256)) public gem;

    function mint(address debt_dst, address coin_dst, uint256 rad) external {
        unbacked_debts[debt_dst] += rad;
        coin[coin_dst] += rad;
    }

    function modify_collateral_balance(
        bytes32 col_type,
        address src,
        int256 wad
    ) external {
        gem[col_type][src] = Math.add(gem[col_type][src], wad);
    }

    function transfer_collateral(
        bytes32 col_type,
        address src,
        address dst,
        uint256 wad
    ) external {
        gem[col_type][src] -= wad;
        gem[col_type][dst] += wad;
    }

    function transfer_coin(address src, address dst, uint256 rad) external {
        coin[src] -= rad;
        coin[dst] += rad;
    }
}

contract MockPriceFeed {
    function peek() external returns (uint256 val, bool ok) {
        return (WAD, true);
    }
}

contract MockSpotter {
    uint256 public par = RAY;
    mapping(bytes32 => ISpotter.Collateral) private cols;

    function set(
        bytes32 col_type,
        address price_feed,
        uint256 liquidation_ratio
    ) external {
        cols[col_type] = ISpotter.Collateral({
            price_feed: price_feed,
            liquidation_ratio: liquidation_ratio
        });
    }

    function collaterals(bytes32 col_type)
        external
        view
        returns (ISpotter.Collateral memory)
    {
        return cols[col_type];
    }
}

contract MockLiquidationEngine {
    function remove_coin_from_auction(bytes32 col_type, uint256 rad) external {}
}

contract MockCalc {
    function price(uint256 top, uint256 dt) external view returns (uint256) {
        return top;
    }
}

contract CollateralAuctionTest is Test {
    MockCDPEngine private cdp_engine;
    MockPriceFeed private price_feed;
    MockSpotter private spotter;
    MockLiquidationEngine private liquidation_engine;
    MockCalc private calc;
    CollateralAuction private auction;
    address private constant debt_engine = address(111);
    address private constant user = address(11);
    address private constant keeper = address(12);

    bytes32 private constant COL_TYPE = bytes32(uint256(1));
    uint256 private constant COIN_AMOUNT = 100 * RAD;
    uint256 private constant COL_AMOUNT = WAD;

    function setUp() public {
        cdp_engine = new MockCDPEngine();
        price_feed = new MockPriceFeed();
        spotter = new MockSpotter();
        liquidation_engine = new MockLiquidationEngine();
        calc = new MockCalc();
        auction = new CollateralAuction(
            address(cdp_engine),
            address(spotter),
            address(liquidation_engine),
            COL_TYPE
        );

        cdp_engine.modify_collateral_balance(
            COL_TYPE, address(auction), int256(COL_AMOUNT)
        );
        cdp_engine.mint(address(this), address(this), COIN_AMOUNT);
        spotter.set(COL_TYPE, address(price_feed), RAY);

        auction.set("fee_rate", 1e15);
        auction.set("flat_fee", RAD);
        auction.set("calc", address(calc));
        auction.set("debt_engine", debt_engine);
    }

    function test_auction() public {
        uint256 id = auction.start(COIN_AMOUNT, COL_AMOUNT, user, keeper);
        auction.take(id, COL_AMOUNT, type(uint256).max, address(this), "");
    }
}
