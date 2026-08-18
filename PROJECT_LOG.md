# HT_MK1 — Project Log

One place to see where the project stands: what is open, what is closed, and what happened on
each working day.

- **Status snapshot** and **Open items** are live — edit them in place as things move.
- **Closed items** and **Activity log** are append-only. Newest day first.
- This file tracks *tasks and decisions*. See [README.md](README.md) for the document map —
  there are four living docs and this is the entry point to them.

ID prefixes: `HW-` schematic/hardware · `FW-` firmware · `BU-` bring-up/verify · `DOC-` documentation ·
`GUI-` raised against the external GUI effort (tracked here so nothing is only in the brief).

---

## Status snapshot — 2026-08-18 (GUI-26: dead "Fault pareto" panel removed from the Results tab)

| Category | Count |
|---|---|
| Blocking — firmware cannot proceed | **0** |
| Agreed, awaiting schematic edit | 3 |
| Awaiting a decision | 3 |
| Firmware work queued | 1 |
| Awaiting the GUI side | 1 |
| Verify at bring-up | 9 |
| Closed to date | 60 |

**GUI-26 (CL-60): the Results tab's "Fault pareto · this shift" panel removed — it could never show
anything.** User asked what it was for; it's a Pareto chart of fault types by frequency (a
standard manufacturing-QA "fix the most common failure first" view), but `RunHistoryEntry`
(`app/run_history.dart`) only ever stored pass/fail *counts* per run, never per-fault codes or
locations — so the panel was permanently stuck on its own hardcoded "Not tracked yet" message,
regardless of how many runs piled up. Confirmed genuinely dead (no test referenced it, nothing
else read from it) and removed the whole `HtPanel` from `ResultsView`
(`lib/views/misc_views.dart`) rather than leave known-dead UI around. Reviving it for real would
mean extending `RunHistoryEntry` to carry fault codes/locations — a real feature addition, not
something to fake back in. `flutter analyze`: 0 issues. `flutter test`: 229/229 (unchanged).

**GUI-25 (CL-59): the demo simulator's insulation test was hardcoded to `--nets` (12 by default),**
**completely unaware of the loaded netlist — the same bug class GUI-21 fixed for continuity/
resistance, just never extended to HV.** User asked why the HV section only ever showed 12 pins
regardless of how many nets were actually loaded. Checked the real firmware first rather than
guessing at the fix: `run_insulation_all()` (`Core/Src/app/tasks.c`) iterates
`Proto_NetlistCount()`/`Proto_NetlistGet()` — the *same* MTX netlist continuity/resistance
upload via `NETLIST BEGIN/ADD/END`, confirming insulation genuinely shares it on real hardware
(the HV netlist *file* the GUI lets an operator browse only ever set a card count for
`stackMatch()` — see GUI-11/required_format's README — it was never the source of per-net
topology). Each result is reported against the real hi pin (`Proto_EvtInsul(hi, ...)`).
`htproto/simulator.dart`'s `_runInsul` did neither: it always iterated the fixed
`scenario.nets` (sized by the launch-time `--nets` flag, 12 by default) and emitted
`INSUL <sequential index 1..N> ...` instead of the real pin — so loading a netlist with more
(or just different) nets than 12 either capped the results at 12 or matched the wrong ones
entirely once `AppState._onInsul`'s `_netByHiPin` tried to resolve that index against real pin
numbers. Fixed by reusing GUI-21's `_effectiveNets(_st.netlist)` (already positionally applies
the scenario's scripted pass/fail pattern to whatever was actually uploaded) and reporting each
result's real `hi` pin instead of a loop index. Verified end to end against a real
`SimulatorServer`: new `test/insulation_pairing_test.dart` uploads a 20-net MTX netlist, moves to
J-HV, arms, and runs insulation — all 20 nets resolve now, not just the first (or a mismatched)
12. `flutter analyze`: 0 issues. `flutter test`: 229/229.

**GUI-24 (CL-58): every internal hardware/bus detail across the whole app is developer-only now,
not just what's behind the Diagnostics tab.** User asked directly: SPI/I2C/chip-level detail has
no business in the customer GUI, only the developer build. GUI-14 (2026-08-16) had already split
customer/developer at compile time (`kCustomerBuild`), but only ever gated the Diagnostics tab as
a whole — every other view (Run, Continuity, Resistance, HV) still showed chip part numbers, bus
protocol names, register addresses and internal signal names unconditionally, e.g. Continuity's
`Band` row `CD74HC4051 · 256 HS × 256 LS`, Resistance's `Sense path` panel tracing
`ADS124S08 IDAC1 → AIN9 → HI_COM → ... → R131 100 Ω`, HV's `Leakage loop` panel
(`DAC8830 → CA05P-5 → ... → R3002 1 MΩ ... R3004 1 kΩ`), and the bottom log bar's "Console" tab
(raw `>CMD`/`<REPLY`/`!EVENT` wire protocol traffic — about as internal as this app gets).
Audited every view file with a subagent first, then went through the findings one at a time.
Three patterns: **(1)** whole panels whose only purpose is an internal signal trace —
Continuity's "Switch path", Resistance's "Sense path", HV's "Leakage loop" — dropped entirely
(`if (!kCustomerBuild) HtPanel(...)`), including reworking the layouts around them so a customer
build doesn't leave a blank slot where the panel used to be. **(2)** individual rows inside a
panel that's otherwise customer-relevant (a `Band` mixing "Connector"/"Scan scope" — real,
useful — with "Switching"/"Sense" — internal chip names) — the internal rows are conditionally
spread in (`if (!kCustomerBuild) ...[...]`), the customer-relevant ones stay unconditional.
**(3)** single strings that mix one legitimate fact with one internal identifier (`"4-wire Kelvin
· ADS124S08 IDAC1"`, `"500 V DC · R3002 1 MΩ"`, the HV rail's "Leakage" meter caption naming a
raw trip voltage) — reworded per-build with a ternary rather than dropping the whole row, so the
customer-relevant half survives. Also gated: the bottom log bar's "Console" tab (raw wire
traffic — the "Log" tab, human-readable run events, stays for everyone), the Run view's
domain-card condition text (`AppState.dcCond`/`dhCond`, and a literal string in `run_view.dart`
itself), the "Fixture sequence" panel's stage-box text (`CD74HC4051`/`MHV05` part numbers,
`lib/app/parts.dart`), and one stray `I2C2` each in an HV-netlist explainer modal
(`lib/app/modals.dart`) and a status-bar log line (`AppState.pickStack`). Left the Program view's
"HV nets" table (which HV card/relay a net lands on) alone — that's a harness/wiring assignment
an operator setting up a real fixture plausibly needs, not MCU-bus-level detail like the examples
above; flagged for the user rather than assumed. Verified two ways: the full test suite passes
unchanged under the normal (developer) default, and re-run with `--dart-define=CUSTOMER_BUILD=true`
end to end — every view builds/lays out cleanly across wide/medium/narrow and light/dark with the
internal panels/rows/tabs gone, and the only test failures are the three that are *supposed* to
fail under that flag (the Diagnostics-tab test, the Console-tab test, and `build_tag_test.dart`'s
own "defaults to false" check). `flutter analyze`: 0 issues. `flutter test`: 228/228 (default).

**GUI-23 (CL-57): two real bugs found from one user report — src/dst pin resolution, and a Part**
**Number column that had data available but was never wired up.** User reported the continuity
wiring diagram/results looked wrong: "Connector A pin 1 and pin 2 are connected" when it should
read "Connector A pin 1 -- Connector B pin 1." Traced to `AppState.rebuildNets`'s `pinNode` —
it searched the *same* flat connector list for both `hi` and `lo`. HI and LO are the
instrument's two independently-addressed 1..256 spaces (matrix_card.h) — not a shared range — so
a straight-through net (`Src Pin # == Dst Pin #`, the ordinary case per GUI-08) always resolved
src and dst to whichever connector happened to own that numeric sub-range, regardless of which
side (`Conn ID` vs `Conn ID B`) it actually came from. Every net in `netlist_full_256x256.xlsx`
showed "MTX-A1 pin 5" on *both* ends instead of "MTX-A1 pin 5" -> "MTX-B1 pin 5" — confirmed with
a diagnostic probe against the real file before touching any code. This had been broken since
GUI-11 shipped (2026-08-14); it slipped through because the only existing coverage checked
`srcConnId != dstConnId` never got asserted, just `!= '—'` (not blank), and the demo's own seeded
harness (`buildNets()`) bypasses `pinNode` entirely so it never exercised the bug. Fixed two
things together: **(1)** `_fixtureFromGuess` now computes `base` as two *separate* running
offsets (Source and Destination each restart at 0) whenever a guess has real per-connector
side provenance (`GuessedConnector.side`, GUI-19), instead of one combined sequence across all
four — falls back to the old combined sequence when side is ambiguous (a symmetric connector
pair reusing one id for both mating halves, e.g. `example_netlist27072026.xlsx`, unchanged).
**(2)** `pinNode` now takes `isSrc` and searches Source-side connectors first for `hi`,
Destination-side first for `lo`, falling back to the unrestricted search only when the
side-specific one comes up empty — which also required rewriting `rebuildNets`'s "extend the
fixture to cover an unmatched pin" fallback to run that *same* side-then-fallback search
(`coversPin`) rather than compare against a precomputed numeric boundary, since a fixture can be
in either base scheme and only the real search gets both right. Second bug, found investigating
the first: the report/GUI's "Part Number" column was hardcoded blank in `report.dart`/
`report_pdf.dart`/the GUI's `ConnectionResultsTable` even though the netlist file's own `Part
Number`/`Part Number B` columns were already parsed (`GuessedConnector.partNumber`) — the value
just dead-ended at `_fixtureFromGuess`, folded into `ConnectorDef.label` (a display name, not a
part number — the demo fixture's own labels are things like "Engine bay") instead of kept
separate. Added a real `ConnectorDef.partNumber` field (default `''`, so `buildFixture`'s demo
defs and other call sites are unaffected), threaded through `_fixtureFromGuess`,
`FixtureGuessModal`'s confirm step (so editing shape/label doesn't wipe it), `_onCont`/`_onRes`
(`ContReportRow`/`ResReportRow` gained `srcPartNumber`/`dstPartNumber`), and every place that
previously hardcoded `''` for that column — CSV, PDF, and the GUI's "Connection results" tables.
`Source`/`Destination` (the free-text labels, distinct from Part Number) stay blank still — genuinely
not parsed from the file anywhere, unlike Part Number, so left alone rather than half-fixed.
Verified end to end against a real `SimulatorServer` and a real uploaded netlist, not just by
reading the code: new `test/pin_resolution_test.dart` (src/dst resolve to different connectors,
real part numbers flow through to the CSV, blank stays blank when the netlist has none — not
fabricated), plus a new `netlist_file_load_test.dart` case pinning the fix at the parser/guess
layer directly. `flutter analyze`: 0 issues. `flutter test`: 228/228.

**GUI-22 (CL-56): untested ("idle") wires in the wiring diagram were nearly invisible — a real
contrast bug exposed by the taller vertical diagram, not a rendering failure.** User loaded a
netlist, saw pin dots and connector shells clearly, but no lines between them at all.
`painters.dart`'s `_paintWires` drew idle (not-yet-tested) nets in `c.gridEmpty` at .55 alpha —
`gridEmpty` (`0xFF1B282D` dark theme) is meant for *empty grid cells*, barely different from the
canvas background `c.sunk` (`0xFF0E171A`); at reduced alpha over a thin 1.5px stroke it's
essentially invisible. On the old compact 8-connector canvas the wires were short diagonal
curves, faint enough not to matter; GUI-19's vertical ladder can run an idle wire most of the
canvas's 1060px width, at which point "barely visible" became "not visible" — confirmed by
rendering the exact idle state to a PNG and inspecting it pixel by pixel, not just reading the
code. Meanwhile the pin *dots* for the same untested nets were already drawing in `c.ink3` (a
much lighter grey, `0xFF6E878F`), so the inconsistency was really "dots visible, wires using a
different, much darker colour for the same 'present but untested' meaning." Fixed: idle wires
now use `c.ink3` (matching the dots) and a slightly higher alpha (.55 → .7). Verified by
re-rendering the same idle state — wires clearly visible now, still visually subdued relative to
pass (green)/fail (red)/hovered (accent), which is the intended hierarchy. `flutter analyze`: 0
issues. `flutter test`: 225/225 (no behavioural change to test — this is a colour choice, not
logic — verified visually via the PNG render instead).

**GUI-21 (CL-55): reverses GUI-20's "real hardware only" call — the demo simulator now honours
whatever netlist gets uploaded, not just its own baked-in pairing.** User pushed back: the file
should "strictly pass" in the demo, not be carved out as real-hardware-only. Root cause (from
GUI-20's trace) was `htproto/simulator.dart`'s `_runCont`/`_runRes` comparing an uploaded `(hi,
lo)` pair against the scenario's fixed `_goodNets()` pairing (`1↔2, 3↔4, 5↔6, …`) *by literal
value* — any netlist using a different, equally-valid pairing (real hardware's straight-through
`Src Pin # == Dst Pin #`) could never match. Fixed at the actual root instead of working around
it with a second file: new `InstrumentSim._effectiveNets(netlist)` reuses the scenario's
scripted pass/fail/open/short pattern *positionally* — row `i` of whatever was uploaded gets row
`i`'s scripted outcome, with rows past the scenario's own length defaulting to pass — instead of
matching by literal pin value. Falls back to the scenario's fixed nets unchanged when nothing's
been uploaded, so demo-without-a-netlist behaviour is untouched. Applied to both `_runCont`'s
verify path and `_runRes` (resistance shares the MTX netlist with continuity on real hardware);
left `_runInsul` alone — there is no wire-protocol netlist upload for HV at all (`NETLIST` is
MTX-only), so it has nothing to defer to. **Side effect, verified separately**: this also
resolves the older "`--nets` must match the loaded file's net count or CONT RUN FAILs"
constraint (`test_netlists/README.md`) for verify-mode runs generally, not just this one file —
a 20-row netlist now passes fully against a simulator booted with the 12-net default, confirmed
with a throwaway probe test before writing the permanent one. New
`test/simulator_pairing_test.dart`: a straight-through netlist passes end to end against a real
`SimulatorServer`, `opens_shorts` still injects faults positionally rather than by literal pin
match, and a bigger-than-`--nets` netlist passes fully. `required_format/README.md` and
`test_netlists/README.md` corrected — the "real hardware only" language GUI-20 added is now
"passes against `--sim` too," and `test_netlists/README.md`'s `--nets`-matching instructions
rewritten to describe the new (much simpler) reality. `flutter analyze`: 0 issues. `flutter
test`: 224/224.

**GUI-20 (CL-54): `netlist_full_256x256.xlsx` (GUI-18) shows 0 pass against the customer demo — traced,
confirmed expected, not a bug.** User reported `CONT RUN verify` reading 0 pass with this file
loaded in the customer demo build. `htproto/simulator.dart`'s fake harness is a fixed internal
model set at launch (`_goodNets()`: pin 1↔2, 3↔4, 5↔6, …), completely independent of whatever
netlist actually gets uploaded afterward — `_runCont`'s verify path looks up each uploaded
`(hi, lo)` pair against that fixed model and reports NOT CONNECTED for anything not in it.
`test_netlists/`'s three `AV-880_MTX_*.xlsx` files work in the demo only because they were
*generated* to already match that 1-2/3-4 pattern (`test_netlists/README.md` says so directly);
`--nets` only ever needed to match their net *count*. `netlist_full_256x256.xlsx` uses the real
instrument's straight-through addressing instead (`Src Pin # == Dst Pin #` — HI and LO are
separate independently-addressed banks, `matrix_card.h`), which never matches the simulator's
fixed 1↔2/3↔4 model at any `--nets` value — 0 pass is the simulator working as designed, not a
netlist or parser defect. Asked the user how to proceed (real-hardware-only vs. a demo-safe
variant vs. teaching the simulator to accept any uploaded pairing); **decided: real hardware
only** — no code change. `required_format/README.md` and `test_netlists/README.md` both updated
with an explicit "does not pass against `--sim` at any `--nets` value, use `--serial`" note so
this doesn't get re-discovered as a bug.

**GUI-19 (CL-53): the wiring diagram redrawn as a vertical pin ladder, and a real bug in how
Source/Destination connectors get assigned to each side.** User loaded GUI-18's
`netlist_full_256x256.xlsx`, screenshotted the result, and called it out directly: the diagram
was unreadable, connector shells overlapping each other. Root cause was `design/model.dart`'s
per-shape connector footprint (`connSize`/`layoutConn`) — a D-sub's pins are laid out as two
staggered rows, which scales *width* with pin count; at 128 pins that's ~860px, nearly the whole
1060px canvas, so two such shells stacked in the same column visually collided. Fixed by
replacing the three per-type footprints (D-sub two-row, circular concentric rings, rect grid)
with one layout for every connector: a single vertical column, pin 1 at the top, one row per pin
— scales to any pin count by getting taller, never wider. `kCanvasH` (`design/model.dart`) is no
longer a fixed `440` const; `layoutFixture()` now grows it to fit whatever the current fixture
actually needs (floor of 440, so the original 8-connector demo fixture's canvas is unchanged).
`painters.dart`'s `_paintConnectors` drops the D-sub/circular-specific shell geometry for one
plain rounded-rect shell, and now draws a pin-number label in the space freed up next to each
dot. **Found a second, independent bug tracing why the layout looked wrong even before the
overlap**: `AppState._fixtureFromGuess` split connectors left/right by blind list-half of a
minPin-sorted list, with no concept of which side of the netlist (`Conn ID` vs `Conn ID B`) a
connector actually came from — fine for `example_netlist27072026.xlsx` (which reuses one id for
both mating halves of a symmetric pair), but for GUI-18's file (distinct ids per side, e.g.
`MTX-A1`/`MTX-B1`), the sorted order interleaves Source and Destination ids, so the "left/right"
split scattered one harness end's connectors across both visual halves instead of keeping
Source on the left and Destination on the right. Fixed: `GuessedConnector` (`netlist_file.dart`)
now records `side` ('src'/'dst'/null — null when an id genuinely appears on both columns, the
symmetric-pair case), and `_fixtureFromGuess` uses it to split left/right whenever every
connector in the guess has one, falling back to the old list-half heuristic otherwise (keeps
`example_netlist27072026.xlsx`'s existing behaviour exactly). Verified by rendering the actual
`netlist_full_256x256.xlsx` fixture through the real `DiagramPainter` to a PNG (not just
inferred from code): Side-A's two 128-pin blocks and Side-B's two 128-pin blocks land at
identical y-coordinates, straight-through nets draw as short horizontal lines row-for-row, zero
overlap. New tests: `netlist_file_test.dart` (`GuessedConnector.side` src/dst/null),
`netlist_file_load_test.dart` (end-to-end: a distinct-id file splits L/R by side, not sort
order), `gui_test.dart` (vertical single-column pin geometry, no overlap between two stacked
128-pin connectors, canvas grows past the 440px floor). `flutter analyze`: 0 issues. `flutter
test`: 222/222.

**GUI-18 (CL-52): a full-scale netlist covering every one of the instrument's 256 HI/256 LO
pins, plus a draft physical connector layout for the fixture body.** User asked for "one proper
netlist and also the fixture file," then clarified: 256 pins on each side (512 total —
`matrix_card.h`'s `hi_en[]`/`hi_sns[]` vs `lo_en[]`/`lo_sns[]`, each independently addressed
1..256), and asked how those land on real physical connectors mounted on the tester body,
floating a few options (two DB37s, a single high-pin-count Amphenol, or two 128-pin connectors
per side). Checked `fw_status.txt`/`Doc/` first — `J-MTX`/`J-HV` are named throughout but no
physical fixture connector part number is decided anywhere in this repo, so there was no real
answer to defer to; this is a draft proposal, not a recorded hardware fact, and every part
number in the new files is marked accordingly. New `required_format/netlist_full_256x256.xlsx`
— the same `required_format` netlist columns as `example_netlist27072026.xlsx`, one row per pin
1..256, straight-through (`Src Pin # == Dst Pin #`, same convention GUI-08 established), `Conn
ID` grouped into four 128-pin blocks (`MTX-A1`/`A2` Side-A, `MTX-B1`/`B2` Side-B — 128 x 2 per
side, the cleanest round split of 256, one of the user's own suggested options). `Part Number`
reads `AMPHENOL-128CKT (TBD)` throughout, not a fabricated real catalog number. A working copy
also lives in `test_netlists/` so it loads through the GUI's real netlist picker (`--nets 256`
on the simulator to match it). New `required_format/fixture_connector_layout_256x256.xlsx` — a
plain reference table (not read by any code) of the same four-connector breakdown for
mechanical/procurement: `Side`, `Conn ID`, `Part Number`, `Connector Type`, pin range, pin
count, mounting location, mates-with, notes. `netlist_file_test.dart` gained a real end-to-end
regression test against the new file (256 pairs, all straight-through, four 128-pin connectors
guessed correctly), same pattern as the existing `example_netlist27072026.xlsx` test. `flutter
analyze`: 0 issues. `flutter test`: 219/219. **Left open**: the exact connector part
number/shell size is still a placeholder — see the new "Awaiting a decision" row below.

**GUI-17 (CL-51): `required_format`'s two samples reconciled for real.** User pointed at
`example_netlist27072026.xlsx` (netlist in) and `report_20260725_184312_HT-0004.pdf` (report
out) and asked for both to be the format going forward. The netlist side was already done
(GUI-08/CL-41) — confirmed still matching, `netlist_file_test.dart`'s real-file test still
passes, no code change needed. The PDF side had drifted from its own docstring's claim: GUI-10
said the PDF matched "the same column set as the CSV twin," but `buildContReportPdf`'s Results
table only ever had 6 of the CSV's 12 columns — `Conn ID` (real since GUI-11) was silently
dropped, along with the always-blank `Source`/`Part Number`/`Destination` the sample keeps for
shape. Rebuilt `report_pdf.dart`: full column set on every Results table (continuity/
resistance/insulation), dark-header-band + green/red row tinting by status (matching the
sample's colour language, via `TableHelper.fromTextArray`'s `cellDecoration`), and the bundled
`company_logo.jpeg` (new `assets/`, declared in `pubspec.yaml`, loaded through `rootBundle` —
degrades to no logo rather than throwing if the asset is ever missing, so a report is never
blocked on branding). Two of the sample's metadata rows got different treatment: **"Test
Duration"** is now real — new `AppState._runStart` (set in `_beginRun`) feeds
`ReportMeta.testDuration` at `_onDone`, PDF-only (not part of the CSV shape, same as the
sample). **"Profile" was deliberately left out** — there is no profile/preset concept anywhere
in this app to draw a real value from, and printing a field that looks real but isn't is exactly
what "GUI Reality Check" (GUI-09/GUI-12/GUI-13) spent two sessions removing elsewhere; the
sample's own PDF docstring already flagged both rows as tracking nothing this app had before
this fix. Caught one real rendering bug along the way: the `pdf` package's default Helvetica
core font has no glyph for the em dash (`—`, `report.dart`'s "connector unknown" placeholder) —
adding the `Conn ID` column would have printed missing-glyph boxes for every unresolved
connector, so PDF cell text runs through a `_pdfSafe()` substitution (plain hyphen) while the
CSV/GUI keep the em dash Flutter renders fine. GUI-11's shared `ConnectionResultsTable`
(Continuity/Resistance/HV "Connection results" panels) got the same full-field-set treatment on
screen, plus two real fields the HV table was missing entirely (`Leak V`, `Limit (MΩ)` — already
computed, just never displayed). New `test/report_pdf_smoke_test.dart` (PDF bytes non-empty,
logo loads under `TestWidgetsFlutterBinding`, no glyph warnings); `report_test.dart` gained
`ReportMeta.stampDuration` unit coverage and asserts `testDuration` is real on a live-simulator
run. `flutter analyze`: 0 issues. `flutter test`: 218/218.

**GUI-16 (CL-50): the demo build's simulator now heartbeats every 2 s, like real firmware
does — an idle demo connection used to "link lost" at ~5 s.** User rebuilt all four exes and
reported exactly that, for real: a session log confirmed `LINK LOST: no traffic for 5.0s` at
+5.4 s on every demo. `InstrumentSim` never sent anything while idle at all — the identical
false-"link lost" bug this project already fixed on the firmware side
(`Proto_EvtHeartbeat()`), never mirrored into the simulator. New `emitHeartbeat()` (re-sends
`!STATE <current>`) on a `Timer.periodic(2s)` per client connection, cancelled on disconnect
and explicitly in `stop()` so no test can race a pending `Timer`. **Verified live**: rebuilt,
launched the real exe idle for 15 s, log shows heartbeats every 2 s on the dot and zero
`LINK LOST` — the exact failure reproduced from the old log, then confirmed gone. `flutter
analyze`: 0 issues. `flutter test`: 212/212.

**GUI-15 (CL-49): the demo build's simulator now always binds to a random OS-assigned port
instead of the fixed default 46000** — the same default a real `--host`/`--port` TCP-bridge
target uses, so the demo could in principle collide with (or, worse, be mistaken for) an
already-running real server on the same machine. Fixed in `main.dart`'s `--sim` branch; there
is no host/port entry UI exposed under `--sim` (`serialLink` is false, and the status bar's
port selector is the only thing gated on it), so the launch command was already the sole way
the demo's connection target gets set — a random port now guarantees it can never be anything
but the demo's own bundled simulator. `flutter analyze`: 0 issues. `flutter test`: 212/212.

**FW-14 (CL-47): DS18B20 temperature sensor driven — new `drivers/ds18b20`, new `>TEMP READ`
protocol command.** Follow-on to HW-13 below. Bit-banged 1-Wire on `PA0` (open-drain, DWT-cycle-
counter microsecond timing against the confirmed 64 MHz HCLK — not a NOP-loop guess), single
device so every transaction uses SKIP ROM (no ROM search), scratchpad CRC8-checked before a
reading is trusted. `board.c` gained `board_init_temp()` (configures `PA0` directly — not yet in
the CubeMX `.ioc`, same "configure directly so a regen can't clobber it" idiom
`Log_HwInit_LPUART1()`/`ADS1232_HwInit_Nucleo()` already use) and `g_ds18b20`; its failure does
**not** gate `Board_IsReady()` — a diagnostic sensor must not be able to block the electrical-test
subsystems, unlike the matrix/frontend/HV chain. Protocol: `>TEMP READ` → `<OK started`, reading
follows as a `!TEMP <deci_celsius>` event — routed through the sequencer (`CMD_TEMP_READ`), not
answered inline in `proto.c`, because a real conversion blocks ~750 ms and doing that in `tComms`
would stall every other command's reply for as long (same reasoning `>CONT/RES/INSUL RUN` already
follow). Assumes external (not parasitic) power — a fixed worst-case delay is used rather than
busy-bit polling. `Doc/GUI_development_brief.md` §3.2/§3.3/Appendix B updated (new command, new
event) — also corrected two stale Appendix B rows found in passing (`RES RUN` has actually worked
since FW-02; the table still called it always-failing). Full clean `make all` (toolchain resolved
manually, same gap prior sessions hit): 0 errors, 0 warnings, 66772 B text (was 65264 B).
**Unverified on real hardware** — no DS18B20 to bit-bang against in this session; bus timing
follows the standard Maxim AN126 non-overdrive slot times, same caveat this project already
carries for `ads1232.c`'s own bit-banged driver.

