# GUI Protocol Command Coverage — What's Wired, What Isn't, and What Should Happen

Companion to `GUI_development_brief.md` §3.2. Written after an audit of every tappable
control in `gui_flutter/lib/` turned up ~20 buttons that don't reach the instrument. This
document cross-references three things that need to agree and currently don't:

1. What `>` commands the firmware actually implements (`Core/Src/app/proto.c`, and the brief's
   own Appendix B, "what the instrument does today").
2. What commands the GUI's codec *can* send (`gui_flutter/lib/htproto/codec.dart`).
3. What `AppState` *actually* sends (`gui_flutter/lib/app/app_state.dart`) — and which button,
   if any, triggers it.

Every command in §3.2 already has a byte-exact encoder in `codec.dart` — the codec is
complete. The gap is entirely at the wiring layer (2 → 3) and, for a handful of buttons,
at the protocol layer itself (no command exists for what the button claims to do at all).

> **Status update, same session:** everything in group 1 of §7 ("wire the real gaps") and
> group 2 ("remove, don't wire") has been implemented and verified against real hardware —
> `FAULT CLEAR`, `MANUAL PATH`, `MANUAL OFF`, the MTX netbar routing, "Re-measure worst," the
> real Calibration panel, and removing the `MANUAL RELAY` buttons. The tables below are kept
> as the original audit record; rows that changed are marked **Done**. Groups 3 and 4 are
> unchanged — see `Doc/GUI_protocol_proposed_commands.md` for group 4's detailed proposal.

## 1. Command-by-command status

| Command | Codec encoder | Called from `AppState`? | Per brief Appendix B | Notes |
|---|---|---|---|---|
| `PING` | `commands.ping()` | Never | Works | No GUI reason to send this; harmless to leave unwired |
| `ID` | `commands.identify()` | Never | Works | Same — `fw`/`proto` aren't shown anywhere in the UI |
| `STATUS` | `commands.status()` | Yes — internally, by `ConnectionManager.connect()` | Works | Not a button; part of the connect handshake |
| `SAFE` | `commands.safe()` | Never | Works | `ABORT` already covers every case the GUI currently offers a control for — no button claims to be a pure "force safe" distinct from "stop and go safe" |
| `ABORT` | `commands.abort()` | Yes — `AppState.abort()` | Works | Wired to "Abort & discharge" (hazard bar) and "Emergency discharge" (HV view) |
| `NETLIST BEGIN/ADD/END` | `commands.netlistBegin/Add/End` | Yes — `AppState.saveDiscoveredNetlist()` | Works | Fixed this session — was previously defined and never called at all |
| `NETLIST GET` | `commands.netlistGet()` | Yes — `AppState.connect()` (via `cm.netlistGet()`) | Works | |
| `CONT RUN verify\|discover` | `commands.contRun()` | Yes — `AppState.runCont()` | Works | |
| `RES RUN` | `commands.resRun()` | Yes — `AppState.runRes()` | **Runs but always fails** (fail_high, FW-02 hardware gap) | Not a GUI bug — see the firmware README note added this session |
| `INSUL ARM` / `INSUL RUN` | `commands.insulArm/insulRun()` | Yes — `AppState.runHv()` | Works | |
| `HV SET` | `commands.hvSet()` | Never | **Accepted, does not move the rail** (rail is driven by `INSUL RUN` itself) | Correctly unused for the normal flow; only meaningful as a manual/diagnostic control |
| `FIXTURE` | `commands.fixture()` | Yes — `AppState.confirmHandover()` | Works | |
| `MANUAL PATH` | `commands.manualPath()` | **Done** — `AppState.manualClosePath()` | Works | Wired to "Close path"; verified against real hardware (`<OK started`) |
| `MANUAL OFF` | `commands.manualOff()` | **Done** — `AppState.manualOff()` | Works | Wired to "Discharge"; verified against real hardware |
| `MANUAL RELAY` | `commands.manualRelay()` | Never (by design) | **Refused by design** (`ERR EHW`) | Brief §0 and §8 Q3: *"the firmware refuses, a GUI confirm is not sufficient... **do not offer the control**."* **Done** — "Close HS only"/"Close LS pattern" removed, replaced with an explanatory note |
| `FAULT CLEAR` | `commands.faultClear()` | **Done** — `AppState.clearFault()` | Works | Wired; a "Clear Fault" control now appears in the status bar while `AppState.inFault` is true. See §2 — kept as the original finding, now resolved |
| `CAL GET` | `commands.calGet()` | Yes — `AppState.connect()` | Works | **Done** — the Diag "Calibration" panel now reads `s.cal` instead of static mock numbers; the three rows CAL GET doesn't cover (loopback/ADC offset, HV divider) are labelled as not reported rather than shown as invented |
| `LIMITS GET` | `commands.limitsGet()` | Yes — `AppState.connect()` | Works | |
| `LIMITS SET` | `commands.limitsSet()` | **Never** | Works | Real gap — there is no way to change `r_max_mohm`/`ins_min_mohm` from the GUI at all |

