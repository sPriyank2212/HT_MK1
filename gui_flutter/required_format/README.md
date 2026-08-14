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
