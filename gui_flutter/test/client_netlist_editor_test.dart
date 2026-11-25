// The client's netlist editor, driven through the real window: create a
// continuity / resistance netlist and an HV netlist, see validation, apply them
// to the test, and edit one that is already loaded.
//
// Set CLIENT_SHOTS_OUT=<dir> to also write PNGs.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ht_mk1_gui/app/app_state.dart';
import 'package:ht_mk1_gui/client/client_app.dart';
import 'package:ht_mk1_gui/client/client_controller.dart';
import 'package:ht_mk1_gui/client/client_netlist_editor.dart';
import 'package:ht_mk1_gui/client/netlist_doc.dart';
import 'package:ht_mk1_gui/design/model.dart';
import 'package:ht_mk1_gui/htproto/connection.dart';
import 'package:ht_mk1_gui/htproto/simulator.dart';

final String? kShots = Platform.environment['CLIENT_SHOTS_OUT'];
final GlobalKey _boundary = GlobalKey();

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      final file = File('C:/Windows/Fonts/$f');
      if (file.existsSync()) {
        l.addFont(file.readAsBytes().then((b) => ByteData.sublistView(b)));
      }
    }
    await l.load();
  }

  await load('Segoe UI', ['segoeui.ttf', 'segoeuib.ttf', 'seguisb.ttf', 'segoeuii.ttf']);
}

class Rig {
  late SimulatorServer sim;
  late ConnectionManager cm;
  late AppState s;
}

