/// Application state: the design's closure variables plus the live protocol
/// layer that drives them.
///
/// Two files fold into this one:
///
///   * the `<script>` block of `gui/htweb/index.html` — the net model, the
///     gating rules in `can()`, `updateControls()`, `resetAll()`,
///     `finishStage1()`, the modals and the log.
///   * `gui/htweb/live.js` — the protocol layer that replaces the design's
///     three simulated run functions with instrument-driven ones.
///
/// In the shipped web GUI `live.js` is always loaded, and `S.setRun(...)`
/// rebinds `runCont` / `runRes` / `runHv` before anything can call them. The
/// design's simulated bodies are therefore dead code in production, and are
/// not ported: [runCont], [runRes] and [runHv] below are the live versions.
///
/// The safety rules from brief 2 and 3.5 are enforced HERE as well as in the
/// firmware, because the GUI must never be the only thing enforcing them:
///
///   - "safe to handle" comes from !SAFE and nothing else. Not from a run
///     ending, not from event ordering, not from silence.
///   - link loss forces "unknown" and disables everything that could
///     energise; it never degrades to "safe".
///   - arming is dropped by any !FIXTURE, any !SAFE, any !STATE idle, and any
///     link trouble.
///   - HV controls are enabled only from the fixture the INSTRUMENT reports.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../design/model.dart';
import '../design/widgets.dart' show PillVariant;
import '../htproto/codec.dart' as proto;
import '../htproto/connection.dart';
import '../htproto/messages.dart' as msg;
import '../htproto/netlist_file.dart';
import 'report.dart';
import 'report_pdf.dart';
import 'run_history.dart';

/// matches PROTO_HV_LIVE_MV in the firmware
const int kHvLiveMv = 50000;

class LogEntry {
  final double t;
  final String lvl;
  final String src;
  final String message;
  const LogEntry(this.t, this.lvl, this.src, this.message);
}

/// One line of raw wire traffic — the exact text `SessionLogger` writes to
/// the session file's `[tx]`/`[rx]` lines, surfaced live instead of read back
/// off disk. `dir` is `'tx'` or `'rx'`.
class WireLogEntry {
  final DateTime t;
  final String dir;
  final String text;
  const WireLogEntry(this.t, this.dir, this.text);
}

class PillState {
  final PillVariant variant;
  final String text;
  const PillState(this.variant, this.text);
}

/// One row of the status-bar port selector — the UI-side twin of `PortInfo`
/// in `htproto/serial_transport.dart`. Defined here so this file (and its
/// tests) never pull in the native serial library; `main.dart` adapts
/// `availableSerialPorts()` to it.
class PortEntry {
  final String name;
  final String description;
  const PortEntry(this.name, this.description);
}

/// `const HV_FILES=[...]`, sized from the generated harness.
// MOCK: three fixed example filenames shown in the HV-netlist picker modal,
// sized only off netc (itself possibly the demo-seed net count). Real file
// browsing exists separately ("Browse the file system…" in modals.dart) -
// this canned list is decoration alongside it, not a real file listing.
List<HvFile> hvFilesFor(int netc) => [
      HvFile('AV-880_HV_3card.hnl', 3, netc, '$netc nets · 3-card map'),
      HvFile('AV-880_HV_4card.hnl', 4, netc + 42,
          '${netc + 42} nets · 4-card map'),
      HvFile('AV-880_HV_1card.hnl', 1, 52, '52 nets · single card'),
    ];

class AppState extends ChangeNotifier {
  // -------------------------------------------------------------------------
  // the design's model
  // -------------------------------------------------------------------------

  // MOCK: buildNets() is a 118-net fake "AV-880" demo harness (design/model.dart).
  // rebuildNets() only replaces it with the real loaded netlist when NETLIST GET
  // returns a non-empty list - and the instrument's netlist is RAM-only, empty on
  // every boot. So on a freshly-connected real instrument this demo harness is
  // what actually drives the wiring diagram, resistance histogram/ranked table
  // and net inspector, even though nlMtx.loaded correctly reads false. Real once
  // a netlist is uploaded; fake by default otherwise. See "GUI Reality Check", cause A.
  List<Net> nets = buildNets();
  late Map<String, Net> netAt = buildNetAt(nets);
  late int netc = nets.length;

  late MtxNetlist nlMtx;
  late HvNetlist nlHv;
  late FixNetlist nlFix; // MOCK: kFix (design/model.dart) - permanently static fixture
  // geometry, no protocol command exists to read it back from the instrument.

  /// HV cards detected on I2C2
  // MOCK: nothing detects this. `stack` is set only by the operator's own Seg
  // control (pickStack/setStack) - there is no protocol field carrying a real
  // I2C2-detected card count, despite the doc comment and the UI text above it.
  int stack = 3;

  /// "net" | "cross"
  String cmode = 'net';

  /// "good" | "bad" — presentational only, per the README
  String scenario = 'good';

  /// null | "cont" | "res" | "insul" | "hv"
  String? running;
  bool onHv = false;

  /// null | "pass" | "fail", keyed cont / res / hv
  final Map<String, String?> R = {'cont': null, 'res': null, 'hv': null};
  final Map<String, bool> faultsOn = {'f06': false, 'f08': false, 'f04': false};

  bool tested = false;
  double? scanX;
  Net? selNet;
  Net? hoverNet;

  /// "all" | "fault" | "conn"
  String filter = 'all';
  String? selConn;

  /// which rail tab is showing
  String view = 'run';

  bool logOpen = false;
  final List<LogEntry> logs = <LogEntry>[];
  double _lt = 0.4;
  String logLineText =
      '[   0.000] INFO  bsp   Board_Init complete — idle state safe';

  /// 'ops' (the human-readable log above) | 'wire' (raw tx/rx traffic).
  /// Independent of [logOpen] — switching tabs while collapsed just changes
  /// what the next expand shows.
  String logView = 'ops';

  /// Raw wire traffic — exactly what `SessionLogger` writes to the session
  /// file, surfaced live. Capped: a heartbeat every 2 s plus every streamed
  /// run event adds up over a full shift, and this is operator-visible
  /// scrollback, not the audit trail — the session file on disk is already
  /// complete and unbounded; this doesn't need to be too.
  static const int wireLogCap = 2000;
  final List<WireLogEntry> wireLog = <WireLogEntry>[];

  final math.Random _rand = math.Random();

  // -- verdict panel --
  String vTitle = 'READY';
  String vSub =
      'Harness on J-MTX. Run continuity and resistance; HV unlocks only after both pass.';
  String vStage = '—';
  String vElapsed = '00.0 s';

  /// `renderFaults()` sets `#vFaults` to the open count, or to "0" while a run
  /// is in flight with none found yet, or to an em dash when idle.
  String get vFaults {
    final n = faultList.length;
    if (n == 0) return running != null ? '0' : '—';
    return '$n';
  }

  // -- fixture sequence --
  String sb1S = 'active';
  PillState sb1Pill = const PillState(PillVariant.idle, 'Ready');
  String sb2S = 'lock';
  PillState sb2Pill = const PillState(PillVariant.idle, 'Locked');
  bool gateArmed = false;

  // -- header --
  String stFix = 'J-MTX · stage 1';
  PillState statePill = const PillState(PillVariant.idle, 'Ready');
  PillState hvPill = const PillState(PillVariant.idle, 'HV Safe');
  PillState hvStatePill = const PillState(PillVariant.idle, 'Safe');
  bool hvLive = false;

  // -- domain cards --
  String dContS = 'idle';
  String dResS = 'idle';
  String dHvS = 'lock';
  String dcN = '—';
  String drN = '—';
  String dhN = '—';
  double dcBar = 0;
  double drBar = 0;
  double dhBar = 0;

  // -- continuity tallies --
  String ctFound = '—';
  String ctMiss = '—';
  String ctExtra = '—';
  String auNets = '—';
  String auNodes = '—';
  String auMulti = '—';
  String auCols = '—';

  // -- HV rail --
  // All six below are REAL, updated live from HvEvent.millivolts (rail) and
  // the last-tested net's !INSUL result (leakage) in paintLink().
  int gRail = 0;
  double gTrack = 0;
  String mLeak = '0.000';
  String mSense = '0.000';
  bool mLeakBad = false;
  String hzRail = '0 V';
  String hzLeak = '0.000 V';

  // -- relays --
  Net? relayNet;
  bool relayLeak = false;

  // -- cross discovery --
  bool saveNlEnabled = false;
  String crossNote =
      'Run cross continuity to build a netlist from the harness itself.';

  // -- modals --
  bool mdNlOpen = false;
  bool mdVerifyOpen = false;
  bool mdMtxOpen = false;
  bool ackChecked = false;

  // -------------------------------------------------------------------------
  // the live layer's instrument state, as told to us
  // -------------------------------------------------------------------------

  bool link = false;
  String linkDetail = 'not connected';
  proto.State? instState;
  proto.Fixture? instFixture;
  int hvMv = 0;
  bool armed = false;

  /// unknown | safe | live — never inferred
  String handling = 'unknown';

  /// A latched fault. The only recovery is `>FAULT CLEAR` (brief §3.2.1,
  /// FW-10) — never automatic, always a deliberate operator action.
  bool get inFault => instState == proto.State.fault;

  String? runKind;
  int doneCount = 0;
  int totalCount = 0;
  msg.LimitsReply? limits;
  msg.CalReply? cal;

  /// From `>ID`, fetched once on connect. Null until then - the status bar
  /// falls back to a "not yet known" label rather than a guessed version.
  String? fwVersion;

  /// Operator-entered, session-scoped (not persisted) — set once on the
  /// status bar, carried into every `required_format` test report generated
  /// after that (see `report.dart`). Both blank by default, same as the
  /// real `required_format` samples' `Operator` field.
  String dutId = '';
  String operatorName = '';

  void setDutId(String v) {
    dutId = v;
    notifyListeners();
  }

  void setOperatorName(String v) {
    operatorName = v;
    notifyListeners();
  }

  final ConnectionManager cm;

  /// where [connect] aims — the COM port name on a serial link, mutable so
  /// the port selector can re-aim it
  String host;

