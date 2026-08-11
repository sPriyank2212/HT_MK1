# required_format/ — report and netlist format examples

Reference examples for the two file shapes the GUI reads (netlist in) and will need to write
(reports out). Not consumed by any code — these are the spec, by example, for GUI-04/GUI-05
(`PROJECT_LOG.md`) once report generation is built.

## Netlist in

`example_netlist27072026.xlsx` — the operator-supplied netlist convention: `Net`, `Source`,
`Conn ID`, `Part Number`, `Src Pin Label`, `Src Pin #`, `Dst Pin #`, `Dst Pin Label`,
`Conn ID B`, `Part Number B`, `Destination`, `Connector Detail`, `Harness ID`.

`lib/htproto/netlist_file.dart` reads `Net`/`Src Pin #`/`Dst Pin #` (header aliases added
2026-08-10 so these exact names are recognised) and ignores the rest. **GUI-08 (see
`PROJECT_LOG.md`): every row in this example has `Src Pin # == Dst Pin #`** — the sheet numbers
pins per-connector and relies on `Conn ID` to disambiguate, but the parser, the wire protocol
(`NETLIST ADD <hi> <lo>`) and the firmware's matrix routing all use one flat `1..256` fixture
address with no connector concept. Loaded as-is, every row collides and is rejected (correctly
— see `test/netlist_file_test.dart`'s GUI-08 test). A `Conn ID` → base-offset map is needed
before this exact file can load; until then, netlists must supply already-global pin numbers.

## Reports out — continuity (the two originals)

`report_20260727_141108_HT-0008.csv` and `report_20260725_184312_HT-0004.pdf` — taken from the
old GUI's continuity report. Format: a `#`-prefixed metadata block (`DUT ID`, `Operator`,
`Netlist`, `Verdict`, `Date/Time`), a blank line, then a results table — `Test #, Source, Part
Number, Conn ID, Src Pin Label, Src Pin #, Status, Dst Pin #, Dst Pin Label, Conn ID, Part
Number, Destination`. The PDF adds a Summary block (Total/CONNECTED/NOT CONNECTED) above the
same table.

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
  `lib/views/res_hv_views.dart`'s `_NetResults` table already displays (that table's data is
  currently a UI mock; this is the same shape, not a new one). `Status` is `PASS`/`FAIL`
  (`InsulResult.status`, wire `!INSUL <net> <leak_mohm> <pass|fail>` — two states, not three;
  the mock table's "Marginal" tier is GUI presentation, not something the instrument reports,
  so it's deliberately not in this format). `Limit (MOhm)` is `ins_min_mohm`.

Neither report writer exists in code yet — GUI-05 (run history storage: instrument vs. GUI
host) has to be answered first, since that decides where the source data for a report comes
from.
