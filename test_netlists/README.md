# MTX Test Netlists

Sample matrix-side netlist files for continuity and resistance testing.
The HV side already has three canned netlist entries in the GUI picker
(`AV-880_HV_3card.hnl`, `AV-880_HV_4card.hnl`, `AV-880_HV_1card.hnl`).
These files are the MTX equivalent: sample harness definitions that the
operator can browse and load for `CONT RUN verify` and `RES RUN`.

## Format

Excel `.xlsx` with a header row and one sheet. Recognised columns:

- `HI` / `HS PIN` / `FROM` / `PIN 1` — the high-side pin, 1..256
- `LO` / `LS PIN` / `TO` / `PIN 2` — the low-side pin, 1..256
- `NET` / `NET NAME` / `NAME` / `SIGNAL` — net name (optional, for display)

See `gui_flutter/lib/htproto/netlist_file.dart` for the full list of accepted
header spellings and validation rules.

## Files

| File | Nets | Use |
|------|------|-----|
| `AV-880_MTX_12net.xlsx` | 12 | Matches the simulator default (`--nets 12`). Good for quick pass/fail/scenario runs. |
| `AV-880_MTX_24net.xlsx` | 24 | Medium harness for layout and regression checks. |
| `AV-880_MTX_118net.xlsx` | 118 | Matches the full demo harness from `buildNets()` in `gui_flutter/lib/design/model.dart`; same net count as the canned HV netlists. |

Pin pairs are `(1,2), (3,4), …`, which matches the simulator's `_goodNets()`
generator. Net names are the demo harness names (`PWR_28V_A`, `GND_RET`, …)
for the first 22 nets, then `NET_023`, `NET_024`, etc.

## How to use in the Flutter GUI

1. Launch the app (`flutter run -d windows --dart-entrypoint-args --sim` for
the simulator, or `--serial,COMx` for hardware).
2. Connect.
3. In the Continuity view, switch to **netlist** mode (the cross/net toggle).
4. Click **Select…** in the MTX netbar.
5. Choose **Browse the file system…** and pick one of these `.xlsx` files.
6. Run `CONT RUN verify` or `RES RUN`.

The same file can be loaded from the Resistance view — continuity and
resistance share the same MTX netlist.

## How to regenerate

```bash
python test_netlists/generate_test_netlists.py
```

The generator is committed alongside the `.xlsx` files so the test data stays
reviewable in diffs even though the binary workbooks are not.
