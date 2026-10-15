# required_format/ — report and netlist format examples

Reference examples for the two file shapes the GUI reads (netlist in) and writes (reports out).
Not consumed by any code directly — these are the spec, by example — but `lib/app/report.dart`
and `lib/app/report_pdf.dart` (added 2026-08-14, GUI-10/CL-42) are built to match them.

## Netlist in

`example_netlist27072026.xlsx` — the operator-supplied netlist convention: `Net`, `Source`,
`Conn ID`, `Part Number`, `Src Pin Label`, `Src Pin #`, `Dst Pin #`, `Dst Pin Label`,
`Conn ID B`, `Part Number B`, `Destination`, `Connector Detail`, `Harness ID`.

`lib/htproto/netlist_file.dart` reads `Net`/`Src Pin #`/`Dst Pin #` (header aliases added
2026-08-10 so these exact names are recognised) and ignores the rest.

**GUI-08 resolved (2026-08-14, CL-41)** — this file loads as-is; no `Conn ID` → offset map is
needed. Two things were previously misread: **(1)** `Src Pin #`/`Dst Pin #` in this file are
already globally flat, not per-connector — `DB15-1` occupies 1..15, `DB15-2` occupies 16..30,
`DB9` occupies 31..39, sequential by connector order, exactly what `NETLIST ADD <hi> <lo>` wants.
**(2)** the parser used to reject any row where `Src Pin # == Dst Pin #` (its straight-through
rows, e.g. `DB15-1` pin 1 → pin 1), reading a matching number as "wired to itself." That was
wrong: `matrix_card.h` routes HI and LO through entirely separate mux/expander banks
(`hi_en[]`/`hi_sns[]` vs `lo_en[]`/`lo_sns[]`, different physical chips), each independently
addressed `1..256` — a matching pin number on both sides is the ordinary case for a symmetric
male/female connector pair, not a collision. The guard is gone; see `test/netlist_file_test.dart`.

**Full-scale draft (2026-08-17, GUI-18/CL-52)** — `netlist_full_256x256.xlsx` is the same
column shape, filled for every one of the instrument's 256 independently-addressed HI pins and
256 LO pins (512 pins total across both sides), not just a curated few nets. Straight-through
(`Src Pin # == Dst Pin #` on every row, same GUI-08 convention above). `Conn ID`/`Part Number`
group into four 128-pin blocks — `MTX-A1` (pins 1-128) / `MTX-A2` (129-256) on Side-A, `MTX-B1`
/ `MTX-B2` mirroring on Side-B — a **draft fixture proposal**, one of the combinations the user
asked about (DB37s, a single high-pin-count Amphenol, or two 128-pin connectors per side); 128 x
2 was picked as the cleanest round split of 256. `Part Number` reads `AMPHENOL-128CKT (TBD)` on
every row rather than a real catalog number — there is no fixture connector part number decided
anywhere else in this repo (`fw_status.txt`/`Doc/` name `J-MTX`/`J-HV` but no physical connector
P/N), so this is something to confirm with mechanical/procurement, not a hardware fact. A working
copy also lives in `test_netlists/` so it's loadable from the GUI's netlist picker. See
`fixture_connector_layout_256x256.xlsx` below for the same four-connector breakdown as a
standalone mechanical reference table. `test/netlist_file_test.dart` reads it end to end the
same way it does the original sample.

**Now passes against `--sim` too (2026-08-17, GUI-21/CL-55)** — this file's straight-through
pairing (`Src Pin # == Dst Pin #`, the real instrument's HI/LO addressing convention) used to
read 0 pass in the demo: `htproto/simulator.dart`'s fake harness compared each uploaded `(hi,
lo)` against its own fixed internal pairing (`1↔2, 3↔4, 5↔6, …`) by literal value, and this
file's `1↔1, 2↔2, 3↔3, …` never matched at any `--nets` value. Fixed at the root — GUI-21 below —
by applying the scenario's scripted pass/fail pattern *positionally* to whatever was actually
uploaded instead of by literal pin match, so the `'pass'` scenario now genuinely means "every
net you load passes," this file included, not just files that happen to already use the
simulator's own baked-in pairing.

`fixture_connector_layout_256x256.xlsx` — not a netlist (`netlist_file.dart` never reads it);
a plain reference table of the same draft breakdown for whoever specs/procures the physical
fixture: `Side`, `Conn ID`, `Part Number`, `Connector Type`, `Pin Range Start/End`, `Pin Count`,
`Mounting Location`, `Mates With`, `Notes`. Every `Mounting Location`/exact-P/N field is a
placeholder pending a real mechanical decision.

## Reports out — continuity (the two originals)

`report_20260727_141108_HT-0008.csv` and `report_20260725_184312_HT-0004.pdf` — taken from the
old GUI's continuity report. Format: a `#`-prefixed metadata block (`DUT ID`, `Operator`,
`Netlist`, `Verdict`, `Date/Time`), a blank line, then a results table — `Test #, Source, Part
Number, Conn ID, Src Pin Label, Src Pin #, Status, Dst Pin #, Dst Pin Label, Conn ID, Part
Number, Destination`. The PDF adds a Summary block (Total/CONNECTED/NOT CONNECTED) above the
same table. `ContReport.toCsv()`/`buildContReportPdf()` (`lib/app/report.dart`/`report_pdf.dart`)
match this exactly; `Source`/`Part Number`/`Conn ID`/`Destination` stay blank, same as the
samples — the wire protocol (`!CONT <hi> <lo> <status>`) carries pins only, never connector
metadata.

