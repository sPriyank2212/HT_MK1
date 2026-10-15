/// HT_MK1 instrument simulator (brief section 4).
///
/// Direct port of `htproto/simulator.py`. Speaks the section 3 protocol over a
/// TCP socket so the GUI can be developed and regression-tested without
/// hardware. The scenario is chosen at launch and represents the *physical
/// harness* plugged into the machine; commands and replies are byte-exact per
/// the contract.
///
/// Scenarios:
///     pass            clean pass on every test
///     opens_shorts    continuity: two opens and one short
///     res_fail        resistance: fail_high and fail_low nets
///     insul_fail      insulation: one low-leakage net + !FAULT F04
///     disconnect      transport drops mid-run, no !DONE
///
/// Python ran each test on its own thread; Dart runs it as an async loop on
/// the event loop. The event ordering, the sleeps between streamed results and
/// the termination sequence are unchanged.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'codec.dart';

const String fwVersion = '1.0.0';
const int protoVersion = 1;

/// Simulator defaults, standing in for instrument configuration.
const int defaultLimitRMaxMohm = 1000;
const int defaultLimitInsMinMohm = 100;
/// Matches the real firmware's kelvin.h constants (KELVIN_FORCE_CURRENT_A,
/// KELVIN_CAL_R_REF_OHM/_TOL_PCT) and its CAL GET reply shape - see
/// Core/Src/app/proto.c. Kept in sync by hand; there is no shared source
/// between Dart and C for this project.
const int defaultCalCurrentUa = 2000;
const String defaultCalMethod = 'ratiometric';
const int defaultCalRrefMohm = 100000;
const int defaultCalRrefTolMohm = 10;
const int defaultCalGainMax = 128;

/// HV rail range accepted by HV SET (500 V in millivolts).
const int hvMaxMv = 500000;

/// Discover mode scans 256 pins and reports nets as they are found.
const int discoverPins = 256;

/// One physical net of the simulated harness.
class NetOutcome {
  final int hi;
  final int lo;
  final ContStatus cont;
  final int resMohm;
  final ResStatus resStatus;
  final int insulLeakMohm;
  final InsulStatus insulStatus;

  const NetOutcome({
    required this.hi,
    required this.lo,
    this.cont = ContStatus.pass,
    this.resMohm = 50,
    this.resStatus = ResStatus.pass,
    this.insulLeakMohm = 500,
    this.insulStatus = InsulStatus.pass,
  });
}

class Scenario {
  final String name;
  final List<NetOutcome> nets;

  /// fraction of a run after which the transport drops (disconnect scenario)
  final double? disconnectAt;

  const Scenario(this.name, this.nets, {this.disconnectAt});
}

List<NetOutcome> _goodNets(int count) =>
    List<NetOutcome>.generate(count, (i) => NetOutcome(hi: 2 * i + 1, lo: 2 * i + 2));

const List<String> scenarioNames = [
  'pass',
  'opens_shorts',
  'res_fail',
  'insul_fail',
  'disconnect',
];

Scenario makeScenario(String name, {int nets = 12}) {
  final base = _goodNets(nets);
  if (nets < 4) throw ArgumentError('need at least 4 nets for scenarios');
  switch (name) {
    case 'pass':
      return Scenario(name, base);
    case 'opens_shorts':
      base[0] = NetOutcome(hi: base[0].hi, lo: base[0].lo, cont: ContStatus.open);
      base[1] = NetOutcome(hi: base[1].hi, lo: base[1].lo, cont: ContStatus.open);
      base[2] = NetOutcome(hi: base[2].hi, lo: base[2].lo, cont: ContStatus.short);
      return Scenario(name, base);
    case 'res_fail':
      base[0] = NetOutcome(
          hi: base[0].hi,
          lo: base[0].lo,
          resMohm: 2500,
          resStatus: ResStatus.failHigh);
      base[1] = NetOutcome(
          hi: base[1].hi, lo: base[1].lo, resMohm: 2, resStatus: ResStatus.failLow);
      return Scenario(name, base);
    case 'insul_fail':
      base[2] = NetOutcome(
          hi: base[2].hi,
          lo: base[2].lo,
          insulLeakMohm: 5,
          insulStatus: InsulStatus.fail);
      return Scenario(name, base);
    case 'disconnect':
      return Scenario(name, base, disconnectAt: 0.4);
    default:
      throw ArgumentError("unknown scenario '$name'");
  }
}

