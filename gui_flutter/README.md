# HT_MK1 Operator GUI — Flutter (Windows)

A Flutter Windows desktop build of the HT_MK1 operator console. Same design,
same protocol, same safety rules as `../gui`, with no Python at runtime: the
protocol layer is ported to Dart and the UI is Flutter widgets rather than a
browser page.

> Builds, analyzes clean, and has been run against both `--sim` and real
> hardware (a NUCLEO-G474RE on this repo's firmware) — connect, netlist
> upload and netlist-mode continuity confirmed end to end. See **Status** at
> the bottom, and **Known limitations** for the one thing that needs a
> hardware fix, not a software one: resistance measurement.

## Source to executable, in one script

```
build_exe.cmd
```

From a fresh checkout that is the whole thing. It checks the toolchain,
generates the `windows\` runner, fetches packages, analyzes, runs the tests,
builds the release and packages it — six steps, and it names exactly what is
missing rather than failing halfway with a CMake error.

```
build_exe.cmd --skip-tests      package a work in progress
build_exe.cmd --skip-analyze
```

Needs, on the **build** machine only:

| | |
|---|---|
| [Flutter SDK](https://docs.flutter.dev/get-started/install/windows) | |
| Visual Studio + "Desktop development with C++" | `flutter build windows` shells out to MSVC |
| **Developer Mode** | Flutter symlinks plugin sources into the build tree, and unprivileged symlinks need it. Any plugin at all fails without it |
| 7-Zip | only to compress the payload; the script installs it via winget if absent |

The `windows\` runner is machine-generated boilerplate tied to your SDK
version, so it is not checked in. The script scaffolds it into a scratch
directory and copies only `windows\` back, so `lib\`, `test\` and `pubspec.yaml`
are never touched — then patches the window title, the default size, the binary
name and the version metadata. Safe to re-run; it reuses `windows\` if present.

There is exactly one third-party package, `flutter_libserialport`. Dart has no
serial API in `dart:io` and the instrument's link is a UART, so talking to real
hardware needs an FFI binding to libserialport. It is used by one file,
`lib/htproto/serial_transport.dart`, which nothing else imports — the protocol
layer, the UI and the whole test suite stay free of it.

### Day to day

Once `build_exe.cmd` has run once, `windows\` exists and the normal loop works:

```
flutter analyze
flutter test
flutter run -d windows --dart-entrypoint-args --sim
```

or press F5 in VS Code — `.vscode/launch.json` has configs for the simulator,
the fault and link-drop scenarios, and the Nucleo.

## What it produces

Two ~7.8 MB portable executables in `dist\`:

| | |
|---|---|
| `HT_MK1_GUI.exe` | connects to the instrument on the ST-LINK VCP (`--serial auto`) |
| `HT_MK1_GUI_demo.exe` | built-in simulator, no hardware |

Copy either anywhere and double-click. Neither needs Flutter, Python, or any
runtime on the target.

**Flutter Windows has no one-file mode.** `HT_MK1_GUI.exe` out of
`flutter build windows` is a ~90 KB launcher; the app is `flutter_windows.dll`
(~20 MB) plus `data\app.so`, and `data\` has to keep its layout. Anything that
looks like a single file has to unpack first — so `build_exe.cmd` wraps the
Release tree in a self-extracting archive that unpacks to `%TEMP%\7ZipSfx.NNN\`
and runs the app. The cost is a second or two of extraction on every launch. If
that matters more than portability, ship `Release\` as a folder or a zip
instead: same bits, instant start.

Two exes rather than one because the SFX runs a fixed command line — the same
reason the Python build shipped `ht-gui.cmd` and `ht-demo.cmd`. For anything
else (`--serial COM7`, `--sim --scenario insul_fail`, `--log-dir`), run the exe
inside `Release\` directly.

The self-extracting stub is vendored in `tools\` — see `tools\README.md` for
why the stock 7-Zip module will not do.

Verified by wiping `windows\`, `build\`, `dist\` and `.dart_tool\`, running
`build_exe.cmd` against nothing but source, then staging the result outside the
project and launching it with the working directory set to `C:\Windows`. The
demo exe came up and connected; `--serial auto` found COM13, completed the
handshake, held the link, and wrote its session log to
`%LOCALAPPDATA%\HT_MK1\sessions`. That last check is the one the Python build
used to catch its relative-`sessions\` bug.

## Running it

```
ht_mk1_gui.exe --serial COM7          talk to the instrument over the VCP
ht_mk1_gui.exe --serial auto          find the ST-LINK VCP automatically
ht_mk1_gui.exe --list-ports           which COM ports exist
ht_mk1_gui.exe --sim                  demo mode: built-in simulator
ht_mk1_gui.exe --host 10.0.0.4 --port 46000
ht_mk1_gui.exe --log-dir D:\logs
```

`--sim` runs the simulator inside the same process and says so on the console.
Nothing it displays is a measurement. `--scenario`, `--nets` and `--interval`
pick the simulated harness, same names as `python -m htproto.simulator`.

### The status-bar port selector

Started with no arguments — the double-click path — the app comes up
disconnected on a serial link, and the operator picks the port from the status
bar: a dropdown, a refresh button, and Connect.

- **The dropdown selects; it does not dial.** Picking a port sets the pending
  choice and closes the menu. **Connect** opens it, at `--baud` (default
  115200). Keeping the two separate is what lets a failed connect be retried
  without reopening the menu.
- **Refresh** re-enumerates and logs what it found. A selection that is still
  present survives; one whose port has gone away is moved to the first port,
  and the log bar says so.
- While a connect is in flight the button reads **Connecting** and stops taking
  clicks. A second connect tears down the first one's half-open link, so an
  impatient double-click used to cause the failure it was reacting to.
- Under `--sim` or `--host` the transport is a socket, so there is no COM port
  to pick and the dropdown and refresh button are hidden.

## Testing against the Nucleo

The firmware in this repo already speaks the protocol, on **LPUART1 (PA2/PA3)
at 115200 8N1** — which on a NUCLEO-G474RE is the ST-LINK Virtual COM Port, so
it shows up as an ordinary COM port. See `Log_HwInit_LPUART1()` in
`Core/Src/app/log.c` and `Core/Src/app/proto.c`.

Checked against the firmware, and compatible:

| | |
|---|---|
| Terminator | firmware sends CRLF; `LineFramer` strips the trailing `\r`, and `Proto_RxByte` tolerates CRLF inbound |
| `>` prefix | `Proto_RxByte` strips it, and the GUI always sends it |
| Commands | the full set the GUI issues is implemented |
| `<ID` | reports `fw=0.1.0`, which passes the codec's semver check |

One quirk worth knowing: `<STATUS` only ever reports `idle` or `hv_armed`,
never `running`. That is fine — the GUI deliberately treats a STATUS reply as
saying nothing about whether the harness is safe to touch, and stays `unknown`
until `!SAFE`.

**Bring the GUI up before the hardware**, or two unknowns get debugged at once:

```
1. build_exe.cmd                                     once: scaffolds, analyzes, tests, builds
2. flutter run -d windows --dart-entrypoint-args --sim
                                                     GUI works, no hardware involved
3. flutter run -d windows --dart-entrypoint-args --serial,COM7
```

Note the comma: `--dart-entrypoint-args` takes one comma-separated list, so it
is `--serial,COM7`, not `--serial COM7`.

Close anything else holding the port first — a terminal, or the STM32CubeIDE
console. The port cannot be shared, and `SerialTransport` will say so rather
than failing silently.

If the link comes up, the log bar shows `connected — state idle, fixture none`
and the header pills go live. If it does not, the session log under
`%LOCALAPPDATA%\HT_MK1\sessions` has every byte in both directions.

Session logs go to `%LOCALAPPDATA%\HT_MK1\sessions`, never to a relative path —
same reasoning as the Python build: the log is opened as part of connecting, so
an unwritable working directory used to take the whole link down.

Under `flutter run`, arguments go through `--dart-entrypoint-args`:

```
flutter run -d windows --dart-entrypoint-args --sim
flutter run -d windows --dart-entrypoint-args --port,46000
```

## Layout

```
lib/htproto/codec.dart        wire codec: byte-exact encoders, strict parser
lib/htproto/messages.dart     reply/event types
lib/htproto/connection.dart   connection manager: timeouts, link loss, session log
lib/htproto/paths.dart        where session logs go
lib/htproto/simulator.dart    instrument simulator, five scenarios
lib/htproto/serial_transport.dart  the real link: COM port via libserialport

lib/design/tokens.dart        the CSS custom properties, value for value
lib/design/widgets.dart       one widget per CSS component class
lib/design/icons.dart         the page's inline SVG icons
lib/design/svg_path.dart      SVG path-data parser (so icons are exact, not redrawn)
lib/design/model.dart         fixture, harness nets, netlists, connector geometry
lib/design/painters.dart      the three canvases: diagram, histogram, sparkline

lib/app/app_state.dart        design state + the live protocol layer, and the safety rules
lib/app/shell.dart            status header, hazard banner, rail, log bar
lib/app/parts.dart            netbar, verdict, stage flow, domain cards, lock overlay
lib/app/modals.dart           the two HV modals
lib/views/                    the seven views
lib/main.dart                 CLI args, theme, keyboard shortcuts

test/protocol_test.dart       codec, connection manager, simulator
test/gui_test.dart            harness determinism, gating, safety rules
```

## What was ported from what

| Flutter | Python / web original |
|---|---|
| `lib/htproto/*` | `gui/htproto/*`, one file to one file |
| `lib/design/*`, `lib/app/parts.dart`, `lib/views/*` | the markup + CSS of `gui/htweb/index.html` |
| `lib/design/model.dart`, the state half of `app_state.dart` | the `<script>` block of `index.html` |
| the live half of `app_state.dart` | `gui/htweb/live.js` |
| — | `gui/htweb/server.py` has no counterpart: there is no HTTP/SSE bridge any more, the UI calls the connection manager directly |

Two deliberate non-ports:

- **The design's three simulated run functions.** In the shipped web GUI
  `live.js` always loads and `S.setRun(...)` rebinds `runCont` / `runRes` /
  `runHv` before anything can call them, so those bodies are dead code in
  production. `runCont`, `runRes` and `runHv` here are the live versions.
- **The Tk frontend** (`gui/htgui/`). It exists in the Python build because its
  state model is where the safety rules were unit-tested without a display;
  here `test/gui_test.dart` does that job directly against `AppState`.

## How the safety rules are implemented

`lib/app/app_state.dart` is the only place they live, and `test/gui_test.dart`
exercises them with no widgets involved:

- **"Safe to handle" comes from `!SAFE` and nothing else.** Not from a run
  finishing, not from event ordering, not from silence. Everything else is
  `unknown`, which is never presented as safe.
- **Link loss forces `unknown`** and drops the arm — the GUI cannot know what
  the instrument is doing once it stops hearing from it.
- **Arming is dropped by any fixture change**, solicited or not, by `!SAFE`, by
  `!STATE idle`, and by any link trouble. The case this exists to stop is: arm
  on the HV fixture, claim a move back to the matrix, then energise.
- **Insulation controls are enabled only from `!FIXTURE hv`** as reported by the
  instrument — never from what the GUI asked for.
- **Abort is never disabled while the link is up**, and never sits behind a
  confirmation dialog.

Commands never block the UI: `execute()` returns a `Future` and the 2 s command
timeout bounds it, so the abort button stays live throughout.

## Behaviour carried over from the connection manager

Per brief 3.5: commands time out after 2 s (`CommandTimeoutError`), 5 s without
traffic or a closed port flips the state to `linkLost` ("state unknown" — every
command then throws until you `connect()` again), and `connect()` always
re-issues `>STATUS` before reporting connected. Every session is logged both
directions, flushed per line.

Python used a reader thread, a watchdog thread and two locks. Dart's event loop
is single-threaded, so the ordering those locks protected comes for free —
appending to the pending queue and writing the command happen in one
synchronous block. Observable behaviour is unchanged.

For real hardware, implement `Transport` over a serial port (115200 8N1 on the
USB VCP) and pass it as `transportFactory`; nothing above the transport changes.

## What is live, and what is still presentation

Unchanged from the web build — the instrument's protocol is narrower than the
design:

| Live from the instrument | Presentational only |
|---|---|
| link state, `!STATE`, `!HV`, `!SAFE`, `!FIXTURE` | connector/fixture map (`J1…J8`) — a GUI-side artifact; the instrument only knows pins 1..256 |
| continuity, resistance and insulation results and progress | net *names* — the protocol carries pin pairs, not names |
| faults, instrument log lines | HV card-stack detection, leakage voltage trace |
| netlist download, cal, limits, abort, arm, fixture handover | scenario/seed pickers left from the mock, run history, fault pareto |

## On "exactly the same look"

Flutter has no CSS, so every rule was hand-translated. Where a number appears in
this code it is the number the stylesheet uses — colours, spacing, type sizes,
weights, and letter-spacing converted from `em` to logical pixels (CSS
`letter-spacing:.13em` at `font-size:10px` is `letterSpacing: 1.3`). Both themes
are transcribed, the toggle is kept, and the icons are the design's own SVG path
data parsed at runtime rather than redrawn.

What cannot be identical, and is not:

- **Glyph rasterisation.** Chromium and Skia hint and antialias text
  differently. The fonts are the same (`Segoe UI Variable Text`, `Cascadia
  Mono`, both stock on Windows 11) and the metrics are the same, but pixels at
  the edges of letters will differ.
- **Sub-pixel layout rounding** in flex/grid vs. Flutter's box model, worth a
  fraction of a pixel per box and occasionally visible as a 1px difference in a
  long row.
- **Shadow softness.** CSS blur radius is twice the Gaussian sigma and Flutter's
  is not; `tokens.dart` scales by 0.866 to land on the same sigma, which is
  close but not bit-identical.
- **`.rail-end`.** `margin-left:auto` inside a horizontally scrolling row has no
  Flutter equivalent that does not assert, so at narrow widths the Diag button
  sits after a fixed 16px gap instead of being pushed to the far edge.

Everything else — layout, colour, both themes, all eight views, the canvas
wiring diagram with its hit-testing and tooltips, the histogram, the sparkline,
the relay grids, the modals, the hazard banner, F5/Esc — is reproduced.

## Status

Verified on Flutter 3.44.9 / Dart 3.12.2, Windows 11:

- **`flutter analyze` — clean.**
- **`flutter test` — 164 passing.** Codec, connection manager (timeouts, link
  loss, netlist sequencing), simulator scenarios, harness determinism, gating,
  the safety rules, `test/layout_test.dart`, `test/port_selector_test.dart`,
  `test/netlist_upload_test.dart`, `test/manual_and_fault_test.dart`,
  `test/netlist_select_flow_test.dart`, `test/diag_controls_flow_test.dart`
  and `test/wire_log_test.dart` — the last four drive the real widget tree
  through `tester.tap()`, not just `AppState` methods directly, specifically
  because a correct method proves nothing about whether the button that's
  supposed to call it actually does.
- **`flutter build windows` — builds.**
- **Runs against `--sim`** with no rendering exceptions: connects, handshakes
  `>STATUS` / `>CAL GET` / `>LIMITS GET` / `>NETLIST GET`, and writes a session
  log.

`test/layout_test.dart` renders all seven views at four window sizes in both
themes, plus thirteen specific states (handover, faults, HV live, link lost,
cross mode, both modals, 1–4 card stacks) and fails on any rendering exception.
It found 27 overflows on its first run — none of which `flutter analyze` or the
headless tests can see, because they only exist once real constraints flow
through the tree. Run it before believing any layout change.

- **Runs against real hardware.** `--serial COM13` against a NUCLEO-G474RE
  running this repo's firmware completes the whole connect sequence:

  ```
  [gui] connected COM13:115200
  [tx] >STATUS       [rx] <STATUS state=idle fixture=none hv_mv=0
  [tx] >CAL GET      [rx] <CAL current_ua=3000 gain=32 rref_mohm=100000
  [tx] >LIMITS GET   [rx] <LIMITS r_max_mohm=5000 ins_min_mohm=10000000
  [tx] >NETLIST GET  [rx] <NETLIST 0
  ```

  The limits match `s_lim_r_mohm` / `s_lim_ins_mohm` in `Core/Src/app/proto.c`,
  so those values came off the board rather than out of the simulator. With the
  firmware heartbeat in place the link then holds indefinitely.

  `SerialTransport.open()` flushes the input buffer. The instrument heartbeats
  whether or not anyone is listening, so opening the port used to deliver a
  burst of stale events — starting mid-message, so the first line arrived with
  its `!` already gone and failed to parse. A TCP connect gets a clean stream by
  construction; this is the serial equivalent. (The malformed line was survived
  correctly — surfaced through `onProtocolError`, link intact — but there is no
  reason to hand the parser data that predates the session.)

### One crash, found and fixed on hardware

The first hardware run died about fifteen seconds after the watchdog dropped
the link — a Windows crash dialog, `0x80000003` in `ucrtbased.dll`, which is
the debug CRT's `_invalid_parameter` → `abort()`.

Cause was in `SerialTransport.close()`: it called `port.close()` and then
`port.dispose()` while `SerialPortReader`'s background isolate could still be
mid-read. `SerialPortReader.close()` signals that isolate but does not wait for
it, so freeing the port handed an already-released handle back to the CRT.

`close()` now drops `dispose()` entirely, waits 100 ms for the reader to
observe the shutdown, and guards against re-entry (link loss and an explicit
disconnect can both fire). The `sp_port` struct is left to leak — a few hundred
bytes per connect, against a crash dialog on a console that arms 500 V.

Verified by leaving the app connected through a link-loss cycle for 100 s: no
crash, process alive, session log intact.

### The netlist was never uploaded

Found running against real hardware, not `--sim`: pressing **Run S1** (netlist
-mode continuity) was refused every time —

```
[tx] >CONT RUN verify
[rx] <ERR ERANGE no netlist
```

— and `RES RUN` failed the same way. The instrument's netlist lives in RAM
only (`s_net_hi`/`s_net_lo` in `Core/Src/app/proto.c`) and starts empty on
every boot; nothing repopulates it. `NETLIST BEGIN`/`ADD`/`END` exist in the
codec for exactly this (3.2), and `protocol_test.dart` exercises them directly
against the connection manager — but nothing in `AppState` ever called them.
The status bar kept saying "MTX netlist loaded: AV-880_RevC.hnl" regardless,
because that name comes from `buildNets()`, a seeded placeholder for the
pre-connection UI (`design/model.dart` — "same as the browser's demo
harness"), not from the instrument.

The one route the GUI already offered to build a real netlist — cross
continuity, "Save as MTX netlist" — did not work either: `saveNlEnabled` had
no setter anywhere, so the button was permanently disabled, and even reachable
it only renamed the placeholder without sending anything.

Fixed in `lib/app/app_state.dart`:

- `connect()` now clears `nlMtx.loaded` when the instrument's own `NETLIST
  GET` comes back empty, instead of leaving the placeholder claiming a
  netlist is ready.
- A cross-continuity (`CONT RUN discover`) run now accumulates the pairs
  `!CONT` actually reports as passing, live-updates the discovery tallies,
  and enables **Save as MTX netlist** once it finds any.
- `saveDiscoveredNetlist()` sends `NETLIST BEGIN` / one `ADD` per pair /
  `END`, then rebuilds the net model from what the instrument confirmed —
  the same pin data, not a re-derivation — before marking the MTX netlist
  loaded.

Confirmed on hardware, by hand over the raw serial link and then rebuilt into
the exe:

```
>NETLIST BEGIN 2      <OK
>NETLIST ADD 1 2      <OK
>NETLIST ADD 3 4      <OK
>NETLIST END          <OK loaded=2
>CONT RUN verify       <OK started      (was ERR ERANGE no netlist)
                        !CONT 1 2 open
                        !CONT 3 4 open
                        !DONE cont 0 2
```

("open" is correct — no harness was on the fixture; the point is the command
was *accepted*.) `test/netlist_upload_test.dart` reproduces the same sequence
against the real simulator (which enforces the identical `ERR ERANGE no
netlist` gate) end to end: discover, save, then verify-mode continuity runs
and passes on the same connection.

Since verified on hardware: netlist-mode continuity and resistance runs
complete end to end — `>NETLIST BEGIN/ADD/END` load the netlist the instrument
needs before it will accept `CONT RUN verify` or `RES RUN` at all (3.2), then
the run streams `!CONT`/`!RES`, `!PROGRESS` and `!DONE` exactly as the protocol
describes. See **The netlist was never uploaded** above — that gap is what
`test/netlist_upload_test.dart` exists to catch a regression of.

Still unverified:

- **Insulation has not been run against real hardware.** It requires the
  harness on the HV fixture and 500 V applied; nothing here has exercised that
  path outside `--sim`.
- **Nothing has been compared side by side with the HTML.** The "On exactly the
  same look" section is still a claim about what the code says. Font resolution
  in particular is unchecked: if `Segoe UI Variable Text` or `Cascadia Mono` do
  not resolve, metrics will be visibly wider than the browser's.

See **Known limitations** below for the one thing found on hardware that is
not a GUI or firmware bug: resistance measurement itself.

### Buttons that looked like features but weren't wired to anything

A full audit of every tappable control (`Doc/GUI_protocol_command_coverage.md`) found ~20
buttons that didn't reach the instrument — some because nobody had called the command yet,
some because no command exists, and one, `FAULT CLEAR`, because there was no button at all
despite the brief requiring one (§3.2.1, FW-10). Fixed this session, using only commands the
firmware already answers — no firmware changes:

- **`FAULT CLEAR`** — added `AppState.clearFault()` and a "Clear Fault" control that appears
  in the status bar only while `!STATE fault` is latched (`AppState.inFault`). Also fixed a
  correctness bug found while wiring this: a run refused by a latched fault answers
  `!STATE fault` then `!DONE <kind> 0 0`, and `0 failed` was reading as a pass. It no longer
  does — `test/manual_and_fault_test.dart` pins the fix and the event-ordering assumption it
  depends on (the fault event must land before `!DONE`, not after).
- **`MANUAL PATH`** ("Close path", Diagnostics) and **`MANUAL OFF`** ("Discharge",
  Diagnostics) — both had a real command sitting unused; now wired.
- **MTX netbar "Select…"/"Change…"** — routes to the Continuity view in cross-discovery mode
  instead of doing nothing, since there is no file picker for the MTX netlist (see above);
  cross-discovery + Save is the only way to give the instrument one. **Revised after real
  operator feedback**: the first version jumped to the Continuity view silently, with only a
  collapsed-by-default log line explaining why — which read as "I clicked Select… and nothing
  happened," reasonably enough. It now opens an explanatory modal first
  (`AppState.openMtxNlExplainer` / `MtxNetlistModal`) that says plainly there is no file to
  browse for, before an explicit "Take me there" (`confirmGoToBuildMtxNetlist`) does the
  navigation. Same reasoning as the HV netlist picker modal, just for the case where there is
  no file list to show.
- **"Re-measure worst"** (Resistance view) — re-runs `RES RUN` via the existing gating; there
  is no protocol primitive to measure only the worst nets, so a full re-run is the honest
  version of this button.
- **Diagnostics — Calibration panel** — was showing static mock numbers (a "0.412 Ω system
  offset" that was never computed by anything). Now reads the real `<CAL GET` reply already
  fetched on connect. Three of the panel's original five rows (loopback offset, ADC offset, HV
  divider ratio) aren't part of `CAL GET` at all — they're now labelled as not reported rather
  than shown as invented numbers.

Removed rather than wired, because the brief already settles it:

- **"Close HS only" / "Close LS pattern"** (Diagnostics — Manual relay) sent `MANUAL RELAY`,
  which the firmware refuses by design (`ERR EHW`) — brief §0 and §8 Q3 say outright *"the
  firmware refuses, a GUI confirm is not sufficient... do not offer the control."* Replaced
  with a note explaining why, not a button that always fails.
- **FIX netbar "Change…"** — the fixture file is a hardware property, not something an
  operator loads or swaps; there was never anything for this to do.

Left disabled rather than silently doing nothing, because no protocol command exists for them
yet — see `Doc/GUI_protocol_command_coverage.md` §4 and
`Doc/GUI_protocol_proposed_commands.md` for what each would need: Rescan (Bus map), Read ADC
and Sweep this HS (Manual switch), Run self-cal / Compliance sweep / Cal certificate
(Calibration), Auto-range PGA (Resistance), Relay self-test (HV view).

**Verified against real hardware, and it caught nothing new.** A long interactive session
(COM13, `session-20260808-151124.log`, ~90 minutes) ran `CONT RUN verify`, `CONT RUN discover`
×2, and sat idle the rest of the time. Every `CONT RUN discover` came back `!DONE cont 0 0` —
zero nets found, because no harness was physically on J-MTX, not because anything is broken.
"Save as MTX netlist" correctly stayed disabled: there was nothing to save. This was confirmed
by reading the session log, not by guessing — the log is the honest record of what the GUI
actually sent and what the instrument actually answered, which is also why the next section
exists.

### The log bar now has a Console tab: every byte, live, not just in the session file

Every command sent and every line received already went to the session log file
(`SessionLogger` — brief §3.5.5). What didn't exist was any way to see that traffic *while
using the GUI* — the only way to check what was actually said on the wire was to close the
app and go read a file. Given how much of this session's debugging came down to exactly that
("read the session log to see what really happened"), that gap is now closed:

- `ConnectionManager` gained a fourth callback, `onWire(direction, text)`, called from the
  same two places `SessionLogger.tx()`/`.rx()` already are (`connection.dart`) — so the console
  shows *exactly* what the file would, nothing reformatted or filtered.
- The status bar's log panel now has two tabs, **Log** (the existing human-readable operator
  log) and **Console** (raw `tx`/`rx` lines) — independent of the panel's expand/collapse
  state, so switching tabs while collapsed just changes what the next expand shows.
- Capped at 2000 lines (`AppState.wireLogCap`) — a heartbeat every 2 s plus every streamed
  run event adds up over a shift, and this is operator-visible scrollback, not the audit
  trail. The session file on disk is already complete and uncapped; this doesn't need to be.

`test/wire_log_test.dart` covers all three layers: `ConnectionManager.onWire` firing with the
exact wire text, `AppState.wireLog`'s capping behaviour, and — through a real `tester.tap()`,
not a direct method call — that switching to the Console tab actually shows the `>STATUS` /
`<STATUS ...` lines a real connect produced.

## Known limitations — not fixable from this GUI or its firmware protocol layer

**Resistance measurement reports `fail_high` on every net.** `RES RUN` is now
*accepted* by the instrument (see above), but every result comes back
`fail_high` with `!FAULT F08 resistance path unavailable`:

```
>RES RUN     <OK started
              !RES 1 2 0 fail_high
              !FAULT F08 resistance path unavailable
              !DONE res 0 2
```

This is a hardware routing gap, not a software bug, and it is already tracked
in-repo as **FW-01 / FW-02**: `Kelvin_MeasurePair()` (`Core/Src/test/kelvin.c`)
deliberately returns `HAL_ERROR` rather than a number from a measurement path
that no longer exists — Matrix_Card 2 deleted the AD7476 (U33) the old 2-wire
reading used, and the replacement 4-wire Kelvin read via the ADS124S08
(FW-02) is not implemented pending FW-01 (`drivers/ads124s08`). Per the
Matrix_Card-6 / Control_Card-4 schematic rework, that ADC is currently
electrically unreachable from this MCU: `ADC_CS_1`, `ADC_RST_1`,
`Start_SYNC_1`, `DRDY_1` and `SPI1_SCLK` exist only on the Matrix Card, with
no path to the Control Card or connector J101. The boot log says as much on
every startup:

```
[warn] spi   SPI1 ADS124S08 device-ID read failed — CS unrouted (HW-01)
```

Fixing this needs a Control-Card routing change (or a rework), not a firmware
or GUI change — do not treat `RES RUN` succeeding at the protocol level as
resistance measurement working. Continuity (a different ADC, AD7476 U33/U4,
unaffected by this gap) and, so far as tested, insulation are not affected.

## The idle-quiet link, and the firmware heartbeat

Brief 3.5.3 calls five seconds without traffic a lost link, and both this build
and the Python one implement exactly that. But the firmware used to emit nothing
when idle — its only periodic logger sits behind `HT_ENABLE_ADS1232`, which is
not defined in the build — so the rule fired on a perfectly healthy link about
five seconds after the operator connected:

```
14:33:54.338 [rx] <NETLIST 0
14:33:59.824 [gui] LINK LOST: no traffic for 5.0s
```

Inherited, not introduced: `htproto/connection.py` has the identical watchdog.
Fixed in the firmware rather than the GUI, because the rule assumes a talkative
instrument and the instrument was not one:

- `Proto_EvtHeartbeat()` in `Core/Src/app/proto.c` re-announces the current
  state; `PROTO_HEARTBEAT_MS` is 2000, so two beats fit inside the 5 s window
  and one dropped line does not cost the link.
- `CommsTask` in `Core/Src/app/tasks.c` swapped `osWaitForever` for a timed
  wait, and beats off `osKernelGetTickCount()` rather than off queue timeouts —
  a steady trickle of received bytes would otherwise keep resetting the wait and
  starve the heartbeat, exactly when the GUI is waiting to hear back.

`!STATE` carries it rather than a `#` log line: the GUI folds a repeated
`!STATE` into state it already holds, whereas a periodic `#` would overwrite the
operator's log summary every two seconds.

One deliberate inconsistency: the heartbeat reports `running`, while the
`>STATUS` reply still answers only `hv_armed`-or-`idle`. Changing STATUS was out
of scope — but a heartbeat claiming `idle` mid-run would clear `armed` in the
GUI, so the heartbeat uses the more precise answer. See `proto_state_name()`.

Verified on hardware: 90 s connected, no link loss, 65 heartbeats at 1.997 s.
