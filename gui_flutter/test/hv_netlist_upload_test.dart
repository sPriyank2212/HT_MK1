// A separate HV netlist reaches the instrument: sent just before the insulation
// run, results named from it, and the continuity netlist sent back before the
// next continuity / resistance run. The instrument keeps ONE netlist and the
// firmware's insulation test reads it (HI = HS relay on card (hi-1)/64).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ht_mk1_gui/app/app_state.dart';
import 'package:ht_mk1_gui/client/netlist_doc.dart';
import 'package:ht_mk1_gui/design/model.dart';
import 'package:ht_mk1_gui/htproto/connection.dart';
import 'package:ht_mk1_gui/htproto/simulator.dart';

class Rig {
  late SimulatorServer sim;
  late ConnectionManager cm;
  late AppState s;
}

Future<Rig> rig(WidgetTester tester, {bool upload = true}) async {
  final r = Rig();
  await tester.runAsync(() async {
    r.sim = await SimulatorServer.start(makeScenario('pass', nets: 20),
        port: 0, interval: Duration.zero);
    r.cm = ConnectionManager(
      onEvent: (m) => r.s.onEvent(m),
      onLinkState: (st, d) => r.s.onLinkState(st, d),
      logDir: Directory.systemTemp,
    );
    r.s = AppState(
      cm: r.cm,
      host: '127.0.0.1',
      port: r.sim.port,
      serialLink: false,
      pickNetlistFile: () async => (
            'mtx.xlsx',
            File('required_format/example_netlist27072026.xlsx')
                .readAsBytesSync()
          ),
    );
    r.s.uploadHvNetlist = upload;
    await r.s.connect();
    await r.s.browseMtxNetlist();
  });
  addTearDown(() async {
    await r.cm.disconnect();
    await r.sim.stop();
    setActiveFixture(buildDefaultFixture());
  });
  return r;
}

Future<void> until(WidgetTester tester, bool Function() cond) async {
  final sw = Stopwatch()..start();
  while (!cond()) {
    if (sw.elapsedMilliseconds > 15000) fail('timed out');
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump();
  }
}

/// Five HV nets: three on card 1, two on card 2.
NetlistDoc hvDoc() {
  final d = NetlistDoc.blank(NetlistKind.hv);
  d.fillStraightThrough(3, 1, netPrefix: 'HVNET_');
  d.fillStraightThrough(2, 70, netPrefix: 'HVNET_');
  return d;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('insulation runs over the HV netlist and names its nets',
      (tester) async {
    final r = await rig(tester);
    final s = r.s;
    s.setStack(2);
    await tester.runAsync(() => s.loadHvNetlistBytes('hv.xlsx', hvDoc().toXlsx()));
    expect(s.nlHv.loaded, isTrue);
    expect(s.nlHv.nets, 5);
    expect(s.nlHv.cards, 2);

    await tester.runAsync(() => s.confirmHandover());
    s.runInsulation();
    await tester.runAsync(() => s.runHv());
    await until(tester, () => s.running == null && s.R['hv'] != null);

    final rows = s.insulRowsLive;
    expect(rows.length, 5, reason: 'the 5 HV nets, not the 20 continuity nets');
    expect(rows.map((x) => x.net), ['HVNET_1', 'HVNET_2', 'HVNET_3', 'HVNET_4', 'HVNET_5']);
    expect(rows.map((x) => x.hvCard), ['H1', 'H1', 'H1', 'H2', 'H2']);
    expect(rows.map((x) => x.hsPin),
        ['HS-01', 'HS-02', 'HS-03', 'HS-06', 'HS-07']);
    expect(s.lastInsulReport!.meta.netlistName, 'hv.xlsx');
  });

  testWidgets('the continuity netlist is sent back before the next continuity run',
      (tester) async {
    final r = await rig(tester);
    final s = r.s;
    s.setStack(2);
    await tester.runAsync(() => s.loadHvNetlistBytes('hv.xlsx', hvDoc().toXlsx()));
    await tester.runAsync(() => s.confirmHandover());
    await tester.runAsync(() => s.runHv());
    await until(tester, () => s.running == null && s.R['hv'] != null);
    expect(s.insulRowsLive.length, 5);

    // back to the Matrix connector
    s.resetAll();
    await tester.runAsync(() => s.runCont());
    await until(tester, () => s.running == null && s.R['cont'] != null);
    expect(s.contRowsLive.length, 20,
        reason: 'continuity must run over the 20-pair continuity netlist, not the 5-net HV one');
    expect(s.logs.any((e) => e.message.contains('continuity netlist sent back')), isTrue);
  });

  testWidgets('an HS pin beyond the fitted cards is refused before anything is armed',
      (tester) async {
    final r = await rig(tester);
    final s = r.s;
    s.setStack(1); // pins 1..64 only; the doc has pins 70 and 71
    await tester.runAsync(() => s.loadHvNetlistBytes('hv.xlsx', hvDoc().toXlsx()));
    await tester.runAsync(() => s.confirmHandover());
    await tester.runAsync(() => s.runHv());
    await tester.pump();
    expect(s.running, isNull);
    expect(s.insulRowsLive, isEmpty);
    expect(s.armed, isFalse);
    expect(s.logs.any((e) => e.message.contains('only 1 HV card')), isTrue);
  });

  testWidgets('with the upload switched off (the console default) nothing changes',
      (tester) async {
    final r = await rig(tester, upload: false);
    final s = r.s;
    s.setStack(2);
    await tester.runAsync(() => s.loadHvNetlistBytes('hv.xlsx', hvDoc().toXlsx()));
    await tester.runAsync(() => s.confirmHandover());
    await tester.runAsync(() => s.runHv());
    await until(tester, () => s.running == null && s.R['hv'] != null);
    expect(s.insulRowsLive.length, 20,
        reason: 'the instrument still holds the continuity netlist');
  });
}