class _InstrumentState {
  State state = State.idle;
  Fixture fixture = Fixture.none;
  int hvMv = 0;

  /// uploaded by GUI; null = not uploaded
  List<List<int>>? netlist;
  List<List<int>>? netlistStaging;

  int rMaxMohm = defaultLimitRMaxMohm;
  int insMinMohm = defaultLimitInsMinMohm;
  int calCurrentUa = defaultCalCurrentUa;
  String calMethod = defaultCalMethod;
  int calRrefMohm = defaultCalRrefMohm;
  int calRrefTolMohm = defaultCalRrefTolMohm;
  int boardTempDeciC = 250; // 25.0 C, a plausible bench room temperature
  int calGainMax = defaultCalGainMax;
}

/// Protocol state machine. Transport feeds it lines and it sends lines back.
class InstrumentSim {
  final Scenario scenario;
  final Duration interval;
  final void Function(String line) _send;
  final void Function()? _onDrop;

  final _InstrumentState _st = _InstrumentState();
  bool _runStop = false;
  Future<void>? _runFuture;
  Future<void> Function()? _deferred;

  InstrumentSim(
    this.scenario, {
    this.interval = const Duration(milliseconds: 20),
    required void Function(String) send,
    void Function()? onDrop,
  })  : _send = send,
        _onDrop = onDrop;

  // -- transport interface ---------------------------------------------------

  /// Process one received command line (without trailing newline).
  ///
  /// Python ran `_dispatch` on the receiving thread, so a command whose
  /// handler changes state — FIXTURE, SAFE, ABORT, FAULT CLEAR — emitted its
  /// `!HV` / `!SAFE` / `!STATE` / `!FIXTURE` events *before* the `<OK` reply
  /// went out. Those handlers are async here (they await a ramp or a run
  /// stopping), so this awaits them before replying, which keeps the event
  /// ordering the firmware contract describes. Only the two cases Python also
  /// deferred — the HV ramp and a run starting — run after the reply.
  Future<void> handleLine(String line) async {
    line = line.replaceAll(RegExp(r'\r+$'), '');
    if (line.startsWith('>')) {
      line = line.substring(1); // leading '>' is optional on commands (appendix B)
    }
    final tokens = line.split(' ');
    final reply = await _dispatch(tokens);
    if (reply != null) _emitReply(reply);
    final deferred = _deferred;
    if (deferred != null) {
      _deferred = null;
      unawaited(deferred());
    }
  }

  /// Client went away: stop any run, disarm nothing (state is unknown to GUI).
  Future<void> close() => _stopRun();

  // -- emit helpers ----------------------------------------------------------

  void _emitReply(String body) => _send('<$body\n');

  void _emitEvent(String body) {
    try {
      _send('!$body\n');
    } on Object {
      _runStop = true; // client vanished mid-run
    }
  }

  void _setState(State state) {
    _st.state = state;
    _emitEvent('STATE ${state.wire}');
  }

  /// Mirrors the real firmware's `Proto_EvtHeartbeat()`: re-announces state
  /// on a fixed cadence so an idle-but-healthy link never trips
  /// `ConnectionManager`'s 5 s watchdog (`connection.dart`'s
  /// `defaultLinkTimeout`) just because nothing has happened since connect.
  /// Without this, the simulator sends nothing at all while idle - unlike
  /// real firmware - and every demo connection would "link lost" a few
  /// seconds after connecting if the operator hadn't started a run yet.
  void emitHeartbeat() => _emitEvent('STATE ${_st.state.wire}');

  void _setHv(int mv) {
    if ((mv - _st.hvMv).abs() > 10) {
      _st.hvMv = mv;
      _emitEvent('HV $mv');
    }
  }

