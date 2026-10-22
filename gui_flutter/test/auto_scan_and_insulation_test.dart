/// Auto scan and the insulation prerequisites prompt ("Continue anyway").
///
/// Auto scan is cross continuity presented as its own section: it must find
/// the harness's connections with no netlist, and it must NOT count as the
/// Mode 1 pass that unlocks insulation. The insulation prompt lets an
/// operator run without Mode 1 on purpose, but only after being asked.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ht_mk1_gui/app/app_state.dart';
import 'package:ht_mk1_gui/htproto/connection.dart';
import 'package:ht_mk1_gui/htproto/simulator.dart';

Future<void> waitUntil(bool Function() cond,
    {Duration timeout = const Duration(seconds: 8)}) async {
  final sw = Stopwatch()..start();
  while (!cond()) {
    if (sw.elapsed > timeout) fail('condition not met within $timeout');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

AppState offlineState() => AppState(
    cm: ConnectionManager(logDir: Directory.systemTemp),
    host: '127.0.0.1',
    port: 46000);

void main() {
  group('auto scan (real simulator)', () {
    late SimulatorServer sim;
    late ConnectionManager cm;
    late AppState s;

    setUp(() async {
      sim = await SimulatorServer.start(makeScenario('pass', nets: 4),
          port: 0, interval: Duration.zero);
      cm = ConnectionManager(
        onEvent: (m) => s.onEvent(m),
        onLinkState: (st, d) => s.onLinkState(st, d),
        logDir: Directory.systemTemp,
      );
      s = AppState(cm: cm, host: '127.0.0.1', port: sim.port);
      await s.connect();
    });

    tearDown(() async {
      await cm.disconnect();
      await sim.stop();
    });

    test('finds the connections with no netlist and is not a Mode 1 pass',
        () async {
      expect(s.nlMtx.loaded, isFalse);
      s.go('auto');

      await s.runAutoScan();
      await waitUntil(() => s.running == null && s.discoveredPairs.isNotEmpty);

      expect(s.discoveredPairs.length, 4);
      expect(s.auNets, '4');
      expect(s.saveNlEnabled, isTrue);

      // A survey, not a verdict: nothing is recorded as continuity passed,
      // and the handover to J-HV is not offered.
      expect(s.R['cont'], isNull);
      expect(s.phase, isNot('hold'));
      expect(s.preTestsDone, isFalse);
      expect(s.sb2S, 'lock');
    });

    test('hands cross mode back to netlist mode once the view is left',
        () async {
      s.go('auto');
      await s.runAutoScan();
      await waitUntil(() => s.running == null && s.discoveredPairs.isNotEmpty);
      expect(s.cmode, 'cross');

      s.go('cont');
      expect(s.cmode, 'net');
    });

    test('is refused while the harness is on J-HV', () {
      s.onHv = true;
      expect(s.canAutoScan.$1, isFalse);
      expect(s.canAutoScan.$2, contains('J-HV'));
    });
  });

  group('insulation prerequisites', () {
    test('asked first when Mode 1 has not passed', () {
      final s = offlineState();
      s.runInsulation();
      expect(s.mdPreOpen, isTrue);
      expect(s.onHv, isFalse);
      expect(s.mdNlOpen || s.mdVerifyOpen, isFalse);
    });

    test('runTest("hv") goes through the same prompt', () {
      final s = offlineState();
      s.runTest('hv');
      expect(s.mdPreOpen, isTrue);
    });

    test('cancel closes it without side effects', () {
      final s = offlineState();
      s.runInsulation();
      s.cancelModals();
      expect(s.mdPreOpen, isFalse);
      expect(s.onHv, isFalse);
      expect(s.preTestsSkipped, isFalse);
    });

    test('"Go to Mode 1" lands on continuity', () {
      final s = offlineState();
      s.runInsulation();
      s.goToMode1();
      expect(s.mdPreOpen, isFalse);
      expect(s.view, 'cont');
    });

    test('"Continue anyway" runs insulation with no pre-test', () async {
      final s = offlineState();
      s.runInsulation();
      await s.continueToInsulation(skipped: true);

      expect(s.mdPreOpen, isFalse);
      expect(s.preTestsSkipped, isTrue);
      expect(s.onHv, isTrue);
      // ...and carries straight on into the usual HV prompts.
      expect(s.mdNlOpen, isTrue);

      // The pre-HV checklist shows the skipped tests as skipped, not failed.
      final checks = s.verifyChecks;
      expect(checks[0].state, 'warn');
      expect(checks[0].value, 'skipped');
      expect(checks[1].state, 'warn');
      expect(checks[1].value, 'skipped');
    });

    test('a reset forgets the skip', () async {
      final s = offlineState();
      await s.continueToInsulation(skipped: true);
      s.resetAll();
      expect(s.preTestsSkipped, isFalse);
      expect(s.onHv, isFalse);
    });

    test('with both pre-tests passed the prompt is only the handover', () {
      final s = offlineState();
      s.R['cont'] = 'pass';
      s.R['res'] = 'pass';
      expect(s.preTestsDone, isTrue);
      s.runInsulation();
      expect(s.mdPreOpen, isTrue);
    });

    test('nothing opens while a test is running', () {
      final s = offlineState();
      s.running = 'cont';
      s.runInsulation();
      expect(s.mdPreOpen, isFalse);
    });
  });
}
