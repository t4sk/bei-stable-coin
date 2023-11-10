## Topics

ETH A - 0x4b4e432d41000000000000000000000000000000000000000000000000000000

ETH C - 0x4554482d43000000000000000000000000000000000000000000000000000000

### TODO

- unit tests
- mainnet tests

- dictionary

shell

- solidity
- vyper
- sway

- overview
- `wad`, `ray`, `rad`
- `BEI`, `wards`, `rely`, `deny`
- proxy
- proxy action
  - `Common`
    - `DaiJoin`
      - `Gem`, `Vat`
  - `GemJoin`
    - `join`
      - `vat.slip`
  - `DaiJoin`
    - `vat.move`
  - `Vat`
    - `slip`
    - `move`
      - `wish`
  - `openLockETHAndDraw` TODO: or `openLockGemAndDraw`
    - `jug`
    - `ilk`
    - `cdp`
    - `open`
      - `CDPManager`
        - `open`
          - `SafeHandler`
            - `Vat.hope`
          - doubly linked list (insert)
    - `lockGemAndDraw`
      - `GemJoin.join`
      - `frob`
        - `Ilk`
        - `Urn`
          - `ink` Collateral balance
          - `art` Normalized outstanding stable coin debt

`gem` - Collateral tokens

`vat` - Core vault engine of dss. Stores vaults and tracks all the associated BEI and collateral balances

`jug` - Smart contract to accumulate stability fees

`urn` - CDP state, a vault (rename `safe`)

`ilk` - Collateral type

`cdp` - Collateralized debt position

`wad` - 1e18

`frob(i, u, v, w, dink, dart)`

- Modifies the Vault of user `u`, using gem `i` from user `v` and creating BEI for user `w`.
- `dink` - change in collateral
- `dart` - change in debt

### Omit

- BEI permit