  /// force=true is used on the discharge path: an abort must never leave the
  /// rail up because the stop flag is set.
  Future<void> _rampHv(int target, {bool force = false}) async {
    final step = ((target - _st.hvMv).abs() ~/ 20).clamp(10, 1 << 30);
    final wait = interval < const Duration(milliseconds: 5)
        ? interval
        : const Duration(milliseconds: 5);
    while (_st.hvMv != target && (force || !_runStop)) {
      final cur = _st.hvMv;
      final nxt = (target - cur).abs() <= step
          ? target
          : cur + (target > cur ? step : -step);
      _setHv(nxt);
      await Future<void>.delayed(wait);
    }
  }

  // -- command dispatch ------------------------------------------------------

  Future<String?> _dispatch(List<String> t) async {
    final head = t[0];
    try {
      if (head == 'PING' && t.length == 1) return 'PONG';
      if (head == 'ID' && t.length == 1) {
        return 'ID HT_MK1 fw=$fwVersion proto=$protoVersion';
      }
      if (head == 'STATUS' && t.length == 1) {
        return 'STATUS state=${_st.state.wire} fixture=${_st.fixture.wire} '
            'hv_mv=${_st.hvMv}';
      }
      if (head == 'SAFE' && t.length == 1) {
        await _forceSafe();
        return 'OK';
      }
      if (head == 'ABORT' && t.length == 1) {
        await _forceSafe();
        return 'OK';
      }
      if (head == 'FAULT' && t.length == 2 && t[1] == 'CLEAR') {
        // 3.2.1: forces safe FIRST, then clears the latch. Accepted while
        // faulted, which nothing else is.
        await _forceSafe();
        // Arming here is "state is HV_ARMED", so idling disarms.
        if (_st.state != State.idle) _setState(State.idle);
        return 'OK started';
      }
      if (head == 'FIXTURE' &&
          t.length == 2 &&
          const ['none', 'mtx', 'hv'].contains(t[1])) {
        // 8.1 answer 6: a fixture change drops the arm and forces the
        // hardware safe BEFORE the !FIXTURE event goes out.
        await _changeFixture(Fixture.fromWire(t[1])!);
        return 'OK';
      }
      if (head == 'NETLIST') return _netlist(t.sublist(1));
      if (head == 'CONT' &&
          t.length == 3 &&
          t[1] == 'RUN' &&
          (t[2] == 'verify' || t[2] == 'discover')) {
        return _startRun('cont', t[2]);
      }
      if (head == 'RES' && t.length == 2 && t[1] == 'RUN') {
        return _startRun('res', null);
      }
      if (head == 'INSUL' && t.length == 2 && t[1] == 'ARM') return _insulArm();
      if (head == 'INSUL' && t.length == 2 && t[1] == 'RUN') {
        return _startRun('insul', null);
      }
      if (head == 'HV' && t.length == 3 && t[1] == 'SET') return _hvSet(t[2]);
      if (head == 'MANUAL' && t.length == 4 && t[1] == 'PATH') {
        final hi = int.parse(t[2]);
        final lo = int.parse(t[3]);
        if (!(hi >= 1 && hi <= 256 && lo >= 1 && lo <= 256)) {
          return 'ERR ERANGE pin out of range';
        }
        // Real firmware queues MANUAL PATH (CMD_CONTINUITY) - <OK started,
        // then a !MANUAL event once the one-shot connect/read/release
        // finishes (GUI-06, 2026-08-21). A connected pair reads a plausible
        // "wire present" voltage (~1.5 V of the CONTINUITY_CONNECTED_V_MIN..
        // _MAX band in continuity.h); this fake harness has no real
        // pass/fail model per pin outside a run, so it always reports as
        // connected - honest within what a --sim connection can simulate.
        _deferred = () async {
          await Future.delayed(const Duration(milliseconds: 20));
          const mv = 1500;
          const code = (mv * 4096) ~/ 3300; // AD7476 12-bit, VREF 3.3 V
          _emitEvent('MANUAL adc_mv=$mv adc_code=$code');
        };
        return 'OK started';
      }
      if (head == 'MANUAL' && t.length == 5 && t[1] == 'RELAY') {
        // Refused by design (brief section 0).
        return 'ERR EHW manual relay control refused by design';
      }
      if (head == 'MANUAL' && t.length == 3 && t[1] == 'SWEEP') {
        final hi = int.parse(t[2]);
        if (hi < 1 || hi > 256) return 'ERR ERANGE pin out of range';
        return _startSweep(hi);
      }
      if (head == 'MANUAL' && t.length == 2 && t[1] == 'OFF') return 'OK';
      if (head == 'CAL' && t.length == 4 && t[1] == 'RUN') {
        final hi = int.parse(t[2]);
        final lo = int.parse(t[3]);
        if (!(hi >= 1 && hi <= 256 && lo >= 1 && lo <= 256)) {
          return 'ERR ERANGE pin out of range';
        }
        // No real ADS124S08 to ratio against - reports a plausible healthy
        // reading, same honesty level as MANUAL PATH's fixed !MANUAL value.
        _deferred = () async {
          await Future.delayed(const Duration(milliseconds: 30));
          _emitEvent('CAL_RESULT r_mohm=45 ratiometric=1 pass');
        };
        return 'OK started';
      }
      if (head == 'CAL' && t.length == 2 && t[1] == 'GET') {
        return 'CAL current_ua=${_st.calCurrentUa} method=${_st.calMethod} '
            'rref_mohm=${_st.calRrefMohm} rref_tol_mohm=${_st.calRrefTolMohm} '
            'gain_max=${_st.calGainMax}';
      }
      if (head == 'LIMITS' && t.length == 2 && t[1] == 'GET') {
        return 'LIMITS r_max_mohm=${_st.rMaxMohm} ins_min_mohm=${_st.insMinMohm}';
      }
      if (head == 'LIMITS' && t.length == 4 && t[1] == 'SET') {
        return _limitsSet(t[2], t[3]);
      }
      if (head == 'TEMP' && t.length == 2 && t[1] == 'READ') {
        return _readTemp();
      }
      if (head == 'BUS' && t.length == 2 && t[1] == 'SCAN') {
        return _busScan();
      }
    } on FormatException {
      // fall through to ESYNTAX
    } on RangeError {
      // fall through to ESYNTAX
    }
    return 'ERR ESYNTAX unrecognised command: ${t.join(' ')}';
  }

