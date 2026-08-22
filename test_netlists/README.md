# MTX Test Netlists

Sample matrix-side netlist files for continuity and resistance testing —
sample harness definitions that the operator can browse and load for
`CONT RUN verify` and `RES RUN`. The HV side uses the same `.xlsx` format and
the same "Browse the file system…" picker (there is no canned-entry picker on
either side any more — see "GUI Reality Check" in `PROJECT_LOG.md`; a canned
picker offering fabricated metadata as if it were real was removed).

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
| `AV-880_MTX_118net.xlsx` | 118 | Matches the full demo harness from `buildNets()` in `gui_flutter/lib/design/model.dart`. |
| `netlist_full_256x256.xlsx` | 256 | Full-scale fixture — every one of the instrument's 256 independently-addressed HI/256 LO pins, straight-through (pin N -> pin N). Passes against both `--sim` and real hardware — see below. |

Pin pairs for the first three files above are `(1,2), (3,4), …`, matching
the simulator's `_goodNets()` generator. Net names are the demo harness
names (`PWR_28V_A`, `GND_RET`, …) for the first 22 nets, then `NET_023`,
`NET_024`, etc. Regenerate them with `generate_test_netlists.py` (below).

`netlist_full_256x256.xlsx` is a different kind of file, not from that
generator — it's the `required_format` netlist convention (`Net`, `Source`,
`Conn ID`, `Part Number`, `Src Pin Label`, `Src Pin #`, `Dst Pin #`, `Dst Pin
Label`, `Conn ID B`, `Part Number B`, `Destination`, `Connector Detail`,
`Harness ID` — see `gui_flutter/required_format/README.md`) filled out for
every pin instead of a curated few, straight-through rather than `(1,2),
(3,4)` pairing (matching pin N on both sides is the ordinary case for a
symmetric connector pair — see `example_netlist27072026.xlsx`'s own
straight-through rows and GUI-08 in `PROJECT_LOG.md`). Its `Conn ID`/`Part
Number` columns group into four 128-pin connector blocks (`MTX-A1`/`MTX-A2`
on Side-A, `MTX-B1`/`MTX-B2` on Side-B) — a **draft** fixture proposal, not
a decided one: there is no real fixture connector part number anywhere else
in this repo yet, so `Part Number` reads `AMPHENOL-128CKT (TBD)` on every
row rather than a fabricated real catalog number. See
`gui_flutter/required_format/fixture_connector_layout_256x256.xlsx` for the
same breakdown as a standalone mechanical/procurement reference.

**Now passes against `--sim` too (2026-08-17, GUI-21/CL-55).** This file's straight-through
`1↔1, 2↔2, 3↔3, …` pairing used to read 0 pass in the demo — the simulator's fake harness
(`_goodNets()` in `gui_flutter/lib/htproto/simulator.dart`: pin 1↔2, 3↔4, 5↔6, …) compared
uploaded pairs against its own fixed pairing *by literal value*, independent of whatever netlist
actually got uploaded. `--nets` only ever needed to match *net count* for the three `(1,2),
(3,4)`-paired files above, because they were generated to already match that pattern — this
file's different (but equally valid) pairing convention couldn't, at any `--nets` value. Fixed
at the root (`InstrumentSim._effectiveNets`, GUI-21): the scenario's scripted pass/fail pattern
now applies positionally to whatever was actually uploaded, so `--sim`'s `'pass'` scenario
passes this file too — no `--nets` tuning needed, since verify mode sizes itself to however many
rows were uploaded.

## How to use in the Flutter GUI

**`--nets` no longer needs to match the file you load, for netlist-mode `CONT RUN verify` /
`RES RUN` (2026-08-17, GUI-21/CL-55).** It used to: the simulator only modeled the number of
nets it was told about at launch (`makeScenario(nets: ...)` in
`gui_flutter/lib/htproto/simulator.dart`), compared against the uploaded netlist by literal pin
value, so any net past `--nets` (or using a different pairing convention entirely, see
`netlist_full_256x256.xlsx` above) read NOT CONNECTED. `InstrumentSim._effectiveNets` now sizes
a verify-mode run to however many rows the *uploaded netlist* actually has, applying the
scenario's scripted pass/fail pattern positionally — `--nets` only still matters for **cross-
continuity discovery** (`CONT RUN discover`), which has no netlist to defer to and always scans
the simulator's own fixed `--nets`-sized fake harness.

