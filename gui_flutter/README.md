# HT_MK1 Operator GUI — Flutter (Windows)

A Flutter Windows desktop build of the HT_MK1 operator console. Same design,
same protocol, same safety rules as `../gui`, with no Python at runtime: the
protocol layer is ported to Dart and the UI is Flutter widgets rather than a
browser page.

> **This has never been compiled.** It was written on a machine with no
> Flutter SDK and no Visual Studio C++ toolchain, so nothing here has been
> built, run, or seen on screen. Treat the first `flutter analyze` as part of
> the job. See **Status** at the bottom.

## Getting it building

```
setup.cmd
```

Needs the [Flutter SDK](https://docs.flutter.dev/get-started/install/windows)
and **Visual Studio with the "Desktop development with C++" workload** —
`flutter build windows` shells out to MSVC. `flutter doctor` will tell you if
either is missing.

There is exactly one third-party package, `flutter_libserialport`. Dart has no
serial API in `dart:io` and the instrument's link is a UART, so talking to real
hardware needs an FFI binding to libserialport. It is used by one file,
`lib/htproto/serial_transport.dart`, which nothing else imports — the protocol
layer, the UI and the whole test suite stay free of it.

`setup.cmd` generates the `windows\` runner (which is machine-generated
boilerplate tied to your SDK version, so it is not checked in), patches the
window title and default size, and runs `flutter pub get`. It scaffolds into a
scratch directory and copies only `windows\` back, so `lib\`, `test\` and
`pubspec.yaml` are never touched. Safe to re-run.

```
flutter analyze                                   static analysis
flutter test                                      the suite
flutter run -d windows --dart-entrypoint-args --sim
flutter build windows --release
```

The release build lands in `build\windows\x64\runner\Release\`. **Ship the whole
folder, not just the exe** — see below.

## Packaging: portable single-file exes

```
build_exe.cmd
```

Produces two ~7.8 MB portable executables in `dist\`:

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

Needs 7-Zip (`winget install 7zip.7zip`) and the vendored SFX stub in `tools\`
— see `tools\README.md` for why the stock 7-Zip module will not do.

Verified by staging `HT_MK1_GUI.exe` outside the project and launching it with
the working directory set to `C:\Windows`: `--serial auto` found COM13,
completed the handshake, held the link, and wrote its session log to
`%LOCALAPPDATA%\HT_MK1\sessions`. That is the same check the Python build used
to catch its relative-`sessions\` bug.

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
1. setup.cmd                                         once
2. flutter analyze                                   never been run - expect findings
3. flutter test
4. flutter run -d windows --dart-entrypoint-args --sim
                                                     GUI works, no hardware involved
5. flutter run -d windows --dart-entrypoint-args --serial,COM7
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
- **`flutter test` — 125 passing.** Codec, connection manager (timeouts, link
  loss, netlist sequencing), simulator scenarios, harness determinism, gating,
  the safety rules, and `test/layout_test.dart`.
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

Still unverified:

- **No test has actually been run on hardware.** The link is proven; continuity,
  resistance and insulation runs against a real harness are not.
- **Nothing has been compared side by side with the HTML.** The "On exactly the
  same look" section is still a claim about what the code says. Font resolution
  in particular is unchecked: if `Segoe UI Variable Text` or `Cascadia Mono` do
  not resolve, metrics will be visibly wider than the browser's.

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