  String? _netlist(List<String> t) {
    if (t.isNotEmpty && t[0] == 'BEGIN' && t.length == 2) {
      _st.netlistStaging = <List<int>>[];
      return 'OK';
    }
    if (t.isNotEmpty && t[0] == 'ADD' && t.length == 3) {
      if (_st.netlistStaging == null) {
        return 'ERR ESYNTAX NETLIST ADD without BEGIN';
      }
      final hi = int.parse(t[1]);
      final lo = int.parse(t[2]);
      if (!(hi >= 1 && hi <= 256 && lo >= 1 && lo <= 256)) {
        // 8.1 answer 1
        return 'ERR ERANGE pin out of range';
      }
      _st.netlistStaging!.add([hi, lo]);
      return 'OK';
    }
    if (t.isNotEmpty && t[0] == 'END' && t.length == 1) {
      final staging = _st.netlistStaging ?? <List<int>>[];
      _st.netlist = List<List<int>>.from(staging);
      _st.netlistStaging = null;
      return 'OK loaded=${staging.length}';
    }
    if (t.isNotEmpty && t[0] == 'GET' && t.length == 1) {
      // One command, one reply sequence per 3.2: header first, then one <NET
      // line per entry, all before the next command's reply.
      final nets = _st.netlist ?? <List<int>>[];
      _emitReply('NETLIST ${nets.length}');
      for (final pair in nets) {
        _emitReply('NET ${pair[0]} ${pair[1]}');
      }
      return null;
    }
    return 'ERR ESYNTAX unrecognised NETLIST command';
  }

  String _limitsSet(String rTok, String insTok) {
    if (!rTok.startsWith('r_max_mohm=') || !insTok.startsWith('ins_min_mohm=')) {
      return 'ERR ESYNTAX expected r_max_mohm=<int> ins_min_mohm=<int>';
    }
    _st.rMaxMohm = int.parse(rTok.split('=')[1]);
    _st.insMinMohm = int.parse(insTok.split('=')[1]);
    return 'OK';
  }