**HW-13 (CL-46): schematics resynced — one real change found, plus a filename cleanup.**
User added updated `Doc/*.pdf` schematics; diffed each against the revision it replaces
(`Control_Card 1.pdf`/`HV_Card-3.pdf`/`Matrix_Card-8.pdf`, pulled from git history) via
`pdftotext`, not eyeballed. **Control Card: a new component** — U2, a DS18B20U+T&R 1-Wire
temperature sensor, wired to `PA0` on the `uC` sheet (R2 4.7 kΩ pull-up on `1_Wire`, R3 47 Ω
series on `DQ`). `PA0` was previously unused and undocumented anywhere in `fw_status.txt` or the
codebase. Also 14 new test points (TP1–TP14) on the GPIO-isolator/Isolator sheets, labeling
existing nets (`GPIO0-3_ISO`, `SDA1/SCL1`, `MISO/MOSI`, `MISO1/MOSI1`, `SCK/SCK1`) for probing —
no new signal, no firmware impact. **HV Card:** only a resistor reference-designator shuffle
around R503/R546; the actual net labels (`GPB5`, `GPB7`, `H_CONT`/`L_CONT`, `RET_ISO`) are
unchanged, consistent with a re-annotation artifact of the KiCad resave rather than a topology
change. **Matrix Card:** no content change at all. All three files also dropped their `-N`/` 1`
suffixes (`Control_Card.pdf`/`HV_Card.pdf`/`Matrix_Card.pdf`), resolving the naming inconsistency
flagged in CL-27/CL-32. `README.md`'s hardware baseline table and `fw_status.txt`'s
source-of-truth filenames and bus/pin map updated to match. Firmware follow-on: **FW-14**, done
the same session — see above.