  /// The second half of the target: a TCP port on [TcpTransport], a baud rate
  /// on a serial link. `main.dart` resolves which via `linkPortFor`.
  final int port;

  /// Whether the link is a COM port. False under `--sim` and `--host`, where
  /// the transport is a socket and a port picker would be meaningless — the
  /// status bar hides the dropdown and refresh rather than let the operator
  /// aim a socket at "COM7".
  final bool serialLink;

  /// Enumerates the serial ports for the selector. Injected from `main.dart`,
  /// which adapts `availableSerialPorts()`; the default is "no ports".
  final List<PortEntry> Function() listPorts;

  /// the ports the last [refreshPorts] found
  List<PortEntry> ports = const [];

  /// Opens the native "pick a file" dialog and reads it. Injected from
  /// `main.dart`, which adapts `netlist_picker_io.dart`'s `pickNetlistFile()`
  /// — the same isolation `listPorts` uses to keep the native serial library
  /// out of this file and its tests; here it is `file_picker`'s platform
  /// channel instead. Returns null if the operator cancelled. The default is
  /// "nothing ever picked", for tests that never inject one.
  final Future<(String name, Uint8List bytes)?> Function() pickNetlistFile;

  static Future<(String, Uint8List)?> _noPick() async => null;

  /// GUI-05: where completed runs are recorded — stored on the GUI host, not
  /// the instrument (decided 2026-08-12). Defaults to in-memory only, so the
  /// existing test suite never touches disk unless a test explicitly passes
  /// a real directory. `main.dart` passes `defaultHistoryDir()`.
  final RunHistoryStore history;

  /// Opens the native "save file" dialog for exporting run history to CSV.
  /// Injected the same way as [pickNetlistFile] — keeps `file_picker`'s
  /// platform channel out of this file and its tests. Default is "nothing
  /// ever gets a path", which makes [exportHistoryCsv] a no-op in tests that
  /// never inject one.
  final Future<String?> Function({
    required String dialogTitle,
    required String fileName,
    required List<String> allowedExtensions,
  }) pickSavePath;

  static Future<String?> _noSavePath({
    required String dialogTitle,
    required String fileName,
    required List<String> allowedExtensions,
  }) async =>
      null;

  /// the selector's pending choice, set by [choosePort] and preselected from
  /// `--serial` or the first enumerated port; becomes [host] when [connectTo]
  /// opens the link
  String? selPort;

  /// A connect is in flight. The button reads "Connecting…" and stops
  /// accepting clicks: a second [connect] tears the first one's half-open link
  /// down inside `cm.connect`, so an impatient double-click used to guarantee
  /// the failure it was reacting to.
  bool connecting = false;

  static List<PortEntry> _noPorts() => const [];

  AppState({
    required this.cm,
    required this.host,
    required this.port,
    this.serialLink = true,
    List<PortEntry> Function()? listPorts,
    Future<(String, Uint8List)?> Function()? pickNetlistFile,
    RunHistoryStore? history,
    Future<String?> Function({
      required String dialogTitle,
      required String fileName,
      required List<String> allowedExtensions,
    })? pickSavePath,
  })  : listPorts = listPorts ?? _noPorts,
        pickNetlistFile = pickNetlistFile ?? _noPick,
        history = history ?? RunHistoryStore(),
        pickSavePath = pickSavePath ?? _noSavePath {
    nlMtx = MtxNetlist(
      loaded: true,
      name: 'AV-880_RevC.hnl',
      nets: netc,
      pins: netc * 2 + 8,
      time: clock(),
      origin: 'file',
    );
    nlHv = HvNetlist(loaded: false);
    nlFix = FixNetlist(
      loaded: true,
      name: kFix.name,
      conns: kFix.connectors.length,
      pins: kFixPins,
      time: clock(),
    );

    layoutFixture();
    setStack(3, quiet: true);
    setMode('net', quiet: true);
    resetAll(quiet: true);
    selNet = nets.length > 11 ? nets[11] : null;

    // The design's boot log, before the link says anything.
    _bootLog();
  }

  /// Printed at app startup, before any connection exists - so it can only
  /// state what is actually true at that point (nothing has been scanned or
  /// read from an instrument yet), not describe a bus scan or netlist load
  /// that hasn't happened.
  void _bootLog() {
    log('info', 'app', 'HT_MK1 console started — not yet connected');
  }

  // -------------------------------------------------------------------------
  // log
  // -------------------------------------------------------------------------

  /// `function log(lvl,src,msg)`
  void log(String lvl, String src, String message) {
    _lt += 0.03 + _rand.nextDouble() * 0.4;
    logs.add(LogEntry(_lt, lvl, src, message));
    logLineText = '[${_lt.toStringAsFixed(3).padLeft(8)}] '
        '${lvl.toUpperCase().padRight(4)}  $src   $message';
    notifyListeners();
  }

  void toggleLog() {
    logOpen = !logOpen;
    notifyListeners();
  }

  void setLogView(String v) {
    logView = v;
    notifyListeners();
  }