  String _hvSet(String mvTok) {
    final mv = int.parse(mvTok);
    if (mv > hvMaxMv) {
      return 'ERR ERANGE hv setpoint $mv mV exceeds $hvMaxMv mV';
    }
    // 8.1 answer 2: only HV SET 0 is accepted while not armed.
    if (mv > 0 && _st.state != State.hvArmed) {
      return 'ERR ENOTARMED hv set refused: not armed';
    }
    // Reply goes out first; the ramp streams !HV events afterwards (3.4).
    _deferred = () => _rampHv(mv);
    return 'OK';
  }

  String _insulArm() {
    if (_st.state == State.running) return 'ERR EBUSY a run is already in progress';
    if (_st.fixture != Fixture.hv) {
      return 'ERR EFIXTURE harness is on the ${_st.fixture.wire} fixture';
    }
    _setState(State.hvArmed);
    return 'OK armed';
  }

  // -- runs ------------------------------------------------------------------

  String _startRun(String kind, String? mode) {
    if (_st.state == State.running) {
      // 8.1 answer 3: run-starting commands are refused, not queued.
      return 'ERR EBUSY a run is already in progress';
    }
    if (kind == 'insul' && _st.state != State.hvArmed) {
      return 'ERR ENOTARMED insulation not armed';
    }
    if (kind == 'cont' && mode == 'verify' && _st.netlist == null) {
      // 8.1 answer 4: no golden-harness fallback, the firmware errors.
      return 'ERR ERANGE no netlist';
    }
    _runStop = false;
    _st.state = State.running;

    _deferred = () async {
      // After the <OK started reply: state event, then the run.
      _emitEvent('STATE ${State.running.wire}');
      final fn = switch (kind) {
        'cont' => () => _runCont(mode),
        'res' => () => _runRes(),
        _ => () => _runInsul(),
      };
      _runFuture = fn();
      await _runFuture;
      _runFuture = null;
    };
    return 'OK started';
  }

  /// `MANUAL SWEEP <hi>` (GUI-06, 2026-08-21) — one HS pin against all 256
  /// LS. Same whole-run EBUSY gating as `_startRun`, but its own dispatch:
  /// `!DONE sweep ...` isn't one of `_startRun`'s three kinds and shouldn't
  /// touch `AppState`'s main run state either (`TestKind.sweep`).
  String _startSweep(int hi) {
    if (_st.state == State.running) {
      return 'ERR EBUSY a run is already in progress';
    }
    _runStop = false;
    _st.state = State.running;
    _deferred = () async {
      _emitEvent('STATE ${State.running.wire}');
      _runFuture = _runSweep(hi);
      await _runFuture;
      _runFuture = null;
    };
    return 'OK started';
  }

  Future<void> _runSweep(int hi) async {
    final matches = scenario.nets.where((n) => n.hi == hi);
    var found = 0;
    for (final n in matches) {
      if (_runStop) break;
      if (n.cont == ContStatus.pass) {
        _emitEvent('CONT ${n.hi} ${n.lo} ${n.cont.wire}');
        found++;
      }
      await Future<void>.delayed(interval);
    }
    _emitEvent('PROGRESS 256 256');
    await _endRun('sweep', found, 0, _runStop);
  }

  /// `BUS SCAN` (GUI-06, 2026-08-21). The demo has no real bus to probe, so
  /// this reports the same device set the real firmware's `Board_ScanBus`
  /// does, all healthy — a plausible instrument's answer, not a claim that
  /// this is reading real hardware.
  static const List<String> _busDevices = [
    'U21', 'U101', 'U105', 'U102', 'U106', 'U66', 'U67', 'U107', 'U108',
    'U69', 'U68',
  ];