**GUI-14: two build tags — customer (no Diagnostics section) and developer (full).** User
asked for this directly. `lib/app/build_tag.dart`'s `kCustomerBuild` is a genuine
`bool.fromEnvironment` compile-time constant, not a runtime flag reading a launch argument —
set via `--dart-define=CUSTOMER_BUILD=true`, so the AOT/release compiler can prove the
Diagnostics branch unreachable and tree-shake it out of a customer build entirely, not just
hide a menu item a `--dart-define` away from being un-hidden. `app/shell.dart`'s `Rail` only
adds the Diag button `if (!customerBuild)` (parameter defaults to the real flag, overridable so
`test/build_tag_test.dart` can exercise both branches without two separate test runs);
`main.dart`'s view switch gates the `'diag'` route the same way as a defensive fallback.
`build_exe.cmd` restructured: the analyze/test pass stays a single run (the Dart source itself
doesn't change per tag), then a new `:build_variant` subroutine runs `flutter build windows
--release` once per tag and packages each into its own real-hardware + demo SFX pair, so
`dist\` now holds `HT_MK1_GUI_developer.exe`, `HT_MK1_GUI_developer_demo.exe`,
`HT_MK1_GUI_customer.exe`, `HT_MK1_GUI_customer_demo.exe` — real/demo stays the independent
runtime axis it already was (`--serial`/`--sim`), customer/developer is the new compile-time
one. The subroutine is deliberately `call`ed twice with plain sequential lines rather than a
`for` loop body — under this file's existing plain (non-delayed) `setlocal`, a loop body's
`%VAR%` references are all substituted once at parse time before any iteration runs, which
would have silently kept both packaging passes on the first tag's values.
**Verified end to end this session**, and caught a real bug doing it: `Rail`'s vertical layout
(`app/shell.dart`) hardcoded `buttons[0]`…`buttons[6]` by literal index, assuming exactly 7
buttons always — a customer build's 6-button list made `buttons[6]` throw `RangeError` and
would have crashed the shipped customer exe outright, not just the test. Fixed
(`if (buttons.length > 6) buttons[6]`, the Diag slot being the only conditional one).
`test/build_tag_test.dart` had two of its own bugs, unrelated to the app: it checked for
`'Diag'`/`'Run'` when `_RailButton` actually renders labels uppercased, and its harness didn't
give `Rail`'s `Expanded` spacer a bounded height the way the real app's `Expanded(child:
Row(children: [Rail(s: s), ...]))` does. `flutter analyze`: 0 issues. `flutter test`: passes
except one pre-existing test unrelated to this change (`netlist_upload_test.dart`'s
real-`SimulatorServer` discovery test, timing-sensitive under full-suite parallel load — passed
3/3 in isolation, not touched by this session's code). Real `build_exe.cmd` run confirmed all
four exes package correctly (`~8.28 MB` each, developer build ~80s, customer ~68s). One
unrelated finding: the script's `if exist dist rmdir /s /q dist` has no error check, so a
locked leftover from a prior run (the old pre-split `HT_MK1_GUI.exe`, left running/locked from
earlier this session) silently survived alongside the four new exes instead of being cleared —
harmless (the new files are unambiguously named and correct) but worth hardening later.

**GUI-12 (CL-44) and GUI-13 (CL-45): every "GUI Reality Check" finding — fixed AND now
verified.** Both landed unverified in the prior session (no Flutter SDK available then); user
ran `build_exe.cmd` this session and confirmed `flutter analyze`/`flutter test` both pass.
Full account of both in the closed-items table below.

**GUI-11 (CL-43): connector layout is real and configurable, not a hardcoded 8-connector demo
prop.** User asked for this directly: 256 flat instrument pins actually land on several named,
differently-shaped connectors (e.g. "first 37 pins are a DB37, the rest are circular") — the
GUI needed to know that, not just draw a fixed placeholder. Decided with the user: the layout is
**guessed from the netlist file's `Conn ID`/`Part Number` columns**, operator confirms/edits
before it's relied on (not a separate config file, not a fully manual editor); HV card/relay
became a **direct function of the pin number** (`(pin-1)~/64`, `(pin-1)%64`), replacing net-list
-order assignment — flagged VERIFY pending real HV harness wiring, same footing as the BU- items.
`kFix`/`kConn`/`kConnsL`/`kConnsR`/`kFixPins` (`design/model.dart`) are runtime-swappable now
(`setActiveFixture()`) instead of one fixed constant; `netlist_file.dart` groups rows by `Conn
ID`/`Conn ID B`, infers pin-block boundaries and guesses D-sub/circular/rect from the mating
part number; `AppState.rebuildNets()`'s `pinNode()` does a real per-connector lookup instead of
the old `(pin-1) % 128` fabrication; a new `FixtureGuessModal` (`app/modals.dart`) lets the
operator fix a wrong shape/label before applying. Cross-continuity/discovery drops the wiring
diagram entirely (no known connector identity during a scan) and shows only the existing
Side-A/Side-B result table. New shared `ConnectionResultsTable` (`app/parts.dart`) — "every
connection in one table," connector-qualified — now backs Continuity's netlist-verify mode
(previously had no per-pin table at all), and extends Resistance/HV alongside their existing
ranked/worst-N tables. `report.dart`'s `Conn ID` CSV/PDF columns (blank since GUI-10) are
populated for real. `flutter analyze`: 0 issues. `flutter test`: 206/206 (14 new — connector-
guess inference, real pin-mapping, modal confirm/cancel, all against real and synthetic data).

**GUI-10 (CL-42): `required_format`'s CSV + PDF test reports are built.** User asked for the
report side of `required_format/` (netlist side was GUI-08 above) — continuity/resistance/
insulation, both formats, matching the bundled samples column-for-column. New
`lib/app/report.dart` (data model + CSV) and `lib/app/report_pdf.dart` (PDF, new `pdf` package
dependency — pure Dart, no Material, matches this project's existing dependency discipline).
Built from real per-pin/per-net rows captured while a run streams results in
(`AppState._onCont`/`_onRes`/`_onInsul`), snapshotted into `lastContReport`/`lastResReport`/
`lastInsulReport` at `!DONE` — not persisted, decided with the user in favour of simplicity over
`RunHistoryEntry` growing full row detail. New `DUT ID`/`Operator` fields on the status bar
(session-scoped, not persisted, also decided with the user), and a "Test reports" panel on the
Results view with Export CSV/PDF per completed run. `flutter analyze`: 0 issues. `flutter test`:
201/201 (6 new — 4 CSV-format unit tests, 2 real-simulator end-to-end).

**GUI-08 turned out not to need a decision at all (CL-41)** — user report ("select a netlist,
still shows Select…") led straight to it: see below.

**Two items closed today (CL-39, CL-40) — both traced and scoped in a prior session's handoff,
no product/hardware decision blocking either:**
- **FW-13 (CL-39): the bare-dev-kit HardFault is fixed.** `Board_Init()`'s return value was
  discarded at `main.c:106` with nothing tracking success, and `hv_bus_claim`/`hv_bus_release`
  (`hv_card.c`) and `MatrixCard_BusClaim`/`BusRelease` (`matrix_card.c`) wrote to `en_port` with
  no NULL check — on any board where a card's I2C init fails to complete (no daughter card
  fitted, one unseated, or a future partial-hardware bring-up), `>SAFE`, an armed `>FIXTURE`
  change, `>FAULT CLEAR`, or a real fault running `SafetyTask`'s `force_safe_all()` HardFaulted
  the instrument instead of degrading gracefully. Fixed both ends: all four bus-claim/release
  functions are now NULL-guarded the same way `DAC8830_WriteCode` already was, and a new
  `Board_IsReady()` lets the sequencer (`proto.c`) refuse `CONT/RES/INSUL RUN` and `>SAFE` with a
  clean `ERR EHW` when hardware init didn't fully succeed, instead of attempting them. Full clean
  `make all`: 0 errors, 0 warnings, 65264 B text.
- **GUI-09 (CL-40): the "GUI Reality Check" audit's real-data wiring and stale-doc-text items
  fixed.** `AppState._onInsul` now writes real per-net insulation data (`Net.ins`/`insFail`) and
  drives `setRelays()`, so the HV view's relay grid and "Net results" table reflect an actual
  run; `gRail`/`mSense`/`mLeak`/`mLeakBad`/`hzLeak` are real, computed from live `HvEvent`
  millivolts and the last-tested net's leakage; Continuity's "Export CSV" and the status bar's
  firmware version are both wired to real data; `_bootLog()`, the pre-HV verify modal, and the
  stale "Auto-range PGA" button no longer assert or offer things that aren't real; the bus map,
  Instrument limits, Resistance sense-path, and fixture-sequence panels no longer describe
  hardware the schematic has since replaced (`DAC8775`, `U33`, `CD4067`, Matrix rev 6). `flutter
  analyze`: 0 issues. `flutter test`: 194/194.

**GUI-08 (CL-41): resolved as two real bugs, not a design decision.** User reported "I select
the test netlist and it still shows the Select… option" — tracing it found `netlist_file.dart`
rejecting `required_format/example_netlist27072026.xlsx` outright, for two independent reasons,
neither of which needed the Conn-ID-to-offset-map decision GUI-08 had been waiting on since
2026-08-10. **(1)** The parser's `hi == lo` guard treated a matching HI/LO pin number as "wired to
itself" and rejected it — wrong: `matrix_card.h` routes HI and LO through entirely separate
mux/expander banks (`hi_en[]`/`hi_sns[]` vs `lo_en[]`/`lo_sns[]`, different physical chips), each
independently addressed `1..256`, so a matching label on both sides is the ordinary case for a
symmetric connector pair, not a collision — confirmed against the real example file, whose pin
numbers turn out to already be globally flat by connector order (`DB15-1`→1..15, `DB15-2`→16..30,
`DB9`→31..39), not per-connector-relative as GUI-08's original analysis assumed. Guard removed.
**(2)** Separately, and further upstream, the file could not even be *decoded*: it was generated
by `openpyxl`, whose default `.xlsx` writer emits a package-absolute worksheet relationship
target (`Target="/xl/worksheets/sheet1.xml"`) — legal OOXML, but the `excel` package (4.0.6) only
handles the relative form and crashed with a bare null-check failure instead of a catchable
error. Confirmed with a fresh `openpyxl.Workbook().save()` that this is *every* openpyxl file,
not one bad export — a real compatibility gap for any operator-supplied netlist from that tool,
not a one-off. Fixed by patching the relationship XML before handing bytes to the `excel`
package (`netlist_file.dart`'s new `_normalizeRelationshipTargets`, using the `archive` package
already pulled in transitively — now declared directly). `required_format/README.md` corrected.
New regression test reads the real bundled file off disk end to end (20 pairs). `flutter
analyze`: 0 issues. `flutter test`: 195/195.

**Five decisions the round before (CL-35 through CL-37, plus HW-04 and HW-09 below):**
- **HW-04 agreed** — routes to `AIN8` (not the originally-proposed `AIN2`), next schematic
  revision. Moved to "agreed, awaiting schematic edit."
- **HW-09 left open at the user's request** — a 5th-HV-card-via-J1-spare-pins plan is being
  worked out; the exact mechanism isn't settled. See the row itself for what was verified
  (the real J1 pinout, read pin-by-pin off `Control_Card 1.pdf`) versus what's still open.
- **GUI-04 decided: RAM-only** (CL-35) — no code change, matches current behaviour.
- **GUI-05 decided + built: stored on the GUI host** (CL-37) — real local run-history storage
  and a working `Export CSV`, replacing five hardcoded mock rows. See below.
- **GUI-06: feasibility re-checked against current firmware** (post FW-02/FW-12) — five of
  seven proposed commands are buildable today with no hardware blocker, one (Auto-range PGA)
  turns out to already be done and just needs its button removed, one (Compliance sweep)
  stays a deliberate non-command. Still awaiting the actual per-command go/no-go.
- **GUI-08 left open at the user's request** — no change.
- **BU-10 decided: not required** (CL-36) — the schematic change current reversal would have
  needed will not be pursued; documented as an accepted accuracy limit instead.

**FW-12 + DOC-04 done (CL-33, CL-34): Kelvin excitation now runs on the ADS124S08's own
IDAC, and the excitation-window derivation agrees with it.** `kelvin.c` routes IDAC1 to
`AIN9` (= `HI_COM`) at the IDAC's 2 mA ceiling instead of calling the now-nonexistent
DAC8775 via `control_frontend.c`; the DAC8775 half of the front end and the `dac8775.h`/`.c`
driver are deleted outright rather than left as orphans. `Doc/4wire_resistance_validation.md`
§7.1 re-derived for 2 mA as a *fixed* operating point rather than a target — margin is
comfortable on both ends (45% compliance, 239 mV common-mode), and the pass also corrected
the compliance-ceiling formula to a real datasheet number (AVDD − 0.6 V = 2.7 V) instead of
the earlier ~3.0 V guess. **BU-10 (thermal-EMF current reversal) moved from "verify at
bring-up" to "awaiting a decision"**: the IDACs are source-only with no reverse mode, and the
excitation loop's return path (R131) is asymmetric — reversal now needs a schematic change,
not a firmware register write. Full clean `make all`: 0 errors, 0 warnings (65024 B text).

**Six items closed 2026-08-12 earlier in the day (CL-26 through CL-31): FW-06, DOC-01,
DOC-02 (retroactive), DOC-03, HW-08, GUI-07.** All were coding/documentation work with no
product or hardware decision blocking them — see the activity entries below for the full
account. One item surfaced in passing and logged, not fixed: **FW-11** (`LIMITS SET
ins_min_mohm` has no effect on the insulation verdict — needs a decision, not just code).

**The DAC8775 is gone from the schematic — Kelvin excitation now sources from the
ADS124S08's own IDAC.** Confirmed against the current `Control_Card 1.pdf`/`Matrix_Card-8.pdf`:
the DAC8775 sheet is now empty except unrelated pull-ups, and `AIN9` is wired directly to
`HI_COM`, the ADS124S08's own excitation-current pin. This closed **HW-11** outright (CL-32)
— there's no DAC left to replace, so the LTC2662-16 investigation was moot. Full write-up:
`Doc/idac_current_source.md`.

**FW-02 is done: `RES RUN` now measures instead of failing every net.** `Kelvin_MeasurePair`
reads HI_SENSE/LO_SENSE on the Matrix Card's ADS124S08 (PGA auto-ranged, zero-current baseline
subtracted per point), instead of returning `HAL_ERROR` by design. Getting there also required
wiring the ADS124S08 into `bsp/board.c` for the first time (it had a driver since FW-01 but no
board-level instance), and fixing two things that would have made every reading silently wrong:
SPI1 was still 4-bit/mode 0 (the removed AD7476's leftover config; the ADS124S08 needs 8-bit
mode 1) and running at 32 MHz against the part's 10 MHz ceiling. See CL-23. **Unverified on real
hardware** — this closes the gap between "the protocol works" and "the instrument measures
resistance" in code, but BU-01 (excitation current / system offset) and BU-08 (formula) still
gate trusting a real number.

**The Matrix Card and every HV card share one I2C address range — firmware never gated it.**
All five cards' expanders hard-strap to 0x20–0x27. The Control Card wires the isolated I2C2 bus
out to every HV connector (J1–J4) as one shared set of wires, and the Matrix Card is confirmed on
that same bus too — so two cards live at once meant a guaranteed address collision. `HV_Card_EN1..4`
(PC5/PC6/PA10/PA9, one per slot — EN1 for the Matrix Card's own J1) exist in the schematic to gate
this, but nothing in firmware ever touched them; CubeMX still had the pins under a stale name
(`HV_CARD_DT_3_0` etc.) configured as unused inputs. Fixed for the HV cards (CL-24) and then for
the Matrix Card itself once confirmed (CL-25) — `MatrixCard_Init` now takes separate handles for
U21 (I2C3, local, never shared) and its own eight expanders (I2C2, shared, gated by `EN1`), and
U69 (the ADS124S08 control expander) follows the same gating. Diagram and plain-English write-up:
`Doc/i2c_bus_sharing.md`.

**HW-12 resolved: the ADC-control/sense-enable I2C straps were wrong in firmware, not just
unconfirmed.** Reading the actual address labels off `Matrix_Card-7.pdf` sheet 9 (cropped and
rendered from the PDF, not inferred) found the sense-side expanders at 0x20/0x21/0x22/0x24/0x26
for U66/U69/U67/U107/U108 — the U69-vs-U101 collision fw_status.txt warned about is gone (U69
moved to BUFF2, its own segment), but `matrix_card.h`'s strap constants still assumed the old
sequential 4..7 block. Fixed in code against the schematic; see CL-22. The force-side expanders
(U101/U102/U105/U106, sheet 3) were cross-checked the same way and matched the code exactly —
no change needed there.

**GUI: Flutter is now the primary build (decision 2026-08-10).** `gui_flutter/` (Dart/Flutter,
native Windows exe, no Python at runtime) landed 2026-08-07 as a full rebuild of `gui/` — same
design, same protocol, same safety rules, ported file-for-file. Verified: `flutter analyze`
clean, 130 tests, confirmed against both the simulator and a real NUCLEO-G474RE (connect,
netlist upload, netlist-mode continuity). **`gui/` (Python, htweb + Tk) is superseded** — kept
on disk for reference, no longer tracked for new work. GUI-03 is the one item still open
against it. See the 2026-08-07/08 activity entries.

**Firmware: the heartbeat closes a false "link lost."** `Proto_EvtHeartbeat()` re-announces
state every 2 s so an idle-but-healthy link never trips the GUI's 5 s watchdog — that watchdog
was firing on every connect before this, on both GUI builds, since the instrument said nothing
at all when idle. Verified on hardware: 90 s connected, no link loss, 65 beats at 1.997 s.

**FW-04 closed retroactively (CL-19).** Rereading `matrix_card.c` for this review found the U21
mux-addressing rework already landed in `f778ba7` (2026-08-01) as a side effect of the FW-03
rework — it was just never marked closed under its own ID. The 400 kHz-vs-100 kHz bus-speed
half of the original item is still unresolved (no I2C3 timing override found in `board.c`),
carried forward as a note under BU-03.

**Two new Doc/ files folded into the document map, not left as a fifth/sixth tracking doc.**
`GUI_protocol_command_coverage.md` and `GUI_protocol_proposed_commands.md` (both 2026-08-08)
audited every tappable control in `gui_flutter/` against the protocol. The wiring gaps they
found are already fixed (`FAULT CLEAR`, `MANUAL PATH`, `MANUAL OFF`, real netlist file
browsing); the real open items from that audit are now GUI-04 through GUI-07 below. README
updated to list both as reference material — this log stays the one place status is tracked.

**`>ABORT` is correct by inspection at last, but still unproven on hardware.** FW-07, FW-08 and
FW-09 closed 2026-08-05 (CL-12, CL-13, CL-15) fixed the scheduling bugs that made abort a
no-op. **BU-12 is still the gate** and this review found no evidence abort has been exercised
on real hardware since that fix — a clean build and a simulator prove nothing about scheduling.

**The 4-wire method is proven on the bench**, and now implemented (not yet hardware-verified) on
the product ADS124S08: the ADS1232 bench rig measured a 0.033 Ω resistor to **0.4 %** with no
current calibration at all, because the ratiometric arrangement cancels the excitation. Write-up
in `Doc/4wire_resistance_validation.md`.

**Next actions, in order:** BU-01 (excitation current / system offset on real hardware) is now
the thing standing between FW-02 and a trustworthy number. BU-12 (abort on real hardware) should
be exercised before anything ships. HW-04 and HW-09 are still awaiting a schematic decision from
2026-07-27 — the bench result is now the concrete argument for HW-04.

**Forward risk list** is in `Doc/4wire_resistance_validation.md` §7. Headline: the excitation
has a **usable window of roughly 1–8 mA**, target **5 mA** — below that the sense common mode
falls under the PGA floor (BU-07), above it the force loop runs out of compliance on 3.3 V.
At 5 mA both ends have wide margin.
Highest-value next measurement is **CD74HC4051 Rₒₙ at 3.3 V**, because it sets that whole
window and nothing downstream can be finalised without it.

---

## Open items

### Agreed — awaiting schematic edit

| ID | Item | Agreed |
|---|---|---|
| HW-03 | Matrix card moves to the non-isolated domain: `+5V_ISO` → plain `+5V`, no isolators in the Matrix path. Follow-ons: the Matrix card's ADuM1205 (U103) becomes redundant once both sides share ground — DNF with links or keep as a buffer; and feed the slot raw `I2C3_SDA`/`I2C3_SCL` rather than `ISO_SDA3`/`ISO_SCL3`. | 2026-07-29 |
| HW-10 | Add pull resistors on the three ADC control lines that U69 drives, so they are defined while the MCP23017 is still in its power-on high-Z input state: `ADC_CS_1` and `ADC_RST_1` pulled **up** to +3V3 (CS deasserted, ADC out of reset), `Start_SYNC_1` pulled **down** to GND. Sheet 9 currently carries only 4.7 K (I2C and address strapping) and 47 Ω (series damping) — nothing on these nets. Same argument as the mux enables. | 2026-07-29 |
| HW-04 | **Decided 2026-08-12: implement in the next schematic revision, using `GPIO0_AIN8` (not the originally-proposed `AIN2`).** Route the `LO_COM` node (top of R131) to ADS124S08 `AIN8` (Matrix sheet 9), with the same RC treatment as originally proposed (1 kΩ series + 100 nF to AINCOM) unless the schematic spec says otherwise. `AIN8` is confirmed free — it's `AIN9`'s old calibration-tap partner, unconnected since FW-12 routed `AIN9` to the IDAC (CL-32). Purpose unchanged: R = V_kelvin / I, and without measuring I across R131 the current comes from the IDAC's programmed magnitude, so resistance accuracy equals the excitation source's tolerance instead of R131's 0.01 %. Firmware side (ratiometric read via `AIN8`, `ADS124S08_OhmsRatiometric`) is not implemented yet — waiting on the schematic edit to land. | 2026-08-12 |

### Awaiting a decision

| ID | Item | Raised |
|---|---|---|
| GUI-18b | **Fixture connector part number/shell size not decided.** `required_format/netlist_full_256x256.xlsx` and `fixture_connector_layout_256x256.xlsx` (GUI-18/CL-52) draft a 4-connector layout (128 pins x 2 per side) with `Part Number` = `AMPHENOL-128CKT (TBD)` on every row — a placeholder, not a real catalog number. Needs an actual Amphenol (or equivalent) part number and shell size from mechanical/procurement, or a different split entirely (the user also floated DB37 x N or one large connector) before this becomes the real fixture spec. | 2026-08-17 |
| HW-09 | **Four card slots, five cards — left open at the user's request 2026-08-12.** The Control card has 50-pin connectors J1–J4 (confirmed by reading `Control_Card 1.pdf`'s `/Connector/` sheet directly, pin by pin — J1 is not a separate 5th connector as this row previously assumed; J5 on that sheet is the power barrel jack, not a card slot). J1 carries the Matrix Card's own signals (`LO_S1-4`/`HI_S1-4`/`IN`/`SPI1_*`) plus an apparently-unused `ISO_HV_Card_1.0-3` nibble and its own `EN1` (already claimed for Matrix bus gating) — the plan discussed is a 5th physical HV connector fed by spare/unused J1 pins via a new harness branch, but the exact mechanism is still being worked out. Also noted: `Matrix_Card-8.pdf`'s `J101` does not use matching pin numbers for the same signals as `Control_Card 1.pdf`'s `J1` — consistent with this project's established pattern (BU-06) of harness-level, not schematic-level, signal mapping. | 2026-07-27 |
| GUI-06 | **Seven proposed protocol commands** awaiting a firmware-side yes/no: `BUS SCAN`, `MANUAL READ`, `MANUAL SWEEP`, self-cal, PGA auto-range, compliance sweep, relay self-test. Full command-by-command writeup with size estimates in `Doc/GUI_protocol_proposed_commands.md` (2026-08-08, pre-FW-02/FW-12) — two (auto-range PGA, compliance sweep) are recommended against as separate commands at all. **Feasibility re-checked against the current firmware 2026-08-12 — see the note below the table.** Still awaiting the actual per-command yes/no. | 2026-08-08 |
| ~~GUI-08~~ | **DONE 2026-08-14 — see CL-41.** Turned out not to be a decision at all: (1) `netlist_file.dart`'s `hi == lo` guard wrongly rejected the file's straight-through rows — HI and LO are separate mux banks in `matrix_card.h`, so a matching pin number on both sides is not a collision, and the file's pin numbers are already globally flat by connector order, not per-connector-relative as originally assumed; (2) the file also could not be decoded at all — it's `openpyxl`-generated, and `openpyxl`'s default writer emits a package-absolute relationship target the `excel` package (4.0.6) can't resolve. Both fixed; the real `required_format/example_netlist27072026.xlsx` now loads end to end (20 pairs, regression-tested off disk). | 2026-08-10 |

### Firmware work queued

| ID | Item | Raised |
|---|---|---|
| ~~FW-01~~ | **DONE 2026-08-01** — `drivers/ads124s08` written, see CL-10. Original scope: new `drivers/ads124s08` — reset, device-ID read, PGA / data-rate config, internal 2.5 V reference, offset self-calibration. **CS, RESET and START/SYNC are driven over I2C via U69 (0x25), not by MCU GPIO**, so each conversion sequences I2C(CS low) → SPI → I2C(CS high). `DRDY_1` is likewise an expander *input*: no interrupt is possible and polling costs a bus round-trip, so use a timed wait derived from the configured data rate and read DRDY only as a sanity check. | 2026-07-27 |
| ~~FW-02~~ | **DONE 2026-08-11** — `test/kelvin.c` rewritten for 4-wire, see CL-23. Original scope: Rewrite `test/kelvin.c` for 4-wire. It currently reads the AD7476 and hard-codes `KELVIN_FORCE_CURRENT_A = 0.010f`; both are wrong under the new scheme. Add PGA auto-ranging and system-offset subtraction. | 2026-07-27 |
| ~~FW-03~~ | **DONE 2026-08-01** — `matrix_card` reworked for the Matrix_Card 2 geometry: 8:1 muxes, 32 per bank, 3 select bits, 8 enable expanders across two buffered I2C segments, byte-swapped enable map, segment switching via `HI_S3`/`LO_S3`. AD7476 binding removed (rev 2 deleted U33). | 2026-07-27 |
| ~~FW-04~~ | **DONE, retroactively closed 2026-08-10 — see CL-19.** Mux address lines via MCP23017 U21 landed in `f778ba7` (2026-08-01) as part of the FW-03 rework; never marked closed under its own ID. Original scope: mux address lines come from MCP23017 U21 on I2C3, not MCU GPIO; add OLAT shadow registers, and consider 400 kHz — a 256 × 256 scan is roughly 70 s of pure bus time at 100 kHz versus 18 s at 400 kHz. **The 400 kHz question is still open** — no I2C3 timing override found in `board.c` — carried forward under BU-03. | 2026-07-27 |
| ~~FW-05~~ | **DONE 2026-08-01** — `app/proto.c`, see CL-11. Original scope: implement the instrument side of the GUI protocol defined in `Doc/GUI_development_brief.md` §3 — line-based ASCII over the VCP at 115200. Replaces the current single-keystroke bring-up console (`c`/`k`/`i`/`s`/`f`/`r`). Needs: command parser, `<` replies with 2 s worst-case latency, `!` result streaming during a run, and `!STATE`/`!FIXTURE`/`!HV`/`!SAFE` events. The GUI is being built against this contract, so changes to it must be agreed, not made. | 2026-08-01 |
| ~~FW-06~~ | **DONE 2026-08-12** — see CL-26. Original scope: **`>STATUS` never reports `running` or `fault`.** `proto_exec` builds the reply from `s_armed` alone, so a GUI that reconnects mid-run and re-issues `>STATUS` — which the brief §3.5 rule 4 requires it to do — is told `idle` while a run is executing. `!STATE` does carry `running`, so the information exists; only the polled path is missing it. Fix is to report from `s_busy` and `Safety_InFault()` as well. | 2026-08-05 |
| ~~FW-13~~ | **DONE 2026-08-14** — see CL-39. Original scope: an un-initialised card (Board_Init() failed or never ran for it) HardFaults the sequencer the moment `>SAFE`, an armed `>FIXTURE` change, `>FAULT CLEAR`, or a real fault runs `force_safe_all()` — `hv_bus_claim`/`MatrixCard_BusClaim` wrote through a NULL `en_port` with no guard, and `Board_Init()`'s return value was discarded at `main.c:106`. Fixed: NULL-guarded both bus-claim/release pairs, and a new `Board_IsReady()` gates `CONT/RES/INSUL RUN` and `>SAFE` with `ERR EHW` instead of attempting them against un-initialised state. | 2026-08-14 |
| FW-11 | **`LIMITS SET ins_min_mohm` changes a number nothing reads.** Found while wiring GUI-07 to a real control. `Proto_LimitInsMinMohm()` is defined and returned correctly by `>LIMITS GET`, but has exactly zero callers anywhere in `Core/Src/test` or `tasks.c` — insulation's pass/fail comes only from the fixed `INSULATION_V_PASS_MAX` voltage threshold in `insulation.c`, never from this configurable limit. Separately, the firmware's own default (`s_lim_ins_mohm = 10000000`) is commented `/* 10 Mohm */` but at genuine wire-milliohm units (matching `r_max_mohm`'s confirmed convention) that value is 10,000 mΩ = 10 kΩ, not 10 MΩ — three orders of magnitude off from what the comment claims and from the ~10 MΩ threshold used everywhere else in the project. Not fixed here: wiring a dead parameter into the verdict path is a behavior change to a safety-relevant pass/fail test, not a mechanical sync — needs a decision on whether `LIMITS SET` should gate insulation at all before the code changes. | 2026-08-12 |
| ~~FW-12~~ | **DONE 2026-08-12** — see CL-33. Original scope: Kelvin excitation needs to move from the DAC8775 to the ADS124S08's own IDAC. The DAC8775 is confirmed gone from the schematic (HW-11, closed as CL-32) — `AIN9` on the ADS124S08 now wires straight to `HI_COM`. `kelvin.c` still calls `Frontend_SetCurrentCode`/`Frontend_SetMode(FRONTEND_MODE_IMPEDANCE)` against a chip that no longer exists on the board. Needs: an `ADS124S08_SetIdac()`-style helper, `kelvin.c` switched over to it, the DAC8775 half of `control_frontend.c`/`.h` removed, and `board.c`'s SPI2/DAC8775 CS wiring dropped. Full scope in `Doc/idac_current_source.md` §5. | 2026-08-12 |
| ~~FW-07~~ | **DONE 2026-08-05** — see CL-12. Original scope: **`>ABORT` cannot stop a run — the comms thread is starved for the whole run.** `tSequencer` is `osPriorityNormal`, `tComms` is `osPriorityBelowNormal`, and the sequencer never yields during a run: the settle delays are `HAL_Delay` (the stock `__weak` one — a busy-spin on `HAL_GetTick`, TIM1 timebase, nothing overrides it) and the I2C/SPI calls are polled. With `configUSE_PREEMPTION=1` a lower-priority task never runs while a higher-priority one is runnable, so `Proto_RxByte` is never called during a run: **the abort flag the run loops poll can never be set, and the polling in `tasks.c` is unreachable in practice.** Worse, RX is single-byte polled with no interrupt or DMA, so mid-run bytes are lost to overrun rather than buffered. Scale: insulation is 256 × ~250 ms ≈ 64 s, discover 65,536 × ~2 ms ≈ 131 s — an operator pressing Abort during a 500 V run has no effect for that long. Physical E-stop and the safety task (`osPriorityHigh`, blocks on `osDelay`) are unaffected. Found by the GUI-side task-2 review. Two candidate fixes, neither started: interrupt/DMA RX into a ring buffer with `tComms` blocking on it, or `osDelay` instead of `HAL_Delay` in the test settle paths so the sequencer yields. | 2026-08-05 |
| ~~FW-08~~ | **DONE 2026-08-05** — see CL-13. Original scope: **`Proto_SetFixture` announces `!SAFE` before the hardware is safe.** It posts `CMD_FORCE_SAFE` to the queue and then immediately emits `!HV 0` and `!SAFE`, without waiting for execution — so the instrument tells the GUI it is safe while the rail may still be up. Directly contradicts the brief's central rule that the GUI must never show a safe state it has not been told is real. Masked today by FW-07 (a fixture change cannot be received mid-run), so **fixing FW-07 unmasks this** — do them together. Also in the same path: the arm is dropped with no `!STATE idle`, and `!SAFE` is emitted twice (once inline, once when the queued force-safe runs). | 2026-08-05 |
| ~~FW-09~~ | **DONE 2026-08-05** — see CL-15. Original scope: **An abort in the first moments of a run is silently lost.** `proto_post_run` clears `s_abort` and posts; the sequencer then calls `Proto_ClearAbort()` *again* at run entry (`tasks.c` 281 / 348 / 396). An `>ABORT` processed in the window between the post and that second clear is wiped, the GUI has already had its `<OK`, and the run continues to completion — up to 64 s at 500 V for insulation. **The FW-07 fix made this more reachable, not less:** `tComms` now sits above the sequencer, so it can preempt and set the flag exactly in that window. Fix is to delete the three entry-side clears — `proto_post_run` is the only path that starts a run and it already clears the flag at the one point where clearing is correct, before the command is queued. Raised verbally on 2026-08-05 and not logged at the time; logged now. | 2026-08-05 |
| ~~FW-10~~ | **DONE 2026-08-05** — see CL-16. Original scope: **A latched fault wedges the run path permanently, and the GUI waits forever.** `run_command` returns early when `s_fault` is set, *before* the switch — so a dequeued run command never reaches `Proto_EvtDone`. `s_busy` stays 1, every later run is refused `ERR EBUSY`, and no `!DONE` is ever emitted, so a GUI that is waiting for the run to finish waits for ever. Compounded by there being **no protocol command to clear a fault** (`Safety_ClearFault` is not reachable from `proto.c`), so recovery is a power cycle. Fix is small — in the skip path, emit `!FAULT` and `!DONE` for run commands so the GUI is released, and add a way to clear the latch. Found while closing FW-09; **not a release blocker on its own** (it needs a fault first, and a faulted instrument is already unusable) but it turns one fault into a hung GUI. | 2026-08-05 |
| ~~DOC-01~~ | **DONE 2026-08-12** — see CL-27. Original scope: `fw_status.txt` still describes the 2-wire path, 10 mA excitation, and Matrix U33 as the resistance ADC. Sync it with v1.4. | 2026-07-27 |
| ~~DOC-03~~ | **DONE 2026-08-12** — see CL-29. Original scope: `Doc/4wire_resistance_validation.md` §7.1 still targets **~5 mA** excitation. Superseded 2026-08-01 by BU-09 (real CD74HC4051 datasheet, worst-case Rₒₙ 250–320 Ω) which revised the target to **3 mA**, but that revision was never propagated into §7.1's compliance table — only into the project log. **Superseded again the same day — see DOC-04.** | 2026-08-11 |
| ~~DOC-04~~ | **DONE 2026-08-12** — see CL-34. Original scope: `Doc/4wire_resistance_validation.md` §7.1 needs re-deriving a second time, same day as CL-29. CL-29's 3 mA derivation assumed an unbounded current source (true for the DAC8775 it was written against); the ADS124S08's internal IDAC that replaced it (HW-11, CL-32) tops out at **2 mA** — there's no `IDACMAG` code above that. Re-derive §7.1's compliance/common-mode table with 2 mA as the fixed operating point rather than a target being justified. See `Doc/idac_current_source.md` §3–4. | 2026-08-12 |
| ~~DOC-02~~ | **Retroactively closed 2026-08-12 — see CL-28.** Already fixed as a side effect of the heartbeat commit (`c579830`, 2026-08-07), before this item was ever logged as open in this form: `HT_ENABLE_ADS1232`'s default was flipped 1→0 in the same change that added `Proto_EvtHeartbeat()`, "carrying the bench diagnostic off with it." README's "default off" and the header have matched since; nobody had marked this row closed. | 2026-08-05 |

### Awaiting the GUI side

Raised in `Doc/GUI_development_brief.md` §8.4 and `Doc/GUI_protocol_command_coverage.md`
against the GUI deliverables. Tracked here so the outstanding set is visible from one place,
not only from inside a brief or an audit doc. **As of 2026-08-10, `gui_flutter/` is the
primary build** — new items are filed against it. GUI-03 is against the now-superseded Python
`gui/` and kept only as a record.

| ID | Item | Raised |
|---|---|---|
| ~~GUI-01~~ | **FIXED 2026-08-05 (GUI side)** — `_link_lost` is now called after `_io_lock` is released, and there is a regression test (`TestSendFailure`: the `execute()` call runs in a thread, so a regression fails the test instead of hanging the suite). Re-verified on the fixed code: send failure now surfaces `LinkLostError` immediately and the link drops to `LINK_LOST`. Original scope: Blocker — a send failure deadlocks the connection manager; `_execute` called `_link_lost()` while holding the non-reentrant `_io_lock`. | 2026-08-05 |
| ~~GUI-02~~ | **FIXED 2026-08-05 (GUI side)** — `!RES` milliohms, `!INSUL` leak_mohm, `<STATUS hv_mv`, the `<LIMITS` values and `!HV` now parse as signed int32; pins, counts and progress stay unsigned. Regression test added (`test_signed_measurement_values`), and the old malformed-case test that asserted `hv_mv=-5` was invalid has been corrected — it was encoding the bug. Original scope: signed wire fields parsed as unsigned, so a valid negative reading was reported as a protocol violation. | 2026-08-05 |
| GUI-03 | **Three minors, in `gui/` (Python, superseded 2026-08-10 — low priority).** A single non-ASCII byte kills the reader thread and turns into a misleading 5 s "link lost" (`UnicodeDecodeError` is caught outside the read loop); `_link_lost` nulls `_transport` under a live reader/sender, so `AttributeError` escapes instead of `LinkLostError`; and `parse_line('')` raises, where ignoring empty lines would be safer. Acknowledged by the GUI side 2026-08-05, not yet done. | 2026-08-05 |
| ~~GUI-07~~ | **DONE 2026-08-12** — see CL-31. Original scope: `LIMITS SET` never wired, in `gui_flutter/`. The codec encoder exists (`commands.limitsSet()`) and the firmware answers it, but nothing in `AppState` calls it — there is no way to change `r_max_mohm`/`ins_min_mohm` from the GUI at all. Found by `Doc/GUI_protocol_command_coverage.md` §1. | 2026-08-08 |
| ~~GUI-04~~ | **DECIDED 2026-08-12: stays RAM-only.** No firmware or GUI change needed — matches current behaviour exactly (confirmed on hardware that netlists do not persist across reboot today). Original question (brief §8 Q2): should an uploaded netlist survive a reboot? Answer: no. | 2026-08-08 |
| ~~GUI-05~~ | **DECIDED + DONE 2026-08-12 — see CL-37.** Decision: stored on the GUI host, not the instrument. Original scope: run history storage (brief §8 Q4) blocked the Results view's Export CSV / Print report from being anything but decoration — that table was static mock data. `Export CSV` now writes real data; `Print report` is left honestly disabled (real OS print integration is a different scope, not the storage-location question this item asked). | 2026-08-08 |
| ~~GUI-09~~ | **DONE 2026-08-14** — see CL-40. Original scope: the "GUI Reality Check" audit (linked artifact, prior session) found mock/dead/stale UI elements annotated inline with `MOCK:` comments (`grep -rn "MOCK:" gui_flutter/lib`) — real protocol data (`InsulResult.net/.leakMohm`, `HvEvent.millivolts`, `>ID`) discarded instead of wired to the HV relay grid, Net results table, HV rail meters, status bar, and Continuity's Export CSV; a boot log and a pre-HV verify modal asserting things never checked; a stale "Auto-range PGA" button; and reference panels (bus map, Instrument limits, Resistance sense path, fixture sequence) still describing hardware since replaced (`DAC8775`, `U33`, `CD4067`). All fixed — see the status snapshot above. | 2026-08-14 |
| ~~GUI-10~~ | **DONE 2026-08-14** — see CL-42. Original scope: `required_format/`'s report side (continuity/resistance/insulation, CSV + PDF) had no writer in code — the README flagged this as blocked on GUI-05 (run history storage), which resolved 2026-08-12 (CL-37), unblocking it. Built to the samples' exact column shape; see the status snapshot above and `gui_flutter/required_format/README.md`. | 2026-08-14 |
| ~~GUI-11~~ | **DONE 2026-08-14** — see CL-43. Original scope: the fixture's connector layout (which named, differently-shaped connector each of the 256 flat instrument pins actually lands on) was a hardcoded 8-connector demo constant with no relationship to any real harness, and real netlists were mapped onto it with a `(pin-1) % 128` fabrication. Made configurable — guessed from the netlist file's own `Conn ID`/`Part Number` columns, operator confirms/edits. See the status snapshot above. | 2026-08-14 |
| ~~GUI-12~~ | **DONE 2026-08-16** — see CL-44. Original scope: user report ("without selection it is showing data") traced to `AppState` seeding `nets`/`nlMtx`/`nlFix` with fake "loaded" demo data at construction, before any netlist existed. | 2026-08-15 |
| ~~GUI-13~~ | **DONE 2026-08-16** — see CL-45. Original scope: every other `MOCK:`-tagged item the "GUI Reality Check" audit had left open, worked through one by one. | 2026-08-15 |
| ~~GUI-14~~ | **DONE 2026-08-16** — see CL-48. Original scope: two build tags, customer (no Diagnostics section) and developer (full). Caught a real `RangeError` crash in the customer build along the way (`Rail`'s vertical layout hardcoded 7 button slots by index). | 2026-08-16 |

### Verify at bring-up

| ID | Item | Raised |
|---|---|---|
| BU-01 | Excitation current — run the 0 Ω loopback compliance sweep. 10 mA is unachievable through two CD4067B plus 100 Ω on a 3.3 V rail; expect roughly 1–3 mA. Capture the system offset at the same time. | 2026-07-27 |
| BU-02 | ~~SPI1 shared by U33 and U68~~ **Dissolved** — Matrix_Card 2 removed the AD7476, so SPI1 has exactly one device. Mode confirmed from SBAS660C: DIN latched on the SCLK falling edge, DOUT changes on the rising edge → **CPOL=0, CPHA=1 (mode 1)**. `SPI1_CS` on J101 now has no consumer. | 2026-07-27 |
| BU-03 | U101 / U102 I2C addresses are set by strapping and not annotated, unlike the sheet-9 trio at 0x23 / 0x24 / 0x25. Scan and log. **Also carries the FW-04 400 kHz-vs-100 kHz decision** (moved here 2026-08-10 when FW-04 closed) — no I2C3 timing override found in `board.c`; confirm the bus speed at the same bring-up session. | 2026-07-27 |
| BU-04 | JP1 (AINCOM → GND, Matrix sheet 9) must be fitted, or the ADC's analog common floats. Populate with a 0 Ω link by default and mark it on the assembly drawing. | 2026-07-27 |
| BU-05 | ~~No differential RC filter~~ **DONE in Matrix rev 2** — R234/R235 4.99 k 0.1 % + C33 47 nF + C142/C143 4.7 nF fitted. | 2026-07-27 |
| BU-07 | **Common-mode: hold the excitation at ≥1 mA.** `LO_SENSE = I × (R_LOmux + R131) = I × 200 Ω` against an ADS124S08 floor of `0.15 + 15.5·\|V_IN\|`. At 1 mA that is 0.200 V vs 0.165 V (+35 mV); at the 5 mA target it is 1.000 V vs 0.227 V (+772 mV) — comfortable, **nothing to fix in hardware**. Revised 2026-08-01: the earlier "marginal" framing overstated it. The real caveat is that the floor grows with the measured resistance, capping R at ~11 Ω at 5 mA on gain 32 — handled by PGA auto-ranging, since gain ≤16 uses a much lower floor. See Doc/4wire_resistance_validation.md §5.1. | 2026-08-01 |
| BU-09 | **Measure CD74HC4051 Rₒₙ at 3.3 V** — reduced 2026-08-01 after reading SCHS122O. Channel-to-channel spread (ΔrON) is **10 Ω max**, so the "some wires read wrong" concern is largely closed; a sanity check across a few channels is enough. What remains is that rON is characterised only from **VCC = 4.5 V** (typ 70 Ω, max 160 Ω at 25 °C, 200 Ω at 85 °C) and the card runs at 3.3 V — extrapolate typ ~110–140 Ω, max ~250–320 Ω. **Excitation target revised 5 mA → 3 mA**, which stays inside both compliance and common-mode limits even at worst-case rON. | 2026-08-01 |
| BU-11 | **Measure sense-path leakage.** `HI_SENSE` is the common node of 32 CD74HC4051s with 31 disabled; summed off-channel leakage into the 4.99 kΩ series resistor could be a large offset (1 µA → 5 mV). Should largely cancel between HI and LO legs, but unverified. Cheap test: enable a sense bank with no excitation and check the differential reads near zero. Rises sharply with temperature. See §7.4. | 2026-08-01 |
| BU-08 | **Do not copy the bench resistance formula.** ADS1232 full scale is ±0.5·VREF/Gain, ADS124S08 is ±VREF/Gain. The bench divides by `2 × gain × 2²³`; the product must divide by `gain × 2²³`. Copy-pasting gives a silent 2× error. | 2026-08-01 |
| BU-06 | Harness build must encode `ISO_HV_CARD_ENx` per card slot (card 1 → EN1 … card 4 → EN4). HV_Card-1 sheet 1 states this is done in the cable, not the schematic. | 2026-07-27 |
| BU-12 | **Prove `>ABORT` on real hardware.** The FW-07 fix (CL-12) is verified only by inspection and a clean link — the failure was a scheduling one, and scheduling bugs do not show up in a build. Press abort during a 256-pin discover scan and again during an insulation run; the run must stop within roughly one measurement point and still emit its `!DONE`. Check at the same time that a mid-run `>PING` is answered inside 2 s, and that a `>FIXTURE` change during a run stops it. | 2026-08-05 |

---

## Closed items

| ID | Closed | Item | Resolution |
|---|---|---|---|
| CL-60 | 2026-08-18 | GUI-26 dead "Fault pareto" panel removed from Results tab | User asked what it was for. It's a Pareto chart of fault types by frequency, but `RunHistoryEntry` only ever stored pass/fail counts per run, never per-fault codes/locations, so the panel was permanently stuck on a hardcoded "Not tracked yet" message. Confirmed dead (no test referenced it) and removed the whole panel from `ResultsView` rather than leave known-dead UI around. Reviving it for real needs `RunHistoryEntry` extended to carry fault codes/locations — a real feature addition. `flutter analyze`: 0 issues. `flutter test`: 229/229 (unchanged). |
| CL-59 | 2026-08-18 | GUI-25 demo insulation testing was capped at --nets, unaware of the loaded netlist | User asked why the HV section only ever showed 12 pins. Checked real firmware first: `run_insulation_all()` (`Core/Src/app/tasks.c`) iterates `Proto_NetlistCount()`/`Proto_NetlistGet()` — the same MTX netlist continuity/resistance upload — and reports each result against the real hi pin (`Proto_EvtInsul(hi, ...)`); the HV netlist file the GUI lets an operator browse only ever sets a card count for `stackMatch()`, never per-net topology. `htproto/simulator.dart`'s `_runInsul` did neither — always iterated the fixed `scenario.nets` (sized by launch-time `--nets`, 12 by default) and emitted a sequential index instead of the real pin, so more (or just different) nets than 12 either got capped or matched wrong once `AppState._onInsul` tried to resolve the index as a real pin. Fixed by reusing GUI-21's `_effectiveNets(_st.netlist)` and reporting the real `hi` pin per result. New `test/insulation_pairing_test.dart`: uploads a 20-net MTX netlist, moves to J-HV, arms, runs insulation — all 20 resolve now. `flutter analyze`: 0 issues. `flutter test`: 229/229. |
| CL-58 | 2026-08-18 | GUI-24 internal bus/chip detail dropped from customer builds everywhere, not just Diagnostics | User asked directly: SPI/I2C/chip-level internal detail should only ever show in the developer build. GUI-14 (2026-08-16) had already split customer/developer at compile time (`kCustomerBuild`) but only gated the Diagnostics tab as a whole — every other view still showed chip part numbers, bus names, register addresses, internal signal names unconditionally. Audited every view file, then fixed three patterns: whole panels whose only purpose is an internal signal trace (Continuity's "Switch path", Resistance's "Sense path", HV's "Leakage loop") dropped entirely with layouts reworked so no blank slot is left; individual rows inside an otherwise customer-relevant panel (`Band` mixing "Connector"/"Scan scope" with "Switching"/"Sense") conditionally spread in/out; single strings mixing one legitimate fact with one internal identifier (`"4-wire Kelvin · ADS124S08 IDAC1"`, `"500 V DC · R3002 1 MΩ"`) reworded per-build via ternary. Also gated the log bar's "Console" tab (raw wire protocol traffic), the Run view's domain-card condition text, the Fixture-sequence stage-box text, and two stray `I2C2` mentions (an HV-netlist modal, a status-bar log line). Left the Program view's "HV nets" relay-assignment table alone — an operator setting up a real fixture plausibly needs to know which card/relay a net lands on, unlike MCU-bus-level detail — flagged for the user rather than assumed. Verified against both the normal default and `--dart-define=CUSTOMER_BUILD=true`: every view builds/lays out cleanly with the internal content gone; the only failures under the customer flag are the three tests that are supposed to fail under it. `flutter analyze`: 0 issues. `flutter test`: 228/228 (default). |
| CL-57 | 2026-08-17 | GUI-23 src/dst connector resolution bug + Part Number wired up | User reported continuity showing "Connector A pin 1 -- Connector A pin 2" instead of crossing to Connector B. Traced to `AppState.rebuildNets`'s `pinNode` searching the same flat connector list for both `hi` and `lo` — HI/LO are independently-addressed 1..256 spaces (matrix_card.h), so a straight-through net always resolved src and dst to whichever connector owned that numeric range, regardless of actual side. Broken since GUI-11 (2026-08-14); existing tests only checked `!= '—'`, never that src/dst differ, and the demo's seeded harness bypasses `pinNode` entirely. Fixed: `_fixtureFromGuess` computes `base` as two separate per-side offsets when a guess has real Source/Destination provenance (`GuessedConnector.side`, GUI-19), falling back to the old combined sequence for ambiguous/symmetric files; `pinNode` takes `isSrc` and searches the matching side first, falling back to unrestricted search — required rewriting `rebuildNets`'s fixture-extension fallback to run that same search (`coversPin`) rather than a precomputed numeric boundary. Second bug found in the same investigation: "Part Number" was hardcoded blank everywhere (CSV/PDF/GUI table) even though the netlist file's own Part Number columns were already parsed and just never threaded through — added a real `ConnectorDef.partNumber` field (separate from `label`, which is a display name/id fallback, not a part number) and wired it through `_fixtureFromGuess`, the fixture-guess confirm step, `_onCont`/`_onRes`, and every report/GUI surface. `Source`/`Destination` free-text columns stay blank — genuinely not parsed anywhere, left alone rather than half-fixed. New `test/pin_resolution_test.dart` (real `SimulatorServer`, real uploaded netlist) plus a `netlist_file_load_test.dart` case at the parser/guess layer. `flutter analyze`: 0 issues. `flutter test`: 228/228. |
| CL-56 | 2026-08-17 | GUI-22 idle wires in the wiring diagram were nearly invisible | User loaded a netlist and saw pin dots/connector shells but no wires between them. Traced to `painters.dart`'s `_paintWires` drawing untested ("idle") nets in `c.gridEmpty` (`0xFF1B282D` dark theme, meant for empty grid cells) at .55 alpha — barely different from the canvas background `c.sunk` (`0xFF0E171A`), tolerably faint on the old compact 8-connector canvas's short diagonal wires but effectively invisible once GUI-19's vertical ladder made idle wires run most of the canvas's 1060px width. Confirmed by rendering the exact idle state to a PNG and inspecting it, not just reading the code. The pin dots for the same untested nets already used `c.ink3` (a much lighter grey) for the same "present but untested" meaning — fixed the inconsistency by switching idle wires to `c.ink3` too, and bumping alpha .55 → .7. Verified by re-rendering: clearly visible now, still visually subdued relative to pass/fail/hovered. `flutter analyze`: 0 issues. `flutter test`: 225/225 (no test added — a colour choice, verified visually). |
| CL-55 | 2026-08-17 | GUI-21 demo simulator now honours any uploaded netlist's own pairing convention | Reverses GUI-20's "real hardware only" call — user pushed back that the file should pass in the demo, not be carved out. Root cause: `htproto/simulator.dart`'s `_runCont`/`_runRes` compared an uploaded `(hi, lo)` pair against the scenario's fixed `_goodNets()` pairing (`1↔2, 3↔4, 5↔6, …`) by literal value, so any netlist using a different pairing (real hardware's straight-through `Src Pin # == Dst Pin #`) could never match. Fixed at the root: new `InstrumentSim._effectiveNets(netlist)` reuses the scenario's scripted pass/fail/open/short pattern positionally (row `i` of whatever was uploaded gets row `i`'s scripted outcome, rows past the scenario's own length default to pass) instead of matching by literal pin value; falls back to the scenario's fixed nets unchanged when nothing's uploaded. Applied to `_runCont` verify and `_runRes` (shares the MTX netlist with continuity); `_runInsul` untouched — no wire-protocol netlist upload exists for HV. Side effect, verified: also resolves the older "`--nets` must match the loaded file's net count" constraint for verify-mode runs generally — a 20-row netlist now passes fully against a 12-net-default simulator. New `test/simulator_pairing_test.dart` (straight-through pass, positional fault injection, bigger-than-`--nets` file). `required_format/README.md` and `test_netlists/README.md` corrected. `flutter analyze`: 0 issues. `flutter test`: 224/224. |
| CL-54 | 2026-08-17 | GUI-20 `netlist_full_256x256.xlsx` 0-pass-in-demo traced and decided | User reported `CONT RUN verify` reading 0 pass with `netlist_full_256x256.xlsx` (GUI-18) loaded in the customer demo build. Traced to `htproto/simulator.dart`'s fake harness being a fixed internal model set at launch (`_goodNets()`: pin 1↔2, 3↔4, 5↔6, …), independent of whatever netlist gets uploaded afterward. `test_netlists/`'s three `AV-880_MTX_*.xlsx` files only work in the demo because they were generated to already match that 1-2/3-4 pattern; `--nets` only ever needed to match their net count. `netlist_full_256x256.xlsx` uses the real instrument's straight-through addressing (`Src Pin # == Dst Pin #`) instead, which never matches the simulator's fixed model at any `--nets` value — 0 pass is expected, not a defect. Asked the user how to proceed; decided real-hardware-only, no code change. `required_format/README.md` and `test_netlists/README.md` updated with an explicit "does not pass against `--sim`, use `--serial`" note. |
| CL-53 | 2026-08-17 | GUI-19 wiring diagram redrawn vertical, Source/Destination L/R split fixed | User screenshotted GUI-18's 256-pin fixture in the wiring diagram — connector shells overlapping, unreadable — and asked for a vertical layout instead of horizontal. Root cause: `design/model.dart`'s per-shape connector footprint scaled *width* with pin count (a D-sub's two-row layout hits ~860px at 128 pins, nearly the full 1060px canvas), so stacked large connectors visually collided. Replaced all three per-type footprints (D-sub, circular rings, rect grid) with one: a single vertical pin column for every connector type, scaling taller not wider; `kCanvasH` is no longer a fixed 440 const, `layoutFixture()` grows it to fit content (440 floor, so the original demo fixture is unaffected); `painters.dart` drops per-shape shell geometry for one plain rounded-rect shell plus per-pin number labels. Also found and fixed a second, independent bug: `AppState._fixtureFromGuess` split connectors left/right by blind list-half of a minPin-sorted list, with no concept of which netlist column (`Conn ID` vs `Conn ID B`) a connector came from — harmless for `example_netlist27072026.xlsx` (reuses one id per mating pair) but scattered Source/Destination connectors across both visual halves for GUI-18's file (distinct ids per side). Fixed: `GuessedConnector.side` ('src'/'dst'/null) now tracks provenance, `_fixtureFromGuess` splits by it when unambiguous, falling back to the old heuristic otherwise. Verified by rendering the real fixture through `DiagramPainter` to a PNG: Side-A/Side-B blocks land at identical y-coordinates, nets draw as short horizontal lines, zero overlap. New tests in `netlist_file_test.dart`, `netlist_file_load_test.dart`, `gui_test.dart`. `flutter analyze`: 0 issues. `flutter test`: 222/222. |
| CL-52 | 2026-08-17 | GUI-18 full 256x256 fixture netlist + draft connector layout | User asked for a "proper netlist" and "the fixture file," then gave the real constraint: 256 independently-addressed pins per side (512 total), and asked how those map onto physical connectors mounted on the tester body (floated DB37 x N, one large Amphenol, or 128-pin x 2 per side as options). No real fixture connector part number exists anywhere in the repo (`fw_status.txt`/`Doc/` name `J-MTX`/`J-HV` only) so there was nothing real to defer to — treated as a draft proposal, not a hardware fact, and labeled as such throughout. New `required_format/netlist_full_256x256.xlsx`: same `required_format` columns as `example_netlist27072026.xlsx`, all 256 pins, straight-through, grouped into four 128-pin `Conn ID` blocks (`MTX-A1`/`A2`/`B1`/`B2`) — 128 x 2 per side, the cleanest round split of 256 and one of the user's own suggested options; `Part Number` reads `AMPHENOL-128CKT (TBD)` everywhere. Copied into `test_netlists/` so it's loadable through the real GUI netlist picker (`--nets 256`). New `required_format/fixture_connector_layout_256x256.xlsx`: a plain mechanical-reference table of the same four-connector breakdown (not read by any code) — `Side`/`Conn ID`/`Part Number`/`Connector Type`/pin range/pin count/mounting location/mates-with/notes, every placeholder field marked as such. `netlist_file_test.dart` gained a real end-to-end test against the new file (256 pairs, all straight-through, four 128-pin connectors correctly guessed), same pattern as the existing sample's test. `flutter analyze`: 0 issues. `flutter test`: 219/219. |
| CL-51 | 2026-08-17 | GUI-17 `required_format` netlist/report reconciliation | User asked for `example_netlist27072026.xlsx` (netlist in) and `report_20260725_184312_HT-0004.pdf` (report out) to be the canonical formats. Netlist side already matched (GUI-08/CL-41), confirmed and unchanged. PDF side had drifted from GUI-10's own "matches the CSV column-for-column" claim — the Results table was missing `Conn ID` (real since GUI-11) and the three permanently-blank `Source`/`Part Number`/`Destination` columns the sample keeps for shape. Rebuilt `report_pdf.dart`: full column set, dark-header-band + green/red row tinting by status, bundled `company_logo.jpeg` (new `assets/`, `pubspec.yaml`, loaded via `rootBundle`, degrades to no logo rather than throwing). "Test Duration" is now real (`AppState._runStart`→`ReportMeta.testDuration`, set at `_beginRun`/`_onDone`); "Profile" deliberately omitted — no profile/preset concept exists anywhere in this app, and the sample's own docstring already flagged it as unbacked (same "GUI Reality Check" reasoning as GUI-09/12/13). Found and fixed a real rendering bug in passing: the `pdf` package's core Helvetica font has no glyph for the em dash `report.dart` uses as its "connector unknown" placeholder — new `_pdfSafe()` substitutes a plain hyphen for PDF cell text only (CSV/GUI keep the em dash, which Flutter renders fine). GUI-11's shared `ConnectionResultsTable` (Continuity/Resistance/HV "Connection results" panels) mirrors the same full field set on screen, plus two real HV fields (`Leak V`, `Limit (MΩ)`) that were computed but never shown. New `test/report_pdf_smoke_test.dart`; `report_test.dart` gained `stampDuration` unit coverage and a live-run `testDuration` assertion. `flutter analyze`: 0 issues. `flutter test`: 218/218. |
| CL-50 | 2026-08-17 | GUI-16 demo/simulator had no heartbeat — every idle demo connection died at ~5 s | User rebuilt all four exes via `build_exe.cmd` and reported every demo losing its connection 3-5 s after connecting — real, not a false alarm: a session log (`%LOCALAPPDATA%\HT_MK1\sessions\`) from before this fix showed the handshake completing, then silence, then `LINK LOST: no traffic for 5.0s` at +5.4 s, exactly matching `connection.dart`'s `defaultLinkTimeout` (5 s). Root cause: `htproto/simulator.dart`'s `InstrumentSim` never emits anything while idle — no periodic re-announcement at all — unlike real firmware, which this project already found and fixed the identical false-"link lost" bug for (`Proto_EvtHeartbeat()`, re-announces state every 2 s, noted elsewhere in this file: "an idle-but-healthy link never trips the GUI's 5 s watchdog"). That firmware-side fix was apparently never mirrored into the simulator, so the demo build has probably always had this gap — GUI-15's port fix just made the demo connect reliably enough for someone to sit on it past 5 s and notice. Fixed: new `InstrumentSim.emitHeartbeat()` re-sends `!STATE <current>` (any bytes reset `ConnectionManager`'s watchdog — `connection.dart`'s `_lastRx` updates on raw receipt, before line parsing, so this doesn't need to be a special event type), driven by a `Timer.periodic(Duration(seconds: 2))` in `SimulatorServer._handleClient`, cancelled both in the client's `onDone` and explicitly in `SimulatorServer.stop()` (not just relying on the async socket-close callback, so a test that stops and immediately tears down can't race a still-pending `Timer` against `flutter_test`'s `!timersPending` invariant). Checked every real-`SimulatorServer` test for a link-loss-timing assumption this could disturb — the two that exist (`protocol_test.dart`) test either mid-run transport drop (socket actually closes, independent of any watchdog) or use `FakeTransport`, not the real simulator; neither is affected. `flutter analyze`: 0 issues. `flutter test`: 212/212. **Verified live, not just in tests**: rebuilt all four exes via `build_exe.cmd`, launched the real built `HT_MK1_GUI.exe --sim`, left it idle 15 s (3× the old failure point) and confirmed the session log shows `!STATE idle` arriving every 2 s on the dot with zero `LINK LOST` — the exact failure mode the user hit, reproduced from an old log and then confirmed gone from a new one. |
| CL-49 | 2026-08-17 | GUI-15 demo build can no longer collide with a real local server | User asked, after GUI-14 shipped the customer/developer split, for one more demo-safety guarantee: the demo exe must not be able to connect to a real local server. Found the gap in `main.dart`'s `--sim` handling: `SimulatorServer.start(..., port: o.port, ...)` passed `o.port`, which defaults to `46000` — the exact same default a real `--host`/`--port` TCP-bridge target uses. `SimulatorServer.start`'s own default is `port: 0` (OS-assigned free port, the pattern every test file already relies on), so main.dart was overriding a safe default with an unsafe fixed one for no reason tied to `--sim`'s actual purpose. Practical effect: if anything else was already listening on 46000 locally (a real bridge, another running instance), the demo's bind would collide — at best a crash at launch, at worst ambiguity about what it's actually talking to. Fixed: `--sim` now always binds to `port: 0`; confirmed there is no host/port entry UI exposed when `s.serialLink` is false (`shell.dart`'s status bar only shows the COM-port selector, gated on `serialLink`, with nothing filling the gap for `--sim`), so the launch command is the only way the demo's connection target is ever set — with a random OS-assigned port, it now can never end up pointed at anything but its own bundled simulator. `flutter analyze`: 0 issues. `flutter test`: 212/212. |
| CL-48 | 2026-08-16 | GUI-14 customer/developer build split | User asked for two build tags: customer (no Diagnostics section) and developer (full). `lib/app/build_tag.dart`'s `kCustomerBuild` is a `bool.fromEnvironment` compile-time constant (`--dart-define=CUSTOMER_BUILD=true`), not a runtime flag, so the AOT/release compiler can prove the Diagnostics branch unreachable and tree-shake it out of a customer build entirely. `app/shell.dart`'s `Rail` only adds the Diag button `if (!customerBuild)`; `main.dart`'s view switch gates the `'diag'` route the same way as a defensive fallback. `build_exe.cmd` restructured: a new `:build_variant` subroutine runs `flutter build windows --release` once per tag and packages each into its own real-hardware + demo SFX pair (`call`ed twice with plain sequential lines, not a `for` loop — under this file's plain non-delayed `setlocal`, a loop body's `%VAR%` would substitute once at parse time and both passes would read the first tag's values). **Verification caught a real bug**: `Rail`'s vertical layout hardcoded `buttons[0]`…`buttons[6]` by literal index assuming exactly 7 buttons always — a customer build's 6-button list threw `RangeError` on `buttons[6]` and would have crashed the shipped customer exe outright. Fixed (`if (buttons.length > 6) buttons[6]`). `test/build_tag_test.dart` had two of its own bugs, unrelated to the app: checked for `'Diag'`/`'Run'` when `_RailButton` renders labels uppercased, and its harness didn't give `Rail`'s `Expanded` spacer a bounded height the way the real app's `Row`/`Expanded` ancestor chain does. `flutter analyze`: 0 issues. `flutter test`: passes except one pre-existing, unrelated test (`netlist_upload_test.dart`'s real-simulator discovery test, timing-sensitive under full-suite parallel load, confirmed 3/3 in isolation). Real `build_exe.cmd` run confirmed: all four exes package correctly (~8.28 MB each). Found in passing, not fixed: the script's `dist\` cleanup (`if exist dist rmdir /s /q dist`) has no error check, so a locked leftover exe from an earlier run can silently survive alongside a fresh build instead of being cleared — harmless this time (new files are unambiguously named) but worth hardening. **Follow-up same day, twice**: user re-ran the suite and hit that `netlist_upload_test.dart` timeout for real. First pass bumped its private `waitUntil` default 5 s → 8 s (matching `protocol_test.dart`'s `_waitForDone`) — measurably helped but didn't fix it: one full-suite run came back 212/212 clean, another still timed out, on this test and separately on two in `report_test.dart` (same `waitUntil` pattern). Decided to stop chasing it as "broad CPU-contention flakiness" — until the user hit the *same* failure a third time, actually blocking their `build_exe.cmd` run, which prompted finding the real cause instead of padding the timeout further. **Measured directly** (`dart run` a standalone timing probe, 256 iterations each): a nominal `Duration(milliseconds: 1)` `Future.delayed` costs ~14-15 ms in practice on this Windows machine (system timer granularity), while `Duration.zero` costs ~0.02 ms. `simulator.dart`'s cross-continuity discover mode always sweeps a full 256 pins (`discoverPins`) regardless of scenario size, awaiting `interval` every iteration — at the "1 ms" both `netlist_upload_test.dart` and `report_test.dart` used, that's ~3.6-3.9 s of pure OS timer overhead alone, before any real socket I/O, leaving almost no margin against even the 8 s timeout. Not CPU contention in the abstract — a specific, measurable, fixable cost. Both files' `interval` changed to `Duration.zero` (still exercises the real async `SimulatorServer`/socket path, just without paying Windows' timer tax 256 times over); `protocol_test.dart` left alone since its simulator-backed tests only use small verify-mode net counts (4-8), never the 256-iteration discover path, so it was never actually affected. Confirmed with four consecutive full-suite runs: 212/212 clean every time, and total suite time dropped from ~27-41 s to ~20-22 s — the fix also just made the suite faster, not only more reliable. |
| CL-47 | 2026-08-16 | FW-14 DS18B20 temperature sensor driven, `>TEMP READ` added | New `Core/{Inc,Src}/drivers/ds18b20.c/.h` — bit-banged 1-Wire (DWT-cycle-counter microsecond timing, 64 MHz HCLK), SKIP ROM (single device), CRC8-checked scratchpad. `board.c`: `board_init_temp()` configures `PA0` directly (not yet in the CubeMX `.ioc`) and binds new global `g_ds18b20`; called from `Board_Init()` but its result does not gate `Board_IsReady()` — a missing/faulty temperature sensor must not block `CONT/RES/INSUL RUN`. New `TestCmdType_t` `CMD_TEMP_READ` (`tasks.h`/`tasks.c`) — runs on the sequencer, not inline in `proto.c`, because a real conversion blocks ~750 ms. New protocol command `>TEMP READ` → `<OK started`, result as `!TEMP <deci_celsius>` (`Proto_EvtTemp`), same "post to sequencer, event follows" shape as `MANUAL PATH`; guarded by `proto_hw_ready()` (the same NULL-pointer HardFault class FW-13/CL-39 fixed elsewhere — `g_ds18b20.port` would be NULL if `Board_Init()` never ran). `Doc/GUI_development_brief.md` §3.2/§3.3/Appendix B updated for the new command/event; also fixed two stale Appendix B rows found in passing (`RES RUN` marked always-failing since before FW-02, and missing from the "Works" list even though FW-02 fixed it in 2026-08-11). Full clean `make all` (toolchain resolved manually under `C:\ST\STM32CubeIDE_2.1.1`, same gap prior sessions hit — this session's install is a newer CubeIDE version than the `C:\ST\STM32CubeIDE_1.19.0` path baked into `Debug/makefile`'s linker-script rule, which still points at another machine's absolute workspace path and was verified separately by invoking the link step by hand with the repo's real relative path): 0 errors, 0 warnings, 66772 B text (was 65264 B). **Unverified on real hardware** — bus timing follows the standard Maxim AN126 non-overdrive 1-Wire slot times with no DS18B20 to bit-bang against in this session, the same caveat this project already carries for `ads1232.c`'s own bit-banged driver; also assumes external (not parasitic) sensor power. |
| CL-46 | 2026-08-16 | HW-13 schematics resynced — DS18B20 temp sensor found, filenames normalized | User added updated `Doc/*.pdf` schematics; diffed `Control_Card.pdf`/`HV_Card.pdf`/`Matrix_Card.pdf` against the revisions they replace (pulled from git history at `d12899a`) via `pdftotext` token/text diffing, not eyeballed. **Control Card**: new U2 (DS18B20U+T&R 1-Wire temperature sensor) on `PA0` — R2 4.7 kΩ pull-up on `1_Wire`, R3 47 Ω series on `DQ`, `uC` sheet; plus 14 new test points (TP1–TP14) on the GPIO-isolator/Isolator sheets labeling existing nets (`GPIO0-3_ISO`, `SDA1/SCL1`, `MISO/MOSI`, `MISO1/MOSI1`, `SCK/SCK1`) — probe points only, no new signal. **HV Card**: resistor refdes renumbering only around R503/R546; net labels (`GPB5`, `GPB7`, `H_CONT`/`L_CONT`, `RET_ISO`) unchanged — reads as a KiCad re-annotation artifact, not a topology change. **Matrix Card**: no content change beyond the KiCad 10.0.0→10.0.3 tool-version bump. All three sheets' title-block date moved to 2026-08-06. Filenames normalized (`Control_Card 1.pdf`/`HV_Card-3.pdf`/`Matrix_Card-8.pdf` → `Control_Card.pdf`/`HV_Card.pdf`/`Matrix_Card.pdf`), resolving the naming break flagged in CL-27/CL-32. `README.md`'s hardware baseline table and `fw_status.txt`'s source-of-truth filenames/bus-pin map updated to match; new **FW-14** filed for the DS18B20 driver, which does not exist yet. |
| CL-45 | 2026-08-16 | GUI-13 every remaining "GUI Reality Check" `MOCK:` finding | User asked to clear the rest of the audit's open items after GUI-12/CL-44 fixed the one they'd reported. `grep -rn "MOCK:" gui_flutter/lib` found ~20 sites across 6 files; each triaged as a real bug (wired to live data or an honest empty/unverified state) or an intentional static reference (left alone, comment clarified as accurate-not-fake) or explicitly declined with a documented reason. **The HV netlist picker's three canned example files were more than decoration** — clicking one called `loadHv()` with fabricated name/cards/net-count metadata and proceeded straight to the pre-HV-energize verification modal, exactly the "GUI must never show a safe-adjacent state it hasn't been told is real" rule this project is otherwise careful about; removed outright (`hvFilesFor`/`pickHvFile`/`HvFile` deleted from `app_state.dart`/`design/model.dart`), "Browse the file system…" (`modals.dart`) is now the only path. **The Faults panel and the pre-HV verify modal's resistance row** used to name a fixed `nets[4]`/`nets[5]`/`nets[2]` and show invented voltage/margin numbers regardless of which net actually failed; `AppState.faultList`/`verifyChecks` now find the real first failing net per code (`Net.open`/`Net.r` vs `rmax`/`Net.insFail`, all real since `_onCont`/`_onRes`/`_onInsul`) and show its real name/refs/measurement — F06's "value" is honestly `—` since `ContResult` carries no voltage over the wire at all, and the resistance row's "worst margin" is computed from real `s.nets`, not a fixed "+0.09 Ω · 1.84 mA". **Resistance view's "Measurement conditions" panel still said "2-wire fallback (HW-01)" and a 3.3 V compliance ceiling** — both stale since FW-12/DOC-04 (real 4-wire Kelvin, corrected 2.7 V = AVDD − 0.6 V ceiling); fixed, and the invented "Measured 1.840 mA / −8%" and a specific resolution figure dropped rather than shown as real (no wire field backs either, and resolution varies with the now-correctly-described auto-ranged PGA, not a fixed ×16 — same correction applied to the Run view's Resistance domain card and the Excitation/Gain band). **HV view's "Interlock" always read "closed · safe"** with no protocol field behind it — same rule as `verifyChecks` row 5 already followed; now reads "not reported by the instrument · unverified" to match. **"MTX nets" and "HV nets" (Program view, `misc_views.dart`) were fully static example tables** (invented part numbers/pin refs, unrelated to any loaded file) — now built from `s.nets`, real once a netlist is loaded via GUI-11's per-pin card/relay mapping, with an honest empty state when nothing is loaded and "Wire" left blank rather than invented (no netlist format this app reads carries a wire-gauge column). **Results view's "First-pass yield · last 24 builds" (a fixed 78% pill + a fixed `SparkPainter` array) and "Fault pareto · this shift" were both entirely invented** — no build/shift concept exists in the protocol or `AppState.history`; pareto has no real substitute yet (would need `RunHistoryEntry` extended with fault codes/locations, a feature addition not a wiring fix) so it now says so plainly instead of showing four made-up fault locations, and yield is renamed "Pass rate · recent runs," computed for real from `AppState.history` (`SparkPainter` in `design/painters.dart` takes real data now instead of a fixed 24-value array). **Diagnostics' "Cards" table always claimed every fitted card was "Ready"/"Degraded" at a formula-generated rail voltage** ("Matrix rev 6" was stale too — GUI-11 already corrected it to rev 8 elsewhere, this occurrence was missed) — no protocol field reports per-card status or rail voltage at all, so both now honestly read "not reported"/`—`, keeping only the real fitted/empty state. **"Instrument limits"' header tag ("1 blocking · 2 pending") was a hand-typed literal that had drifted from its own list** — HW-02 (closed CL-08) and FW-04 (closed CL-19, its still-open bus-speed half already tracked as BU-03) were still shown as live blockers; both removed/relabelled, the tag is now computed from the real list length. `cont_view.dart`'s Continuity band corrected `CD4067` → `CD74HC4051` (the mux swap CL-40 already fixed elsewhere but missed here). **Left as fixed text on purpose, not fixed for real**: the HV "Limit: ≥ 10 MΩ" band item and "HV nets"' "Insul min" column — FW-11 (still open) found the firmware's own `ins_min_mohm` default is off by 1000× from its documented meaning and has no effect on the insulation verdict either way, so a live number would be either wrong or would wrongly imply the verdict is gated on it; needs FW-11 resolved first, not a GUI-side unit guess. New/updated tests in `gui_test.dart` (real F06/F08/F04 fault-list data, real worst-margin verify-modal row) and updates to `netlist_upload_test.dart`, `netlist_file_load_test.dart`, `run_history_app_state_test.dart` where they'd encoded the old fabricated pre-connection/canned-file behaviour as their expectation. Verified this session (2026-08-16) via `build_exe.cmd`: `flutter analyze`/`flutter test` both pass. |
| CL-44 | 2026-08-16 | GUI-12 nets/netlist status no longer fake pre-selection ("GUI Reality Check" cause A) | User reported the GUI showing data with nothing selected. Traced to `AppState`'s constructor seeding `nets` from `buildNets()` (the 118-net fake "AV-880" demo harness) and marking `nlMtx`/`nlFix` `loaded: true` with canned names (`AV-880_RevC.hnl`, `FX-880-C.fixture`) before any connection or netlist selection existed — so the wiring diagram, net inspector (auto-selecting `nets[11]`, a seeded fault net, on startup), resistance/insulation ranked tables, connector list, and both netlist status strips all showed fabricated data with no operator action at all. `connect()` already corrected `nlMtx.loaded` once a real (possibly empty) instrument netlist came back (GUI-09/CL-40's own comment named this the one bucket-A finding it hadn't covered), but nothing cleared the placeholder before that point, and `nlFix` was never touched after construction regardless. Fixed in `gui_flutter/lib/app/app_state.dart`: `nets` now starts `[]`, `nlMtx`/`nlFix` now start `loaded: false` — nothing renders as loaded/selected until `rebuildNets()` (real `NETLIST GET`, a browsed file, or a saved cross-scan) actually populates it. `buildNets()`/`buildDefaultFixture()` themselves are unchanged (still used by tests and as `kFix`'s scaffold fixture geometry, which is legitimate placeholder geometry to draw against, not a "loaded" claim). Three tests that had encoded the old placeholder as their expectation updated (`netlist_upload_test.dart`, `netlist_file_load_test.dart`, `run_history_app_state_test.dart`). Verified this session (2026-08-16) via `build_exe.cmd`: `flutter analyze`/`flutter test` both pass. |
| CL-43 | 2026-08-14 | GUI-11 configurable connector layout, real pin mapping | User asked directly: the 256 flat instrument pins actually land on several named, differently-shaped connectors (e.g. "first 37 pins are a DB37, the rest are circular"), and the GUI needed to know that instead of drawing a fixed 8-connector demo prop (`kFix`, `design/model.dart`) unrelated to any real harness — worse, a *real* netlist was mapped onto that prop with `(pin-1) % 128`, fabricated, not derived from anything. Two decisions made with the user before starting: the layout is guessed from the netlist file's own `Conn ID`/`Part Number` columns (already present in `required_format`'s sample, previously parsed and thrown away) with the operator confirming/editing before it's relied on — not a separate config file, not a fully manual editor; and HV card/relay becomes a direct function of the pin number (`(pin-1)~/64`, `(pin-1)%64`) rather than net-list-order assignment, flagged VERIFY pending real hardware, same footing as the BU- bring-up items. **Model**: `kFix`/`kConn`/`kConnsL`/`kConnsR`/`kFixPins` changed from `final` constants to mutable top-level bindings, plus a new `setActiveFixture()` that reassigns all five and relays out — every existing consumer (`painters.dart`, `cont_view.dart`, `layoutFixture`/`connSize`/`pinXY`) keeps working unchanged since they already read these by name. `buildFixture()` gives every connector one continuous `base` sequence across the *whole* pin space (not two independent 128-pin per-side halves, which is what the wire protocol and a real netlist's pin numbering actually do) — caught a real bug here: alternating `side` assignment for layout balance unbalanced the demo fixture's L/R pool sizes (105/151 instead of 128/128) and starved `buildNets()`'s draw loop down to 105 nets instead of 118, fixed by assigning `side` by list-half instead of alternating, which also reproduces the original hand-authored fixture's own split exactly. **Parsing**: `netlist_file.dart` gained `Conn ID`/`Part Number`/`Conn ID B`/`Part Number B` header aliases (optional — files without them parse exactly as before) and `_guessFixture()`, which groups per-connector pin observations, infers block boundaries by sort order, and guesses D-sub/circular/rect from mating part-number keywords — returned as `ParsedNetlist.fixture`, kept independent of `design/model.dart`'s `ConnType` (a plain string) so `htproto/` stays decoupled from the UI/design layer. **Mapping**: `AppState.rebuildNets()`'s `pinNode()` replaced with a real per-connector range lookup (`_fixtureFromGuess` extends the guess to cover every pin the netlist itself references, and `rebuildNets` itself extends the active fixture with a synthetic "Unassigned" connector if a *different* real netlist ever exceeds it, so no pin can ever fail to resolve to *some* connector). **UI**: new `FixtureGuessModal` (`app/modals.dart`) lets the operator fix a wrong shape/label before applying — needed this session's first real free-text input widget reuse (`TextInput`, from GUI-10) plus the existing `Seg` control for the shape picker; `browseMtxNetlist()` applies the guess optimistically and opens the modal, remembering the prior fixture so Cancel/Escape reverts cleanly. Cross-continuity/discovery mode now skips the wiring diagram entirely (`_WiringPanel` gated on `!cross` in `cont_view.dart`) since there is no known connector identity during a scan — `_DiscoveryPanel`'s existing plain Side-A/Side-B pin-pair table is the sole result surface there, matching what the user asked for almost exactly as it already stood. New shared `ConnectionResultsTable` (`app/parts.dart`) backs a new "Connection results" panel in Continuity's netlist-verify mode (which had no per-pin table at all before this — only the wiring diagram and pass/fail tallies) and Resistance (both showing every real row, not just the worst-N `_RankedTable`/`_NetResults` already showed); `_NetResults` (HV) also gained a `Conn` column directly. `report.dart`'s `ContReportRow`/`ResReportRow` gained `srcConnId`/`srcPinLabel`/`dstConnId`/`dstPinLabel`, populated for real in `AppState._onCont`/`_onRes` and finally filling the `Conn ID` CSV/PDF columns GUI-10 left blank. `kFix` being process-global mutable state now required test-isolation `tearDown(() => setActiveFixture(buildDefaultFixture()))` in every test file that exercises it, to stop one test's fixture guess leaking into the next. 14 new tests across `netlist_file_test.dart` (guess inference: grouping, shape keywords, null when no Conn ID columns), `netlist_file_load_test.dart` (`browseMtxNetlist` applying/confirming/cancelling a real guess end to end against a fake transport), and updates to `gui_test.dart`'s two tests that had encoded the old fabricated behaviour as their expectation. Verified against the real `required_format/example_netlist27072026.xlsx` directly (not just synthetic test data): all 20 pairs resolve to the correct connector and connector-relative pin, including the three-way `Y_SENSE_BUS` branch spanning all three connectors, and `layoutFixture()` produces full pin geometry for the guessed layout without error. `flutter analyze`: 0 issues. `flutter test`: 206/206. |
| CL-42 | 2026-08-14 | GUI-10 `required_format` CSV + PDF test reports built | User asked for the report side of `required_format/` once GUI-08 (netlist side) was resolved. New `gui_flutter/lib/app/report.dart`: `ReportMeta` (the shared `#`-prefixed metadata block every kind writes) plus `ContReport`/`ResReport`/`InsulReport`, each holding its own row type and a `toCsv()` matching the bundled samples column-for-column — `Source`/`Part Number`/`Conn ID`/`Destination` stay blank throughout, same as the real samples, since the wire protocol never carries connector metadata, only pins. New `gui_flutter/lib/app/report_pdf.dart` renders the same data via the new `pdf` package dependency (pure Dart, no Material — matches this project's existing dependency discipline; declared in `pubspec.yaml` with the same reasoning as `excel`/`file_picker`) — same sections as the sample PDFs (title/DUT/Verdict header, metadata rows, Summary, Results table via `pw.TableHelper.fromTextArray`), not a pixel match (the samples' extra Profile/Test Duration rows track nothing this app has). Row capture happens live: `AppState._onCont`/`_onRes`/`_onInsul` append a report row per real `!CONT`/`!RES`/`!INSUL` result to a buffer cleared at `_beginRun`, snapshotted into `lastContReport`/`lastResReport`/`lastInsulReport` at `!DONE` — decided with the user (over growing `RunHistoryEntry` to carry full per-row detail) to keep run history as a summary table and treat a report as a live artifact of the run that just finished, available only until that kind's next run starts. Insulation's `Leak V` column reuses the exact same derived-estimate formula (`_leakVoltsFor`, factored out of `paintLink()`) the live "Leakage" meter already used (GUI-09/CL-40) — no wire field carries a real per-net voltage, so both the meter and the report say so in their comments rather than presenting it as measured. Two new `DUT ID`/`Operator` fields on the status bar (`AppState.dutId`/`operatorName`, session-scoped, not persisted — both decided with the user), which needed this session's first free-text input widget (`design/widgets.dart`'s new `TextInput`, wrapping `EditableText` directly since the project carries no Material dependency). Discovered the status bar has very little width margin: adding the two fields at the existing `kMediumBreak` (1080px) breakpoint still overflowed by 131px at the 1480px "default" test width whenever the conditional Clear Fault button was also showing — raised the fields' own show/hide breakpoint to 1600px instead of fighting for the last pixels alongside content that can appear at any time. Results view gained a "Test reports" panel (`misc_views.dart`) listing whichever kinds have a report available with Export CSV/PDF per row. 6 new tests (`report_test.dart`): 4 pin the exact CSV text against the required_format shape, 2 run a real `SimulatorServer` + `AppState` continuity/resistance flow end to end and check the captured rows, same pattern `netlist_upload_test.dart` established. `flutter analyze`: 0 issues. `flutter test`: 201/201. |
| CL-41 | 2026-08-14 | GUI-08 resolved: two real bugs, not a decision | User reported the actual symptom ("select the test netlist, it still shows Select…"), which led straight past the decision GUI-08 had been waiting on. Two independent fixes in `gui_flutter/lib/htproto/netlist_file.dart`. **(1)** Removed the `hi == lo` rejection: `Core/Inc/cards/matrix_card.h` confirms HI and LO route through entirely separate mux/expander banks (`hi_en[]`/`hi_sns[]` vs `lo_en[]`/`lo_sns[]`, different physical chips — U101/U105 vs U102/U106), each independently addressed `1..256`, so "HI pin 5 → LO pin 5" is an ordinary straight-through wire (same pin label on both connector halves), not a self-connection — the guard's premise (one shared flat address space) was wrong. Dumping `required_format/example_netlist27072026.xlsx` with `openpyxl` directly (not re-guessing from the header names) also showed its `Src Pin #`/`Dst Pin #` are already globally flat by connector order (`DB15-1`→1..15, `DB15-2`→16..30, `DB9`→31..39) — GUI-08's original "per-connector, needs a Conn-ID offset map" read of the file was itself mistaken; most rows have distinct HI/LO values (crossed pins, Y-branches) and only the straight-through ones matched, which is what triggered the false rejection on every one of them. **(2)** Separately found while verifying the fix on the real file (not the test's synthetic bytes): `Excel.decodeBytes` crashed on it entirely — `excel` 4.0.6's `Parser._parseTable` null-checks a worksheet lookup that fails when the relationship `Target` is package-absolute (`/xl/worksheets/sheet1.xml`) rather than relative. Confirmed this is not specific to this one file: a fresh, default `openpyxl.Workbook().save()` was inspected directly and emits the same absolute form — legal OOXML, but a real compatibility gap for any `openpyxl`-authored netlist. Fixed with a new `_normalizeRelationshipTargets()` that unzips the bytes (`package:archive`, already a transitive dependency of `excel`, now declared directly in `pubspec.yaml`), rewrites `Target="/xl/` → `Target="` in every `.rels` entry, and re-zips, before handing bytes to `Excel.decodeBytes`. `required_format/README.md`'s "Netlist in" section rewritten — it had stated the per-connector/offset-map theory as fact. `test/netlist_file_test.dart`: the old GUI-08 collision test now asserts the row parses instead of throwing; a new test reads `required_format/example_netlist27072026.xlsx` off disk end to end and checks all 20 pairs, including the three-way `Y_SENSE_BUS` branch. `flutter analyze`: 0 issues. `flutter test`: 195/195. |
| CL-40 | 2026-08-14 | GUI-09 "GUI Reality Check" bucket A/B wired to real data | Bucket A: `AppState._onInsul` (app_state.dart) now matches `m.net` against the loaded netlist's real `pinHi` (only resolves once a real MTX netlist is loaded, same as `_onCont`/`_onRes`'s existing pattern) and sets `Net.ins`/`Net.insFail` (new field, model.dart) from the real `!INSUL leak_mohm`/status, then calls `setRelays()` — the HV view's relay grid and "Net results" table (`res_hv_views.dart` `_NetResults`, rewritten to rank `s.nets` live the same way `_RankedTable` already does for resistance, dropping the "Leak V" column since no wire field carries it) now reflect an actual run instead of only the canned fault card. `gRail`/`hzRail`/`mSense`/`mLeak`/`mLeakBad`/`hzLeak` (`paintLink()`) are all real now, computed from the live `HvEvent.millivolts` and, for the leakage pair, the last-tested net's real insulation resistance through the documented R3002/R3004 sense divider — a derived estimate, not a directly-sensed value, since no raw ADC voltage crosses the wire protocol; commented as such for whoever verifies it against hardware. `cont_view.dart`'s "Export CSV" now writes the discovered-netlist pairs via a new `AppState.exportDiscoveredNetlistCsv()`, same save-dialog pattern as `exportHistoryCsv()`. Status bar firmware version (`shell.dart`) is read from a real `>ID` sent once on connect (`AppState.fwVersion`) instead of a hardcoded string. `_bootLog()` no longer claims a bus scan or netlist load that hasn't happened — one honest "not yet connected" line. `verifyChecks` (the pre-HV verify modal) rows 3 and 5: row 3 ("harness moved") now reads the real `onHv` flag instead of an unconditional `'ok'`; row 5 ("interlock closed") has no backing protocol field at all, so it now reads honestly as unverified rather than an unconditional "safe". The stale "Auto-range PGA" button is deleted outright (`kelvin_ranged_read()` already auto-ranges every measurement since FW-02 — nothing was waiting to be wired). Bucket B: `misc_views.dart`'s bus map (SPI1 now shows the real ADS124S08/U69 CS-via-I2C path instead of the removed U33/"CS unrouted", SPI2 drops the removed DAC8775) and Instrument limits panel (the resolved HW-01 entry removed, tag count corrected to "1 blocking · 2 pending"); `res_hv_views.dart`'s Resistance band strip and Sense path diagram (DAC8775 → the real ADS124S08 IDAC1 → AIN9 → HI_COM path, FW-12); `app/parts.dart`'s fixture-sequence description (CD4067/rev 6 → CD74HC4051/rev 8). `flutter analyze`: 0 issues. `flutter test`: 194/194 (full suite, no known gaps remaining since CL-38). |
| CL-39 | 2026-08-14 | FW-13 bare-dev-kit HardFault fixed | Traced function-by-function in a prior session, fixed this one: `main.c:106` discarded `Board_Init()`'s return value with nothing tracking success, and on any board where a card's I2C init fails to complete (no daughter card fitted, one unseated, or a future partial-hardware bring-up), `hv_bus_claim`/`hv_bus_release` (`hv_card.c`) and `MatrixCard_BusClaim`/`BusRelease` (`matrix_card.c`) wrote to `en_port` with no NULL check — `HvCard_Init`/`MatrixCard_Init` never having run left that a null `GPIO_TypeDef*`, so `SafetyTask`'s `force_safe_all()` (`HvCard_OpenAllRelays` → `hv_bus_claim`; `MatrixCard_AllOff` → `MatrixCard_BusClaim`) HardFaulted the instrument the moment `>SAFE`, an armed `>FIXTURE` change, `>FAULT CLEAR`, or a real fault tried to force it safe. Fixed both ends: all four bus-claim/release functions are now NULL-guarded (`hv->cfg.en_port == NULL`/`m->en_port == NULL` returns early, no-op), the same pattern `DAC8830_WriteCode` already used; and `board.c` gained `Board_IsReady()` (a static flag set only when `Board_Init()` reaches `HAL_OK` on every sub-init), which `proto.c` checks via a new `proto_hw_ready()` before `CONT RUN`/`RES RUN`/`INSUL RUN`/`SAFE`, replying `ERR EHW` instead of attempting them against un-initialised card state. `main.c`'s comment updated to explain the two-part design (return value still intentionally not trapped at boot, but no longer silently unaccounted for downstream). Full clean `make all` (resolved toolchain paths under `C:\ST\STM32CubeIDE_1.19.0`, since a bare `make`/`arm-none-eabi-gcc` aren't on PATH in this shell): 0 errors, 0 warnings, 65264 B text. |
| CL-38 | 2026-08-13 | Removed `netlist_file_generated_test.dart`, the permanent "1 failure" in every `flutter test` run | User re-ran the suite and hit the same failure flagged since CL-20. Read the file directly rather than re-describing it from memory: it's a "Temporary verification" test (its own doc comment) that lists `.xlsx` files out of a `test_netlists/` directory *at load time* (outside any `test()` block), so a missing directory fails the whole file to load rather than failing a normal assertion. Confirmed genuinely unreproducible, not just currently broken: `git log` shows it was introduced in the `ee1e0f7` "WIP" commit, `test_netlists/` was never committed alongside it, and no generator script for it exists anywhere in the repo — three sessions (CL-20, CL-29's GUI-07 pass, CL-37) had already independently re-confirmed the same gap without fixing it. Deleted rather than patched to skip-if-missing: it can never pass on a fresh clone and was providing no signal, only permanent noise. Full suite now 194/194. |
| CL-37 | 2026-08-12 | GUI-05 run history stored on the GUI host | User decided: stored on the GUI host, not the instrument. New `gui_flutter/lib/app/run_history.dart` — `RunHistoryEntry` (timestamp, kind, MTX/HV netlist names, passed/failed) and `RunHistoryStore`, one JSON line per completed run appended and flushed immediately (same reliability reasoning as `SessionLogger` — a crash between runs must not lose the ones already finished). `RunHistoryStore()` with no directory is in-memory only, so the ~180 pre-existing GUI tests that construct `AppState` without a history directory keep working unmodified; `main.dart` passes a real `defaultHistoryDir()` (new in `paths.dart`, factored out of `defaultLogDir()`'s existing candidate-search logic rather than duplicated — same `%LOCALAPPDATA%\HT_MK1\` search, one leaf folder over: `history` next to `sessions`). `AppState._onDone` appends an entry for every completed run except a fault-refused one (FW-10's `!DONE <kind> 0 0` is not a real result and would show a false pass). `ResultsView`'s "Run history" table now reads `s.history.load()` instead of five hardcoded rows — column shape changed from the mock's per-*build* layout (Serial, parallel Continuity/Resistance/HV columns) to per-*run* (When/Test/MTX netlist/HV netlist/Passed/Failed/Verdict), because the protocol has no build/serial-number concept tying three test kinds together, and forcing one would have been invented, not real. `Export CSV` (`AppState.exportHistoryCsv`) writes real rows to a path from a native save dialog (`file_picker`, isolated in `netlist_picker_io.dart` via the same injected-function pattern as `pickNetlistFile`) — empty history or a cancelled dialog both return `false` without writing anything. `Print report` left honestly disabled (`Btn(..., disabled: true)`) rather than wired to a no-op — real OS print integration is a different scope than "where does history live," and this project has no print/PDF package dependency to build it with yet. Explicitly out of scope, left mock: the "First-pass yield" sparkline and "Fault pareto" table on the same view — GUI-05's ticket named Export CSV/Print report specifically, not those. 12 new tests (`run_history_test.dart`, `run_history_app_state_test.dart`): in-memory mode never touches disk, persistence survives a fresh `RunHistoryStore` on the same directory, one corrupt line doesn't hide the rest, fault-refused runs are not recorded, CSV export writes a real header + rows. Full suite: 193/194 (the one failure is the pre-existing unrelated gap from CL-20). `flutter analyze`: 0 issues. |
| CL-36 | 2026-08-12 | BU-10 decided: current reversal not required | User decided thermal-EMF current reversal is not required — the schematic change CL-33/CL-34's session identified as necessary (a symmetric force-side return path, since the IDACs are source-only) will not be pursued. `Doc/4wire_resistance_validation.md` §7.3 updated: the 500 µΩ-per-µV-of-junction-EMF accuracy floor at the fixed 2 mA operating point is now documented as an accepted limitation, not a gap something is expected to close. `G_CHOP` (the ADS124S08's own offset cancellation, unrelated mechanism) stays in use. No code changed — this closes a decision, not a defect. |
| CL-35 | 2026-08-12 | GUI-04 decided: netlist stays RAM-only | User decided: no persistence across reboot, matching current behaviour exactly (confirmed on hardware previously that netlists do not survive a reboot today). No code change needed — the answer to brief §8 Q2 is "no," and nothing currently does otherwise. |
| CL-34 | 2026-08-12 | DOC-04 §7.1 re-derived for 2 mA fixed operating point | `Doc/4wire_resistance_validation.md` §7.1 gained a new "Revised again 2026-08-12 (DOC-04)" block, kept alongside (not overwriting) the CL-29/DOC-03 3 mA derivation per the flag already left in place. Framing changed, not just the number: 3 mA was a target picked from inside a window (true for the DAC8775 this replaces); 2 mA is the only current `IDACMAG` can produce, so the question is only whether it clears both bounds, which it does with room — 45% compliance margin (1.22 V of 2.7 V), 239 mV common-mode margin. Also corrected the compliance ceiling itself: earlier passes used an inferred "~3.0 V, rail minus some headroom" figure; the IDAC has a real datasheet number instead (`AVDD − 0.6 V` = 2.7 V, from the Excitation Current Sources table), which is a *tighter* ceiling than the old guess, and 2 mA still clears it comfortably. Noted for the record that 3 mA would also have cleared compliance under the corrected ceiling (0.48 V margin) — DOC-03 wasn't wrong on the physics, it's just unreachable now. Resolution cost: 4.66 µΩ/count at gain 32 vs 3 mA's 3.10 µΩ/count, a noise-floor cost PGA auto-ranging already absorbs, not a functional one. Also updated §7.3 (thermal EMF / BU-10): current reversal needs a schematic change now, not a firmware register write — see BU-10's updated entry above and CL-33's note. |
| CL-33 | 2026-08-12 | FW-12 Kelvin excitation moved to the ADS124S08's own IDAC | `ADS124S08_SetIdac(dev, idac1_mux, idac2_mux, mag)` added to `ads124s08.{h,c}` (two register writes: `IDACMUX` then `IDACMAG`), following `ADS124S08_SetGain`'s pattern, plus `ADS124S08_MUX_AIN9`, `ADS124S08_IDAC_OFF` and the `ADS124S08_IMAG_*` magnitude codes (sourced from `Datasheet/ads124s08.pdf` Tables 32/33 - IDACMAG's magnitude field is shared between both IDACs, only the output pin is independent). `kelvin.c` now calls `ADS124S08_SetIdac(&g_ads124s08, ADS124S08_MUX_AIN9, ADS124S08_IDAC_OFF, KELVIN_IDAC_MAG)` instead of `Frontend_SetCurrentCode`; `kelvin.h`'s `KELVIN_FORCE_CODE` (a DAC8775 code) is replaced by `KELVIN_IDAC_MAG` (`ADS124S08_IMAG_2000UA`) and `KELVIN_FORCE_CURRENT_A` becomes a fixed 0.002f - no longer a TUNE placeholder, the hardware ceiling. **`FRONTEND_MODE_IMPEDANCE` kept, not deleted**: `Frontend_SetMode` never touched the DAC8775 (pure OPT0_CNTR GPIO toggle), and it still does real work - the continuity divider's 10 k pull-up on `ADC_IN` would otherwise load `HI_COM` in parallel with the IDAC's 2 mA, so Kelvin still swings the SPDT to isolate it before exciting. Only `Frontend_SetCurrentCode`, the `idac` field, and `idac_spi`/`idac_cs_port`/`idac_cs_pin` came out of `control_frontend.{h,c}`. `board.c`: `BOARD_IDAC_SPI`/`BOARD_IDAC_CS_PORT`/`_PIN` removed, `board_init_frontend()` no longer configures an IDAC (hspi2 itself stays - HV DAC8830/AD7476 still use it). `dac8775.{h,c}` deleted outright (register map was still VERIFY and now moot) along with the matching entries in `Debug/Core/Src/drivers/subdir.mk` and `Debug/objects.list` so `make all` doesn't try to compile a file that no longer exists (the CL-23 lesson - these lists don't update themselves). Full clean `make clean && make all`: 0 errors, 0 warnings, 65024 B text (was 64872 B before FW-02; net change reflects the new driver code minus the deleted DAC8775 driver). GUI still references the DAC8775 in three places (`gui_flutter/lib/views/misc_views.dart`'s Diagnostics bus-map panel, `res_hv_views.dart`'s path/band labels ×2) - noted, not fixed, out of this task's file scope (`Doc/idac_current_source.md` §5 lists firmware files only). |
| CL-32 | 2026-08-12 | HW-11 resolved: DAC8775 removed, ADS124S08 IDAC sources excitation instead | User pointed at the current schematic and asked to check; confirmed directly, not inferred. `DAC8775` no longer appears anywhere in `Control_Card 1.pdf` — its sheet (`DAC.kicad_sch`) is now four unrelated pull-up resistors, the component was deleted. On `Matrix_Card-8.pdf`, ADS124S08 pin `GPIO1_AIN9` (previously a calibration-resistor tap) is now wired directly to `HI_COM`, matching the chip's documented IDAC-to-AINx routing (`IDACMUX`/`IDACMAG`, already in `ads124s08.h`'s register map from FW-01, never used). No DAC to replace, so the LTC2662-16 investigation this item was tracking is moot - closed as superseded by hardware rather than decided. Datasheet-confirmed: IDAC accuracy at the 2 mA range is typ ±0.5%/worst-case ±3%, current matching between the two IDACs typ 0.07%/worst-case 0.4% - a real, vendor-characterized spec for exactly this application, stronger footing than the DAC8775 path (whose register map was still marked VERIFY). Hard constraint found in the same pass: IDAC tops out at 2 mA (`IDACMAG` code `1001`), reopening the excitation target CL-29 had just closed at 3 mA the same day - see **DOC-04**. Firmware not yet updated for the new current source - see **FW-12**. Full write-up: `Doc/idac_current_source.md`. Also flagged, not chased: the new PDFs are still uncommitted and `Control_Card 1.pdf` breaks the project's `-N` naming convention. |
| CL-31 | 2026-08-12 | GUI-07 `LIMITS SET` wired to a real control | `gui_flutter/lib/app/app_state.dart` gained `AppState.setLimits(rMaxMohm, insMinMohm)` — issues `LIMITS SET`, checked against the same `_reportRefusal` pattern every other operator action uses, and updates `limits` locally from the values just sent on `<OK` (no round-trip `LIMITS GET` needed, since the brief §3.2.1 says any value is accepted). Diagnostics screen (`gui_flutter/lib/views/misc_views.dart`) gained a "Test limits" panel — two sliders (R max in Ω, Insulation min in Ω, both wire-milliohm fields ÷1000 same as the Calibration panel's reference-resistor readout) seeded once from `LIMITS GET` on connect, plus an Apply button. `flutter analyze`: 0 issues. `flutter test`: 181/182 pass, the one failure (`netlist_file_generated_test.dart`) is the pre-existing unrelated WIP-scaffolding gap noted in CL-20. Found in passing (not fixed): `Proto_LimitInsMinMohm()` has no caller in the insulation verdict path at all, and the firmware's own default is off by 1000× from what its comment claims — logged as **FW-11**, not fixed here since it changes safety-relevant pass/fail behaviour and needs a decision first. |
| CL-30 | 2026-08-12 | HW-08 confirm-and-close | Read `HV_Card-3.pdf`'s title block text directly (`pdftotext -layout`): sheet shows `R3003 5KOhms` next to the schematic's own stated formula `V_HV_Sense = 0.00049 * HV_Voltage`, matching firmware's scaling exactly. The 50 kΩ drawing error (originally raised 2026-07-20) is resolved in the current schematic. No firmware change was needed — `board.c`'s 0.00049 scaling was already correct against the *intended* value, only the drawing was wrong. |
| CL-29 | 2026-08-12 | DOC-03 §7.1 re-derived for 3 mA | `Doc/4wire_resistance_validation.md` §7.1's compliance table was still built around a ~100 Ω placeholder Rₒₙ and a stale ~5 mA target from before BU-09 measured the real CD74HC4051 figures (typ ~110–140 Ω, worst-case ~250–320 Ω at 3.3 V). Re-derived using worst-case Rₒₙ (320 Ω) for the compliance/upper-bound check and typ-low Rₒₙ (110 Ω) for the common-mode/lower-bound check — the same asymmetric worst-case reasoning §7.2 already used. Result explains *why* BU-09 moved the target: with real Rₒₙ, worst-case compliance now fails around ~4 mA (not ~10 mA as the old ~100 Ω placeholder implied), so 3 mA is the point that sits with real margin on both ends (≈0.8 V / 26 % compliance headroom, 433 mV common-mode headroom) rather than an arbitrary round number. The 1 mA lower-bound conclusion carries over unchanged, as instructed — it never depended on the mux swap. One stray downstream reference to "~5 mA" (§7.8's BU-01 row, citing the same superseded figure) was also corrected for consistency. |
| CL-28 | 2026-08-12 | DOC-02 `HT_ENABLE_ADS1232` default (retroactive) | Confirmed already fixed: `Core/Inc/drivers/ads1232.h`'s default flipped 1→0 in commit `c579830` (2026-08-07, the heartbeat change), which explicitly notes in its commit message "Carries HT_ENABLE_ADS1232 off with it." README's "default off" claim and the header have agreed since that commit; this open item was simply never marked closed. No code change made — verified current state matches both README and this item's intent. |
| CL-27 | 2026-08-12 | DOC-01 `fw_status.txt` synced to FW-02 | Full pass over `fw_status.txt` against the current architecture: schematic filenames updated to `Control_Card-5.pdf`/`Matrix_Card-7.pdf`/`HV_Card-3.pdf` (the git-tracked current revisions — see note below); BUS/PERIPHERAL MAP rewritten for the real I2C2-shared/I2C3-local split (`Doc/i2c_bus_sharing.md`) and SPI1 now correctly names the ADS124S08 as the resistance ADC, not the long-removed Matrix U33; every place the doc still described the superseded 2-wire/100 Ω-return/10 mA resistance test, the single-char console, or the un-gated per-card I2C scheme was marked SUPERSEDED with a pointer to the FW-*/CL-* that replaced it, rather than silently deleted, so the doc's own history stays legible. R3003's value note updated to match HW-08 (CL-30). Added a banner at the top pointing to `PROJECT_LOG.md` as the live tracker, since this file had drifted out of sync for weeks at a time before. **Found in passing:** the working tree has an uncommitted rename churn — `Control_Card-5.pdf`/`Matrix_Card-7.pdf` deleted, replaced by untracked `Control_Card 1.pdf`/`Matrix_Card-8.pdf` with identical embedded title-block dates (2026-08-06 / 2026-07-11) to the files they replaced — almost certainly a design-sync re-export rather than a real new revision, but not committed or reconciled; flagged for the user rather than chased, since it isn't this session's change. |
| CL-26 | 2026-08-12 | FW-06 `>STATUS` reports `running`/`fault` | `proto_state_name()` (already used by the `!STATE` heartbeat) is now also used by the `>STATUS` handler in `Core/Src/app/proto.c`, and gained a fault check (`Safety_InFault()`) it didn't have before — priority order is fault > running > armed > idle, matching what the heartbeat already implied. A GUI that reconnects mid-run or mid-fault and re-issues `>STATUS` (brief §3.5 rule 4) now gets the truth directly instead of waiting for the next event. `Doc/GUI_development_brief.md` updated in the four places that documented the old idle/hv_armed-only contract (§3.2's command table, the prose right below it, the §8.3 exchange, Appendix B, and deviation #14) so the brief matches the fixed behaviour rather than describing a gap that no longer exists. No toolchain available this session to do a full arm-none-eabi-gcc build; change reuses an existing, previously-verified helper function, so risk is low, but this is unverified beyond code review. |
| CL-25 | 2026-08-11 | Matrix Card confirmed on the same shared bus, gated to match | User confirmed directly (not inferred): the Matrix Card's own onboard expanders are on the same bus as HV Card 1, closing what CL-24 had left open. `MatrixCard_Init` split onto two I2C handles - `hi2c_local` for U21 alone (I2C3, stays put, never shares an address with anything) and `hi2c_shared` for the eight Matrix-card expanders (I2C2, same bus as every HV card). Added `en_port`/`en_pin` (`HV_Card_EN1`/J1) to `MatrixCard_t` and public `MatrixCard_BusClaim()`/`BusRelease()`, called around every function that touches `hi_en`/`lo_en`/`hi_sns`/`lo_sns` (`Init`, `SetSensePaired`, `BankOff`, `SelectPin`, `ConnectPair`). U69 (the ADS124S08 control expander, also on the shared bus per HW-12) gets the same treatment in `board.c`'s io callbacks and `board_init_ads124s08()`, which also moved off `BOARD_MATRIX_I2C` onto `BOARD_HV_I2C` to match. `board_init_matrix()` updated for the new signature. Build verified clean (0 errors, 0 warnings). `Doc/i2c_bus_sharing.md` and `PROJECT_LOG.md` updated; the open question this closes was tracked only as prose in CL-24, never given its own BU- number, so nothing to formally close. |
| CL-24 | 2026-08-11 | Shared I2C bus between the Matrix Card and every HV card, ungated | User traced the schematic and confirmed the Matrix Card and all four HV cards share one isolated I2C bus while every card's expanders hard-strap to the same 0x20-0x27 range - a guaranteed address collision the moment two cards are live together. `HV_Card_EN1..4` (PC5/PC6/PA10/PA9, through isolators U18/U19 to each HV connector) exist for exactly this, but nothing in firmware touched them, and CubeMX still had the four pins under a stale pre-rename label (`HV_CARD_DT_3_0`/`_3_1`/`_4_0`/`_4_1`) configured as unused inputs. Fixed: pins relabelled `HV_CARD_EN1..4` and switched to push-pull outputs, default low, in `HT_MK1.ioc`/`main.h`/`gpio.c`. `HvCardCfg_t` gained `en_port`/`en_pin`; `hv_card.c` added `hv_bus_claim()`/`hv_bus_release()` and wraps every function that touches `hv->inject[]`/`hv->ret[]` (Init's expander loop, OpenAllRelays, CloseInject, CloseReturn) so exactly one card's segment is ever live, on every exit path including errors. `board.c` maps HV board index to physical slot as idx+1 (board 0 -> J2/EN2), reserving J1/EN1 for the Matrix Card per HW-09, with a compile-time guard against `BOARD_HV_COUNT` exceeding the 3 slots that leaves. Diagram + plain-English write-up: `Doc/i2c_bus_sharing.md`. Build verified clean (0 errors, 0 warnings). **Whether the Matrix Card itself was on this bus was left open at the time** — resolved same day, see CL-25. |
| CL-23 | 2026-08-11 | FW-02 4-wire Kelvin rewrite | `Kelvin_MeasurePair` now reads HI_SENSE/LO_SENSE on the Matrix Card's ADS124S08 instead of returning `HAL_ERROR`. Sequence: `MatrixCard_SetSensePaired`+`ConnectPair` route both force and sense arrays, `Frontend_SetCurrentCode` forces the excitation, then the PGA is auto-ranged (highest gain first, stepping down on saturation — most wires are near 0 Ω and want the resolution; a real fault falls through to unity gain instead of clipping). A second conversion at the same gain with the excitation off gives a per-point zero-current baseline that is subtracted before `ADS124S08_OhmsFromCurrent` — system-offset subtraction, complementary to the one-time `ADS124S08_SelfOffsetCal` now run at board init (cancels the ADC's own offset only). Current reversal for thermal EMF (BU-10, §7.3) is **not** included: it needs the DAC8775 configured for its bipolar ±24 mA range, and the DAC8775 register map is still placeholder/VERIFY (dac8775.h) — inventing a "reversed" code without knowing the real range encoding could silently drive the wrong current, which is worse than not reversing at all. Left as an explicit gap, not implemented unsafely. Getting a real reading also required work outside kelvin.c itself: `board.c` never had an ADS124S08 instance or U69 io-vtable wiring at all (only the driver existed, from FW-01) — added, including the segment-select dance every U69 access needs (it sits behind the same BUFF2 translator as the sense enables, see CL-22). SPI1 was still CubeMX's default 4-bit/mode-0 config left over from the removed AD7476, and clocked at 32 MHz against the ADS124S08's 10 MHz ceiling — both fixed in `spi.c` and `HT_MK1.ioc` (8-bit, mode 1, /8 prescaler = 8 MHz). Separately, `make` from the command line couldn't link at all: `proto.c` (FW-05, closed 2026-08-01) and `ads124s08.c` (FW-01) were never added to `Debug/Core/Src/{app,drivers}/subdir.mk` or `Debug/objects.list` — only the Eclipse IDE's own indexer knew about them. Fixed so a plain `make all` builds clean (64872 B text, 0 warnings) instead of only working from inside the IDE. **Unverified on real hardware** — BU-01 and BU-08 still gate trusting a specific number. |
| CL-22 | 2026-08-11 | HW-12 sense-side I2C straps confirmed and fixed | Read the actual address labels off `Matrix_Card-7.pdf` sheet 9 directly (PDF pages rendered to PNG with PyMuPDF and cropped around each expander, not inferred from the earlier text-extraction pass, which this sheet's binary-address labels don't survive `pdftotext` at all). Found: U66 = 0x20, U69 = 0x21, U67 = 0x22, U107 = 0x24, U108 = 0x26 — not the sequential 0x24..0x27 block `matrix_card.h` assumed for the sense enables, and not 0x20 for U69 as fw_status.txt's old collision note (U69 vs U101) had it either. The collision itself is confirmed gone: U69 sits on BUFF2 (its own segment) at 0x21, between U66 and U67, nowhere near U101 (0x20 on BUFF1, the force segment). Force-side straps (U101/U102/U105/U106, sheet 3) were cross-checked the same way and matched the existing code exactly (0x20/0x21/0x22/0x23) — confirmed, not changed. `MATRIX_HI_SNS_LO_STRAP`/`_HI_STRAP`, `MATRIX_LO_SNS_LO_STRAP`/`_HI_STRAP` and `MATRIX_ADCCTL_STRAP` corrected in `matrix_card.h` to match. Without this fix, FW-02 would have addressed the wrong I2C devices for every sense-array and ADC-control access. |
| CL-21 | 2026-08-11 | Verified a re-derived resistance-accuracy calculation against `Datasheet/ads124s08.pdf` and `Datasheet/dac8775.pdf` directly | Two real errors found and fixed. **(1)** The Table-1 (Sinc3, chop disabled) noise values quoted for Gain=128 at 2.5 SPS and 5 SPS were each one row off (true values 0.11 µVPP and 0.16 µVPP, not 0.16 and 0.23 — more margin than stated, not less); the 16.6 SPS row (0.30 µVPP) was correct. **(2)** DAC8775's TUE table has four rows gated on temperature range *and* whether the "4 to 20 mA" range specifically is configured; the design's actual 1–3 mA operating point (§7.1) is below that range's 4 mA floor, so the applicable row is the general ±0.14 %FSR one, not the ±0.4 % "4 to 20 mA"-specific one used in the corrected-but-still-wrong pass. Net effect on the conclusion: unchanged — calibration is mandatory either way, because none of the DAC-limited ceilings (30–107 mΩ depending on FSR) come close to the noise-floor target (sub-1 mΩ). `Doc/4wire_resistance_validation.md` §7.6 rewritten with the sourced numbers and both range-FSR cases; CM-floor formula and FSR-at-gain-128 math were independently re-verified and are correct as originally stated. |
| CL-20 | 2026-08-10 | Netlist parser rejected the required_format header spellings | `Src Pin #`/`Dst Pin #` (the headers `gui_flutter/required_format/example_netlist27072026.xlsx` actually uses) were not in `netlist_file.dart`'s recognised alias lists, so the required-format netlist could not be loaded at all. Added as aliases. Two regression tests in `test/netlist_file_test.dart`: one confirms the new spellings parse with distinct pin numbers, the other pins the still-open GUI-08 gap (the real example file's rows collide under the flat pin model and are correctly rejected, not silently misrouted). Full suite re-run: 181/182 pass — the one failure (`netlist_file_generated_test.dart`) is pre-existing WIP scaffolding from `ee1e0f7` expecting a `test_netlists/` directory that was never committed, unrelated to this change. |
| CL-19 | 2026-08-10 | FW-04 mux addressing (retroactive) | Confirmed already implemented: `matrix_card.c` stages `HI_S`/`LO_S` into a shared word and pushes it to MCP23017 U21 on I2C3 (`f778ba7`, 2026-08-01, bundled into the FW-03 rework). Never closed under its own ID until this review. The 400 kHz bus-speed half of the original item is unresolved and carried forward under BU-03. |
| CL-18 | 2026-08-05 | Frontend must match the approved HTML design | Web frontend in `gui/htweb/`. `index.html` is `Doc/HT_MK1_GUI_Proposal.html` **verbatim** — same markup, same CSS, same render code — so the running instrument looks exactly like the design that was signed off. The only change to it is a `window.HT_SEAM` export at the end of its closure, which lets `live.js` swap the three simulated run functions for protocol-driven ones and rebuild the net model from a real netlist. `server.py` is a stdlib HTTP bridge: page, `GET /api/events` (SSE), `POST /api/cmd`. Binds loopback unless `--allow-remote`, because the page can arm and fire 500 V. The Tk frontend stays as the fallback and as the home of the headless safety-rule tests. |
| CL-17 | 2026-08-05 | GUI tasks 3–10 | Operator GUI built in `gui/htgui/` — Tk, standard library only, no dependencies. `model.py` holds the instrument state and every safety rule and imports no Tk, so the rules are tested headlessly; `app.py` is the shell (HV banner on every screen, always-reachable abort, 100 ms redraw tick); `screens.py` is the eight screens. Commands always go out on a worker thread, because `execute()` blocks up to 2 s and freezing the UI would freeze the abort button with it. Suite is now **83 tests**, including a smoke test that drives the real Tk app against the real simulator over a socket and asserts the HV controls are gated by the instrument's reported fixture, not by what the GUI asked for. |
| CL-16 | 2026-08-05 | FW-10 latched fault wedged the run path | `run_command` now answers a run command it cannot execute: `!STATE fault` then `!DONE <kind> 0 0`, so `s_busy` clears and the GUI is released instead of waiting for a `!DONE` that never comes. Added **`>FAULT CLEAR`** (`CMD_CLEAR_FAULT`), handled *before* the fault gate since it is the only recovery short of a power cycle — it forces safe first, then clears the latch, so clearing can never be a way to re-energise something by accident. Protocol addition, so §3.2 and §3.2.1 of the brief were updated, and the simulator and codec now carry it too. |
| CL-15 | 2026-08-05 | FW-09 abort lost at run start | The three `Proto_ClearAbort()` calls at run entry are gone, and **the function itself is deleted** — `proto.h` carries a comment saying why, because the only thing it was ever used for was the bug. The flag now has exactly three writers: `proto_post_run` clears it before the run is queued (the one point where clearing is correct), `>ABORT` and an invalidating fixture change set it, and `Proto_EvtDone` clears it on the way out. No window remains in which an operator stop can be swallowed. Correct by inspection at every point in a run; **BU-12 still has to prove it on hardware.** |
| CL-14 | 2026-08-05 | Boot banner not protocol-framed | Found while reviewing the GUI codec, which was correctly rejecting it. The five `console_puts` lines carried no `<`, `!` or `#` marker, and the banner led with a bare `\r\n` that framed as an empty line — two parse errors at the GUI end on every reset, per brief §3.1. All five are now `#`-prefixed with no leading newline, and `console_puts` documents the requirement for future callers. Protocol-visible, hence a closed item rather than only an activity-log line. |
| CL-13 | 2026-08-05 | FW-08 premature `!SAFE` | `Proto_SetFixture` no longer announces safety it has not achieved. It drops the arm locally, posts `CMD_FORCE_SAFE` carrying the new fixture, and the **sequencer** emits `!HV 0` → `!SAFE` → `!FIXTURE` once the rail is really down — published ordering preserved. The duplicate `!SAFE` is gone with it. If the post fails the instrument latches a fault and emits `!STATE fault` rather than `!SAFE`. A fixture change now also sets the abort flag, so declaring a move stops a run in flight instead of letting 500 V continue for up to 64 s — newly reachable, and newly necessary, once FW-07 let the command through mid-run. `CMD_FORCE_SAFE` also emits `!HV 0` before `!SAFE` on every path now, so `>SAFE` no longer drops the rail silently. |
| CL-12 | 2026-08-05 | FW-07 `>ABORT` could not stop a run | Three causes, all fixed. **RX is interrupt-driven** — `LPUART1_IRQHandler` defined in `log.c` (which owns the hand-rolled LPUART1 bring-up, so CubeMX generated no handler), NVIC priority 5 = `configLIBRARY_MAX_SYSCALL_INTERRUPT_PRIORITY`, bytes pushed to a queue from the ISR and re-armed there; an error callback clears overrun and re-arms, without which one overrun would deafen the instrument permanently. **`tComms` moved `osPriorityBelowNormal` → `osPriorityAboveNormal`** — it blocks on the RX queue so it costs nothing until a byte lands, and it must outrank the sequencer or it is never scheduled during a run. **Settle delays yield** — new `Board_SettleMs()` uses `osDelay` under the RTOS (`+1` tick, so a settle can never come out shorter than `HAL_Delay` gave) and `HAL_Delay` before the scheduler; `continuity.c`, `kelvin.c` and `insulation.c` use it. Raising the comms priority also forced a fourth fix: three threads write the console UART and `HAL_UART_Transmit` is not reentrant, so a preempted line was silently dropped — a lost `<` reply is a 2 s GUI timeout. All console output now goes through `Log_ConsoleWrite()` under a mutex, and `proto_emit` builds the CRLF into its buffer so a line leaves as **one** write. +5,888 bytes: the HAL's IT-receive path was previously discarded by `--gc-sections`. |
| CL-11 | 2026-08-01 | FW-05 GUI protocol, instrument side | `app/proto.c` — line parser, one `<` reply per command on every path including errors, `!` event streaming from the sequencer, and `!STATE`/`!FIXTURE`/`!HV`/`!SAFE`. Replaces the single-keystroke console. Netlist upload/download, whole-run continuity (verify and discover) and insulation added to the sequencer as `CMD_CONT_RUN`/`CMD_RES_RUN`/`CMD_INSUL_RUN`. `>INSUL ARM` refuses unless the fixture is `hv`; `>MANUAL RELAY` refused outright. Log lines now `#`-prefixed so the GUI can separate them. |
| CL-10 | 2026-08-01 | FW-01 ADS124S08 driver | Written. io vtable for CS/RESET/START/DRDY (all on expander U69, not GPIO), SPI mode 1, internal 2.5 V reference explicitly switched ON (REFCON is 00 at reset — selecting the reference is not enough), device-ID check, SFOCAL, RDATA-based reads, timed conversion waits because polling DRDY costs an I2C round-trip. Compiles clean under -Wall -Wextra. |
| CL-09 | 2026-08-01 | HW-06 one clock net | **Done in Matrix_Card 2** — `SPI1_SCLK` throughout including J101; `SPI1_SCK` no longer exists on the Matrix card. |
| CL-08 | 2026-08-01 | HW-02 sense-enable net names | **Done in Matrix_Card 2** — `HI_SENSE_EN1..32` / `LO_SENSE_EN1..32` present and driven by U66/U67 (HI) and U107/U108 (LO) on BUFF2. |
| CL-07 | 2026-07-29 | Mux enable pull direction — full verification requested | All 64 verified: sheet 2 R1–R32 and sheet 8 R33–R64, every one 100 kΩ to **+3V3**, none to GND. The +3V3 label sits at an identical (−31, +11) offset from the refdes on all 64 instances, and R1 and R33 were wire-traced explicitly to the +3V3 label. No resistor has a GND nearer than its +3V3. Sense muxes are U34–**U65** (32 of them). |
| CL-06 | 2026-07-29 | `I2C_EN1` / `I2C_EN2` purpose | Leftover access GPIO from an earlier concept, deliberately kept on the connector as spare lines. No function. Firmware must not drive them; treat as reserved. |
| CL-05 | 2026-07-29 | ADS124S08 control lines believed unrouted | **Not a gap — this finding was wrong.** U69 (MCP23017 at 0x25) drives all four from sheet 9: GPB0 → `ADC_RST_1`, GPB1 → `DRDY_1`, GPB2 → `ADC_CS_1`, GPB3 → `Start_SYNC_1`. They never needed to leave the card. No connector pins and no MCU pins are required; the pin-budget proposal is withdrawn. The error was checking whether the nets reached J101 and concluding they dead-ended, without checking whether they were driven locally on the same sheet. Firmware consequences are tracked in FW-01. |
| CL-04 | 2026-07-20 | LO_COM pull-down value | Fixed at 100 Ω, now fitted as R131, 0.01 %, 1206. |
| CL-03 | 2026-07-27 | `LO_COM` reported missing from the Control Card | Needs no connector pin at all; it returns through R131 to Matrix Card ground locally. What matters instead is a continuous ground return — folded into HW-03. |
| CL-02 | 2026-07-27 | `HI_COM` reported missing from the Control Card | Not missing. It is net `IN` — the Opto SPDT common, switched between `ADC_IN` (10 kΩ pull-up via R26) and `I_OUT` (excitation) — present on card-connector pin 29. A naming difference, not a routing gap. |
| CL-01 | 2026-07-27 | Multiplexer enable polarity — contradictory in v1.3 | Every CD4067 E pin carries a 100 kΩ pull-up to +3V3, force and sense alike. E is active LOW, so expander bit 1 = disabled, 0 = enabled. Initialise all mux OLAT registers to `0xFF`. Safe from power-on while the MCP23017s are still high-Z. |

