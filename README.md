# BEI Stable Coin

```shell
forge build
forge test
```

```shell
# Check this test for how the system works
forge test --match-path test/sim/Sim.test.sol
```

TODO: ESM?
TODO: OSM?
TODO: gov?

test

-   pot
-   vat
-   vow
-   clipper
-   dog
-   flopper
-   flapper
-   cdp manager

### Memo

ETH A - 0x4554482d41000000000000000000000000000000000000000000000000000000

ETH C - 0x4554482d43000000000000000000000000000000000000000000000000000000

```
par [ray] 1000000000000000000000000000
mat [ray] 1450000000000000000000000000
val [wad] 2067300000000000000000
spot [ray] 1429862068965517241379310344827

liquidation ratio = mat / par
                  = collateral USD value / debt USD value

liquidation price = spot = val * 1e9 * par / mat
```

### Links

-   [docs](https://docs.makerdao.com/)
-   [dss](https://github.com/makerdao/dss)
-   [dss-proxy](https://github.com/makerdao/dss-proxy)
-   [dss-proxy-actions](https://github.com/makerdao/dss-proxy-actions)
-   [dss-cdp-manager](https://github.com/makerdao/dss-cdp-manager)
-   [osm](https://github.com/makerdao/osm)