## 2. The one that actually mattered: `FAULT CLEAR` didn't exist in the GUI (now fixed)

This wasn't in the original "dead button" list because there's no dead button for it —
there is no button, screen, or menu item anywhere that sends `FAULT CLEAR`. The brief is
explicit that this is required, not optional (§3.2.1, added with FW-10):

> "A latched fault refuses runs, and says so... `>FAULT CLEAR` is the only recovery — it
> forces safe *first*, then clears the latch... **The GUI should offer it from the fault
> screen as a deliberate operator action, never automatically.**"

And from `Core/Src/app/tasks.c`'s own comment on the command dispatch: *"clearing the latch
is the one thing that has to work WHILE faulted, or the only recovery is a power cycle."*

Fixed this session:

- `AppState.clearFault()` sends `FAULT CLEAR` and logs the outcome — mirrors `abort()`.
- `AppState.inFault` (`instState == proto.State.fault`) gates a "Clear Fault" control in the
  status bar (`shell.dart`'s `StatusBar`) — visible only while a fault is actually latched,
  never a permanent fixture of the UI.
- `paintLink()`'s `statePill` used to render `fault` with the same neutral grey as `idle`
  (`PillVariant.idle`) — now `PillVariant.bad`, so a latched fault reads as an alarm, not a
  quiet state change.
- A related correctness bug found while wiring this: `_onDone` computed `pass = m.failed == 0`
  unconditionally, so a run refused by a latched fault (`!STATE fault` then `!DONE <kind> 0 0`,
  per FW-10) had `0 failed` and read as a **pass** — R[key] was being set to `'pass'` for a
  test that never ran. `_onDone` now checks `inFault` first and leaves the result unset
  (not-run) instead. `test/manual_and_fault_test.dart` pins both the fix and the realistic
  event ordering it depends on (`<OK started` arrives before `!STATE fault`/`!DONE`, not
  after — getting this backwards in a test hides the bug `_beginRun` would otherwise reveal).

Not done, deliberately out of scope for a status-bar fix: a dedicated "fault screen" beyond
the pill + button. If a fault ever needs more explanation than the pill text gives, that's a
bigger UI question than this pass answered.

## 3. Button → command map

| View · panel | Button | Target command | Status |
|---|---|---|---|
| Continuity — Discovered netlist | Save as MTX netlist | `NETLIST BEGIN/ADD/END` | **Done** |
| Continuity — Discovered netlist | Export CSV | — | No command; GUI-only feature, not done (§5) |
| Results — Run history | Export CSV, Print report | — | No command; GUI-only feature, not done, and blocked on brief §8 Q4 (§5) |
| Diagnostics — Bus map | Rescan | — | No command exists, not done (§4) |
| Diagnostics — Manual switch · J-MTX | Close path | `MANUAL PATH` | **Done** |
| Diagnostics — Manual switch · J-MTX | Read ADC, Sweep this HS | — | No command exists, not done — now shown disabled rather than a silent no-op (`Doc/GUI_protocol_proposed_commands.md`) |
| Diagnostics — Manual relay · J-HV | Close HS only, Close LS pattern | `MANUAL RELAY` | **Done — removed**, replaced with an explanatory note |
| Diagnostics — Manual relay · J-HV | Discharge | `MANUAL OFF` | **Done** |
| Diagnostics — Calibration | Run self-cal, Compliance sweep, Cal certificate | — | No command exists for the first two, not done (§4/proposal doc); `Cal certificate` needs a PDF-export dependency, not done (§5) — but `Cal GET`'s three real fields (reference resistor, excitation, PGA gain) are **done**, replacing the mock numbers |
| Resistance — Actions | Re-measure worst | *(none needed)* | **Done** — re-runs `RES RUN` via the existing `runTest('res')` gating |
| Resistance — Actions | Auto-range PGA, Compliance sweep | — | No command exists, not done — recommend against building either as a separate command (`Doc/GUI_protocol_proposed_commands.md`); shown disabled |
| HV view | Relay self-test | — | No command exists, not done — needs a safety review before a protocol design, not just wiring (`Doc/GUI_protocol_proposed_commands.md`); shown disabled |
| Netbar (Run/Cont/Res/Program/HV views) | Select… (MTX) | *(none needed — GUI routing only)* | **Done** — `AppState.goToBuildMtxNetlist()` routes to the Continuity view in cross-discovery mode |
| Netbar (all three) | Change… | *(depends)* | **Done** — MTX/HV now route the same as Select…; FIX no longer shows Change…/Select… at all (fixture geometry is fixed hardware, not a file) |
| HV netlist picker modal | Browse the file system… | — | **Done** — reads a real Excel (`.xlsx`) netlist; see §5 |

## 4. Needs a new firmware command — out of scope for the GUI alone

Per brief §7, "Firmware changes" and "Protocol changes" are explicitly **out of scope** for
GUI work — *"propose them, do not make them."* These buttons all need a new `>` command
designed and implemented firmware-side before there's anything to wire:

| Button | What it would need | Notes |
|---|---|---|
| Rescan (Bus map) | A new bus-enumeration command, plus the enumeration logic itself | Checked `bsp/board.c` directly — there is **no** I2C/SPI scan in firmware at all. The "I2C3 scan: 0x20 0x21 0x23 0x24 0x25 — 5 devices" boot-log line in the GUI is cosmetic placeholder text from `AppState._bootLog()` (the same pre-connection demo narrative as `buildNets()`), not something the instrument has ever reported. This one needs the scan written from scratch, not just exposed |
| Read ADC (manual switch) | A command that reads back the continuity ADC's raw value without asserting pass/fail | No such primitive exists — `MANUAL PATH` only closes the path, it doesn't report a reading |
| Sweep this HS | A bounded version of discovery — one HS against all 256 LS, e.g. `MANUAL SWEEP <hi>` | |
| Run self-cal (Diag), Auto-range PGA (Res view), Compliance sweep (appears on both) | Real measurement-system firmware work: self-cal against the loopback reference, PGA ranging logic, compliance-limit sweep | This is embedded engineering, not a wiring task — and touches the same ADS124S08 path that's already hardware-blocked for resistance (FW-01/FW-02); needs firmware-side scoping to know what's even reachable given current routing |
| Relay self-test | A safe self-check sequence per HV relay (verify open/closed continuity without HV present) | Safety-relevant — needs careful design and hardware validation, not something to improvise from the GUI side |

## 5. GUI-only features — no firmware involvement, but real work

| Button | What's actually missing |
|---|---|
| Export CSV (×2), Print report | No file-write or PDF-generation dependency in `pubspec.yaml` today. Print report in particular has no native Windows print API in Flutter without an added package — realistic scope is "export a PDF," not literal printing |
| Cal certificate | Same PDF-generation gap. Unlike the others this one doesn't need new data — `CAL GET`'s reply is already fetched into `AppState.cal` and just needs a real "Calibration" panel display plus a PDF export of it |
| Run history data itself | The Results view's whole table is static mock data, not sourced from anywhere. This is brief §8 open question 4 ("Run history — stored on the instrument or the GUI host?"), which is **unanswered**. Export/print can't be built properly until this is decided — exporting a mock table is not useful |

**Done, this session:** Browse the file system… was two things, not one: (1) a file-picker
package (`file_picker`, now in `pubspec.yaml`, isolated to `lib/htproto/netlist_picker_io.dart`
the same way `flutter_libserialport` is isolated to `serial_transport.dart`), and (2) — the
actual blocker — **there was no netlist file parser anywhere in this codebase.** Rather than
inventing a `.hnl` format, `lib/htproto/netlist_file.dart` reads a real Excel (`.xlsx`) netlist
(`excel` package, pure Dart, no platform channel) — a header row with a HI/HS pin column and a
LO/LS pin column, an optional NET name column, and (HV only) an optional CARDS column. Both
netbars now browse for real:

- **MTX** (`AppState.browseMtxNetlist`) uploads the parsed (hi, lo) pairs via `NETLIST
  BEGIN/ADD/END` — the exact same wire sequence `saveDiscoveredNetlist` uses for a saved
  cross-continuity scan, now factored into a shared `_uploadNetlistPairs` so a file and a scan
  are just two sources for the same upload. The MTX netlist modal (`lib/app/modals.dart`) no
  longer claims "there is no file to pick" — it offers both: browse a file, or build one from
  cross continuity.
- **HV** (`AppState.browseHvNetlist`) sets the same name/cards/nets metadata `pickHvFile` sets
  from the canned list — there still isn't a wire command for "load an HV netlist" (see §1),
  so a file only ever replaces the three hardcoded demo entries with a real one; it does not
  change what gets uploaded to the instrument.

A malformed file (missing HI/LO header, an out-of-range or duplicate pin pair, a file that
isn't really `.xlsx`) raises `NetlistFileFormatException` with a message an operator can act
on and is logged as a `fail` line — never a silent no-op and never a partial upload. Tests:
`test/netlist_file_test.dart` (the parser, built against real `.xlsx` bytes from the `excel`
package itself) and `test/netlist_file_load_test.dart` (the AppState-level upload/metadata
flow, including the cancel and malformed-file paths).

## 6. Open spec questions this surfaces (need an answer from the firmware/product side, not a GUI decision)

- **Brief §8 Q2**: should the netlist persist in instrument flash, or be uploaded every run?
  Currently RAM-only, re-upload required every boot (confirmed on hardware this session) — the
  fix built this session works with that as given, but the brief flags this as still open.
- **Brief §8 Q4**: run history — stored on the instrument, or the GUI host? Blocks Export
  CSV/Print report on the Results view from being anything but decoration until answered.
- **Fault-screen UI design** (§2 above): not really "open" per se — the brief says what must
  happen, just not how it should look.

## 7. Suggested grouping for follow-up work

Ordered by dependency, not by how the audit found them.

1. **Wire the real gaps — done, this session.** `FAULT CLEAR` (with a minimal fault-state UI),
   `MANUAL PATH` ("Close path"), `MANUAL OFF` ("Discharge"), Netbar "Select…"/"Change…" for
   MTX pointed at cross-discovery, "Re-measure worst" via a plain `RES RUN` re-run, and a real
   Calibration panel reading `s.cal` instead of mock numbers. All used commands the firmware
   already answers; zero firmware changes. Verified with `test/manual_and_fault_test.dart` and
   against real hardware (`MANUAL PATH`/`MANUAL OFF`/`FAULT CLEAR` all confirmed accepted).
2. **Remove, don't wire — done, this session.** "Close HS only" / "Close LS pattern"
   (`MANUAL RELAY`), and the FIX netbar's "Change…". Both were settled by the brief or by what
   the fixture actually is, not open questions.
3. **Decide, then build.** Export CSV / Print report / Cal certificate still need product
   decisions (§6) before there's a "correct" implementation, not just a missing one — those
   buttons sit deliberately disabled rather than as silent no-ops. The netlist file browser no
   longer belongs in this group: **done, a later session** — see §5, "Done, this session."
   Rather than a bespoke `.hnl` format needing its own product decision, it reads a real Excel
   (`.xlsx`) netlist, which is what harness netlists already exist as before there is a fixture
   to run cross-continuity discovery against.
4. **Propose to the firmware side — proposal written, not implemented.** Rescan, Read ADC,
   Sweep this HS, self-cal, PGA auto-range, compliance sweep, relay self-test. Per brief §7,
   this is a protocol proposal, not something to build unilaterally from the GUI — see
   `Doc/GUI_protocol_proposed_commands.md` for a command-by-command writeup, including which
   two (auto-range PGA, compliance sweep) are recommended against as separate commands at all.
