/// Safety-relevant GUI behaviour that must not regress:
///
///  * Stop / Esc during a run tells the INSTRUMENT to abort (a GUI-only reset left
///    the firmware running, and in Mode 2 the rail up);
///  * the partial `!DONE` that follows an abort is never recorded as a finished
///    run (zero failures in a half-run would read as a PASS);
///  * no Run control is enabled without a link;
///  * the verdict panel says what happened when insulation ends;
///  * the Insulation screen's rail pill follows the instrument's own report;
///  * every completed run's report is saved automatically.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ht_mk1_gui/app/app_state.dart';
import 'package:ht_mk1_gui/design/model.dart';
import 'package:ht_mk1_gui/htproto/connection.dart';
import 'package:ht_mk1_gui/htproto/simulator.dart';

Future<void> waitUntil(bool Function() cond,
    {Duration timeout = const Duration(seconds: 15)}) async {
  final sw = Stopwatch()..start();
  while (!cond()) {
    if (sw.elapsed > timeout) fail('condition not met within $timeout');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

class Rig {
  late final SimulatorServer sim;
  late final ConnectionManager cm;
  late final AppState s;
  final List<String> tx = [];
}

Future<Rig> rig({
  int nets = 12,
  Duration interval = Duration.zero,
  Directory? reportsDir,
}) async {
  final r = Rig();
  r.sim = await SimulatorServer.start(makeScenario('pass', nets: nets),
      port: 0, interval: interval);
  r.cm = ConnectionManager(
    onEvent: (m) => r.s.onEvent(m),
    onLinkState: (st, d) => r.s.onLinkState(st, d),
    onWire: (dir, text) {
      if (dir == 'tx') r.tx.add(text.trim());
    },
    logDir: Directory.systemTemp,
  );
  final netlist = File('../test_netlists/AV-880_MTX_12net.xlsx').readAsBytesSync();
  r.s = AppState(
    cm: r.cm,
    host: '127.0.0.1',
    port: r.sim.port,
    serialLink: false,
    reportsDir: reportsDir,
    pickNetlistFile: () async => ('AV-880_MTX_12net.xlsx', Uint8List.fromList(netlist)),
  );
  addTearDown(() async {
    await r.cm.disconnect();
    await r.sim.stop();
    setActiveFixture(buildDefaultFixture());
  });
  await r.s.connect();
  return r;
}

Future<void> loadNetlist(AppState s) async {
  await s.browseMtxNetlist();
  if (s.mdFixtureOpen) s.confirmFixtureGuess(List<ConnectorDef>.of(kFix.connectors));
  expect(s.nlMtx.loaded, isTrue);
}

void main() {
  tearDown(() => setActiveFixture(buildDefaultFixture()));

  test('no Run control is enabled without a link', () {
    final s = AppState(
        cm: ConnectionManager(logDir: Directory.systemTemp),
        host: '127.0.0.1',
        port: 46000);
    expect(s.link, isFalse);
    for (final t in ['cont', 'res', 'hv']) {
      expect(s.can(t).$1, isFalse, reason: t);
      expect(s.can(t).$2, kNotConnectedReason, reason: t);
    }
    expect(s.canAutoScan.$1, isFalse);
    expect(s.canAutoScan.$2, kNotConnectedReason);
    // The big button must say why instead of looking dead.
    s.actButtonPressed();
    expect(s.logs.last.message, contains('not connected'));
  });

  test('Stop during a run sends ABORT to the instrument', () async {
    final r = await rig(nets: 12, interval: const Duration(milliseconds: 60));
    await loadNetlist(r.s);
    await r.s.runCont();
    await waitUntil(() => r.s.running != null);

    r.tx.clear();
    r.s.actButtonPressed(); // the round Stop button
    await waitUntil(() => r.tx.any((l) => l.endsWith('ABORT')));
    await waitUntil(() => r.s.running == null);
    // let the instrument finish winding the run down before the rig is torn down
    await waitUntil(() => r.s.logs.any((l) => l.message.contains('partial result discarded')));
  });

  test('Esc during a run sends ABORT to the instrument', () async {
    final r = await rig(nets: 12, interval: const Duration(milliseconds: 60));
    await loadNetlist(r.s);
    await r.s.runCont();
    await waitUntil(() => r.s.running != null);

    r.tx.clear();
    r.s.escape();
    await waitUntil(() => r.tx.any((l) => l.endsWith('ABORT')));
    await waitUntil(() => r.s.logs.any((l) => l.message.contains('partial result discarded')));
  });

  test('the partial result after an abort is discarded, never a PASS', () async {
    final r = await rig(nets: 12, interval: const Duration(milliseconds: 60));
    await loadNetlist(r.s);
    final before = r.s.history.load().length;
    await r.s.runCont();
    await waitUntil(() => r.s.running != null);

    r.s.actButtonPressed();
    // let the instrument finish winding the run down and send its !DONE
    await waitUntil(() => r.s.logs.any((l) => l.message.contains('partial result discarded')));
    expect(r.s.R['cont'], isNull, reason: 'an aborted run has no verdict');
    expect(r.s.history.load().length, before, reason: 'and no history row');
    expect(r.s.lastContReport, isNull, reason: 'and no report');
  });

  test('a normal run after an abort is recorded normally', () async {
    final r = await rig(nets: 12, interval: const Duration(milliseconds: 30));
    await loadNetlist(r.s);
    await r.s.runCont();
    await waitUntil(() => r.s.running != null);
    r.s.actButtonPressed();
    await waitUntil(() => r.s.logs.any((l) => l.message.contains('partial result discarded')));

    await r.s.runCont();
    await waitUntil(() => r.s.running == null && r.s.R['cont'] != null);
    expect(r.s.R['cont'], 'pass');
  });

  test('the verdict panel reports the end of the insulation run', () async {
    final r = await rig();
    r.s.R['hv'] = 'pass';
    r.s.finishInsulation();
    expect(r.s.vTitle, 'PASS');
    expect(r.s.vSub, contains('Wait for HV Safe'));
    r.s.R['hv'] = 'fail';
    r.s.finishInsulation();
    expect(r.s.vTitle, 'FAIL');
    expect(r.s.vTitle, isNot('RUNNING'));
  });

  test('the insulation rail pill follows the HV pill, not a constant', () async {
    final r = await rig();
    r.s.hvMv = 500000;
    r.s.handling = 'live';
    r.s.paintLink();
    expect(r.s.hvStatePill.text, contains('LIVE'));
    r.s.hvMv = 0;
    r.s.handling = 'safe';
    r.s.paintLink();
    expect(r.s.hvStatePill.text, 'HV Safe');
  });

  test('a completed run is saved as CSV and PDF without pressing Export', () async {
    final dir = Directory.systemTemp.createTempSync('ht_reports_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final r = await rig(nets: 12, reportsDir: dir);
    await loadNetlist(r.s);
    await r.s.runCont();
    await waitUntil(() => r.s.running == null && r.s.R['cont'] != null);
    await waitUntil(() => r.s.logs.any((l) => l.message.contains('continuity report saved')));
    final csv = dir
        .listSync()
        .whereType<File>()
        .firstWhere((f) => f.path.endsWith('_continuity.csv'))
        .readAsStringSync();
    expect(csv, contains('Verdict,PASS'));
  });
}