  String _busScan() {
    if (_st.state == State.running) {
      return 'ERR EBUSY a run is already in progress';
    }
    _deferred = () async {
      _emitEvent('STATE ${State.running.wire}');
      for (final name in _busDevices) {
        _emitEvent('BUSLINE $name ok');
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      _emitEvent('STATE ${State.idle.wire}');
      _emitEvent('DONE bus ${_busDevices.length} 0');
    };
    return 'OK started';
  }

  /// FW-14/DS18B20: `<OK started` immediately, `!TEMP` once the (simulated)
  /// ~750 ms conversion completes - same "OK started then an event" shape as
  /// _startRun, just for a single reading instead of a streamed run.
  String _readTemp() {
    _deferred = () async {
      await Future.delayed(const Duration(milliseconds: 50));
      _emitEvent('TEMP ${_st.boardTempDeciC}');
    };
    return 'OK started';
  }

  /// Signal the run and wait for its termination sequence.
  Future<void> _stopRun() async {
    _runStop = true;
    final f = _runFuture;
    if (f != null) {
      try {
        await f;
      } on Object {
        // a failed run must not break the caller
      }
    }
    _runFuture = null;
  }

  Future<void> _forceSafe() async {
    if (_st.state == State.running) {
      // The run emits !SAFE / !STATE idle / !DONE itself (8.1 answer 7:
      // !DONE is the last event of every run).
      await _stopRun();
      return;
    }
    if (_st.hvMv > 0) {
      await _rampHv(0, force: true);
      _st.hvMv = 0;
    }
    _emitEvent('SAFE');
    if (_st.state != State.idle) _setState(State.idle);
  }

  Future<void> _changeFixture(Fixture fixture) async {
    // 8.1 answer 6: any fixture change drops the arm and forces safe,
    // emitting !HV 0 and !SAFE before !FIXTURE.
    if (_st.state == State.running) await _stopRun();
    if (_st.state == State.hvArmed || _st.hvMv > 0) {
      if (_st.hvMv > 0) {
        await _rampHv(0, force: true);
        _st.hvMv = 0;
      }
      _emitEvent('SAFE');
      _setState(State.idle);
    }
    _st.fixture = fixture;
    _emitEvent('FIXTURE ${fixture.wire}');
  }

  /// Run termination, 8.1 answer 7: discharge, !SAFE, !STATE idle, and !DONE
  /// always last.
  Future<void> _endRun(String kind, int passed, int failed, bool aborted) async {
    if (kind == 'insul') {
      await _rampHv(0, force: true);
      _st.hvMv = 0;
    }
    if (aborted || kind == 'insul') _emitEvent('SAFE');
    _setState(State.idle);
    _emitEvent('DONE $kind $passed $failed');
  }

  /// disconnect scenario: hard-drop the transport part-way through a run.
  bool _maybeDisconnect(int idx, int total) {
    final at = scenario.disconnectAt;
    final drop = _onDrop;
    if (at != null && total >= 3 && idx >= (total * at).toInt() && drop != null) {
      drop();
      return true;
    }
    return false;
  }

  /// The nets a run actually tests, real-hardware style: whichever pin
  /// pairs the operator uploaded (`NETLIST BEGIN/ADD/END`), not the
  /// scenario's own fixed pairing. `scenario.nets`' scripted pass/fail/
  /// open/short/etc. pattern still applies — positionally, row `i` of the
  /// uploaded netlist gets row `i`'s scripted outcome — with every row past
  /// the scenario's own length defaulting to pass rather than running out
  /// of scripted data. Falls back to the scenario's fixed nets unchanged
  /// when nothing has been uploaded (demo-without-a-netlist keeps working
  /// the way it always has).
  ///
  /// Before this, a run compared the uploaded `(hi, lo)` against the
  /// scenario's own fixed pairs by literal value (`1↔2, 3↔4, …`) — any
  /// uploaded netlist using a different pairing convention (e.g. real
  /// hardware's straight-through `Src Pin # == Dst Pin #`, see
  /// `required_format/netlist_full_256x256.xlsx`) could never match, so
  /// every net read NOT CONNECTED regardless of `--nets`. Reusing the
  /// scenario's outcome data *positionally* instead of by literal pin match
  /// is what makes the 'pass' scenario genuinely mean "everything the
  /// operator tests passes," for any netlist they load, not just one that
  /// happens to already match the scenario's own baked-in pairing (see
  /// GUI-21, PROJECT_LOG.md).
  List<NetOutcome> _effectiveNets(List<List<int>>? netlist) {
    if (netlist == null) return scenario.nets;
    return [
      for (var i = 0; i < netlist.length; i++)
        i < scenario.nets.length
            ? NetOutcome(
                hi: netlist[i][0],
                lo: netlist[i][1],
                cont: scenario.nets[i].cont,
                resMohm: scenario.nets[i].resMohm,
                resStatus: scenario.nets[i].resStatus,
                insulLeakMohm: scenario.nets[i].insulLeakMohm,
                insulStatus: scenario.nets[i].insulStatus,
              )
            : NetOutcome(hi: netlist[i][0], lo: netlist[i][1]),
    ];
  }

  Future<void> _runCont(String? mode) async {
    if (mode == 'verify') {
      // netlist presence is checked in _startRun (8.1 answer 4)
      final nets = _effectiveNets(_st.netlist);
      final total = nets.length;
      var passed = 0;
      var failed = 0;
      for (var i = 0; i < total; i++) {
        final n = nets[i];
        if (_maybeDisconnect(i, total)) return; // transport gone: no !DONE
        if (_runStop) {
          await _endRun('cont', passed, failed, true);
          return;
        }
        _emitEvent('CONT ${n.hi} ${n.lo} ${n.cont.wire}');
        _emitEvent('PROGRESS ${i + 1} $total');
        if (n.cont == ContStatus.pass) {
          passed++;
        } else {
          failed++;
        }
        await Future<void>.delayed(interval);
      }
      await _endRun('cont', passed, failed, false);
    } else {
      // discover: scan pins, report nets as found
      final byHi = <int, List<NetOutcome>>{};
      for (final n in scenario.nets) {
        byHi.putIfAbsent(n.hi, () => <NetOutcome>[]).add(n);
      }
      const total = discoverPins;
      var passed = 0;
      for (var pin = 1; pin <= total; pin++) {
        if (_maybeDisconnect(pin, total)) return;
        if (_runStop) {
          final failed = scenario.nets
              .where((n) => n.cont != ContStatus.pass)
              .length;
          await _endRun('cont', passed, failed, true);
          return;
        }
        for (final n in byHi[pin] ?? const <NetOutcome>[]) {
          _emitEvent('CONT ${n.hi} ${n.lo} ${n.cont.wire}');
          if (n.cont == ContStatus.pass) passed++;
        }
        _emitEvent('PROGRESS $pin $total');
        await Future<void>.delayed(interval);
      }
      final failed =
          scenario.nets.where((n) => n.cont != ContStatus.pass).length;
      await _endRun('cont', passed, failed, false);
    }
  }

  Future<void> _runRes() async {
    // Resistance shares the MTX netlist with continuity (real hardware:
    // same J-MTX connector, same uploaded pairs) - see _effectiveNets.
    final nets = _effectiveNets(_st.netlist);
    final total = nets.length;
    var passed = 0;
    var failed = 0;
    for (var i = 0; i < total; i++) {
      final n = nets[i];
      if (_maybeDisconnect(i, total)) return;
      if (_runStop) {
        await _endRun('res', passed, failed, true);
        return;
      }
      _emitEvent('RES ${n.hi} ${n.lo} ${n.resMohm} ${n.resStatus.wire}');
      _emitEvent('PROGRESS ${i + 1} $total');
      if (n.resStatus == ResStatus.pass) {
        passed++;
      } else {
        failed++;
      }
      await Future<void>.delayed(interval);
    }
    await _endRun('res', passed, failed, false);
  }

  Future<void> _runInsul() async {
    await _rampHv(hvMaxMv);
    // GUI-25: real firmware's run_insulation_all() (tasks.c) iterates
    // Proto_NetlistCount()/Proto_NetlistGet() - the *same* uploaded MTX
    // netlist continuity/resistance use, not a fixed count - and reports
    // each result against the real hi pin (Proto_EvtInsul(hi, ...)), not a
    // sequential index. This used to always run exactly `--nets` (12 by
    // default) fake nets regardless of what netlist was actually loaded,
    // identified 1..12 rather than by real pin number - the same class of
    // bug GUI-21 fixed for continuity/resistance, just not yet extended
    // here since HV has no netlist upload of its own (there isn't one -
    // insulation shares the MTX upload, same as real hardware).
    final nets = _effectiveNets(_st.netlist);
    final total = nets.length;
    var passed = 0;
    var failed = 0;
    for (var i = 0; i < total; i++) {
      final n = nets[i];
      if (_maybeDisconnect(i, total)) return;
      if (_runStop) {
        await _endRun('insul', passed, failed, true);
        return;
      }
      _emitEvent('INSUL ${n.hi} ${n.insulLeakMohm} ${n.insulStatus.wire}');
      _emitEvent('PROGRESS ${i + 1} $total');
      if (n.insulStatus == InsulStatus.pass) {
        passed++;
      } else {
        failed++;
        _emitEvent('FAULT F04 insulation low on net ${n.hi}');
      }
      await Future<void>.delayed(interval);
    }
    await _endRun('insul', passed, failed, false);
  }
}

/// TCP front-end: one client at a time, one [InstrumentSim] per scenario.
class SimulatorServer {
  final Scenario scenario;
  final Duration interval;
  ServerSocket? _server;
  Socket? _client;
  InstrumentSim? _sim;
  Timer? _heartbeat;