1. Launch the app with `--sim` (or `--serial,COMx` for real hardware, where none of this
   applies — the instrument reports its own netlist and the demo simulator doesn't exist).
2. Connect.
3. In the Continuity view, switch to **netlist** mode (the cross/net toggle).
4. Click **Select…** in the MTX netbar.
5. Choose **Browse the file system…** and pick any `.xlsx` file from this folder.
6. Run `CONT RUN verify` or `RES RUN` — expect PASS.

The same file can be loaded from the Resistance view — continuity and
resistance share the same MTX netlist.

`gui_flutter/test/demo_fixture_smoke_test.dart` pins the three `AV-880_MTX_*.xlsx` files against
a simulator booted with the matching `--nets`, and `gui_flutter/test/simulator_pairing_test.dart`
pins the `--nets`-independence this section describes (including a file bigger than `--nets`),
so a client demo never regresses on either.

## How to regenerate

```bash
python test_netlists/generate_test_netlists.py
```

The generator is committed alongside the `.xlsx` files so the test data stays
reviewable in diffs even though the binary workbooks are not.

## Connector-layout test files (`TN-*.xlsx`)

The files above only ever exercise the plain `NET`/`HI`/`LO` shape — none of them
have `Conn ID`/`Part Number` columns, so none of them exercise the connector-layout
*guess* (`netlist_file.dart`'s `_guessFixture`/`_guessShape`, the thing that turns a
netlist file into named connectors like "DB9"/"DB37" instead of raw flat pin
numbers — see `PROJECT_LOG.md` GUI-11/GUI-23). These five do, each built to land on
a different code path in that guess:

| File | Nets | What it tests |
|---|---|---|
| `TN-01_symmetric_dsub_pair.xlsx` | 46 | One mating connector pair per block (same `Conn ID` on Source and Destination — an in-line splice, not box-to-box). `GuessedConnector.side` ends up `null` (ambiguous), one shared base sequence. DB9 (9p) then DB37 (37p), both shape-guess `dsub`. |
| `TN-02_distinct_src_dst_connectors.xlsx` | 46 | Box-to-box harness — Source and Destination are genuinely different connectors. Exercises `allSided=true` (separate Source/Destination base sequences) and all three shape guesses at once: DB9 (`dsub`), a 37-pin MIL circular (`circ`), one 46-pin TE CPC block (`rect`). |
| `TN-03_many_small_connectors.xlsx` | 54 | Six small DB9 mating pairs back to back — six separate 9-pin blocks, not one merged connector; stresses block-boundary inference across several consecutive connectors. |
| `TN-04_single_large_connector.xlsx` | 100 | One 100-pin connector, both ends — the "everything is one block" case, no boundary inference needed at all. |
| `TN-05_partial_unused_pins.xlsx` | 26 | A real 9-pin DB9 with only 6 pins wired, followed by a real 37-pin DB37 with only 20 wired. The DB9's unused trailing pins are correctly inferred (extended to just before the DB37 starts) since something else bounds it; the DB37's are **not** — it's the last connector in the file, so nothing bounds its guess and it comes out as a 20-pin connector, not 37. A genuine, documented limit of the guess (see `_fixtureFromGuess` in `app_state.dart`), not a bug in this fixture. |
| `TN-06_conflicting_connector_id.xlsx` | 46 | A real bug, found by hand-editing `TN-01` and turned into a permanent regression case: `DB37-1` is used two different ways in one file — as its own mated pair (pins 10-46, native, like `TN-01`) **and** as the Destination for `DB9-1`'s pins 1-9 (a genuine box-to-box wire, like `TN-02`). Before the fix this corrupted `DB37-1`'s guessed pin count (46 instead of 37) and shifted its offset so pins 1-9's Destination side could never resolve back to it — both ends of that net silently resolved to `DB9-1` instead, drawing as a zero-length "wire" that looked exactly like an open/not-connected net despite passing electrically. Now `DB37-1` keeps its correct 37-pin native range and `GuessedConnector.conflicting` flags the id collision so the operator gets a warning instead of a silently wrong diagram. |

Regenerate with:

```bash
python test_netlists/generate_connector_test_netlists.py
```

`gui_flutter/test/connector_test_netlists_test.dart` reads all six off disk through
the real parser and pins every guess above — including TN-05's asymmetric
6-of-9/20-of-37 result and TN-06's conflict detection — so a change to the guessing
logic can't silently drift without a test noticing.

**Part-number pitfall worth knowing:** `_guessShape` treats any part number
containing `"AMPHENOL"` as **circular**, not rectangular — real Amphenol connectors
come in both. TN-02/TN-04's rectangular case deliberately uses a TE Connectivity CPC
part number instead, so it doesn't trip that keyword.
