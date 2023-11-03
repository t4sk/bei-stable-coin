## Topics

### TODO

- dictionary

shell

- solidity
- vyper
- sway

- overview
- `wad`, `ray`, `rad`
- `DAI`, `wards`, `rely`, `deny`
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
      - `CdpManager`
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

`vat` - Core vault engine of dss. Stores vaults and tracks all the associated Dai and collateral balances

`jug` - Smart contract to accumulate stability fees

`urn` - CDP state, a vault (rename `safe`)

`ilk` - Collateral type

`cdp` - Collateralized debt position

`wad` - 1e18

`frob(i, u, v, w, dink, dart)`

- Modifies the Vault of user `u`, using gem `i` from user `v` and creating dai for user `w`.
- `dink` - change in collateral
- `dart` - change in debt

### Omit

- dai permit