---

## Activity log

### 2026-08-16 (HW-13 schematic resync)
- User added updated `Doc/Control_Card.pdf`/`HV_Card.pdf`/`Matrix_Card.pdf` and asked for a
  review of what changed plus a documentation update.
- Pulled the previous revisions (`Control_Card 1.pdf`/`HV_Card-3.pdf`/`Matrix_Card-8.pdf`) out
  of git history at `d12899a` (their last commit) and diffed each against the new file with
  `pdftotext` (both `-layout` for context and a token-set diff to cut through PDF text-layout
  jitter) rather than eyeballing 600+ KiCad-exported PDF pages.
- **Found**: Control Card gained U2 (DS18B20U+T&R 1-Wire temperature sensor) on `PA0`, plus 14
  test points (TP1–TP14) labeling existing isolator nets. HV Card: cosmetic resistor-refdes
  shuffle only. Matrix Card: unchanged. Full account in the status snapshot and **HW-13/CL-46**
  above.
- Updated `README.md` (hardware baseline table: new filenames, DS18B20 note) and `fw_status.txt`
  (source-of-truth filenames, new `PA0`/DS18B20 bus-map entry, "last updated" banner) to match.
- User then asked for the firmware side to be implemented. **FW-14 (CL-47)**: wrote
  `drivers/ds18b20` (bit-banged 1-Wire, DWT microsecond timing, CRC8-checked), wired it into
  `board.c` (`board_init_temp()`/`g_ds18b20`, non-gating on `Board_IsReady()`), added
  `CMD_TEMP_READ` to the sequencer and a new `>TEMP READ`/`!TEMP` protocol command pair, and
  updated `Doc/GUI_development_brief.md`'s §3.2/§3.3/Appendix B to match (plus two unrelated
  stale Appendix B rows about `RES RUN` fixed in passing). Full clean `make all`: 0 errors,
  0 warnings, 66772 B text. Unverified on real hardware - no DS18B20 to test bit-banged timing
  against this session.

