/// Demo-fixture smoke test — proves the three `test_netlists/` sample
/// harnesses actually pass a verify-mode continuity run in `--sim` mode, the
/// same way an operator would for a client demo: browse the real `.xlsx`
/// file, then `CONT RUN verify`.
///
/// This exists because launching `--sim` with its default `--nets 12` and
/// then loading `AV-880_MTX_118net.xlsx` produces a real FAIL — the
/// simulator only models the net count it was told about (`makeScenario`'s
/// `_goodNets`), so nets beyond that read as NOT CONNECTED. The launch
/// command's `--nets` must match the loaded file's net count. Pinned here so
/// a client demo never hits that mismatch live.
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
    if (sw.elapsed > timeout) {
      fail('condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  group('test_netlists/ demo fixtures pass CONT RUN verify in --sim mode', () {
    for (final MapEntry(key: fileName, value: nets) in const {
      'AV-880_MTX_12net.xlsx': 12,
      'AV-880_MTX_24net.xlsx': 24,
      'AV-880_MTX_118net.xlsx': 118,
    }.entries) {
      test('$fileName ($nets nets, --sim --nets $nets)', () async {
        final path = '${Directory.current.path}/../test_netlists/$fileName';
        final bytes = File(path).readAsBytesSync();

        final sim = await SimulatorServer.start(
          makeScenario('pass', nets: nets),
          port: 0,
          interval: Duration.zero,
        );
        addTearDown(sim.stop);

        late final AppState s;
        final cm = ConnectionManager(
          onEvent: (m) => s.onEvent(m),
          onLinkState: (st, d) => s.onLinkState(st, d),
          logDir: Directory.systemTemp,
        );
        addTearDown(cm.disconnect);
        s = AppState(
          cm: cm,
          host: '127.0.0.1',
          port: sim.port,
          pickNetlistFile: () async => (fileName, bytes),
        );

        await s.connect();
        await s.browseMtxNetlist();
        expect(s.nlMtx.loaded, isTrue);
        expect(s.nets.length, nets);

        s.setMode('net');
        expect(s.can('cont').$1, isTrue, reason: s.can('cont').$2);
        await s.runCont();
        await waitUntil(() => s.running == null);

        expect(s.R['cont'], 'pass');
      });
    }
  });
}
