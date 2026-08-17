/// Netlist-upload regression tests.
///
/// `NETLIST BEGIN/ADD/END` are defined in the codec (and exercised directly
/// against the connection manager in `protocol_test.dart`) but nothing in
/// `AppState` ever sent them — confirmed against real hardware: a freshly
/// booted instrument's netlist is empty (`<NETLIST 0`, RAM-only, nothing
/// re-populates it), and `>CONT RUN verify` / `>RES RUN` are refused outright
/// with `ERR ERANGE no netlist`. The pre-connection demo placeholder
/// (`buildNets()`) kept claiming "MTX netlist loaded" regardless, so netlist
/// -mode continuity and resistance — the default, primary workflow — could
/// never actually run against real firmware.
///
/// Two faults, pinned here:
///   * `connect()` left the stale placeholder marked loaded when the
///     instrument's real netlist came back empty.
///   * cross-continuity discovery found nothing reusable: pairs were never
///     accumulated, "Save as MTX netlist" was permanently disabled
///     (`saveNlEnabled` had no setter), and even if it had fired,
///     `saveDiscoveredNetlist()` only renamed the stale local placeholder —
///     nothing was ever pushed to the instrument.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ht_mk1_gui/app/app_state.dart';
import 'package:ht_mk1_gui/htproto/connection.dart';
import 'package:ht_mk1_gui/htproto/simulator.dart';

class _FakeTransport implements Transport {
  final StreamController<Uint8List> _ctl =
      StreamController<Uint8List>.broadcast();

  /// What `NETLIST GET` answers with — the instrument's ground truth.
  List<List<int>> netlist = const [];

  @override
  Future<void> open(String host, int port) async {}

  @override
  void send(List<int> data) {
    final body = ascii.decode(data).substring(1).trim();
    if (body == 'STATUS') {
      push('<STATUS state=idle fixture=none hv_mv=0\n');
    } else if (body == 'NETLIST GET') {
      push('<NETLIST ${netlist.length}\n');
      for (final p in netlist) {
        push('<NET ${p[0]} ${p[1]}\n');
      }
    } else if (body == 'CAL GET') {
      push('<CAL current_ua=3000 gain=32 rref_mohm=100000\n');
    } else if (body == 'LIMITS GET') {
      push('<LIMITS r_max_mohm=5000 ins_min_mohm=10000000\n');
    } else {
      push('<ERR ENOTSUP not supported by the fake\n');
    }
  }

  void push(String text) {
    if (!_ctl.isClosed) _ctl.add(Uint8List.fromList(ascii.encode(text)));
  }

  @override
  Stream<Uint8List> get incoming => _ctl.stream;

  @override
  Future<void> close() async {
    if (!_ctl.isClosed) _ctl.close();
  }
}