### 2026-08-14 (FW-13 HardFault fix, GUI-09 real-data wiring, GUI-08 netlist bug, GUI-10 reports, GUI-11 connector layout)
- Worked the three ready-to-implement packages left in the previous session's handoff, in the
  order given (firmware fix first, since it's what makes the GUI packages worth doing at all).
- **FW-13 (CL-39)**: null-guarded `hv_bus_claim`/`hv_bus_release` (`hv_card.c`) and
  `MatrixCard_BusClaim`/`BusRelease` (`matrix_card.c`) against a NULL `en_port`, and added
  `Board_IsReady()` (`board.c`) so `proto.c` can refuse `CONT/RES/INSUL RUN` and `>SAFE` with
  `ERR EHW` when `Board_Init()` didn't fully succeed, instead of attempting them. Full clean
  `make all`: 0 errors, 0 warnings, 65264 B text (toolchain resolved manually under
  `C:\ST\STM32CubeIDE_1.19.0`, since neither `make` nor `arm-none-eabi-gcc` are on PATH by
  default in this shell).
- **GUI-09 (CL-40)**: wired every bucket-A mock/dead field the prior session's "GUI Reality
  Check" audit had annotated inline (`_onInsul`, the HV rail meters, Continuity's Export CSV,
  the status bar firmware version, `_bootLog()`, the pre-HV verify modal's rows 3/5) to real
  protocol data, deleted the stale "Auto-range PGA" button, and fixed the bucket-B reference
  panels that had gone factually wrong since FW-02/FW-12 (bus map, Instrument limits, Resistance
  sense path, fixture-sequence text). `flutter analyze`: 0 issues. `flutter test`: 194/194.
- Not started (at that point): HW-09, GUI-06, GUI-08, FW-11 and the rest of the "awaiting a
  decision"/"verify at bring-up" rows — all need a product/hardware decision or a dependency
  this project doesn't have yet, per the prior session's own scoping. Left untouched.
- **User then reported a live bug** (not from the handoff list): selecting the `required_format`
  test netlist left the netbar still showing "Select…", as if nothing had been picked. Traced
  instead of guessed — read `netlist_file.dart`'s rejection logic against `matrix_card.h`'s real
  HI/LO bank separation, then reproduced the exact failure against the real bundled file with a
  throwaway `dart run` script before touching any code.
- **GUI-08 (CL-41)**: turned out to be two real, fixable bugs, not the decision it had been
  tracked as since 2026-08-10 — see the status snapshot and CL-41 above for the full account.
- User also asked for `required_format/`'s "reports out" side (CSV + PDF for continuity/
  resistance/insulation). Two open questions before starting — where DUT ID/Operator come from
  (nothing in the GUI tracks them), and how per-row report detail is kept given run history only
  stores summary counts — put to the user rather than guessed: status bar fields (session-scoped)
  and generate-immediately-from-a-live-run (not persisted), respectively.