Future<Rig> newRig(WidgetTester tester) async {
  final r = Rig();
  await tester.runAsync(() async {
    r.sim = await SimulatorServer.start(makeScenario('pass', nets: 6),
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
      pickSavePath: ({required dialogTitle, required fileName, required allowedExtensions}) async => null,
    );
    await r.s.connect();
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

Future<void> shot(WidgetTester tester, String name) async {
  await tester.pump(const Duration(milliseconds: 300));
  final out = kShots;
  if (out == null) return;
  await tester.runAsync(() async {
    final b = _boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: 1.0);
    final bd = await img.toByteData(format: ui.ImageByteFormat.png);
    Directory(out).createSync(recursive: true);
    File('$out/$name.png').writeAsBytesSync(bd!.buffer.asUint8List());
  });
}

Future<ClientController> boot(WidgetTester tester, AppState s) async {
  tester.view.physicalSize = const Size(1600, 900);
  tester.view.devicePixelRatio = 1.0;
  await tester.pumpWidget(RepaintBoundary(key: _boundary, child: ClientApp(state: s)));
  await tester.pump(const Duration(milliseconds: 300));
  final st = tester.state<State>(find.byType(ClientApp));
  return (st as dynamic).ctl as ClientController;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadFonts);
  tearDown(() => setActiveFixture(buildDefaultFixture()));

  testWidgets('New → Add Wire → Apply loads a continuity netlist', (tester) async {
    addTearDown(tester.view.reset);
    final r = await newRig(tester);
    await boot(tester, r.s);

    await tester.tap(find.text('New').first); // the Netlist card's New
    await tester.pump();
    expect(find.text('Netlist Editor — Continuity / Resistance (J-MTX)'), findsOneWidget);
    expect(find.text('No wires yet — Add Wire, or add straight-through wires above.'),
        findsOneWidget);
    expect(find.text('The netlist has no wires.'), findsOneWidget);

    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('Add Wire'));
      await tester.pump();
    }
    expect(find.text('4 wires'), findsOneWidget);
    expect(find.text('Netlist is valid.'), findsOneWidget);
    await shot(tester, '30_editor_mtx');

    await tester.tap(find.text('Apply to test'));
    await until(tester, () => r.s.nlMtx.loaded);
    await tester.pumpAndSettle();
    expect(r.s.nlMtx.name, 'new_netlist.xlsx');
    expect(r.s.mtxRows.map((p) => (p.hi, p.lo)), [(1, 1), (2, 2), (3, 3), (4, 4)]);
    expect(find.text('Netlist Editor — Continuity / Resistance (J-MTX)'), findsNothing,
        reason: 'the editor closes after Apply');
    await tester.pumpAndSettle(const Duration(seconds: 6));
  });

  testWidgets('an invalid row blocks Apply and says why', (tester) async {
    addTearDown(tester.view.reset);
    final r = await newRig(tester);
    await boot(tester, r.s);
    await tester.tap(find.text('New').first);
    await tester.pump();
    await tester.tap(find.text('Add Wire'));
    await tester.tap(find.text('Add Wire'));
    await tester.pump();

    // make row 2 repeat row 1's pins
    await tester.enterText(find.widgetWithText(TextField, '2').first, '1');
    await tester.enterText(find.widgetWithText(TextField, '2').first, '1');
    await tester.pump();
    expect(find.textContaining('repeats row 1'), findsOneWidget);
    expect(find.text('1 error'), findsOneWidget);
    await shot(tester, '31_editor_error');

    await tester.tap(find.text('Apply to test'));
    await tester.pump();
    expect(find.text('Fix 1 error before applying.'), findsOneWidget);
    expect(r.s.nlMtx.loaded, isFalse);
    await tester.pumpAndSettle(const Duration(seconds: 6));
  });

  testWidgets('HV editor: card/relay shown, beyond-stack pin refused, apply loads it',
      (tester) async {
    addTearDown(tester.view.reset);
    final r = await newRig(tester);
    final ctl = await boot(tester, r.s);
    r.s.setStack(1);
    openNetlistEditor(tester.element(find.byType(Scaffold).first), ctl,
        NetlistKind.hv,
        blank: true);
    await tester.pump();
    expect(find.text('Netlist Editor — HV Insulation (J-HV)'), findsOneWidget);

    await tester.tap(find.text('Add Wire'));
    await tester.tap(find.text('Add Wire'));
    await tester.pump();
    // row 2: HS pin 2 -> 70 (card 2, but only one card is fitted)
    await tester.enterText(find.widgetWithText(TextField, '2').first, '70');
    await tester.pump();
    expect(find.textContaining('beyond the fitted HV cards'), findsOneWidget);
    await shot(tester, '32_editor_hv_error');
    await tester.tap(find.text('Apply to test'));
    await tester.pump();
    expect(r.s.nlHv.loaded, isFalse);

    // two cards fitted now: the same netlist is valid, pin 70 is card 2 relay 6
    r.s.setStack(2);
    await tester.tap(find.text('Add Wire'));
    await tester.pump();
    expect(find.text('Netlist is valid.'), findsOneWidget);
    expect(find.text('H2'), findsWidgets);
    expect(find.text('HS-06'), findsWidgets);
    await shot(tester, '33_editor_hv_ok');
    await tester.tap(find.text('Apply to test'));
    await until(tester, () => r.s.nlHv.loaded);
    await tester.pumpAndSettle();
    expect(r.s.nlHv.name, 'new_hv_netlist.xlsx');
    expect(r.s.hvRows.map((p) => p.hi), [1, 70, 71]);
    await tester.pumpAndSettle(const Duration(seconds: 6));
  });

  testWidgets('Edit opens the loaded netlist and Apply re-loads the change',
      (tester) async {
    addTearDown(tester.view.reset);
    final r = await newRig(tester);
    final ctl = await boot(tester, r.s);
    final doc = NetlistDoc.blank(NetlistKind.mtx)
      ..fillStraightThrough(3, 1)
      ..harnessId = 'HRN-9';
    await tester.runAsync(() => r.s.loadMtxNetlistBytes('first.xlsx', doc.toXlsx()));
    await tester.pump();
    expect(r.s.nlMtx.name, 'first.xlsx');

    await tester.tap(find.text('Edit').first);
    await tester.pump();
    expect(find.text('3 wires'), findsOneWidget);
    expect(find.text('HRN-9'), findsOneWidget);

    await tester.tap(find.text('Add Wire'));
    await tester.pump();
    expect(find.text('4 wires'), findsOneWidget);
    await tester.tap(find.text('Apply to test'));
    await until(tester, () => r.s.mtxRows.length == 4);
    expect(r.s.nlHarnessId, 'HRN-9');
    expect(ctl.autoScan, isFalse);
    await tester.pumpAndSettle(const Duration(seconds: 6));
  });
}