/// 8 s, not 5: this waits on a real `SimulatorServer`'s cross-continuity
/// sweep over a real socket, and under `flutter test`'s full-suite
/// parallelism (200+ tests, many isolates) it can occasionally lose the CPU
/// for a few seconds — confirmed passing reliably in isolation at 5 s,
/// intermittently timing out only under full-suite load. Matches
/// `protocol_test.dart`'s own `_waitForDone` timeout for the same class of
/// wait (real simulator, run completion).
Future<void> waitUntil(bool Function() cond,
    {Duration timeout = const Duration(seconds: 8)}) async {
  final sw = Stopwatch()..start();
  while (!cond()) {
    if (sw.elapsed > timeout) {
      fail('condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  group('connect() and the instrument netlist', () {
    test('an empty instrument netlist leaves the netlist unloaded',
        () async {
      final t = _FakeTransport();
      late final AppState s;
      final cm = ConnectionManager(
        onLinkState: (st, d) => s.onLinkState(st, d),
        transportFactory: () => t,
        logDir: Directory.systemTemp,
      );
      s = AppState(cm: cm, host: '127.0.0.1', port: 46000);
      addTearDown(cm.disconnect);

      // Nothing is loaded before a connection exists either (GUI Reality
      // Check, cause A - no seeded demo placeholder claiming otherwise).
      expect(s.nlMtx.loaded, isFalse);

      await s.connect();

      expect(s.nlMtx.loaded, isFalse,
          reason: 'the instrument truthfully has no netlist yet');
      expect(s.can('cont').$2, contains('needs the MTX netlist'));
    });

    test('a non-empty instrument netlist is loaded as usual', () async {
      final t = _FakeTransport()
        ..netlist = const [
          [1, 2],
          [3, 4],
        ];
      late final AppState s;
      final cm = ConnectionManager(
        onLinkState: (st, d) => s.onLinkState(st, d),
        transportFactory: () => t,
        logDir: Directory.systemTemp,
      );
      s = AppState(cm: cm, host: '127.0.0.1', port: 46000);
      addTearDown(cm.disconnect);

      await s.connect();

      expect(s.nlMtx.loaded, isTrue);
      expect(s.nets.length, 2);
      expect(s.can('cont').$1, isTrue);
    });
  });

  // ===========================================================================
  // Against the real simulator, which enforces the identical gate real
  // firmware does (see protocol_test.dart's "CONT RUN verify without a
  // netlist is refused"). Proving the fix here means it holds against the
  // actual wire behaviour, not just a hand-rolled fake.
  // ===========================================================================
  group('discovery to a working netlist (real simulator)', () {
    late SimulatorServer sim;
    late ConnectionManager cm;
    late AppState s;

    Future<void> boot(String scenario, {int nets = 4}) async {
      sim = await SimulatorServer.start(
        makeScenario(scenario, nets: nets),
        port: 0,
        // Duration.zero, not 1ms: measured directly on this machine, a
        // nominal "1ms" Future.delayed actually costs ~14-15ms (Windows'
        // ~15.6ms system timer granularity) - cross-discovery always sweeps
        // all 256 pins (simulator.dart's discoverPins), so 256 iterations of
        // that costs ~3.6-3.9s of pure timer overhead alone, even with zero
        // contention. That's most of waitUntil's budget gone before any real
        // work or scheduling jitter, which is what actually made this test
        // flaky under load - not "CPU contention" in the abstract.
        // Duration.zero resolves on the next event-loop turn instead of a
        // real OS timer (measured ~0.02ms/iteration), so it still exercises
        // the same real async SimulatorServer/socket path, just without
        // paying Windows' timer tax 256 times over.
        interval: Duration.zero,
      );
      cm = ConnectionManager(
        onEvent: (m) => s.onEvent(m),
        onLinkState: (st, d) => s.onLinkState(st, d),
        logDir: Directory.systemTemp,
      );
      s = AppState(cm: cm, host: '127.0.0.1', port: sim.port);
    }

    tearDown(() async {
      await cm.disconnect();
      await sim.stop();
    });

    test(
        'verify-mode continuity is refused until discovery is saved, '
        'then actually runs', () async {
      await boot('pass', nets: 4);
      await s.connect();

      // Fresh simulator boot: no netlist, same as a fresh instrument.
      expect(s.nlMtx.loaded, isFalse);
      expect(s.can('cont').$1, isFalse);

      // Confirmed against real hardware: this is what pressing "Run S1"
      // actually does right now — refused by the instrument itself.
      s.cmode = 'net';
      await s.runCont();
      expect(s.running, isNull);
      expect(s.R['cont'], isNull);
      expect(s.logs.last.lvl, 'fail');

      // Scan the harness for real...
      s.setMode('cross');
      await s.runCont();
      await waitUntil(() => s.running == null);

      expect(s.saveNlEnabled, isTrue);
      expect(s.auNets, '4');
      expect(s.auMulti, '0');

      // ...and save what was found.
      await s.saveDiscoveredNetlist();

      expect(s.nlMtx.loaded, isTrue);
      expect(s.nlMtx.origin, 'cross');
      expect(s.nets.length, 4);
      expect(s.saveNlEnabled, isFalse);

      // The point of the fix: verify-mode continuity, refused a moment ago,
      // now runs and passes — against the same connection, no reconnect.
      s.setMode('net');
      expect(s.can('cont').$1, isTrue);
      await s.runCont();
      await waitUntil(() => s.running == null);

      expect(s.R['cont'], 'pass');
    });

    test('Save starts disabled and stays that way until a scan finds nets',
        () async {
      await boot('pass', nets: 4);
      await s.connect();
      expect(s.saveNlEnabled, isFalse);
    });
  });
}
