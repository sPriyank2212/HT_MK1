/// The Run screen's "Demo harness" Good / Faulty selector must actually change
/// what the built-in simulator reports. It used to flip a GUI-side text label
/// only, so picking "Faulty" and running still passed.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ht_mk1_gui/app/app_state.dart';
import 'package:ht_mk1_gui/htproto/connection.dart';
import 'package:ht_mk1_gui/htproto/simulator.dart';

Future<void> waitUntil(bool Function() cond,
    {Duration timeout = const Duration(seconds: 10)}) async {
  final sw = Stopwatch()..start();
  while (!cond()) {
    if (sw.elapsed > timeout) fail('condition not met within $timeout');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

AppState offline() => AppState(
    cm: ConnectionManager(logDir: Directory.systemTemp),
    host: '127.0.0.1',
    port: 46000);

void main() {
  test('the selector is hidden when there is no simulator behind it', () {
    final s = offline();
    expect(s.demoScenario, isNull);
    s.pickDemoScenario(true); // harmless without a hook
    expect(s.scenario, 'bad');
  });

  test('picking Faulty makes the simulated continuity run fail', () async {
    final sim = await SimulatorServer.start(makeScenario('pass', nets: 4),
        port: 0, interval: Duration.zero);
    late final AppState s;
    final cm = ConnectionManager(
      onEvent: (m) => s.onEvent(m),
      onLinkState: (st, d) => s.onLinkState(st, d),
      logDir: Directory.systemTemp,
    );
    s = AppState(
      cm: cm,
      host: '127.0.0.1',
      port: sim.port,
      demoScenario: (faulty) => sim.setScenario(
          makeScenario(faulty ? 'opens_shorts' : 'pass', nets: 4)),
    );
    addTearDown(() async {
      await cm.disconnect();
      await sim.stop();
    });
    await s.connect();

    // Give the instrument a netlist the way an operator would: scan, save.
    await s.runAutoScan();
    await waitUntil(() => s.running == null && s.discoveredPairs.isNotEmpty);
    await s.saveDiscoveredNetlist();
    expect(s.nlMtx.loaded, isTrue);
    s.go('run');

    // Good harness: Mode 1 continuity passes.
    s.pickDemoScenario(false);
    await s.runCont();
    await waitUntil(() => s.running == null && s.R['cont'] != null);
    expect(s.R['cont'], 'pass');

    // Faulty harness: the same run now fails.
    s.pickDemoScenario(true);
    expect(s.R['cont'], isNull, reason: 'the selector starts over');
    await s.runCont();
    await waitUntil(() => s.running == null && s.R['cont'] != null);
    expect(s.R['cont'], 'fail');
  });

  test('the big Run button with no netlist explains instead of resetting', () {
    final s = offline();
    expect(s.nlMtx.loaded, isFalse);
    s.actButtonPressed();
    expect(s.mdMtxOpen, isTrue);
  });
}