## Reports out — resistance and HV insulation (added 2026-08-10)

Same metadata-block + Summary + Results convention, fields swapped for what each test actually
measures — column names and enum values traced to the wire protocol, not invented:

- **`report_..._resistance.{csv,pdf}`** — `Status` is `PASS`/`FAIL_HIGH`/`FAIL_LOW`
  (`ResResult.status` in `lib/htproto/messages.dart`, wire `!RES <hi> <lo> <milliohms>
  <pass|fail_high|fail_low>`). `R (mOhm)` is `milliohms`. `Limit (mOhm)` is `r_max_mohm`
  (`LIMITS GET`). Summary is Total/PASS/FAIL HIGH/FAIL LOW, not a binary pass/fail, since the
  wire enum has three states.
- **`report_..._insulation.{csv,pdf}`** — insulation tests one net against every other
  conductor, not a pin pair (see `two-stage-test-workflow` in project memory), so the row shape
  is per-net: `Net`, `HV Card`, `HS Pin`, `Leak V`, `Insulation (MOhm)` — the same columns
  `lib/views/res_hv_views.dart`'s `_NetResults` table shows (real since GUI-09/CL-40 — no longer
  a UI mock). `Status` is `PASS`/`FAIL` (`InsulResult.status`, wire `!INSUL <net> <leak_mohm>
  <pass|fail>` — two states, not three; the "Marginal" tier `_NetResults` used to show doesn't
  exist on the wire, so it's not in this format either). `Limit (MOhm)` is `ins_min_mohm`. `Leak
  V` has no wire field at all — `InsulReportRow.leakV` is a derived estimate (rail voltage
  through the R3002/R3004 sense divider), the same formula and the same caveat as the live
  "Leakage" meter (`AppState.paintLink()`'s `mLeak`).

**Both report writers exist now (2026-08-14, GUI-10/CL-42)** — `lib/app/report.dart` (data model
+ CSV) and `lib/app/report_pdf.dart` (PDF, via the `pdf` package). Built from the real per-pin/
per-net rows a run streams in while it executes (`AppState._onCont`/`_onRes`/`_onInsul`), not
persisted — a report stays available (`AppState.lastContReport`/`lastResReport`/
`lastInsulReport`) until the next run of that kind starts, same lifetime `AppState.nets` already
has. `DUT ID`/`Operator` are new operator-entered fields on the status bar
(`AppState.dutId`/`operatorName`), session-scoped, not persisted. Exported from the Results
view's "Test reports" panel.

**PDF now matches the samples column-for-column, not just the CSV (2026-08-17, GUI-17/CL-51)**
— `report_20260725_184312_HT-0004.pdf`'s bundled `company_logo.jpeg` and dark-header/green-red
row-tinted table styling are reproduced (`assets/company_logo.jpeg`, declared in `pubspec.yaml`,
loaded via `rootBundle`), and the Results table has the full column set the CSV always did —
`Conn ID` (real since GUI-11) and the permanently-blank `Source`/`Part Number`/`Destination`
were previously dropped from the PDF only. **"Test Duration" is real** (`AppState._runStart` to
`_onDone`, PDF-only, not part of the CSV shape). **"Profile" is deliberately not reproduced** —
there is no profile/preset concept anywhere in this app to draw a real value from; printing one
that looks real but isn't is exactly what the "GUI Reality Check" work (GUI-09/12/13) removed
elsewhere. The GUI's own `ConnectionResultsTable` (Continuity/Resistance/HV "Connection results"
panels) mirrors the same field set live on screen, same reasoning as the CSV/PDF twin.
