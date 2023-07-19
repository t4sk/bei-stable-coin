## Topics

-   proxy
-   proxy action
    -   `Common`
        -   `DaiJoin`
            -   `Gem`, `Vat`
    -   `GemJoin`
        -   `join`
            -   `vat.slip`
    -   `openLockETHAndDraw` TODO: or `openLockGemAndDraw`
        -   `jug`
        -   `ilk`
        -   `cdp`
        -   `open`
            -   `CdpManager`
                -   `open`
                    -   `SafeHandler`
                        -   `Vat.hope`
                    -   doubly linked list (insert)
        -   `lockGemAndDraw`
            -   `GemJoin.join`

`gem` - Collateral tokens

`vat` - Core vault engine of dss. Stores vaults and tracks all the associated Dai and collateral balances

`jug` - Smart contract to accumulate stability fees (renamed `feeCollector`)

`urn` - CDP state, a vault (rename `safe`)

`ilk` - Collateral type

`cdp` - Collateralized debt position

`wad` - 1e18