  String get host => _server?.address.address ?? '127.0.0.1';
  int get port => _server?.port ?? 0;

  SimulatorServer(
    this.scenario, {
    this.interval = const Duration(milliseconds: 20),
  });

  static Future<SimulatorServer> start(
    Scenario scenario, {
    String host = '127.0.0.1',
    int port = 0,
    Duration interval = const Duration(milliseconds: 20),
  }) async {
    final s = SimulatorServer(scenario, interval: interval);
    s._server = await ServerSocket.bind(host, port, shared: false);
    s._server!.listen(s._handleClient);
    return s;
  }

  Future<void> stop() async {
    // Cancelled here too, not just in _handleClient's onDone - that fires
    // asynchronously off client.destroy() below, and a test that stop()s and
    // immediately tears down must not race a still-pending heartbeat Timer
    // (flutter_test's "!timersPending" invariant).
    _heartbeat?.cancel();
    _heartbeat = null;
    final sim = _sim;
    _sim = null;
    if (sim != null) await sim.close();
    _client?.destroy();
    _client = null;
    await _server?.close();
    _server = null;
  }

  void _handleClient(Socket client) {
    _heartbeat?.cancel(); // defensive - a new client should never find one live
    _client = client;
    client.setOption(SocketOption.tcpNoDelay, true);

    void send(String line) {
      client.add(ascii.encode(line));
    }

    void drop() {
      // Mid-run disconnect scenario: hard-close the transport.
      try {
        client.destroy();
      } on Object {
        // already gone
      }
    }

    final sim = InstrumentSim(scenario,
        interval: interval, send: send, onDrop: drop);
    _sim = sim;
    send('# HT_MK1 simulator scenario=${scenario.name}\n');

    // Same cadence as the real firmware's Proto_EvtHeartbeat() - see
    // InstrumentSim.emitHeartbeat's doc comment for why this exists at all.
    _heartbeat = Timer.periodic(const Duration(seconds: 2), (_) {
      sim.emitHeartbeat();
    });

    final framer = LineFramer();
    // handleLine is async, so chain the calls: one command must finish before
    // the next is dispatched, exactly as the single receiving thread did.
    var queue = Future<void>.value();
    client.listen(
      (data) {
        List<String> lines;
        try {
          lines = framer.feed(data);
        } on FormatException {
          return;
        }
        for (final line in lines) {
          queue = queue.then((_) => sim.handleLine(line)).catchError((_) {});
        }
      },
      onError: (Object _) {},
      onDone: () {
        _heartbeat?.cancel();
        _heartbeat = null;
        unawaited(sim.close());
        if (identical(_sim, sim)) _sim = null;
        _client = null;
      },
      cancelOnError: true,
    );
  }
}