- **GUI-10 (CL-42)**: both report writers (CSV via `report.dart`, PDF via the new `pdf` package
  and `report_pdf.dart`) built to the `required_format` samples' exact column shape, fed from real
  per-pin/per-net rows captured while a run streams in. New DUT ID/Operator status-bar fields
  needed this session's first free-text input widget (`design/widgets.dart`'s `TextInput`, no
  Material dependency). Found the status bar has very little spare width — adding the two fields
  overflowed the row at the "default" 1480px test size whenever the conditional Clear Fault
  button was also present; raised their own show/hide breakpoint to 1600px rather than fight for
  the last pixels. See the status snapshot and CL-42 above for the full account. `flutter
  analyze`: 0 issues. `flutter test`: 201/201.
- User then asked for a third, larger piece directly: the 256 flat instrument pins actually land
  on several named, differently-shaped connectors in a real harness (their example: "first 37
  pins are a DB37, the rest are circular"), configurable per harness rather than the hardcoded
  8-connector demo fixture the GUI had been drawing regardless of what was actually loaded — plus
  one consolidated "all connections" result table reused across continuity/resistance/HV, and no
  connector diagram at all for cross-continuity discovery (no known connector identity mid-scan).
  Asked for a plan first, no code yet — entered plan mode, researched the existing fixture/
  connector model (`design/model.dart`'s `ConnectorDef`/`FixtureDef`/`ConnType` turned out to
  already be genuinely type-aware, drawing real per-pin D-sub/circular/rect geometry — just fed
  by one hardcoded constant with no relationship to any real netlist), asked two clarifying
  questions (where the layout comes from; whether HV relay mapping should also become pin-based),
  wrote the plan to `refactored-wishing-crane.md`, got it approved, then implemented it in full —
  see **GUI-11 (CL-43)** in the status snapshot above for the complete account. Caught and fixed
  a self-introduced regression along the way (alternating connector side-assignment unbalancing
  the demo fixture's L/R pools, starving `buildNets()` down to 105 nets instead of 118) before it
  ever reached the user, via the existing test suite. `flutter analyze`: 0 issues. `flutter
  test`: 206/206.

### 2026-08-12 (later still still — a round of decisions: HW-04/09, GUI-04/05/06/08, BU-10)
- User answered the open-points list from the previous handoff. Worked each one in turn;
  HW-09 and GUI-08 explicitly left open, not chased further, per the user's instruction.
- **HW-04**: agreed for the next schematic revision, routing to `AIN8` instead of the
  originally-proposed `AIN2` (confirmed free — `AIN9`'s old calibration-tap partner,
  unconnected since FW-12). Moved from "awaiting a decision" to "agreed, awaiting schematic
  edit." No firmware change yet — waiting on the schematic.
- **HW-09**: before leaving it open, read the actual current connector pinout directly off
  `Control_Card 1.pdf`'s `/Connector/` sheet (PyMuPDF renders at high zoom, not `pdftotext` —
  the same lesson CL-22 already learned about dense multi-column schematic tables) to answer
  "do you know the exact pin-to-pin connections" precisely rather than from memory. Found: only
  four 50-pin connectors exist (J1–J4), not the five (J1 + J2–J5) the original HW-09 text
  assumed — J5 on that sheet is the power barrel jack. J1 carries the Matrix Card's own signals
  (`LO_S1-4`/`HI_S1-4`/`IN`/`SPI1_*`) plus an `ISO_HV_Card_1.0-3` nibble that's wired but
  functionally unused by the Matrix Card, and 11 genuinely NC pins. Cross-checked against
  `Matrix_Card-8.pdf`'s `J101` and found the two connectors do **not** share pin numbers for
  the same signals — consistent with BU-06's already-established pattern that this project's
  harness is a custom-wired loom (signal-name to signal-name), not a straight ribbon cable.
  User's plan (a 5th HV connector fed by J1's spare pins via a new harness branch) is
  documented in the row; the exact mechanism is still being worked out, left open as asked.
- **GUI-04**: closed as decided — RAM-only, matches current behaviour, no code change (CL-35).
- **BU-10**: closed as decided — not required. Updated `Doc/4wire_resistance_validation.md`
  §7.3 to record the 500 µΩ/µV accuracy floor as an accepted limitation rather than a gap
  something is expected to close (CL-36).
- **GUI-06**: re-checked all seven proposed commands (`Doc/GUI_protocol_proposed_commands.md`,
  written 2026-08-08) against the firmware as it stands after FW-02/FW-12, since two entries
  were explicitly gated on hardware that has since changed. `CAL RUN` was blocked on the
  ADS124S08 being electrically unreachable — FW-02 fixed exactly that, so it unblocked; added
  a "revisited" section on what it should actually do now that `kelvin.c` already does
  per-point offset subtraction (CL-23), recommending its scope wait for HW-04 rather than
  building a current-source-only version now. Auto-range PGA turned out to be **already done**
  — `kelvin_ranged_read()` auto-ranges automatically, exactly as the original doc recommended
  contingent on FW-02 landing — so that recommendation flipped from "wait" to "remove the
  button, nothing to build." The other four entries (`MANUAL READ`, `BUS SCAN`,
  `MANUAL SWEEP`, `MANUAL RELAYTEST`, Compliance sweep) were unaffected and re-confirmed as-is.
  Reported findings back; did not implement any of the seven — the user's message asked for the
  check, not a go-ahead to build.