  /// `ConnectionManager`'s `onWire` — every line sent and every line
  /// received, exactly as the session file records it (brief 3.5.5: every
  /// byte, both directions). This is the operator-visible twin of that file;
  /// it never filters or reformats a line, so what's on screen is provably
  /// what went over the wire.
  void onWire(String direction, String text) {
    wireLog.add(WireLogEntry(DateTime.now(), direction, text));
    if (wireLog.length > wireLogCap) {
      wireLog.removeRange(0, wireLog.length - wireLogCap);
    }
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // netlists
  // -------------------------------------------------------------------------

  /// `function stackMatch()`
  bool stackMatch() => nlHv.loaded && nlHv.cards == stack;

  /// `function hvConnName()`
  String hvConnName() => stack == 1 ? 'J-HV1' : 'J-HV1–$stack';

  /// `function loadMtx(name,origin)`
  void loadMtx(String name, String origin) {
    nlMtx = MtxNetlist(
      loaded: true,
      name: name,
      nets: netc,
      pins: netc * 2 + 8,
      time: clock(),
      origin: origin,
    );
    log('ok', 'prog',
        'MTX netlist loaded: $name — $netc nets. Bound to continuity and resistance.');
    updateControls();
  }

  /// `function loadHv(name,cards,nets)`
  void loadHv(String name, int cards, int netCount) {
    nlHv = HvNetlist(
        loaded: true, name: name, cards: cards, nets: netCount, time: clock());
    log('ok', 'prog',
        'HV netlist loaded: $name — $netCount nets, $cards-card map.');
    if (!stackMatch()) {
      log('warn', 'prog',
          'HV netlist declares $cards cards, $stack fitted — ${(cards - stack) * 64} nets unreachable');
    }
    updateControls();
  }

  void unloadNetlist(String which) {
    if (which == 'mtx') {
      nlMtx.loaded = false;
      log('warn', 'prog',
          'MTX netlist unloaded — netlist continuity and resistance blocked');
    } else {
      nlHv.loaded = false;
      log('warn', 'prog', 'HV netlist unloaded — HV test blocked');
    }
    updateControls();
  }

  // -------------------------------------------------------------------------
  // HV stack
  // -------------------------------------------------------------------------

  /// `function setStack(n)`
  void setStack(int n, {bool quiet = false}) {
    stack = n;
    setRelays(null);
    if (!quiet) {
      updateControls();
    }
  }

  void pickStack(int n) {
    setStack(n);
    log('info', 'bsp', 'I2C2 rescan — $stack-card HV stack detected');
  }

  // -------------------------------------------------------------------------
  // continuity mode
  // -------------------------------------------------------------------------

  /// `function setMode(m)`
  void setMode(String m, {bool quiet = false}) {
    cmode = m;
    if (!quiet) updateControls();
  }

  String get scScope =>
      cmode == 'net' ? '624 reads · est 3 s' : '65,536 reads · est 18 s @ 400 kHz';

  String get mxHint => cmode == 'net'
      ? 'click a cell to inspect the pair'
      : 'one HS energised at a time, all 256 LS read';

  /// `$("#dcCond")`
  String get dcCond => cmode == 'net'
      ? 'Netlist mode · ${nlMtx.loaded ? nlMtx.nets : "—"} pairs\n'
          '3.3 V · AD7476 U4 · SPI3\nOPTO_CNTR = LOW'
      : 'Cross continuity · 65,536 reads\n3.3 V · AD7476 U4 · SPI3\n'
          'one to many discovery';

  /// `$("#dcU")`
  String get dcU => cmode == 'net'
      ? 'of ${nlMtx.loaded ? nlMtx.nets : "—"} verified'
      : 'nets discovered';

  /// `$("#dhCond")`
  String get dhCond => '500 V DC · MHV05 reed\nAD7476 U302 · SPI2-iso\n'
      'own netlist · $stack-card stack';

  // -------------------------------------------------------------------------
  // relays
  // -------------------------------------------------------------------------

  /// `function setRelays(net,leak)`
  void setRelays(Net? net, [bool leak = false]) {
    relayNet = net;
    relayLeak = leak;
  }

  /// `$("#hvNetLbl")`
  String get hvNetLbl {
    final net = relayNet;
    if (net == null) return 'idle — all relays open';
    var closed = 0;
    for (var ci = 0; ci < stack; ci++) {
      for (var i = 0; i < 64; i++) {
        if (ci == net.card && i == net.relay) continue;
        closed++;
      }
    }
    return 'H${net.card + 1} HS-${pad(net.relay, 2)}  ·  ${net.name}  ·  '
        '$closed LS closed, own return open';
  }

  /// The class `setRelays` puts on one cell.
  /// "" | "closed" | "src" | "leak" | "absent"
  String relayCell({required bool low, required int card, required int index}) {
    if (card >= stack) return 'absent';
    final net = relayNet;
    if (net == null) return '';
    if (!low) {
      return (card == net.card && index == net.relay) ? 'src' : '';
    }
    if (card == net.card && index == net.relay) return '';
    return (relayLeak && card == 0 && index == 22) ? 'leak' : 'closed';
  }

  // -------------------------------------------------------------------------
  // gating — `function can(test)`
  // -------------------------------------------------------------------------

  (bool, String) can(String test) {
    if (running != null) return (false, 'A test is already running');
    if (test == 'cont') {
      if (onHv) {
        return (false, 'Harness is on J-HV — reset to return it to J-MTX');
      }
      if (cmode == 'net' && !nlMtx.loaded) {
        return (
          false,
          'Netlist mode needs the MTX netlist — or switch to cross continuity'
        );
      }
      return (true, '');
    }
    if (test == 'res') {
      if (onHv) {
        return (false, 'Harness is on J-HV — reset to return it to J-MTX');
      }
      if (!nlMtx.loaded) {
        return (
          false,
          'Resistance needs the MTX netlist for the pair list and limits'
        );
      }
      return (true, '');
    }
    if (test == 'hv') {
      if (!onHv) {
        return R['cont'] == 'pass' && R['res'] == 'pass'
            ? (false, 'Confirm the harness has been moved to J-HV first')
            : (false, 'Continuity and resistance must pass before HV unlocks');
      }
      // the HV netlist is requested by the run flow, not blocked here
      return (true, '');
    }
    return (false, '');
  }

  // -- derived control state, from `updateControls()` --

  PillState pillFor(String t) {
    if (running == t || (t == 'hv' && running == 'insul')) {
      return const PillState(PillVariant.acc, 'Running');
    }
    return switch (R[t]) {
      'pass' => const PillState(PillVariant.ok, 'Pass'),
      'fail' => const PillState(PillVariant.bad, 'Fail'),
      _ => const PillState(PillVariant.idle, 'Not run'),
    };
  }

  String get cvWhy {
    final why = can('cont').$2;
    if (why.isNotEmpty) return why;
    return cmode == 'net'
        ? "verifies the netlist's expected pairs"
        : 'builds a netlist from the harness';
  }

  String get rvWhy {
    final why = can('res').$2;
    return why.isNotEmpty ? why : 'measures the pairs the netlist declares';
  }

  /// `.rail button` badge class: null | "st-pass" | "st-fail" | "st-lock"
  String? railBadge(String t) {
    if (R[t] == 'pass') return 'st-pass';
    if (R[t] == 'fail') return 'st-fail';
    if (t == 'hv' && !onHv) return 'st-lock';
    return null;
  }

  /// `body.dataset.stage2`
  String get stage2 => onHv ? 'open' : 'lock';

  /// The big action button: label, hint, and which style.
  ({String label, String hint, bool disabled, String style}) get actButton {
    if (running != null) {
      return (label: 'Stop', hint: 'Esc', disabled: false, style: 'stop');
    }
    if (!onHv && R['cont'] == 'pass' && R['res'] == 'pass') {
      return (
        label: 'Move DUT',
        hint: 'see below',
        disabled: true,
        style: 'normal'
      );
    }
    if (onHv && R['hv'] == null) {
      return (label: 'Run HV', hint: '500 V', disabled: false, style: 'hv');
    }
    if (R['cont'] == null && R['res'] == null) {
      return (label: 'Run S1', hint: 'F5', disabled: false, style: 'normal');
    }
    return (label: 'Reset', hint: 'Esc', disabled: false, style: 'normal');
  }

  /// `body.dataset.phase`
  String get phase {
    final doneS1 =
        running == null && !onHv && R['cont'] == 'pass' && R['res'] == 'pass';
    final anyFail =
        R['cont'] == 'fail' || R['res'] == 'fail' || R['hv'] == 'fail';
    if (running != null) return 'running';
    if (doneS1) return 'hold';
    if (onHv && R['hv'] == null) return 'armed';
    if (anyFail) return 'fail';
    if (R['hv'] == 'pass') return 'pass';
    return '';
  }

  void updateControls() => notifyListeners();

  // -------------------------------------------------------------------------
  // views and selection
  // -------------------------------------------------------------------------

  /// `function go(v)`
  void go(String v) {
    view = v;
    notifyListeners();
  }

  /// The MTX netbar's "Select…"/"Change…". Opens [MtxNetlistModal], which
  /// offers both ways to give the instrument an MTX netlist: browse a real
  /// file ([browseMtxNetlist]), or build one from the harness itself with
  /// cross-continuity + "Save as MTX netlist" (`confirmGoToBuildMtxNetlist`
  /// routes there).
  ///
  /// Used to jump straight to cross mode with only a log-panel line
  /// explaining why (`AppState.log`, collapsed by default) — from the
  /// operator's side that read as "I clicked Select… and nothing happened."
  /// The modal fixes that by explaining the two options up front instead of
  /// silently navigating.
  void openMtxNlExplainer() {
    mdMtxOpen = true;
    notifyListeners();
  }

  void confirmGoToBuildMtxNetlist() {
    mdMtxOpen = false;
    setMode('cross', quiet: true);
    go('cont');
    log('info', 'nl',
        'switched to cross continuity — run it, then Save as MTX netlist');
  }

  /// [MtxNetlistModal]'s "Browse for a netlist file…" — reads real (hi, lo)
  /// pin pairs from an Excel netlist and uploads them exactly the way
  /// [saveDiscoveredNetlist] does for a cross-continuity scan, just sourced
  /// from a file instead of a 256-pin sweep. Operators who already have a
  /// netlist spreadsheet from the harness design should not have to run
  /// discovery to get the instrument one.
  Future<void> browseMtxNetlist() async {
    final picked = await pickNetlistFile();
    if (picked == null) return; // operator cancelled
    final (name, bytes) = picked;
    final ParsedNetlist parsed;
    try {
      parsed = parseNetlistWorkbook(bytes, fileName: name);
    } on NetlistFileFormatException catch (exc) {
      log('fail', 'nl', 'could not read $name — $exc');
      return;
    }
    mdMtxOpen = false;
    // GUI-11: if the file had Conn ID/Part Number columns, apply the
    // guessed connector layout immediately (so the wiring diagram/tables
    // reflect it right away) and open the confirmation panel so the
    // operator can fix a wrong shape guess or a pin count that came up
    // short (see _fixtureFromGuess) before relying on it. Remembers the
    // previous fixture so cancelling reverts cleanly.
    final guess = parsed.fixture;
    if (guess != null && guess.isNotEmpty) {
      fixtureBeforeGuess = kFix;
      setActiveFixture(_fixtureFromGuess(guess, parsed.pairs));
      mdFixtureOpen = true;
      log('info', 'nl',
          'connector layout guessed from $name — ${guess.length} connectors, review before running');
    }
    await _uploadNetlistPairs(
      [for (final p in parsed.pairs) (p.hi, p.lo)],
      name: name,
      origin: 'file',
    );
  }

  /// Builds a real [FixtureDef] from a netlist file's guessed connector
  /// layout ([GuessedConnector], `netlist_file.dart`) — translates the
  /// file-parsing layer's plain-string shape guess into a real [ConnType]
  /// (that layer stays independent of `design/model.dart`, same as the
  /// rest of `htproto/`), and extends the last connector to cover every
  /// pin the netlist itself references even if `Conn ID` was blank on some
  /// rows or a connector's trailing pins were never wired (e.g.
  /// `required_format`'s own sample only wires 6 of DB9's real 9 pins) —
  /// every pin the uploaded netlist can reference must resolve to some
  /// connector, not just the ones a guess happened to observe.
  FixtureDef _fixtureFromGuess(
      List<GuessedConnector> guess, List<ParsedNetPair> pairs) {
    final maxPin =
        pairs.fold<int>(0, (m, p) => math.max(m, math.max(p.hi, p.lo)));
    final connectors = <ConnectorDef>[];
    var base = 0;
    // List-half, not alternating - see buildFixture()'s note in
    // design/model.dart on why alternating can badly unbalance the two
    // sides' pin totals.
    final leftCount = (guess.length / 2).ceil();
    for (var i = 0; i < guess.length; i++) {
      final g = guess[i];
      final isLast = i == guess.length - 1;
      final pins = isLast ? math.max(g.pins, maxPin - base) : g.pins;
      connectors.add(ConnectorDef(
        id: g.id,
        label: g.partNumber.isEmpty ? g.id : g.partNumber,
        type: switch (g.shapeGuess) {
          'dsub' => ConnType.dsub,
          'circ' => ConnType.circ,
          _ => ConnType.rect,
        },
        pins: pins,
        side: i < leftCount ? 'L' : 'R',
        base: base,
      ));
      base += pins;
    }
    return FixtureDef(
        name: 'guessed from netlist', rev: '—', connectors: connectors);
  }

  /// The fixture that was active right before a netlist-derived guess was
  /// applied ([browseMtxNetlist]) — restored by [cancelFixtureGuess]. Null
  /// once there is nothing to revert to (no guess pending).
  FixtureDef? fixtureBeforeGuess;
  bool mdFixtureOpen = false;

  /// The connector-layout confirmation panel's "Apply" — the operator may
  /// have edited shape/label (pin counts/ids/bases stay fixed, they come
  /// from the netlist itself, not from operator guesswork).
  void confirmFixtureGuess(List<ConnectorDef> edited) {
    setActiveFixture(
        FixtureDef(name: kFix.name, rev: kFix.rev, connectors: edited));
    mdFixtureOpen = false;
    fixtureBeforeGuess = null;
    notifyListeners();
  }

  /// The connector-layout confirmation panel's "Cancel" — reverts to
  /// whatever fixture was active before the guess.
  void cancelFixtureGuess() {
    final prev = fixtureBeforeGuess;
    if (prev != null) setActiveFixture(prev);
    mdFixtureOpen = false;
    fixtureBeforeGuess = null;
    notifyListeners();
  }

  void setFilter(String f) {
    filter = f;
    notifyListeners();
  }

  void toggleConn(String id) {
    selConn = selConn == id ? null : id;
    notifyListeners();
  }

  void setHover(Net? n) {
    if (!identical(n, hoverNet)) {
      hoverNet = n;
      notifyListeners();
    }
  }

  void select(Net? n) {
    selNet = n;
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // faults — `const ALL` and `renderFaults()`
  // -------------------------------------------------------------------------

  // MOCK (partially): faultsOn['f06'/'f08'/'f04'] are real - only set when
  // _onCont/_onRes/_onInsul actually see a failure - so this panel correctly
  // stays empty on a clean run. But every displayed detail below is fabricated:
  // always nets[4]/nets[5]/nets[2] by fixed index, and fixed values ('3.281 V',
  // '4.812 Ω', '3.2 MΩ') regardless of which net actually failed or what its
  // real measured value was. See "GUI Reality Check", cause A.
  List<({String code, String title, String detail, String value, bool hot, String go, int net})>
      get faultList {
    final out = <({
      String code,
      String title,
      String detail,
      String value,
      bool hot,
      String go,
      int net
    })>[];
    if (faultsOn['f06']! && nets.length > 4) {
      out.add((
        code: 'F06',
        title: 'Open circuit',
        detail:
            'Continuity · ${nets[4].name} · ${refOf(nets[4].src)} → ${refOf(nets[4].dsts[0])}',
        value: '3.281 V',
        hot: false,
        go: 'cont',
        net: 4,
      ));
    }
    if (faultsOn['f08']! && nets.length > 5) {
      out.add((
        code: 'F08',
        title: 'Resistance high',
        detail: 'Resistance · ${nets[5].name} · limit 2.000 Ω',
        value: '4.812 Ω',
        hot: false,
        go: 'res',
        net: 5,
      ));
    }
    if (faultsOn['f04']! && nets.length > 2) {
      out.add((
        code: 'F04',
        title: 'Insulation below limit',
        detail: 'HV · H1 HS-02 · ${nets[2].name} · 500 V',
        value: '3.2 MΩ',
        hot: true,
        go: 'hv',
        net: 2,
      ));
    }
    return out;
  }

  PillState get faultCountPill {
    final n = faultList.length;
    return n == 0
        ? const PillState(PillVariant.idle, '0 open')
        : PillState(PillVariant.bad, '$n open');
  }

  /// The `#faultList` click handler.
  void openFault(int index) {
    final list = faultList;
    if (index >= list.length) return;
    final f = list[index];
    final n = nets[f.net];
    if (f.go == 'hv' && !onHv) return;
    go(f.go);
    if (f.go == 'cont') {
      selNet = n;
      selConn = null;
      filter = 'fault';
    }
    if (f.go == 'hv') setRelays(n, true);
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // reset — `function resetAll()`
  // -------------------------------------------------------------------------

  void resetAll({bool quiet = false}) {
    running = null;
    onHv = false;
    scanX = null;
    tested = false;
    selNet = null;
    hoverNet = null;
    R['cont'] = R['res'] = R['hv'] = null;
    faultsOn['f06'] = faultsOn['f08'] = faultsOn['f04'] = false;
    hvLive = false;
    mdNlOpen = false;
    mdVerifyOpen = false;
    mdMtxOpen = false;
    ackChecked = false;

    sb1S = 'active';
    sb1Pill = const PillState(PillVariant.idle, 'Ready');
    sb2S = 'lock';
    sb2Pill = const PillState(PillVariant.idle, 'Locked');
    gateArmed = false;
    stFix = 'J-MTX · stage 1';

    dContS = 'idle';
    dResS = 'idle';
    dHvS = 'lock';
    dcBar = drBar = dhBar = 0;
    dcN = drN = dhN = '—';
    ctFound = ctMiss = ctExtra = '—';
    auNets = auNodes = auMulti = auCols = '—';

    statePill = const PillState(PillVariant.idle, 'Ready');
    hvPill = const PillState(PillVariant.idle, 'HV Safe');
    hvStatePill = const PillState(PillVariant.idle, 'Safe');
    gRail = 0;
    gTrack = 0;
    mLeak = '0.000';
    mSense = '0.000';
    mLeakBad = false;
    saveNlEnabled = false;
    _discovered.clear();
    crossNote =
        'Run cross continuity to build a netlist from the harness itself.';

    setRelays(null);
    verdictIdle();
    if (!quiet) notifyListeners();
  }

  /// `function verdictIdle()`
  void verdictIdle() {
    vTitle = 'READY';
    vSub =
        'Harness on J-MTX. Run continuity and resistance; HV unlocks only after both pass.';
    vStage = '—';
    vElapsed = '00.0 s';
  }

  // -------------------------------------------------------------------------
  // stage 1 completion — `function finishStage1()`
  // -------------------------------------------------------------------------

  String hoText =
      'Continuity and resistance passed on J-MTX. Unplug from J-MTX, then plug into J-HV.';

  void finishStage1() {
    final pass = R['cont'] == 'pass' && R['res'] == 'pass';
    final fail = R['cont'] == 'fail' || R['res'] == 'fail';
    if (fail) {
      sb1S = 'fail';
      sb1Pill = const PillState(PillVariant.bad, 'Fail');
      vTitle = 'FAIL';
      vSub =
          'Stage 1 failed on J-MTX. The harness stays where it is — HV is not attempted.';
      statePill = const PillState(PillVariant.bad, 'Fail');
    } else if (pass) {
      sb1S = 'pass';
      sb1Pill = const PillState(PillVariant.ok, 'Pass');
      gateArmed = true;
      sb2S = 'active';
      sb2Pill = const PillState(PillVariant.warn, 'Awaiting DUT');
      vTitle = 'MOVE DUT';
      vStage = 'handover';
      vSub =
          'Continuity and resistance passed on J-MTX. Move the harness to the HV fixture.';
      statePill = const PillState(PillVariant.warn, 'Handover');
      stFix = 'none · moving';
      hoText =
          'Continuity and resistance passed on J-MTX. Unplug from J-MTX, then plug into ${hvConnName()}.';
      log('ok', 'seq', 'stage 1 PASS — awaiting DUT transfer to ${hvConnName()}');
    } else {
      sb1Pill = const PillState(PillVariant.acc, 'Partial');
      vTitle = 'PARTIAL';
      vStage = '—';
      vSub =
          '${R['cont'] == null ? "Continuity" : "Resistance"} has not run yet. Both must pass before HV unlocks.';
      statePill = const PillState(PillVariant.idle, 'Idle');
    }
    updateControls();
  }

  /// `$("#hoConfirm")` — the design's handler. The live layer's handler runs
  /// first, in the capture phase, and sends `FIXTURE hv`.
  Future<void> confirmHandover() async {
    // live.js: cmd("FIXTURE hv").then(res => reportRefusal("fixture hv", res))
    final res = await _cmd(proto.commands.fixture(proto.Fixture.hv));
    _reportRefusal('fixture hv', res);

    // index.html's own handler, on the bubble phase.
    onHv = true;
    sb2Pill = const PillState(PillVariant.warn, 'Armed');
    sb1Pill = const PillState(PillVariant.idle, 'Released');
    stFix = '${hvConnName()} · stage 2';
    dHvS = 'idle';
    vTitle = 'ARMED';
    vStage = 'HV ready';
    vSub =
        'Harness on ${hvConnName()}. Press Run HV — you will be asked to confirm before 500 V is applied.';
    statePill = const PillState(PillVariant.warn, 'Armed');
    log('info', 'fix',
        'DUT transferred to ${hvConnName()} — HV armed, interlock closed');
    updateControls();
  }

  // -------------------------------------------------------------------------
  // MODALS
  //
  // Starting HV always walks two prompts:
  //   1. select the HV netlist — only when one is not already loaded
  //   2. verify this is the harness that passed on J-MTX — always
  // -------------------------------------------------------------------------

  /// `function requestHv()`
  void requestHv() {
    if (!nlHv.loaded) {
      openNlPicker();
      return;
    }
    openVerify();
  }

  /// `function openNlPicker()`
  void openNlPicker() {
    log('warn', 'seq',
        'HV start blocked — no HV netlist loaded, prompting operator');
    mdNlOpen = true;
    notifyListeners();
  }

  void pickHvFile(HvFile f) {
    loadHv(f.name, f.cards, f.nets);
    mdNlOpen = false;
    openVerify();
  }

  /// The HV netlist modal's "Browse the file system…" — a real file, parsed
  /// for real, instead of only ever picking from [hvFilesFor]'s three canned
  /// entries. There is no wire command for "load an HV netlist" (unlike MTX,
  /// nothing here is uploaded to the instrument — see [MtxNetlistModal] and
  /// `_uploadNetlistPairs`); this only ever sets the same name/cards/nets
  /// metadata [pickHvFile] does, sourced from the file instead of a canned
  /// list.
  Future<void> browseHvNetlist() async {
    final picked = await pickNetlistFile();
    if (picked == null) return; // operator cancelled
    final (name, bytes) = picked;
    final ParsedNetlist parsed;
    try {
      parsed = parseNetlistWorkbook(bytes, fileName: name);
    } on NetlistFileFormatException catch (exc) {
      log('fail', 'nl', 'could not read $name — $exc');
      return;
    }
    loadHv(name, parsed.cards ?? stack, parsed.pairs.length);
    mdNlOpen = false;
    openVerify();
  }

  /// `function openVerify()`
  void openVerify() {
    ackChecked = false;
    mdVerifyOpen = true;
    log('info', 'seq',
        'HV pre-start verification shown — awaiting operator acknowledgement');
    notifyListeners();
  }

  /// The five rows of `#mdVChecks`.
  // PARTIAL/MOCK: rows 1, 2 and 4's `state`/`value` are real (R['cont'],
  // R['res'], stackMatch()) - but row 2's `detail` ("worst margin +0.09 Ω ·
  // 1.84 mA excitation") is a fixed literal, not the real worst-margin net or
  // current (and 1.84 mA is stale besides - the IDAC forces a fixed 2 mA,
  // FW-12). Rows 3 and 5 ("Harness moved…confirmed", "Interlock closed…safe")
  // are unconditional `state: 'ok'` literals - nothing is actually checked
  // for either; row 3 in particular claims a transfer that was never verified.
  List<({String state, String title, String detail, String value})>
      get verifyChecks => [
            (
              state: R['cont'] == 'pass' ? 'ok' : 'bad',
              title: 'Continuity passed on J-MTX',
              detail:
                  '${nlMtx.name} · ${cmode == "net" ? "netlist mode" : "cross mode"}',
              value: R['cont'] == 'pass' ? '$netc / $netc' : 'not passed',
            ),
            (
              state: R['res'] == 'pass' ? 'ok' : 'bad',
              title: 'Resistance passed on J-MTX',
              detail: 'worst margin +0.09 Ω · 1.84 mA excitation',
              value: R['res'] == 'pass' ? '0 out of limit' : 'not passed',
            ),
            (
              // Real: onHv reflects the instrument's own !FIXTURE report
              // (or the optimistic set right after `FIXTURE hv` is sent -
              // see requestHv()), not just an operator claim.
              state: onHv ? 'ok' : 'warn',
              title: 'Harness moved to ${hvConnName()}',
              detail: onHv
                  ? 'instrument reports fixture = hv'
                  : 'instrument has not confirmed the harness moved',
              value: onHv ? 'confirmed' : 'not confirmed',
            ),
            (
              state: stackMatch() ? 'ok' : 'warn',
              title: 'HV netlist matches the stack',
              detail:
                  '${nlHv.name} · ${nlHv.cards}-card map · $stack fitted',
              value: stackMatch()
                  ? 'match'
                  : '${(nlHv.cards - stack) * 64} nets unreachable',
            ),
            (
              // No protocol field reports interlock state at all - honestly
              // unverified rather than an unconditional "safe".
              state: 'warn',
              title: 'Interlock closed',
              detail: 'not reported by the instrument - unverified',
              value: 'unverified',
            ),
          ];

  void setAck(bool v) {
    ackChecked = v;
    notifyListeners();
  }

  /// `$("#mdVGo")`
  void confirmEnergize() {
    mdVerifyOpen = false;
    log('ok', 'seq',
        'operator acknowledged HV pre-start checks — energizing');
    runHv();
  }

  void cancelModals() {
    mdNlOpen = false;
    mdVerifyOpen = false;
    log('info', 'seq', 'HV start cancelled by operator');
    notifyListeners();
  }

  void closeMtxNlExplainer() {
    mdMtxOpen = false;
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // LIVE LAYER — transport
  // -------------------------------------------------------------------------

  /// `function post({action:"send", cmd})` -> `{ok, reply}` / `{ok:false, error}`
  Future<({bool ok, msg.Message? reply, String? error})> _cmd(
      Uint8List wire) async {
    try {
      final reply = await cm.execute(wire);
      return (ok: true, reply: reply, error: null);
    } on proto.ProtocolError catch (exc) {
      return (ok: false, reply: null, error: 'protocol error: $exc');
    } on Object catch (exc) {
      // Timeouts and link loss land here; the page shows them and stops.
      return (ok: false, reply: null, error: '${exc.runtimeType}: $exc');
    }
  }

  /// `function reportRefusal(what, res)`
  bool _reportRefusal(
      String what, ({bool ok, msg.Message? reply, String? error}) res) {
    if (!res.ok) {
      log('fail', 'link', '$what - ${res.error}');
      return true;
    }
    final reply = res.reply;
    if (reply is msg.ErrReply) {
      // Never retry automatically: a refusal is the instrument's decision.
      log('fail', 'seq', '$what refused - ${reply.code} ${reply.text}');
      return true;
    }
    return false;
  }

  /// `function paintLink()`
  void paintLink() {
    if (!link) {
      hvPill = const PillState(PillVariant.warn, 'Link lost');
      statePill = const PillState(PillVariant.warn, 'State unknown');
      stFix = 'link lost';
      hvLive = false;
      notifyListeners();
      return;
    }
    final live = hvMv >= kHvLiveMv;
    hvLive = live;
    if (live) {
      hvPill = PillState(
          PillVariant.bad, 'HV LIVE ${(hvMv / 1000).toStringAsFixed(0)} V');
    } else if (armed) {
      hvPill = const PillState(PillVariant.warn, 'HV armed');
    } else if (handling == 'safe') {
      hvPill = const PillState(PillVariant.ok, 'HV Safe');
    } else {
      hvPill = const PillState(PillVariant.idle, 'HV state unknown');
    }

    final lbl = runKind ?? (instState?.wire ?? 'idle');
    statePill = PillState(
      // A latched fault must never read as a neutral "Idle" grey — it is the
      // one state that blocks every run until the operator clears it.
      inFault
          ? PillVariant.bad
          : runKind != null
              ? PillVariant.acc
              : PillVariant.idle,
      lbl[0].toUpperCase() + lbl.substring(1),
    );
    stFix = instFixture == proto.Fixture.hv
        ? 'J-HV · stage 2'
        : instFixture == proto.Fixture.mtx
            ? 'J-MTX · stage 1'
            : 'no fixture declared';
    hzRail = '${(hvMv / 1000).toStringAsFixed(0)} V';
    final railVolts = hvMv / 1000.0;
    gRail = (hvMv / 1000).round();
    // HV_Sense ADC (U301) reads the rail through the R3002/R3004 divider -
    // same 0.00049 ratio the meter's own "range" label already documents
    // (res_hv_views.dart _HvRailPanel), just not applied to a live value
    // until now.
    mSense = (railVolts * 0.00049).toStringAsFixed(3);
    // Leakage ADC (U302) sits across R3004 in that same divider, in series
    // with whatever insulation resistance the harness presents - real once a
    // real net has actually been tested (relayNet is set from a live
    // !INSUL result by _onInsul); 0 V with nothing under test, same as the
    // idle state before this fix.
    final leakVolts = _leakVoltsFor(relayNet?.ins);
    mLeak = leakVolts.toStringAsFixed(3);
    mLeakBad = leakVolts >= 0.045;
    hzLeak = '$mLeak V';
    notifyListeners();
  }

  /// Leakage ADC (U302) estimate for a net with the given insulation
  /// resistance, at the current live rail voltage - see the note on `mLeak`
  /// in `paintLink()`. Shared with the per-net report rows in `_onInsul` so
  /// the report and the live meter never disagree on the formula.
  double _leakVoltsFor(double? insMohm) {
    final railVolts = hvMv / 1000.0;
    if (railVolts <= 0 || insMohm == null || insMohm <= 0) return 0.0;
    const r3002Ohm = 1.0e6, r3004Ohm = 1.0e3;
    return railVolts * r3004Ohm / (r3002Ohm + insMohm * 1.0e6 + r3004Ohm);
  }

  // -------------------------------------------------------------------------
  // LIVE LAYER — the three runs, driven by the instrument
  // -------------------------------------------------------------------------

  /// `function beginRun(kind, domSel, label, sub)`
  void _beginRun(String kind, String domSel, String label, String sub) {
    running = kind;
    runKind = kind;
    doneCount = 0;
    totalCount = 0;
    R[kind == 'insul' ? 'hv' : kind] = null;
    switch (kind) {
      case 'cont':
        _contRows.clear();
      case 'res':
        _resRows.clear();
      case 'insul':
        _insulRows.clear();
    }
    _setDom(domSel, 'run');
    vTitle = 'RUNNING';
    vStage = label;
    vSub = sub;
    sb1S = 'active';
    updateControls();
    paintLink();
  }

  void _setDom(String id, String s) {
    switch (id) {
      case 'dCont':
        dContS = s;
        break;
      case 'dRes':
        dResS = s;
        break;
      case 'dHv':
        dHvS = s;
        break;
    }
  }

  /// `function startRun(kind, wire, domSel, label, sub)`
  Future<void> _startRun(String kind, Uint8List wire, String domSel,
      String label, String sub) async {
    // Never mark a run started until the instrument has accepted it.
    final res = await _cmd(wire);
    if (_reportRefusal(label, res)) {
      running = null;
      updateControls();
      return;
    }
    _beginRun(kind, domSel, label, sub);
    log('info', kind, '$label started');
  }

  /// `function runCont()`
  Future<void> runCont() async {
    final cross = cmode == 'cross';
    if (cross) {
      // A fresh scan replaces whatever the last one found; the operator must
      // re-save before a new discovery counts as "the" netlist.
      _discovered.clear();
      saveNlEnabled = false;
      auNets = auNodes = auMulti = auCols = '0';
    }
    await _startRun(
      'cont',
      proto.commands
          .contRun(cross ? proto.ContMode.discover : proto.ContMode.verify),
      'dCont',
      'Continuity · J-MTX',
      cross
          ? 'J-MTX — energising one HS at a time and reading all 256 LS.'
          : 'J-MTX — testing the pairs the netlist expects.',
    );
  }

  /// `function runRes()`
  Future<void> runRes() async {
    await _startRun(
      'res',
      proto.commands.resRun(),
      'dRes',
      'Resistance · J-MTX',
      'J-MTX — measuring every pair the netlist declares.',
    );
  }

  /// `function runHv()` — arming is a separate, explicit step and the
  /// instrument enforces it too.
  Future<void> runHv() async {
    final res = await _cmd(proto.commands.insulArm());
    if (_reportRefusal('arm', res)) return;
    armed = true;
    paintLink();
    await _startRun(
      'insul',
      proto.commands.insulRun(),
      'dHv',
      'Insulation · J-HV',
      'J-HV — 500 V across each net in turn.',
    );
  }

  // -------------------------------------------------------------------------
  // LIVE LAYER — results
  // -------------------------------------------------------------------------

  int _countPass = 0;
  int _countFail = 0;

  /// Per-row detail for the report the current (or just-finished) run would
  /// produce — see `report.dart`. Cleared at the start of each run
  /// (`_beginRun`), snapshotted into `lastXReport` at `_onDone`. Not
  /// persisted: a report is a live-generated artifact of the run that just
  /// finished, not part of run history.
  final List<ContReportRow> _contRows = [];
  final List<ResReportRow> _resRows = [];
  final List<InsulReportRow> _insulRows = [];

  /// Read-only views onto the accumulating row buffers, for the on-screen
  /// connection-results tables (GUI-11) — unlike `lastXReport`, these fill
  /// in live while a run is still executing, not only once `!DONE` snapshots
  /// them.
  List<ContReportRow> get contRowsLive => List.unmodifiable(_contRows);
  List<ResReportRow> get resRowsLive => List.unmodifiable(_resRows);
  List<InsulReportRow> get insulRowsLive => List.unmodifiable(_insulRows);

  ContReport? lastContReport;
  ResReport? lastResReport;
  InsulReport? lastInsulReport;

  /// Pairs found by the current (or last completed) cross-continuity scan —
  /// only ever the passing ones. The real firmware's discover loop already
  /// only emits `!CONT ... pass` (it does not walk 65,536 points to report
  /// what ISN'T there), but the simulator's is more literal and also emits
  /// `open`/`short` for its scripted-fault scenarios, so the filter is
  /// enforced here rather than assumed from the source.
  final List<(int hi, int lo)> _discovered = [];

  void _updateDiscoveryTallies() {
    auNets = '${_discovered.length}';
    final nodes = <int>{};
    final byHi = <int, int>{};
    for (final p in _discovered) {
      nodes.add(p.$1);
      nodes.add(p.$2);
      byHi[p.$1] = (byHi[p.$1] ?? 0) + 1;
    }
    auNodes = '${nodes.length}';
    auMulti = '${byHi.values.where((c) => c > 1).length}';
  }

  /// `function netByPins(hi, lo)`
  Net? _netByPins(int hi, int lo) {
    for (final n in nets) {
      if (n.pinHi == hi && n.pinLo == lo) return n;
    }
    return null;
  }

  /// `!INSUL <net> ...` carries only the pin under test (see Proto_EvtInsul,
  /// tasks.c) - no return pin, unlike `!CONT`/`!RES`.
  Net? _netByHiPin(int hi) {
    for (final n in nets) {
      if (n.pinHi == hi) return n;
    }
    return null;
  }

  void _onCont(msg.ContResult m) {
    final n = _netByPins(m.hi, m.lo);
    if (n != null) n.open = m.status != proto.ContStatus.pass;
    final pass = m.status == proto.ContStatus.pass;
    if (pass) {
      _countPass++;
    } else {
      _countFail++;
    }
    dcN = '$_countPass';
    ctFound = '$_countPass';
    ctMiss = '$_countFail';
    if (_countFail > 0) faultsOn['f06'] = true;
    if (runKind == 'cont' && cmode == 'cross' && pass) {
      _discovered.add((m.hi, m.lo));
      _updateDiscoveryTallies();
    }
    if (runKind == 'cont' && cmode == 'net') {
      _contRows.add(ContReportRow(
        testNum: _contRows.length + 1,
        srcPin: m.hi,
        dstPin: m.lo,
        status: pass ? 'CONNECTED' : 'NOT CONNECTED',
        srcConnId: n?.src.c ?? '—',
        srcPinLabel: n == null ? null : 'Pin ${n.src.p}',
        dstConnId: n?.dsts[0].c ?? '—',
        dstPinLabel: n == null ? null : 'Pin ${n.dsts[0].p}',
      ));
    }
    notifyListeners();
  }

  void _onRes(msg.ResResult m) {
    final n = _netByPins(m.hi, m.lo);
    if (n != null) n.r = m.milliohms / 1000.0;
    if (m.status == proto.ResStatus.pass) {
      _countPass++;
    } else {
      _countFail++;
    }
    drN = '$_countFail';
    if (_countFail > 0) faultsOn['f08'] = true;
    _resRows.add(ResReportRow(
      testNum: _resRows.length + 1,
      srcPin: m.hi,
      dstPin: m.lo,
      resistanceMohm: m.milliohms.toDouble(),
      status: m.status.wire.toUpperCase(),
      srcConnId: n?.src.c ?? '—',
      srcPinLabel: n == null ? null : 'Pin ${n.src.p}',
      dstConnId: n?.dsts[0].c ?? '—',
      dstPinLabel: n == null ? null : 'Pin ${n.dsts[0].p}',
    ));
    notifyListeners();
  }

  void _onInsul(msg.InsulResult m) {
    final pass = m.status == proto.InsulStatus.pass;
    if (pass) {
      _countPass++;
    } else {
      _countFail++;
    }
    dhN = '$_countFail';
    if (_countFail > 0) faultsOn['f04'] = true;
    // Wire mΩ (see Proto_EvtInsul, tasks.c: MΩ estimate x1e9) back to MΩ for
    // display, and light up the relay grid on whichever net was actually
    // under test - this only resolves once a real netlist is loaded
    // (pinHi is null on the demo harness, see buildNets()).
    final n = _netByHiPin(m.net);
    if (n != null) {
      n.ins = m.leakMohm / 1.0e9;
      n.insFail = !pass;
      setRelays(n, !pass);
    }
    final insMohm = m.leakMohm / 1.0e9;
    _insulRows.add(InsulReportRow(
      testNum: _insulRows.length + 1,
      net: n?.name ?? '—',
      hvCard: n != null ? 'H${n.card + 1}' : '—',
      hsPin: n != null ? 'HS-${pad(n.relay, 2)}' : '—',
      leakV: _leakVoltsFor(insMohm),
      insulationMohm: insMohm,
      status: pass ? 'PASS' : 'FAIL',
    ));
    notifyListeners();
  }

  void _onProgress(msg.Progress m) {
    doneCount = m.done;
    totalCount = m.total;
    final pct = m.total != 0 ? m.done / m.total : 0.0;
    switch (runKind) {
      case 'cont':
        dcBar = pct;
        break;
      case 'res':
        drBar = pct;
        break;
      default:
        dhBar = pct;
    }
    // Discovery reports progress in HS columns swept (0..256), not pairs.
    if (runKind == 'cont' && cmode == 'cross') {
      auCols = '${m.done}';
    }
    vElapsed = '${m.done} / ${m.total}';
    notifyListeners();
  }

  void _onDone(msg.Done m) {
    final kind = m.kind.wire; // cont | res | insul
    final key = kind == 'insul' ? 'hv' : kind;
    if (inFault) {
      // FW-10: a latched fault refuses the run outright — !STATE fault, then
      // !DONE <kind> 0 0. Zero failed must never read as a pass; R[key] stays
      // whatever _beginRun left it (null — not run), not "pass".
      running = null;
      runKind = null;
      _countPass = _countFail = 0;
      log('fail', kind,
          '$kind refused — fault latched; clear the fault and retry');
      updateControls();
      paintLink();
      return;
    }
    final pass = m.failed == 0;
    final reportMeta = ReportMeta(
      dutId: dutId,
      operatorName: operatorName,
      netlistName: nlMtx.loaded ? nlMtx.name : null,
      pass: pass,
      when: DateTime.now(),
    );
    switch (kind) {
      case 'cont':
        lastContReport =
            _contRows.isEmpty ? null : ContReport(reportMeta, List.of(_contRows));
      case 'res':
        lastResReport = _resRows.isEmpty
            ? null
            : ResReport(
                reportMeta,
                cal != null ? (cal!.currentUa / 1000.0).toStringAsFixed(3) : '—',
                limits != null ? '${limits!.rMaxMohm}' : '—',
                List.of(_resRows),
              );
      case 'insul':
        lastInsulReport = _insulRows.isEmpty
            ? null
            : InsulReport(
                reportMeta,
                '500',
                limits != null
                    ? (limits!.insMinMohm / 1.0e9).toStringAsFixed(1)
                    : '—',
                List.of(_insulRows),
              );
    }
    // GUI-05: one history row per completed run, whatever the netlist
    // context was at the moment it finished. There is no "build"/serial
    // number concept in the protocol to group cont+res+insul together, so
    // this is per-test, not per-harness.
    history.append(RunHistoryEntry(
      timestamp: DateTime.now(),
      kind: kind,
      mtxNetlist: nlMtx.loaded ? nlMtx.name : null,
      hvNetlist: nlHv.loaded ? nlHv.name : null,
      passed: m.passed,
      failed: m.failed,
    ));
    R[key] = pass ? 'pass' : 'fail';
    _setDom(
      kind == 'cont'
          ? 'dCont'
          : kind == 'res'
              ? 'dRes'
              : 'dHv',
      pass ? 'pass' : 'fail',
    );
    running = null;
    runKind = null;
    log(
      pass ? 'ok' : 'fail',
      kind,
      '$kind ${pass ? "PASS" : "FAIL"} — ${m.passed} passed, ${m.failed} failed',
    );
    _countPass = _countFail = 0;
    if (kind == 'cont' && cmode == 'cross') {
      saveNlEnabled = _discovered.isNotEmpty;
      crossNote = _discovered.isEmpty
          ? 'No nets found. Check the harness is seated on J-MTX and run again.'
          : '${_discovered.length} nets found across $auNodes pins. '
              'Save to load them as the working MTX netlist.';
    }
    updateControls();
    paintLink();
    if (key == 'cont' || key == 'res') finishStage1();
  }

  // -------------------------------------------------------------------------
  // LIVE LAYER — event dispatch
  // -------------------------------------------------------------------------

  /// `function onEvent(m)`
  void onEvent(msg.Message m) {
    switch (m) {
      case msg.ContResult():
        _onCont(m);
      case msg.ResResult():
        _onRes(m);
      case msg.InsulResult():
        _onInsul(m);
      case msg.Progress():
        _onProgress(m);
      case msg.Done():
        _onDone(m);
      case msg.HvEvent():
        hvMv = m.millivolts;
        if (m.millivolts > 0) handling = 'live';
        gTrack = math.min(1.0, m.millivolts / 500000);
        paintLink();
      case msg.SafeEvent():
        // The one and only source of "safe to handle".
        handling = 'safe';
        armed = false;
        hvMv = 0;
        log('ok', 'safe', 'instrument reports SAFE');
        paintLink();
      case msg.FixtureEvent():
        if (m.fixture != instFixture) armed = false; // any change disarms
        instFixture = m.fixture;
        onHv = m.fixture == proto.Fixture.hv;
        log('info', 'fix', 'fixture is now ${m.fixture.wire}');
        updateControls();
        paintLink();
      case msg.StateEvent():
        instState = m.state;
        if (m.state == proto.State.hvArmed) {
          armed = true;
          handling = 'live';
        } else if (m.state == proto.State.running) {
          handling = 'live';
        } else if (m.state == proto.State.idle) {
          armed = false;
        } else if (m.state == proto.State.fault) {
          armed = false;
          handling = 'unknown';
        }
        paintLink();
      case msg.Fault():
        log('fail', 'seq', '${m.code} ${m.text}');
        notifyListeners();
      case msg.LogLine():
        log('info', 'fw', m.text);
      default:
        break;
    }
  }

  /// `function linkDown(detail)`
  void linkDown(String detail) {
    link = false;
    armed = false;
    handling = 'unknown';
    runKind = null;
    running = null;
    linkDetail = detail;
    log('fail', 'link', 'link lost — $detail (state unknown)');
    updateControls();
    paintLink();
  }

  void onLinkState(LinkState state, String detail) {
    if (state == LinkState.connected) {
      link = true;
      linkDetail = detail;
      paintLink();
    } else {
      linkDown(detail);
    }
  }

  /// surfaced, never dropped
  void onProtocolError(String raw, Object error) {
    log('warn', 'proto', '$error');
  }

  // -------------------------------------------------------------------------
  // LIVE LAYER — connect + netlist wiring
  // -------------------------------------------------------------------------

  /// The refresh button: re-enumerate the serial ports. The pending choice
  /// survives if its port is still there, otherwise the first port is
  /// preselected.
  ///
  /// Says what it found. Re-enumerating and landing on the same list is the
  /// common case — with no log line the button looked broken precisely when it
  /// was working, and an operator whose board is not enumerating needs to be
  /// told that, not left guessing whether the click registered.
  void refreshPorts({bool quiet = false}) {
    final before = selPort;
    ports = listPorts();
    if (ports.isEmpty) {
      selPort = null;
    } else if (selPort == null || !ports.any((p) => p.name == selPort)) {
      selPort = ports.first.name;
    }
    if (!quiet) {
      if (ports.isEmpty) {
        log('warn', 'link',
            'port scan found no serial ports — is the board plugged in?');
      } else {
        log('info', 'link',
            'port scan: ${ports.map((p) => p.name).join(", ")}');
        if (before != null && selPort != before) {
          log('warn', 'link', '$before is gone — selection moved to $selPort');
        }
      }
    }
    notifyListeners();
  }

  /// The dropdown: choose a port without opening it. Connecting is the Connect
  /// button's job — picking used to dial immediately, which left no way to
  /// retry a failed connect without reopening the menu and re-picking the port
  /// that was already selected.
  void choosePort(String name) {
    if (selPort == name) return;
    selPort = name;
    notifyListeners();
  }

  /// The selector's Connect: aim at the chosen port and open the link.
  void connectTo(String name) {
    selPort = name;
    host = name;
    unawaited(connect());
  }

  /// The selector's Disconnect. `ConnectionManager.disconnect` reports the
  /// drop through `onLinkState` only when it had a link to drop, so if the
  /// GUI still thinks it is linked, take the same `linkDown` path here.
  Future<void> disconnect() async {
    await cm.disconnect();
    if (link) linkDown('disconnected');
  }

  /// `function connect()`
  Future<void> connect() async {
    if (connecting) return;
    connecting = true;
    updateControls();
    try {
      await _connect();
    } finally {
      connecting = false;
      updateControls();
    }
  }

  Future<void> _connect() async {
    msg.StatusReply st;
    try {
      st = await cm.connect(host: host, port: port);
    } on Object catch (exc) {
      log('fail', 'link', '$exc');
      return;
    }
    link = true;
    instState = st.state;
    instFixture = st.fixture;
    hvMv = st.hvMv;
    armed = st.state == proto.State.hvArmed;
    // A STATUS reply says nothing about whether the harness is safe to touch,
    // and it cannot report `running` at all - so stay UNKNOWN.
    handling = (armed || hvMv > 0) ? 'live' : 'unknown';
    onHv = st.fixture == proto.Fixture.hv;
    log('ok', 'link',
        'connected — state ${st.state.wire}, fixture ${st.fixture.wire}');

    final idRes = await _cmd(proto.commands.identify());
    if (idRes.ok && idRes.reply is msg.IdReply) {
      fwVersion = (idRes.reply as msg.IdReply).fw;
    }
    final calRes = await _cmd(proto.commands.calGet());
    if (calRes.ok && calRes.reply is msg.CalReply) {
      cal = calRes.reply as msg.CalReply;
    }
    final limRes = await _cmd(proto.commands.limitsGet());
    if (limRes.ok && limRes.reply is msg.LimitsReply) {
      limits = limRes.reply as msg.LimitsReply;
    }

    try {
      final entries = await cm.netlistGet();
      if (entries.isNotEmpty) {
        rebuildNets(entries);
        log('ok', 'nl',
            'netlist read from instrument — ${entries.length} nets');
      } else {
        // The instrument's netlist is empty — every boot starts that way; it
        // is RAM-only and nothing re-populates it. The pre-connection
        // placeholder (a demo harness, not measured data — see buildNets())
        // must not keep claiming "MTX netlist loaded" once we know better:
        // that reads as "Run S1 will work" when the instrument would refuse
        // CONT RUN verify / RES RUN outright with ERR ERANGE no netlist.
        // Geometry stays as-is — only the loaded flag the gating reads on
        // (can()) changes — same as the operator unloading it by hand.
        nlMtx.loaded = false;
        log(
          'warn',
          'nl',
          'no netlist on the instrument — run cross continuity and save it '
          'before netlist-mode continuity or resistance will run',
        );
      }
    } on Object {
      // A missing netlist is not an error the operator needs to see here;
      // the netbars already say none is loaded.
    }

    updateControls();
    paintLink();
  }

  /// `S.rebuildNets(pairs)` — rebuild the harness model from real (hi,lo) pin
  /// pairs. The fixture map — which connector each board pin lands on — is a
  /// GUI-side artifact; the instrument only ever talks in pins 1..256.
  void rebuildNets(List<msg.NetEntry> pairs) {
    // The active fixture (whatever setActiveFixture() last set - the demo
    // placeholder, or a netlist-derived guess, see _fixtureFromGuess and
    // browseMtxNetlist()) might not cover every pin THIS netlist references
    // - e.g. a real NETLIST GET from the instrument can differ from
    // whatever file was last used to guess a layout. Extend it with a
    // synthetic trailing connector rather than let a pin resolve to nothing
    // - every PinRef this method creates must have a real entry in kConn,
    // since painters.dart/cont_view.dart look it up unconditionally.
    final maxPin =
        pairs.fold<int>(0, (m, p) => math.max(m, math.max(p.hi, p.lo)));
    if (maxPin > kFixPins) {
      final extended = List<ConnectorDef>.from(kFix.connectors)
        ..add(ConnectorDef(
          id: '?',
          label: 'Unassigned',
          type: ConnType.rect,
          pins: maxPin - kFixPins,
          side: kFix.connectors.length.isEven ? 'L' : 'R',
          base: kFixPins,
        ));
      setActiveFixture(
          FixtureDef(name: kFix.name, rev: kFix.rev, connectors: extended));
    }

    // Real per-connector lookup against the (now guaranteed-covering)
    // active fixture (GUI-11) - used to modulo-wrap every pin onto a
    // same-side pool regardless of which connector it actually belonged
    // to, fabricating the mapping for any real (uploaded/read) netlist.
    PinRef pinNode(int pin) {
      for (final c in kFix.connectors) {
        if (pin > c.base && pin <= c.base + c.pins) {
          return PinRef(c.id, pin - c.base);
        }
      }
      return PinRef('?', pin); // unreachable after the extension above
    }

    nets = <Net>[];
    for (var i = 0; i < pairs.length; i++) {
      final pr = pairs[i];
      nets.add(Net(
        name: 'NET_${pad(i + 1, 3)}',
        src: pinNode(pr.hi),
        dsts: [pinNode(pr.lo)],
        joint: null,
        hs: pr.hi - 1,
        ls: pr.lo - 1,
        pinHi: pr.hi,
        pinLo: pr.lo,
        r: 0,
        v: 0,
        ins: 0,
        rmin: 0.05,
        rmax: 2.00,
        wire: '—',
        open: false,
        // HV relay assignment is a direct function of the source pin's own
        // flat position, not this loop's index - see the matching note in
        // design/model.dart's buildNets(). VERIFY against real HV harness
        // wiring at bring-up (PROJECT_LOG.md BU- items).
        card: (pr.hi - 1) ~/ 64,
        relay: (pr.hi - 1) % 64,
      ));
    }
    netc = nets.length;
    netAt = buildNetAt(nets);
    nlMtx.loaded = nets.isNotEmpty;
    nlMtx.nets = nets.length;
    nlMtx.pins = nets.length * 2;
    layoutFixture();
    updateControls();
  }

  // -------------------------------------------------------------------------
  // operator controls
  // -------------------------------------------------------------------------

  /// `#abortHv` / `#abortHv2` — live.js sends ABORT on the capture phase,
  /// then the design's own listener resets the view.
  Future<void> abort() async {
    await _cmd(proto.commands.abort());
    log('warn', 'seq', 'ABORT sent');
    resetAll();
  }

  /// `>FAULT CLEAR` — the only recovery from a latched fault (brief §3.2.1,
  /// FW-10): forces safe first, then clears the latch. A deliberate operator
  /// action only, offered from the status pill — never automatic.
  Future<void> clearFault() async {
    final res = await _cmd(proto.commands.faultClear());
    if (_reportRefusal('fault clear', res)) return;
    log('ok', 'seq', 'fault cleared — instrument returning to idle');
    paintLink();
  }

  /// `LIMITS SET r_max_mohm=<int> ins_min_mohm=<int>` (GUI-07). Both values
  /// are wire milliohms, same convention as `r_max_mohm` elsewhere in the
  /// protocol (brief §3.2). On success, `limits` is updated from the values
  /// just sent rather than re-issuing `LIMITS GET` - `<OK` on this command
  /// means the instrument accepted exactly what was asked for (brief §3.2.1:
  /// "any value" is accepted, there is no range refusal to reconcile).
  Future<void> setLimits(int rMaxMohm, int insMinMohm) async {
    final res = await _cmd(proto.commands.limitsSet(rMaxMohm, insMinMohm));
    if (_reportRefusal('limits set', res)) return;
    limits = msg.LimitsReply(rMaxMohm: rMaxMohm, insMinMohm: insMinMohm);
    log('ok', 'seq',
        'limits set: r_max ${rMaxMohm}mΩ, ins_min ${insMinMohm}mΩ');
    updateControls();
  }

  /// GUI-05: "Export CSV" on the Results view's Run history panel. Writes
  /// every recorded run (oldest history entries last touched runs first) to
  /// a CSV file at a location the operator picks. Returns false, with a log
  /// line explaining why, if there is nothing to export yet or the operator
  /// cancelled the save dialog — never throws for either of those.
  Future<bool> exportHistoryCsv() async {
    final entries = history.load();
    if (entries.isEmpty) {
      log('warn', 'hist', 'no run history to export yet');
      return false;
    }
    final path = await pickSavePath(
      dialogTitle: 'Export run history',
      fileName: 'run_history_${_csvStamp(DateTime.now())}.csv',
      allowedExtensions: ['csv'],
    );
    if (path == null) return false; // operator cancelled

    final buf = StringBuffer(
        'Timestamp,Kind,MTX netlist,HV netlist,Passed,Failed,Verdict\n');
    for (final e in entries.reversed) {
      buf.writeln([
        e.timestamp.toIso8601String(),
        e.kind,
        e.mtxNetlist ?? '',
        e.hvNetlist ?? '',
        e.passed,
        e.failed,
        e.pass ? 'Pass' : 'Fail',
      ].map(_csvField).join(','));
    }
    await File(path).writeAsString(buf.toString());
    log('ok', 'hist', 'run history exported to $path');
    return true;
  }

  /// "Export CSV" next to "Save as MTX netlist" (Continuity view, cross
  /// mode) - writes the pairs the last cross-continuity scan found,
  /// independent of whether they have also been pushed to the instrument.
  /// Same save-dialog/no-op-on-cancel pattern as [exportHistoryCsv].
  Future<bool> exportDiscoveredNetlistCsv() async {
    if (_discovered.isEmpty) {
      log('warn', 'nl', 'no discovered netlist to export yet');
      return false;
    }
    final path = await pickSavePath(
      dialogTitle: 'Export discovered netlist',
      fileName: 'discovered_netlist_${_csvStamp(DateTime.now())}.csv',
      allowedExtensions: ['csv'],
    );
    if (path == null) return false; // operator cancelled

    final buf = StringBuffer('HS pin,LS pin\n');
    for (final p in _discovered) {
      buf.writeln('${p.$1},${p.$2}');
    }
    await File(path).writeAsString(buf.toString());
    log('ok', 'nl', 'discovered netlist exported to $path');
    return true;
  }

  static String _csvStamp(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}-'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }

  static String _csvField(Object? v) {
    final s = v.toString();
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  /// `required_format`-shaped test reports (`report.dart`) — one CSV/PDF
  /// pair per completed run, generated from `lastContReport`/`lastResReport`/
  /// `lastInsulReport`. Each stays available until the next run of the same
  /// kind starts (see `_beginRun`), not persisted across a restart.
  Future<String?> _pickReportPath(String kind, String ext) {
    final stamp = _csvStamp(DateTime.now());
    return pickSavePath(
      dialogTitle: 'Export $kind report',
      fileName: 'report_${stamp}_$kind.$ext',
      allowedExtensions: [ext],
    );
  }

  Future<bool> exportContReportCsv() async {
    final r = lastContReport;
    if (r == null) {
      log('warn', 'rpt', 'no continuity report to export yet');
      return false;
    }
    final path = await _pickReportPath('continuity', 'csv');
    if (path == null) return false;
    await File(path).writeAsString(r.toCsv());
    log('ok', 'rpt', 'continuity report exported to $path');
    return true;
  }

  Future<bool> exportContReportPdf() async {
    final r = lastContReport;
    if (r == null) {
      log('warn', 'rpt', 'no continuity report to export yet');
      return false;
    }
    final path = await _pickReportPath('continuity', 'pdf');
    if (path == null) return false;
    await File(path).writeAsBytes(await buildContReportPdf(r));
    log('ok', 'rpt', 'continuity report exported to $path');
    return true;
  }

  Future<bool> exportResReportCsv() async {
    final r = lastResReport;
    if (r == null) {
      log('warn', 'rpt', 'no resistance report to export yet');
      return false;
    }
    final path = await _pickReportPath('resistance', 'csv');
    if (path == null) return false;
    await File(path).writeAsString(r.toCsv());
    log('ok', 'rpt', 'resistance report exported to $path');
    return true;
  }

  Future<bool> exportResReportPdf() async {
    final r = lastResReport;
    if (r == null) {
      log('warn', 'rpt', 'no resistance report to export yet');
      return false;
    }
    final path = await _pickReportPath('resistance', 'pdf');
    if (path == null) return false;
    await File(path).writeAsBytes(await buildResReportPdf(r));
    log('ok', 'rpt', 'resistance report exported to $path');
    return true;
  }

  Future<bool> exportInsulReportCsv() async {
    final r = lastInsulReport;
    if (r == null) {
      log('warn', 'rpt', 'no insulation report to export yet');
      return false;
    }
    final path = await _pickReportPath('insulation', 'csv');
    if (path == null) return false;
    await File(path).writeAsString(r.toCsv());
    log('ok', 'rpt', 'insulation report exported to $path');
    return true;
  }

  Future<bool> exportInsulReportPdf() async {
    final r = lastInsulReport;
    if (r == null) {
      log('warn', 'rpt', 'no insulation report to export yet');
      return false;
    }
    final path = await _pickReportPath('insulation', 'pdf');
    if (path == null) return false;
    await File(path).writeAsBytes(await buildInsulReportPdf(r));
    log('ok', 'rpt', 'insulation report exported to $path');
    return true;
  }

  /// Diagnostics — "Close path": `MANUAL PATH`, energising exactly the one
  /// HS/LS pair the operator picked. Diagnostics only (brief §3.2); nothing
  /// else about the harness or a run is implied.
  /// `hiPin`/`loPin` are wire pins, 1..256.
  Future<void> manualClosePath(int hiPin, int loPin) async {
    final res = await _cmd(proto.commands.manualPath(hiPin, loPin));
    if (_reportRefusal('manual path', res)) return;
    log('info', 'diag',
        'manual path closed: HS ${pad(hiPin, 3)} -> LS ${pad(loPin, 3)}');
  }

  /// Diagnostics — "Discharge": `MANUAL OFF`, opens the manually driven path
  /// and forces the rail safe.
  Future<void> manualOff() async {
    final res = await _cmd(proto.commands.manualOff());
    if (_reportRefusal('manual off', res)) return;
    log('info', 'diag', 'manual off — path opened, rail forced safe');
  }

  /// `$("#actBtn")` click.
  void actButtonPressed() {
    if (running != null) {
      resetAll();
      return;
    }
    if (onHv && R['hv'] == null && can('hv').$1) {
      requestHv();
      return;
    }
    if (!onHv && R['cont'] == null && can('cont').$1) {
      runCont();
      return;
    }
    if (!onHv && R['cont'] == 'pass' && R['res'] == null && can('res').$1) {
      runRes();
      return;
    }
    resetAll();
  }

  /// The `[data-run]` handlers.
  void runTest(String t) {
    if (!can(t).$1) return;
    if (t == 'cont') runCont();
    if (t == 'res') runRes();
    if (t == 'hv') requestHv();
  }

  /// `$("#saveNl")` — push what cross-continuity found to the instrument as
  /// the working MTX netlist.
  ///
  /// Until this has run once, the instrument's netlist is empty and it
  /// refuses `CONT RUN verify` / `RES RUN` outright with `ERR ERANGE no
  /// netlist` (3.2) — discovery finds what is really there, but finding it
  /// is not the same as the instrument knowing it.
  Future<void> saveDiscoveredNetlist() async {
    if (_discovered.isEmpty) return;
    final stamp = DateTime.now().millisecondsSinceEpoch.toString();
    final ok = await _uploadNetlistPairs(
      List<(int, int)>.from(_discovered),
      name: 'AV-880_cross_${stamp.substring(stamp.length - 4)}.hnl',
      origin: 'cross',
    );
    if (ok) saveNlEnabled = false;
  }

  /// Pushes `pairs` to the instrument via `NETLIST BEGIN/ADD/END` — the only
  /// place that ever sends it — then rebuilds the GUI's own net model from
  /// the same pairs so both sides agree. Shared by cross-continuity's "Save
  /// as MTX netlist" ([saveDiscoveredNetlist]) and a real netlist file's
  /// "Browse the file system…" ([browseMtxNetlist]): the wire sequence and
  /// the rebuild are identical, only where the pairs came from differs.
  /// Returns whether the instrument accepted it.
  Future<bool> _uploadNetlistPairs(
    List<(int, int)> pairs, {
    required String name,
    required String origin,
  }) async {
    final begin = await _cmd(proto.commands.netlistBegin(pairs.length));
    if (_reportRefusal('netlist upload', begin)) return false;
    for (final p in pairs) {
      final add = await _cmd(proto.commands.netlistAdd(p.$1, p.$2));
      if (_reportRefusal('netlist upload', add)) return false;
    }
    final end = await _cmd(proto.commands.netlistEnd());
    if (_reportRefusal('netlist upload', end)) return false;

    rebuildNets([for (final p in pairs) msg.NetEntry(hi: p.$1, lo: p.$2)]);
    loadMtx(name, origin);
    log(
      'ok',
      'nl',
      'netlist uploaded to the instrument — ${pairs.length} nets. '
      'Verify-mode continuity and resistance are now available.',
    );
    updateControls();
    return true;
  }

  /// Escape key.
  void escape() {
    if (mdFixtureOpen) {
      cancelFixtureGuess(); // same as Cancel - reverts the applied guess
      return;
    }
    if (mdNlOpen || mdVerifyOpen || mdMtxOpen) {
      mdNlOpen = false;
      mdVerifyOpen = false;
      mdMtxOpen = false;
      notifyListeners();
      return;
    }
    resetAll();
  }

  @override
  void dispose() {
    unawaited(cm.disconnect());
    super.dispose();
  }
}