- **GUI-05, decided (stored on the GUI host) and built the same session:** new
  `gui_flutter/lib/app/run_history.dart` (`RunHistoryEntry` + `RunHistoryStore`, append-only
  JSON Lines, flushed immediately - same reliability reasoning as `SessionLogger`). Judgment
  call, not explicitly specified by the user: the mock Results table was shaped per-*build*
  (one row = a serial-numbered harness with parallel Continuity/Resistance/HV columns), but the
  protocol has no build/serial-number/multi-stage-grouping concept at all — inventing one would
  have been new UX design, not "where does history live." Went with one row per completed run
  instead, which is what the protocol actually gives (`!DONE <kind> <passed> <failed>`), and
  said so explicitly in the table's own doc comment rather than silently reshaping the mockup.
  `defaultHistoryDir()` added to `paths.dart`, factored out of `defaultLogDir()`'s existing
  search logic instead of duplicated. `AppState._onDone` records every completed run except a
  fault-refused one (FW-10's `!DONE 0 0` is a refusal, not a result). `Export CSV` wired to a
  real native save dialog + real file write; `Print report` left honestly disabled rather than
  a no-op, since real printing needs a package this project doesn't depend on yet — a
  genuinely different scope than the storage-location question GUI-05 asked. Left the
  sparkline and fault-pareto table on the same view as mock data on purpose - GUI-05's ticket
  named Export CSV/Print report specifically. 12 new tests added
  (`run_history_test.dart`, `run_history_app_state_test.dart`); full suite 193/194 (the one
  failure is CL-20's pre-existing unrelated gap); `flutter analyze` clean (CL-37).
- PROJECT_LOG updated throughout: HW-04 moved, GUI-04/GUI-05/BU-10 closed (CL-35/37/36),
  GUI-06 updated in place with the feasibility findings, status snapshot and counts refreshed.

### 2026-08-12 (later still — FW-12 + DOC-04: Kelvin excitation moved to the ADS124S08 IDAC)
- Picked up the handoff from `Doc/idac_current_source.md` (written the previous session
  specifically for this task) and PROJECT_LOG's FW-12/DOC-04 entries. Read both before
  touching anything, as instructed - no history re-derived.
- **`ADS124S08_SetIdac()` added** (`ads124s08.{h,c}`), following `ADS124S08_SetGain`'s
  pattern: two register writes, `IDACMUX` then `IDACMAG`. Confirmed the register layout
  against `Datasheet/ads124s08.pdf` Tables 32/33 directly rather than trusting the doc's
  summary alone - `IDACMAG` has one shared 4-bit magnitude field for both IDACs (not
  independent per-IDAC magnitudes, which the task's phrasing could have been read either
  way), `IDACMUX` has independent 4-bit output-pin fields per IDAC, reset 0xFF (both
  disconnected). Added `ADS124S08_MUX_AIN9`, `ADS124S08_IDAC_OFF` and the `ADS124S08_IMAG_*`
  codes (`0001`=10 µA ... `1001`=2000 µA, confirmed as the ceiling - no code above it).
- **`kelvin.c` switched to the IDAC.** Route IDAC1 → AIN9 at `KELVIN_IDAC_MAG`
  (`ADS124S08_IMAG_2000UA`) instead of `Frontend_SetCurrentCode`; the zero-current baseline
  step now sets both IDACs off (mux disconnected *and* magnitude zero, belt-and-braces)
  instead of a DAC code of 0. `KELVIN_FORCE_CODE` (DAC-code based) removed from `kelvin.h`;
  `KELVIN_FORCE_CURRENT_A` changes from a 10 mA TUNE/VERIFY placeholder to a fixed 2 mA -
  the actual, only current the hardware can produce, not a value to tune later.
- **Judgment call on `control_frontend.c`, worth recording:** the task doc explicitly left
  "does FRONTEND_MODE_IMPEDANCE still mean anything" as an open decision. Traced it rather
  than guessing either way - `Frontend_SetMode` never touched the DAC8775 at all (it's a
  pure OPT0_CNTR GPIO toggle selecting the TS5A3159 SPDT throw), and the continuity throw's
  10 kΩ pull-up on `ADC_IN` would load `HI_COM` in parallel with the IDAC's 2 mA if left
  connected during a Kelvin measurement. So the mode switch stays and `kelvin.c` still calls
  it - it just isolates the pull-up now instead of "selecting the current source." Only
  `Frontend_SetCurrentCode`, the `idac` field and the `idac_spi`/`idac_cs_*` config fields
  came out.
- **`board.c`**: `BOARD_IDAC_SPI`/`BOARD_IDAC_CS_PORT`/`_PIN` removed, `board_init_frontend()`
  no longer builds an IDAC config. `hspi2` itself is untouched - HV DAC8830/AD7476 still need
  it, only the DAC8775-specific CS wiring on that bus went away.
- **`dac8775.{h,c}` deleted outright**, not left as an orphan (the task's explicit call, and
  the register map was still marked VERIFY - nothing worth preserving). Remembered the CL-23
  lesson that `Debug/Core/Src/drivers/subdir.mk` and `Debug/objects.list` don't update
  themselves when a source file is removed - cleaned both, plus the stale `dac8775.o/.d
  /.cyclo/.su` build artifacts, before attempting a build.
- **DOC-04**: re-derived `Doc/4wire_resistance_validation.md` §7.1 for 2 mA as a *fixed*
  point rather than a target, per the flag the previous session left in place - did not
  overwrite the CL-29 3 mA table, added a new block above it instead. Also corrected the
  compliance-ceiling number while in there: earlier passes (this one included, until
  re-reading `idac_current_source.md` §3 closely) used an inferred "~3.0 V, rail minus some
  headroom" figure; the IDAC has a real datasheet number, `AVDD − 0.6 V` = 2.7 V. Recomputed
  the whole table against the corrected ceiling rather than patching just the target row.
- **BU-10 (thermal-EMF current reversal), the "worth a decision" question the task flagged:**
  traced whether reversal is still possible with source-only IDACs. It is not, without a
  schematic change - the excitation loop's return path (R131, 100 Ω to ground) is only on
  the `LO_COM` side; there is no symmetric pull-down on `HI_COM` for a second, low-side IDAC
  to push current back through, and IDACs have no documented direction/sink mode to begin
  with. Moved BU-10 from "Verify at bring-up" to "Awaiting a decision" rather than leaving it
  filed as something a future firmware session can just pick up - it can't, until the
  schematic changes. Documented in `Doc/4wire_resistance_validation.md` §7.3 and here.
- **Build verified with a full clean rebuild**, not just an incremental one: found the
  bundled toolchain under `C:\ST\STM32CubeIDE_1.19.0\STM32CubeIDE\plugins\...gnu-tools-for-
  stm32.14.3.rel1...\tools\bin` and `...externaltools.make...\tools\bin` (matches the
  "14.3.rel1" the generated makefiles already expected), ran `make clean && make all`: 0
  errors, 0 warnings, 65024 B text / 104 B data / 24464 B bss.
- **Found, not fixed - out of this task's file scope:** `gui_flutter`'s Diagnostics bus-map
  panel still labels SPI2 "DAC8775 · DAC8830 · HV AD7476 ×2" (`misc_views.dart`). One static
  string; `Doc/idac_current_source.md` §5's file-by-file scope was firmware-only, so left for
  a GUI-side pass rather than expanding this session's scope.
- PROJECT_LOG updated: FW-12 and DOC-04 closed (CL-33, CL-34), BU-10 moved and rewritten,
  status snapshot counts and the DAC8775 headline paragraph refreshed.

### 2026-08-12 (later — DAC8775 confirmed removed, ADS124S08 IDAC found, HW-11 closed)
- **User asked to check whether the schematics had been updated, and flagged that the DAC
  had been replaced by "the same ADC" for current** - confirmed both directly against
  `Control_Card 1.pdf`/`Matrix_Card-8.pdf`: DAC8775 is physically gone (its sheet is now
  just unrelated pull-ups), and ADS124S08 pin `AIN9` is now wired straight to `HI_COM`,
  matching the chip's own internal IDAC-to-AINx excitation architecture.
- Verified against `Datasheet/ads124s08.pdf` directly rather than taking the pin-routing
  alone as proof: `IDACMUX`/`IDACMAG` registers exist and do exactly this, IDAC accuracy at
  2 mA is typ ±0.5%/worst ±3%, and the ceiling is a hard 2 mA (`IDACMAG` code `1001`) - no
  code goes higher.
- **HW-11 closed as CL-32** - superseded by hardware, not decided: there's no DAC left to
  choose between DAC8775/DAC8760/LTC2662-16 for, so the whole open question is moot.
- **Two new items opened, not fixed this pass** (docs-only pass, per the user's request -
  firmware implementation is next session's work): **DOC-04** (re-derive
  `4wire_resistance_validation.md` §7.1 against the 2 mA ceiling - CL-29 had *just* closed
  DOC-03 the same day against 3 mA, before this finding, so that derivation is superseded
  again within hours) and **FW-12** (move `kelvin.c`'s excitation from the now-nonexistent
  DAC8775 to the ADS124S08's `IDACMUX`/`IDACMAG`, and strip the DAC8775 half out of
  `control_frontend.c`/`board.c`).
- New doc: `Doc/idac_current_source.md` - the full finding, the datasheet numbers, and a
  file-by-file scope for FW-12, written as the reference for the session that implements it.
  `fw_status.txt` got a banner flagging every DAC8775 section as stale (not rewritten line by
  line - that file was just fully resynced this same day as CL-27 and a second full pass
  would fight with FW-12's actual implementation). `README.md`'s hardware baseline table and
  document map updated to match.
- Also verified, since a toolchain was available this session and wasn't for CL-26: the
  pending FW-06 (`proto.c`) change builds clean, 0 errors/0 warnings - no longer just
  "verified beyond code review only."
- Left alone, on purpose: the `Control_Card 1.pdf`/`Matrix_Card-8.pdf` naming/commit churn
  CL-27 already flagged. Still uncommitted, still worth the user's attention, not this
  session's call to rename.

### 2026-08-12 (six ready-to-implement items closed: FW-06, DOC-01/02/03, HW-08, GUI-07)
- Worked the punch list of items that needed no product/hardware decision, in the order
  given: FW-06, DOC-01, DOC-02, DOC-03, HW-08, GUI-07. HW-04, HW-09, HW-11, GUI-04/05/06/08
  were left untouched as instructed.
- **CL-26 (FW-06):** `>STATUS` now reports `running`/`fault`, not just `idle`/`hv_armed` —
  reused the existing `proto_state_name()` heartbeat helper (added a fault check to it)
  instead of duplicating the priority logic. `Doc/GUI_development_brief.md` updated in the
  four places that documented the old contract, so the brief and the firmware agree again.
- **CL-27 (DOC-01):** `fw_status.txt` resynced to the FW-02/CL-23 architecture (4-wire
  Kelvin via the ADS124S08, not the old 2-wire Matrix-U33 path) and the schematic filenames
  it names. Found in passing: the working tree has an **uncommitted rename churn** in
  `Doc/` — `Control_Card-5.pdf`/`Matrix_Card-7.pdf` deleted, replaced by untracked
  `Control_Card 1.pdf`/`Matrix_Card-8.pdf`. Checked the embedded title-block dates on both:
  identical to the files they replaced (2026-08-06 / 2026-07-11), so this reads as a
  design-sync re-export rather than a real new revision — but it is not committed or
  reconciled, and worth the user's attention since the next sync could rename them again.
  Documentation in this session was written against the git-tracked `-5`/`-7` names.
- **CL-28 (DOC-02):** turned out to already be fixed — `HT_ENABLE_ADS1232`'s default
  flipped 1→0 in the 2026-08-07 heartbeat commit (`c579830`), whose own message says so
  ("Carries HT_ENABLE_ADS1232 off with it"). Closed retroactively, same pattern as CL-19.
- **CL-29 (DOC-03):** re-derived `Doc/4wire_resistance_validation.md` §7.1 against the real
  BU-09 CD74HC4051 figures instead of the ~100 Ω placeholder the original table used. This
  produced a real finding, not just a number update: worst-case compliance now fails around
  ~4 mA (not ~10 mA), which is *why* 3 mA is the right target, not an arbitrary revision.
- **CL-30 (HW-08):** confirmed directly from `HV_Card-3.pdf`'s extracted text — `R3003
  5KOhms` — against the schematic's own stated divider formula. No firmware change needed.
- **CL-31 (GUI-07):** added `AppState.setLimits()` and a "Test limits" panel (two sliders +
  Apply) to the Diagnostics screen in `gui_flutter/`, seeded from `LIMITS GET` on connect.
  `flutter analyze` clean, `flutter test` 181/182 (the one failure is the pre-existing
  unrelated gap from CL-20). Found in passing, logged as **FW-11**, not fixed: the
  `ins_min_mohm` limit this wires up has no effect on the actual insulation verdict in
  firmware today, and the firmware's own default for it is off by 1000× from what its own
  comment claims — a safety-relevant behaviour change that needs a decision, not a
  mechanical fix, so left open rather than changed silently.
- No arm-none-eabi-gcc toolchain was available in this session's shell to do a full firmware
  build; the FW-06 change reuses an existing, previously-verified helper (`proto_state_name`)
  so risk is low, but it is unverified beyond code review — worth a build/flash check next
  session. The GUI side was verified for real (`flutter analyze` + `flutter test`).

### 2026-08-11 (later still still — Matrix Card confirmed on the shared bus, CL-25)
- **User confirmed directly**: "We are using same I2C bus which we are using for the HV1 card" -
  settling what CL-24 had left open (whether the Matrix Card's own onboard expanders share the
  HV cards' I2C2, or sit on the separately-confirmed I2C3 that U20 uses).
- Working through the consequence: U21/U20 (local, generates `LO_S1-4`/`HI_S1-4`) is genuinely
  I2C3-only and needed no change, but the Matrix Card's *other* eight expanders (`hi_en`/`lo_en`/
  `hi_sns`/`lo_sns`, i.e. U101/102/105/106/66/67/107/108) had been going through the same single
  `hi2c` parameter as U21 in `MatrixCard_Init` - wrong once the two are confirmed to be on
  different buses. Also realised the existing BUFF1/BUFF2 NTS0102 segment-switch inside the
  Matrix Card (already implemented, addresses reused a second time within the card itself) is a
  second, inner layer of the same problem CL-24 solved at the card-to-card level - the Matrix
  Card needs its own outer `HV_Card_EN1` gate (J1) exactly like each HV card needs its EN2/3/4,
  wrapping around the existing inner segment switch, not replacing it.
- **CL-25**: `MatrixCard_Init` now takes `hi2c_local` (U21, I2C3) and `hi2c_shared` (the eight
  expanders, I2C2) separately, plus `en_port`/`en_pin` (`HV_Card_EN1`). New public
  `MatrixCard_BusClaim()`/`BusRelease()`, used internally by every function touching the shared
  expanders and externally by `board.c`'s U69 (ADS124S08 control) callbacks, since U69 sits on
  the same shared bus. `board_init_ads124s08()` moved from `BOARD_MATRIX_I2C` to `BOARD_HV_I2C`
  to match. Full rebuild after every step: 0 errors, 0 warnings.
- Net effect: the address-collision problem CL-24 fixed for HV-vs-HV is now also fixed for
  Matrix-vs-HV and Matrix-vs-itself-on-two-segments. Nothing left open on this thread.

### 2026-08-11 (later still — shared I2C bus / HV_Card_EN gating, CL-24)
- **User traced the Control Card schematic further and corrected two things from earlier this
  session's read**: the Matrix-vs-4-wire architecture is 2-wire (already logged, unchanged), and
  separately, that J1's `LO_S3`/`HI_S3` naming maps to NTS0102 buffer enables on the Matrix Card
  as `matrix_card.h` already documented, but the *Matrix Card and every HV card also share one
  I2C bus* - confirmed directly by the user against real hardware, not inferred by this session.
- Traced the consequence in the schematic (`Control_Card-5.pdf` sheets `/uC/`, `/Isolator/`,
  `/GPIO_Expander/`): U20 (generating `LO_S1-4`/`HI_S1-4`) is on I2C3; the isolated I2C2 bus
  (`ISO_SDA2`/`ISO_SCL2`) is wired to every HV connector J1-J4 identically; `HV_Card_EN1..4`
  (PC5/PC6/PA10/PA9) exist as per-slot bus-segment enables through isolators U18/U19. Checked the
  actual pin config: CubeMX had those four pins under a stale label (`HV_CARD_DT_3_0` etc., from
  before the schematic was renamed) and configured as unused inputs - confirming firmware had
  zero handling for this collision.
- **CL-24**: implemented the fix - `hv_card.c` now gates every I2C-touching call behind
  `hv_bus_claim`/`hv_bus_release`; CubeMX pins relabelled and switched to outputs; `board.c` maps
  HV board index to physical slot (J2-J4, reserving J1 for the Matrix Card per HW-09) with a
  compile-time bound. Full account and diagram in `Doc/i2c_bus_sharing.md`.
- **Left deliberately open, as BU-13**: whether the Matrix Card's own onboard expanders share this
  same I2C2 bus, or sit on the separately-confirmed I2C3 that U20 uses, isn't resolvable from the
  schematic alone (no `I2C3_SDA`/`SCL` label found anywhere on J1's 50 pins) - `BOARD_MATRIX_I2C`
  left unchanged rather than guessed, since a wrong guess would move the collision, not remove it.
- Full `make all` rebuild after every step this session: 0 errors, 0 warnings throughout.

### 2026-08-11 (new session — HW-12 address check; FW-02 implemented; build fixed)
- **Did the 10-minute HW-12 cross-check the last session's handoff flagged**, before starting
  FW-02: rendered `Matrix_Card-7.pdf` sheet 9 and sheet 3 to images (PyMuPDF, since the sense
  side's binary address labels don't survive `pdftotext` extraction at all — confirmed by
  grepping the extracted text for `0x2` and getting nothing) and read the address off each
  expander directly. Found the straps in `matrix_card.h` were wrong for the sense side (not just
  unconfirmed) — see **CL-22**. Force side matched exactly, no change needed.
- **FW-02 implemented**: `test/kelvin.c` rewritten for 4-wire Kelvin against the ADS124S08 — PGA
  auto-ranging, zero-current-baseline offset subtraction, ratiometric-vs-current-source formula
  chosen correctly (HW-04 isn't done, so `OhmsFromCurrent`, not `OhmsRatiometric`). See **CL-23**
  for the full account, including why current reversal (BU-10) was deliberately left out rather
  than implemented against an unverified DAC8775 register map.
- **`bsp/board.c` gained the ADS124S08 wiring it never had**: a global instance, the U69 io
  vtable (cs/reset/start/drdy, each paying the BUFF2 segment-select the driver's own header says
  it needs), and a `board_init_ads124s08()` hooked into `Board_Init()`. FW-01 had written the
  driver; nothing had ever instantiated it.
- **Found and fixed two things that would have made every reading wrong even with correct
  code**: SPI1 was still CubeMX's 4-bit/mode-0 default (leftover from the removed AD7476) against
  the ADS124S08's required 8-bit/mode 1, and clocked at 32 MHz against its 10 MHz max. Fixed in
  `spi.c` and `HT_MK1.ioc` together so it survives a CubeMX regeneration.
- **Found the command-line build was broken independent of any of this**: `proto.c` (FW-05,
  closed 2026-08-01) and `ads124s08.c` (FW-01) were missing from `Debug/Core/Src/{app,drivers}
  /subdir.mk` and `Debug/objects.list` — the Eclipse IDE's own project index knew about them
  (their `.o`/`.d` files already existed in `Debug/`) but the generated make fragments used for a
  plain `make all` did not. Added both. Full `make all` now builds and links clean: 64872 B
  text, 104 B data, 24456 B bss, 0 warnings.
- Net effect: **`RES RUN` no longer fails every net by design** — it measures. Still unverified
  on real hardware; BU-01 (excitation current / system offset) and BU-08 (formula) are the
  remaining gates before trusting a specific number.

### 2026-08-11 (later still — U68 false-negative corrected; README synced; handoff finalized)
- **Corrected my own error from earlier today.** The claim that U68 (ADS124S08) was missing from
  `Matrix_Card-7.pdf` was wrong — caused by a verification script that truncated each page's
  extracted text at 2500 characters before searching it; page 8 (where U68 lives) has 7,596.
  Re-verified against the untruncated text: U68 = `ADS124S08IRHBR`, full 33-pin list present,
  U69 alongside it on the same sheet. The "page 9" the user cited and "page 8" I found both
  point at the same sheet — its title block reads `Id: 9/8` (KiCad hierarchical sheet 9, 8th
  and last page of this PDF). **FW-02 is not blocked.** HW-12 rewritten to reflect this; the one
  thing still genuinely open from that finding is confirming the new I2C address strapping
  (0x20/21/22/24/26 across U66/U67/U69/U107/U108) actually resolves the old U101-vs-U69
  collision — not yet cross-checked against the force-side sheet.
- **`README.md`'s hardware baseline table updated** to the new file names
  (`Control_Card-5.pdf`/`Matrix_Card-7.pdf`/`HV_Card-3.pdf`), with pointers to HW-11/HW-12/HW-08
  so a reader lands on the open questions, not just the filenames.
- Handoff prompt for the next session finalized — see below.

### 2026-08-11 (later — DAC8760 datasheet confirmed incompatible; schematic swap found; HW-12 raised; handoff prepped)
- **User added `Datasheet/dac8760.pdf` and asked to check it.** Confirmed directly (not via search this time): `AVDD` recommended operating range is a hard **10–36 V minimum**, independent of current-range selection — `DVDD` alone being 2.7–5.5 V doesn't help, since that's only the digital side. This rules DAC8760 out for a 3.3 V-only board exactly as suspected; LTC2662-16 (HW-11) stands as the lead candidate.
- **Found the `Doc/` schematic set had been swapped locally and left uncommitted**: `Matrix_Card-7.pdf`/`Control_Card-5.pdf`/`HV_Card-3.pdf` replaced the files everything above is tracked against. Checked all three for what moved — **HW-08 (R3003 5 kΩ) looks fixed**, **HW-09 may be improved** (6 connectors now vs. 4), but **the ADS124S08 is absent from the new Matrix Card export entirely** (8 pages, no sheet 9, no U68/U69/ADS124/AIN/DRDY text anywhere). Raised as **HW-12** — this blocks starting FW-02 until resolved. Asked the user to confirm; they said it's present on "page 9" of what they're viewing, which does not match the file actually in `Doc/` (verified by page count, full-text search, and file hash) — flagged as unresolved, not assumed either way in either direction.
- **User asked to pause the DAC decision (HW-11 stays open) and prepare a handoff prompt for the next chat**, covering remaining FW/GUI work. Categorized: ready now (FW-06, GUI-07, DOC-01/02/03), blocked on a product decision (GUI-04/05/06/08), blocked on HW-12 (FW-02), out of scope for a coding session (BU-* hardware bring-up items).

### 2026-08-11 (DAC accuracy re-verified against source datasheets; DAC8775 alternatives; HW-11/DOC-03 raised)
- **Re-derived resistance-accuracy calculation checked line-by-line against `Datasheet/ads124s08.pdf` and
  `Datasheet/dac8775.pdf`.** CM-floor formula and FSR-at-gain-128 confirmed correct. Two real errors found —
  see CL-21: two mis-picked noise-table rows (more margin, not less) and a DAC8775 TUE row that doesn't apply
  at this design's actual 1–3 mA operating point (the applicable spec is ±0.14 %FSR, not the ±0.4 % "4 to
  20 mA"-specific row). Conclusion unchanged — calibration is mandatory regardless, because the noise floor
  binds before the DAC error does. `Doc/4wire_resistance_validation.md` §7.6 rewritten with sourced numbers.
- **DOC-03 raised**: the same doc's §7.1 still targets ~5 mA excitation, superseded by BU-09's 3 mA revision
  (closed 2026-08-01) that was never propagated into this section. Flagged in place, not re-derived this pass.
- **HW-11 raised**: DAC8775 is hard to source (mixed lifecycle signals across distributors). Researched
  alternatives — TI DAC8760 (same family, single-channel, easiest port, slightly worse TUE) and ADI AD5758
  (single-channel, better TUE per one search-sourced figure, different register map, full new driver). Only
  channel A of the DAC8775's four is used today, and the real current (1–3 mA) is well under any candidate's
  native range, so a single-channel part is not a functional downgrade — this is an availability/port-effort
  decision, not an accuracy hunt, since every candidate needs calibration anyway.
- **Later same day: reframed after confirming this board only has 3.3 V available.** DAC8775/DAC8760/AD5758
  are all industrial 4-20 mA loop drivers that need wide supplies (10 V+) as a matter of their fundamental
  purpose — not just DAC8775-specific, the whole product category is the wrong fit. Found **LTC2662-16**
  (ADI) instead: purpose-built low-range current-source DAC, 2.85–5.5 V single supply, ranges down to
  3.125 mA full scale, 16-bit, SPI. Confirmed in stock at DigiKey (214 units, $49.18 @ qty 1, MOQ 1) — this
  is now the lead candidate over DAC8760, which would need an added boost regulator this board doesn't have.
  HW-11 rewritten with this finding.

### 2026-08-10 (later — required_format report examples; netlist header fix; GUI-08 found)
- **`gui_flutter/required_format/`** (new, user-provided) sets the report format by example:
  the old GUI's continuity CSV/PDF, plus a real required netlist (`example_netlist27072026
  .xlsx`). Added the resistance and HV-insulation counterparts in the same convention
  (metadata block + Summary + Results table, same navy/green/red styling) — column names and
  status enums traced to `codec.dart`/`messages.dart`, not invented; see the new
  `required_format/README.md` for the field-by-field mapping. Neither report writer exists in
  code yet; these are the target shape for when GUI-05 (run history storage) is answered.
- **CL-20**: the required netlist's actual headers (`Src Pin #`/`Dst Pin #`) didn't match any
  alias `netlist_file.dart` recognised, so the file the user just declared required could not
  be loaded at all. Fixed, with a regression test.
- **GUI-08 found while verifying the fix**: the required-format example numbers pins
  per-connector (`Conn ID` + `Src Pin #`), so a straight-through harness has the same pin
  number on both sides of every row — but the parser, `NETLIST ADD`, and the matrix routing
  all use one flat `1..256` address with no connector concept. Every row in the actual example
  file collides and is correctly rejected. This is deeper than the header-naming issue: it
  needs either pre-globalised pin numbers in the sheet, or a `Conn ID` → base-offset map built
  into the firmware/GUI. Not fixed — pinned by a test and logged, per the standing rule that a
  real finding gets an ID, not just a comment.
- Full `flutter test` re-run: 181/182 pass. The one failure is pre-existing, unrelated WIP
  (`netlist_file_generated_test.dart` from `ee1e0f7`, expects an uncommitted `test_netlists/`
  directory) — flagged to the user, not silently fixed or deleted.

### 2026-08-10 (tracker sync — five days of untracked work folded in)
- Reviewed git history and code against this log for the first time since 2026-08-05 and found
  three real deliverables that had never been logged: the firmware heartbeat, the Flutter GUI
  port, and the netlist-file-browsing / protocol-coverage-audit session. All three folded in
  below and in Open/Closed items.
- **Flutter confirmed as the primary GUI build** (user decision, 2026-08-10). `gui/` (Python) is
  superseded — kept on disk for reference, not tracked for new work. GUI-03 is the one item that
  stays open against it, now marked legacy.
- **FW-04 closed retroactively as CL-19.** The mux-addressing rework it called for was already
  done in `f778ba7` (2026-08-01) as a side effect of FW-03, but nobody closed the ticket. Found
  by rereading `matrix_card.c` for this review, not by new work. The 400 kHz-vs-100 kHz half of
  the original item is still open, moved under BU-03.
- Two new Doc/ files (`GUI_protocol_command_coverage.md`, `GUI_protocol_proposed_commands.md`,
  both 2026-08-08) folded into the document map as reference material — README updated so they
  don't become an unlisted fifth/sixth tracking doc. New items GUI-04 through GUI-07 raised from
  their findings.
- Net effect: no code changed this session. **Biggest unresolved risk is unchanged** — FW-02
  (4-wire resistance) has not been started, so `RES RUN` still fails on every net. BU-12 (abort
  on real hardware) has no evidence of being exercised since the 2026-08-05 fix.

### 2026-08-08 (netlist file browsing; GUI protocol coverage audit)
- **Real Excel netlist browsing** (`gui_flutter/lib/htproto/netlist_file.dart` +
  `netlist_picker_io.dart`). Both netbars (MTX, HV) now open a real `.xlsx` file instead of a
  stub. MTX uploads the parsed pairs via `NETLIST BEGIN/ADD/END`, the same path a saved
  cross-continuity scan uses. A malformed file fails loudly (`NetlistFileFormatException`)
  instead of a silent no-op.
- **Folded in prior uncommitted GUI work**: `FAULT CLEAR` wiring, `MANUAL PATH`/`MANUAL OFF`
  diagnostics, a live wire-traffic Console tab in the log bar, and a serial port selector.
- **Full audit of every tappable control in `gui_flutter/lib/` against the protocol** —
  `Doc/GUI_protocol_command_coverage.md`. Found and fixed the real wiring gaps (group 1) and
  removed the controls that shouldn't exist (group 2 — `MANUAL RELAY`; the firmware refuses it
  by design, brief §0 says don't offer it). Two groups remain open: decide-then-build GUI-only
  features (Export CSV, Print report, Cal certificate — blocked on brief §8 Q2/Q4, now GUI-04/
  GUI-05) and firmware-side proposals (`Doc/GUI_protocol_proposed_commands.md`, now GUI-06).
- **One correctness bug found while wiring `FAULT CLEAR`**: `_onDone` computed `pass =
  m.failed == 0` unconditionally, so a run refused by a latched fault (`!STATE fault` then
  `!DONE <kind> 0 0`, per FW-10) read as a pass. Fixed — `_onDone` now checks `inFault` first
  and leaves the result unset.
- Test suite grew accordingly (`manual_and_fault_test.dart`, `netlist_file_test.dart`,
  `netlist_file_load_test.dart`, `netlist_select_flow_test.dart`, `netlist_upload_test.dart`,
  `port_selector_test.dart`, `wire_log_test.dart`, `diag_controls_flow_test.dart`).

### 2026-08-07 (firmware heartbeat; Flutter GUI port)
- **Heartbeat fixes a false "link lost."** Brief §3.5.3's 5 s no-traffic rule was firing on a
  perfectly healthy link about five seconds after connecting, because the instrument said
  nothing at all when idle. `Proto_EvtHeartbeat()` re-announces `!STATE` every
  `PROTO_HEARTBEAT_MS` (2000 ms — two beats inside the 5 s window), and `CommsTask` swapped
  `osWaitForever` for a timed wait clocked off `osKernelGetTickCount()` so a steady trickle of
  RX bytes can't starve it. Deliberately not shared with `>STATUS`'s reply logic
  (`proto_state_name()` is separate) — a heartbeat claiming `idle` mid-run would clear the
  GUI's arm. Verified on a NUCLEO-G474RE: 90 s connected, no link loss, 65 beats at 1.997 s.
- **`gui_flutter/` — a full Flutter/Dart rebuild of `gui/`, no Python at runtime.** `htproto`
  ported file-for-file (codec, messages, connection manager, simulator); the design brief's CSS
  tokens and every component class rebuilt as Flutter widgets with the page's own SVG icons
  parsed at runtime; the three canvases as `CustomPainter`s. The safety rules live only in
  `app_state.dart`, tested without a display: safe-to-handle comes from `!SAFE` and nothing
  else, link loss forces unknown, any fixture change drops the arm.
  Serial is the one third-party dependency (`flutter_libserialport`), confined to one file
  nothing else imports. `test/layout_test.dart` renders every view at four window sizes in both
  themes plus thirteen specific states — found 27 `RenderFlex` overflows on its first run that
  neither `flutter analyze` nor the headless tests could see.
  Verified: `flutter analyze` clean, 130 tests, runs against both the simulator and a real
  NUCLEO-G474RE over the ST-LINK VCP.

### 2026-08-05 (GUI-01 and GUI-02 fixed)
- **GUI-01 fixed.** `_execute` now releases `_io_lock` before calling `_link_lost`; the
  send-failure path surfaces `LinkLostError` and drops to `LINK_LOST` instead of hanging.
  Regression test `TestSendFailure` runs the call in a thread so a regression fails the test
  rather than deadlocking the suite. Re-verified with the original repro: prompt
  `LinkLostError`, link `link_lost`.
- **GUI-02 fixed.** Signed parsing for the five int32 wire fields (`!RES` milliohms,
  `!INSUL` leak_mohm, `hv_mv` in `<STATUS` and `!HV`, `<LIMITS` values); pins, counts and
  progress stay unsigned. One existing malformed-case test had `hv_mv=-5` listed as invalid —
  it was asserting the bug, now corrected. Regression test `test_signed_measurement_values`.
- Suite: **59 tests, all passing** (was 57), run repeatedly with no flakiness. The two defects
  survived their own verification precisely because no test covered them — both are covered
  now.
- **GUI-03 remains open** (acknowledged, not started): the three minor items from §8.4 —
  decode `errors="replace"`, the `_transport` nulling race, empty-line tolerance.
- Brief §8.2 updated to record the fixes.

### 2026-08-05 (packaged as a standalone exe)
- **`build_exe.cmd` produces `dist\HT_MK1_GUI.exe`**, ~8 MB, PyInstaller one-file. The exe needs
  no Python on the target machine; PyInstaller is a build-time dependency only. `--sim` runs the
  simulator in-process for demos and training, and says on the console that nothing shown is a
  measurement.
- **Two real defects surfaced only when running the packaged exe**, both now fixed:
  - `index.html` and `live.js` are data, not imports, so PyInstaller could not find them.
    Added explicitly at build time, and `server.py` resolves them via `sys._MEIPASS` when frozen.
  - **Session logs defaulted to a relative `sessions/`.** Launched from `C:\Windows` the exe
    died with `PermissionError: [WinError 5]` on *connect*, because the log is opened as part of
    connecting — so an unwritable working directory took the whole link down. Now
    `%LOCALAPPDATA%\HT_MK1\sessions` via a new `htproto/paths.py`, with a temp-dir fallback and
    a `--log-dir` override. The Tk frontend had the same bug and got the same fix.
- Also added `.cmd` launchers (`ht-demo`, `ht-sim`, `ht-gui`) after the module-not-found trap:
  `python -m htweb` only resolves from `gui\`, and running it from `gui\tests` fails.
- Verified by running the built exe from `C:\Windows` — page served, connect, fixture, discover
  all fine, session log written to LOCALAPPDATA. Suite 95 tests.

### 2026-08-05 (frontend rebuilt on the approved HTML design)
- **The frontend is now the mock-up itself** (CL-18). `gui/htweb/index.html` is
  `Doc/HT_MK1_GUI_Proposal.html` verbatim — markup, CSS and every render function — served by a
  stdlib HTTP + SSE bridge and driven by real instrument traffic. Tk could never have matched
  that design; using the design as the frontend is the only way to get "exactly the same".
- The one hole cut in the mock's closure is a `window.HT_SEAM` export, so `live.js` can replace
  the three simulated run functions and rebuild the net model from a real netlist. Nothing that
  draws was touched.
- **Recorded honestly in `gui/README.md`: what is live and what is still presentation.** The
  protocol is narrower than the design — it has no fixture/connector map, no net names, no HV
  card-stack detection. Those panels keep the mock's data. Everything else — link state, HV,
  fixture, results, progress, faults, netlist, cal, limits, abort, arm — is real.
- The server binds loopback unless `--allow-remote`; the page can arm and fire 500 V.
- Suite now **91 tests**. `node --check` used on `live.js` and on both inline blocks of the page
  after the seam edit, since a syntax error in the frontend would not show up in the Python suite.

### 2026-08-05 (FW-10 closed, GUI tasks 3–10 built)
- **FW-10 fixed** (CL-16). A run command that cannot execute now says so — `!STATE fault` then
  `!DONE <kind> 0 0` — instead of leaving `s_busy` latched and the GUI waiting forever. Added
  **`>FAULT CLEAR`**, handled before the fault gate because it is the only recovery short of a
  power cycle; it forces safe first, so clearing a latch can never re-energise anything.
  Protocol addition, so the brief, the codec and the simulator were updated with it.
- **GUI tasks 3–10 built** (CL-17) — `gui/htgui/`, Tk, standard library only. Eight screens,
  persistent HV banner, always-reachable abort, guided fixture handover, netlist manager,
  faults with the clear-latch action, history with first-pass yield and a fault pareto, and
  diagnostics.
- **The safety rules live in one Tk-free module** so they are testable without a display, and
  the model is deliberately pessimistic: `!SAFE` is the only thing that produces "safe to
  handle", and link loss forces "unknown".
- One design point worth recording: after a continuity or resistance run the GUI shows
  **unknown**, not "energised". Those runs never emit `!SAFE`, so there is no evidence either
  way — and claiming "energised" would assert something the instrument never said, just as
  claiming "safe" would. Both are wrong; unknown is the honest answer and is still fail-safe.
- Suite now **83 tests**, including a smoke test that drives the real Tk app against the real
  simulator over a socket. Firmware links clean at **65,184 bytes**.

### 2026-08-05 (FW-09 closed, GUI-01/02 verified fixed — release prep)
- **FW-09 fixed** (CL-15). Removed the three run-entry `Proto_ClearAbort()` calls and deleted the
  function, leaving a comment in `proto.h` explaining why it must not come back. The abort flag
  now has one clear before the run is queued and one after `!DONE`, and nothing in between.
- **GUI-01 and GUI-02 verified fixed on the GUI side.** Re-ran both probes: the send-failure case
  now returns `LinkLostError` instead of hanging, and `!RES 12 34 -5 pass` parses to
  `milliohms=-5`. GUI-03 (the three minors) is still open — `parse_line('')` still raises.
- **FW-10 raised** while closing FW-09: `run_command` returns early on a latched fault *before*
  the switch, so a dequeued run never reaches `Proto_EvtDone` — `s_busy` sticks at 1, every later
  run is refused `EBUSY`, and the GUI waits for a `!DONE` that never comes. No protocol command
  clears a fault either, so recovery is a power cycle.
- Links clean at **64,872 bytes**. Release readiness written into the snapshot: the one thing a
  user will notice immediately is that **`RES RUN` fails on every net** until FW-02.

### 2026-08-05 (GUI side acknowledged §8.4)
- The GUI side amended §8.2 of the brief: the codec and connection manager are conformant *to
  the brief as written*, with a pointer to §8.4 for the deadlock and the signed-value rejection,
  **both reproduced independently on their side**. Accurate — no correction needed.
- **Re-verified against their code: neither is fixed yet.** The send-failure repro still hangs
  `execute()` forever, and `!RES 12 34 -5 pass` is still rejected. Their suite still passes at
  57 tests, which is expected — neither defect has a test covering it, which is half of why
  they survived. GUI-01 and GUI-02 stay open, now marked acknowledged.

### 2026-08-05 (tracker audit)
- Checked the tracker against everything this session produced. Three things were being carried
  in prose or in the brief but were not tracked items — now fixed:
  - **FW-09** — the abort-clear race. I raised it verbally in the first exchange of the day,
    offered to log it, and then never did; FW-07 took the number and the point got lost. It is a
    real hole in the abort path and the FW-07 fix made it *more* reachable, so this is exactly
    the kind of thing that must not live only in conversation.
  - **GUI-01 … GUI-03** — the review findings existed only in brief §8.4. Added a `GUI-` prefix
    and an "Awaiting the GUI side" section so the outstanding set is visible from one place.
  - **DOC-02** — `HT_ENABLE_ADS1232` defaults to 1 while README says "default off". Noticed
    during the hand-link and mentioned in passing; now an item.
- Also promoted the boot-banner fix to **CL-14**. It changed protocol-visible behaviour, so it
  should be findable in the closed table, not only in an activity-log bullet.

### 2026-08-05 (GUI tasks 1 and 2 reviewed)
- Reviewed the `gui/` code against §6 of the brief — codec, messages, connection manager and
  tests. Suite runs clean: **57 tests, all passing**. Structure and intent are right; findings
  written up as **§8.4** of the brief. Their code is theirs to fix — not edited here.
- **One blocker.** A send failure deadlocks the connection manager: `_execute` calls
  `_link_lost()` while holding `_io_lock`, and `_link_lost` → `_fail_all_pending` takes the same
  non-reentrant lock. Reproduced — `execute()` never returns, and the lock is never released, so
  every later command hangs too. This is the ordinary "link dropped mid-run" path that §6 says
  gets tested by pulling the plug. Their failure tests only cover receive-side failures.
- **One conformance bug.** `!RES <milliohms>`, `!INSUL <leak_mohm>`, `hv_mv=` and the `LIMITS`
  values are printed `%ld` from `int32_t`, but the codec parses them as unsigned — a negative
  reading is rejected as a protocol violation. Masked today because `RES RUN` always reports
  `0`/`fail_high`; it will bite the moment FW-02 lands, since a near-zero 4-wire resistance goes
  negative once offset is subtracted (BU-10). Told them before it costs a debugging session.
- **A firmware bug fell out of the review.** The boot banner was not protocol-framed — `[boot]`
  lines carried no `#`, and the banner led with a bare `\r\n` that framed as an empty line, both
  parse errors at the GUI end per §3.1. Fixed: all five `console_puts` lines are now `#`-prefixed
  with no leading newline. The GUI was right to reject them.

### 2026-08-05 (FW-07 and FW-08 fixed)
- **`>ABORT` works.** The abort flag the run loops poll could never be set, because `tComms` sat
  below `tSequencer` and the sequencer never yielded — its settle delays were the stock
  busy-spin `HAL_Delay`. Fixed on three fronts: interrupt-driven console RX, `tComms` raised
  above the sequencer, and `Board_SettleMs()` yielding instead of spinning. CL-12.
- **A fourth fix fell out of the third.** Raising the comms priority meant it could preempt the
  sequencer mid-line, and `HAL_UART_Transmit` is not reentrant — three threads write that UART,
  so a preempted line would have been silently dropped. A dropped `<` reply is a 2 s GUI
  timeout and a "link lost". All console output now goes through `Log_ConsoleWrite()` under a
  mutex, and each protocol line leaves as a single write with its CRLF built in. **This one was
  a regression I introduced and caught in review, not a pre-existing bug** — worth remembering
  that raising a task's priority is a change to every shared resource it touches.
- **FW-08 fixed** — the fixture path posts the force-safe and lets the *sequencer* emit
  `!HV 0` → `!SAFE` → `!FIXTURE` once the rail is down, in the published order. CL-13.
- **New hazard closed while in there:** fixing FW-07 made "operator declares a fixture change
  during a live run" reachable for the first time. It now aborts the run rather than letting an
  insulation run continue at 500 V for up to 64 s.
- Also: every force-safe now emits `!HV 0` before `!SAFE`, so `>SAFE` no longer drops the rail
  without telling the GUI. Brief updated for all of it — the contract itself did not move.
- Links clean at **64,920 bytes**, up 5,888 from 58,932. The increase is the HAL's IT-receive
  path (`HAL_UART_IRQHandler`, `UART_RxISR_*`, `UART_Start_Receive_IT` ≈ 4.9 kB), which
  `--gc-sections` used to discard when the console was transmit-only. 12.4 % of flash.
- Raised **BU-12** — this was a scheduling bug, and a clean build proves nothing about
  scheduling. Abort must be exercised on real hardware.

### 2026-08-05 (later still — GUI side folded in the answers)
- The GUI side struck both §8.2 questions as answered, folded the §8.3 refinements into
  deviations 2, 3 and 9, and **added two more from reading the corrected §3.2**: `SAFE`,
  `MANUAL PATH`, `MANUAL OFF` and idle `ABORT` reply `<OK started` not `<OK` (13), and `STATUS`
  never reports `running` (14). Both verified against `proto.c` — correct, and 14 is FW-06.
- Running total from the GUI side: **fourteen items raised, thirteen real**, one caused by this
  brief. Three firmware defects found this way — the two fixed in `5d837d8`, plus FW-07.
- Still open and **not started**: FW-07 / FW-08, and the review of the `gui/` code itself
  (task 1 and task 2 are both sitting uncommitted in the working tree).

### 2026-08-05 (later — GUI task-2 review returned)
- The GUI side verified its protocol layer against the brief and added **§8.2**: two questions
  and twelve simulator deviations. Checked all fourteen against `proto.c`/`tasks.c`; answers in
  the new **§8.3**.
- **Their question 1 found FW-07**, which is the serious one. They asked whether the GUI should
  lengthen its 2 s timeout during a run, because §3.2.1 said non-run commands were "queued
  behind the run". That wording was mine and was wrong — replies are never queued. But chasing
  it down showed the comms thread is *starved* for the whole run: `tComms` sits below
  `tSequencer` in priority and the sequencer never yields, because the settle delays are the
  stock busy-spin `HAL_Delay`. **`>ABORT` therefore cannot stop a run at all.** Raised FW-07.
- **FW-08 found alongside it** — `Proto_SetFixture` emits `!SAFE` on *posting* the force-safe,
  not on its execution, so the instrument can claim safety while the rail is still up. Masked
  by FW-07 today; fixing FW-07 unmasks it. Do them together.
- Fixed the §3.2.1 wording that caused the question, and answered their question 2 from source:
  `!HV 0` is emitted even when the rail was already at 0; **no** `!STATE idle` accompanies the
  arm drop; and `!SAFE` arrives twice for one fixture change and is idempotent.
- Of their twelve simulator deviations, **eleven are correct**. Number 9 is backwards — their
  simulator answers mid-run commands immediately, which is right; the brief was wrong. Also
  told them the `HV SET` arm check runs *before* the range check, so an unarmed negative value
  gives `ENOTARMED` and not `ERANGE`, and that the 10 mV `!HV` deadband their ramp livelocked
  on never existed — it was a stale line in §3.4, already corrected earlier today.
- No firmware changed. FW-07 and FW-08 are logged, not started.

### 2026-08-05 (GUI brief reconciled with the firmware)
- **§3 of `Doc/GUI_development_brief.md` now matches `proto.c` / `tasks.c`.** Commit `5d837d8`
  changed protocol *behaviour* and only §8.1 was updated — §3 is the normative section the GUI
  is built from, so an AI reading §3 alone would have built to the old behaviour. Everything
  below was checked against the source, not the doc.
- New **§3.2.1 "When a command is accepted"** carries what were previously only answers in
  §8.1: run commands refused with `ERR EBUSY` and **not queued**; `ABORT` answered immediately
  and never queued; netlist required by `CONT RUN verify` *and* `RES RUN`; `HV SET` non-zero
  refused with `ERR ENOTARMED`; pins 1-based `1..256`; fixture change invalidates arming with
  `!HV 0` → `!SAFE` → `!FIXTURE`.
- Corrected the wrong notation in safety rule 5 — `EVT FIXTURE HV` is not a thing, the event is
  `!FIXTURE hv`.
- **Four reply strings in §3.2 did not match the firmware.** `SAFE`, `MANUAL PATH` and
  `MANUAL OFF` answer `<OK started`, not `<OK`, and `ABORT` answers `<OK` mid-run but
  `<OK started` when idle. The brief demands byte-for-byte conformance, so these mattered.
- **`!SAFE` is not emitted by continuity or resistance runs** — they never raise the rail. §8.1
  implied it was emitted after every abort. Now stated in §3.3, §3.4 and §8.1, together with
  the rule that "safe to handle" keys off `!SAFE` and never off `!DONE` or event ordering.
- Also documented, all verified in source: `NETLIST GET` is the one command with more than one
  `<` reply; `!FIXTURE mtx` can arrive unsolicited (and even alongside an `EBUSY`, because
  `CONT RUN`/`RES RUN` assert the fixture before the busy check); a bare `>` gives
  `ERR ESYNTAX empty` but a truly empty line gets no reply; the 72-character line limit;
  `!STATE fault` and `!RES fail_low` are defined but never emitted; `HV SET` does not yet drive
  the rail, the insulation run does.
- Raised **FW-06** — `>STATUS` never reports `running` or `fault`, so a GUI reconnecting mid-run
  is told `idle`. Documented rather than changed: the reply is protocol-visible and the GUI is
  being built against it.
- Docs only, no firmware change, so no rebuild.

### 2026-08-01 (docs + GUI)
- **Document clear-out.** Thirteen documents down to four living ones, with `README.md` as
  the map and the rule "no new parallel documents without removing one". Deleted as
  superseded: operation doc v1.1 and v1.3, `HT_MK1_Functionality.md` (described
  `Matrix_Card-2`, two revisions stale), `Operation.txt`, `working_principle.md` (described
  the CD4067 scheme that no longer exists), and the original SAD. All recoverable from git.
  `ADS1232_bench_wiring.md` merged into the validation doc as Appendix A.
- **CD74HC4051 datasheet read (SCHS122O).** ΔrON between channels is **10 Ω max**, which
  largely closes BU-09. rON is only characterised from 4.5 V though (typ 70 / max 160 at
  25 °C), and the card runs at 3.3 V — so the **excitation target drops from 5 mA to 3 mA**,
  which holds at worst-case rON on both the compliance and common-mode sides.
- **`Doc/GUI_development_brief.md`** written for the external GUI effort: protocol contract,
  task breakdown, acceptance criteria, and the safety rules the GUI must implement. The
  firmware↔GUI protocol **does not exist yet on either side** — the brief defines it as a
  contract, and implementing the instrument half is now a firmware task (FW-05).

### 2026-08-01 (later)
- **FW-03 done** — `matrix_card` reworked for Matrix_Card 2. The previous version was
  written against rev 6 and would have driven the wrong multiplexer on every call: 16 vs 32
  muxes per bank, 4 vs 3 select bits, `>>4` vs `>>3` pin decode, one vs two I2C segments.
- **FW-01 done** — `drivers/ads124s08`. Takes an io vtable for CS/RESET/START/DRDY because
  all four are on expander U69 rather than GPIO; conversions are timed from the data rate
  rather than polled on DRDY, since each poll would cost an I2C round-trip.
- Confirmed from SBAS660C: **SPI mode 1**, and the internal 2.5 V reference is **off at
  reset** — `REFSEL` selects it but `REFCON` must switch it on, an easy one to miss.
- Closed **HW-02** and **HW-06** (both already fixed in Matrix_Card 2) and **BU-02**
  (dissolved — rev 2 removed the AD7476, so SPI1 has one device).
- `kelvin.c` now fails loudly instead of reading a chip that no longer exists on the card;
  the FW-02 requirements are recorded in place.

### 2026-08-01
- Built and validated a 4-wire Kelvin bench rig on a NUCLEO-G474RE with an **ADS1232** as a
  stand-in for the ADS124S08. **Measured a 0.033 Ω resistor to 0.4 %** (predicted code
  7,539, measured 7,553–7,705). Full write-up in `Doc/4wire_resistance_validation.md`.
- Proved the ratiometric method end to end: because REFP sits on the same rail that drives
  the divider, the excitation cancels and no current calibration was needed at all. This is
  the concrete argument for HW-04 on the product board.
- Measured noise floor **±0.6 mΩ at 0.53 mA** on flying leads with a marginal joint; scales
  to ±0.06 mΩ with a 470 Ω divider pair.
- Root causes found along the way, all now documented as recognisable signatures: floating
  DOUT (`code = -1`), SCLK not reaching the ADC (`code = 0`), ~50 % silent link corruption,
  **inputs at ground outside the PGA common-mode window** (the expensive one), a misread
  full-scale convention, and a tare that captured the signal itself.
- Raised BU-07 (common-mode headroom shrank when the muxes improved) and BU-08 (the two ADCs
  use different full-scale conventions — do not copy the formula).
- Added `drivers/ads1232` — bench-only, gated on `HT_ENABLE_ADS1232`, 0 bytes when off,
  `#error` if left enabled in a Release build.

### 2026-07-29
- Hardware owner answered the eight open HW items; each checkable claim was verified against the
  schematics.
- **HW-01 withdrawn.** U69 (0x25) drives `ADC_RST_1`, `DRDY_1`, `ADC_CS_1` and `Start_SYNC_1` from
  GPB0–GPB3 on sheet 9. The "unrouted ADC control lines" finding was wrong, and with it the
  connector pin-budget and MCU pin proposal. Closed as CL-05.
- **HW-07 verified** across all 64 multiplexer enables — pull-ups to +3V3, none to GND. Closed as
  CL-07.
- **HW-05 closed** — the `I2C_EN` lines are deliberate spares from an earlier concept.
- HW-02 refined: the expanders to rename are U66 and U67; U69 must be left alone. Sheet-9 refdes
  confirmed as U66 @ 0x23 (HI), U67 @ 0x24 (LO), U69 @ 0x25 (ADC control).
- HW-03 agreed — Matrix card moves to the non-isolated domain.
- HW-08 flagged: the intent (0.245 V, so 10 M : 5 k) is right, but HV_Card-1.pdf in the repo still
  shows R3003 = 50 kOhms. Needs re-export.
- HW-10 raised: no pull resistors on the three U69-driven ADC control lines, which float until
  firmware configures the expander.
- HW-04 clarified — it is an on-card net to U68 AIN2 for measuring excitation current, not a wire
  to the Control card. Still open.
- Net effect: **zero blocking items.**

### 2026-07-28 — `f863c06`
- GUI front-end proposal added (`Doc/HT_MK1_GUI_Proposal.html`).

### 2026-07-27 — `cdb0520`
- Reviewed the revised schematics `Control_Card-4.pdf` (2026-07-12) and `Matrix_Card-6.pdf`
  (2026-07-11) against operation document v1.3. HV_Card-1 unchanged.
- Identified the headline change: **resistance measurement redesigned from 2-wire to 4-wire
  Kelvin.** New 32-multiplexer sense array (sheet 8, U34–U65) tapping all 512 harness pins;
  ADS124S08 24-bit Σ-Δ ADC (U68, sheet 9) reading `HI_SENSE` − `LO_SENSE` differentially;
  R131 changed 100 kΩ → 100 Ω 0.01 %; three more MCP23017 (0x23/0x24/0x25); mux address
  lines moved off MCU GPIO onto Control-card MCP23017 U21.
- Wrote `Doc/Harness_Tester_Operation_Document_v1.4.docx` — new §1.4 (Kelvin architecture),
  §7 rewritten (compliance characterisation, ratiometric options, PGA gain/range table),
  §5.3 sense-array init, faults F11–F14, open-items block at the front. §3 and §4 (HV)
  carried over unchanged.
- Raised HW-01 … HW-09, FW-01 … FW-04, BU-01 … BU-06. Closed CL-01, CL-02, CL-03.
- Created this log file.

### 2026-07-21 — `cff9623`
- Schematics re-issued: `Control_Card-4.pdf` and `Matrix_Card-6.pdf` replace `Control_Card-1.pdf`
  and `Matrix_Card-3.pdf`. `ht_architecture.html` removed.

### 2026-07-20 — `6a5c829`, `f4d028f`
- LO_COM pull-down fixed at 100 Ω; resistance self-calibration plan added to `fw_status.txt`.
- HV_Sense finalised at 0.245 V for 500 V, with R3003 50 kΩ → 5 kΩ deferred to the next
  schematic revision.

### 2026-07-17 — `c9a5d04`, `62488a3`
- Operation document renamed to v1.3; `fw_status.txt` synced with the v1.3 review; hardware
  owner's clarifications folded in.

### 2026-07-16 — `fe38b94`
- v1.3 firmware-engineering review of the Harness Tester operation document.

### 2026-07-14 — `9b45613`
- Firmware reconciled with the `Doc/` schematics: bus and ADC maps corrected, insulation
  measurement reworked to the leakage node, HV control model fixed (no enable/discharge GPIO).
- Established that the schematics are the source of truth over the prose documents.

### 2026-06-17 — `4318fb2`
- Device / card / test driver stack added, plus logging and RTOS tasks, and Nucleo bring-up.

### 2026-06-16 — `56553f0`, `18d6ed9`
- Project start. Peripherals configured in CubeMX; `fw_status.txt` created.
