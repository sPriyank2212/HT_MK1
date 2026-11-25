// Throwaway: renders the GUI's screens to PNG for the customer documents.
// Not committed. Run: flutter test --dart-define=CUSTOMER_BUILD=true test/zz_shots_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ht_mk1_gui/app/app_state.dart';
import 'package:ht_mk1_gui/design/model.dart';
import 'package:ht_mk1_gui/design/tokens.dart';
import 'package:ht_mk1_gui/htproto/connection.dart';
import 'package:ht_mk1_gui/htproto/simulator.dart';
import 'package:ht_mk1_gui/main.dart';

const String kOut =
    'C:/Users/psoni/AppData/Local/Temp/claude/c--Users-psoni-STM32CubeIDE-workspace-1-19-0-HT-MK1/cfb11f2d-f7d5-4593-b71e-355888b1afea/scratchpad/shots2';
const String kNetlist =
    'C:/Users/psoni/STM32CubeIDE/workspace_1.19.0/HT_MK1/Customer_Package/1_Test_Harness_Plan/Example_Netlists/Reference_3_connector_example.xlsx';

Future<void> loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      l.addFont(File('C:/Windows/Fonts/$f')
          .readAsBytes()
          .then((b) => ByteData.sublistView(b)));
    }
    await l.load();
  }

  await load('Segoe UI Variable Text', [
    'segoeui.ttf',
    'segoeuib.ttf',
    'segoeuil.ttf',
    'seguisb.ttf',
    'segoeuii.ttf',
  ]);
  await load('Segoe UI', [
    'segoeui.ttf',
    'segoeuib.ttf',
    'segoeuil.ttf',
    'seguisb.ttf',
    'segoeuisl.ttf',
    'segoeuii.ttf',
  ]);
  await load('Cascadia Mono', ['CascadiaMono.ttf']);
  await load('Consolas', ['consola.ttf', 'consolab.ttf']);
}

final GlobalKey _key = GlobalKey();

Widget harness(AppState s, {bool dark = true}) => RepaintBoundary(
      key: _key,
      child: HtTheme(
        isDark: dark,
        child: Builder(
          builder: (context) => Directionality(
            textDirection: TextDirection.ltr,
            child: MediaQuery(
              data: MediaQueryData.fromView(View.of(context)),
              child: DefaultTextStyle(
                style: context.type.body,
                child: HtHome(state: s, onToggleTheme: () {}),
              ),
            ),
          ),
        ),
      ),
    );

Future<void> waitUntil(WidgetTester tester, bool Function() cond,
    {int ms = 15000}) async {
  await tester.runAsync(() async {
    final sw = Stopwatch()..start();
    while (!cond()) {
      if (sw.elapsedMilliseconds > ms) { print('WAIT TIMEOUT'); return; }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  });
}

class Rig {
  late SimulatorServer sim;
  late ConnectionManager cm;
  late AppState s;
}

Future<Rig> newRig(WidgetTester tester,
    {String scenario = 'pass',
    int nets = 20,
    bool connect = true,
    int intervalMs = 0}) async {
  final r = Rig();
  await tester.runAsync(() async {
    r.sim = await SimulatorServer.start(makeScenario(scenario, nets: nets),
        port: 0, interval: Duration(milliseconds: intervalMs));
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
      pickNetlistFile: () async =>
          ('Reference_3_connector_example.xlsx', File(kNetlist).readAsBytesSync()),
    );
    if (connect) await r.s.connect();
  });
  addTearDown(() async {
    await r.cm.disconnect();
    await r.sim.stop();
    setActiveFixture(buildDefaultFixture());
  });
  return r;
}

Future<void> snap(WidgetTester tester, AppState s, String name,
    {double w = 1920, double h = 1080, bool dark = true}) async {
  tester.view.physicalSize = Size(w, h);
  tester.view.devicePixelRatio = 1.0;
  await tester.pumpWidget(harness(s, dark: dark));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.runAsync(() async {
    final b = _key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: 1.0);
    final bd = await img.toByteData(format: ui.ImageByteFormat.png);
    Directory(kOut).createSync(recursive: true);
    File('$kOut/$name.png').writeAsBytesSync(bd!.buffer.asUint8List());
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadFonts);
  tearDown(() => setActiveFixture(buildDefaultFixture()));

  testWidgets('main workflow', (tester) async {
    addTearDown(tester.view.reset);
    final r = await newRig(tester, intervalMs: 40);
    final s = r.s;

    await snap(tester, s, '01_run_idle');
    s.openMtxNlExplainer();
    await snap(tester, s, '02_mtx_modal');
    s.closeMtxNlExplainer();

    await tester.runAsync(() => s.browseMtxNetlist());
    await snap(tester, s, '03_confirm_layout', h: 1250);
    s.confirmFixtureGuess(List<ConnectorDef>.of(kFix.connectors));
    await snap(tester, s, '04_run_ready');

    await tester.runAsync(() => s.runCont());
    await waitUntil(tester, () => s.running == null && s.R['cont'] != null);
    s.go('cont');
    await snap(tester, s, '05_continuity', h: 2700);

    await tester.runAsync(() => s.runRes());
    await waitUntil(tester, () => s.running == null && s.R['res'] != null);
    s.go('res');
    await snap(tester, s, '06_resistance', h: 1800);

    s.go('run');
    await snap(tester, s, '07_run_handover');

    await tester.runAsync(() => s.confirmHandover());
    await snap(tester, s, '08_run_armed');
    s.go('hv');
    await snap(tester, s, '09_insulation_idle', h: 1700);

    s.runInsulation(); // on J-HV with no HV netlist: asks for one
    await snap(tester, s, '10_hv_netlist_modal');
    await tester.runAsync(() => s.browseHvNetlist());
    await snap(tester, s, '11_verify_modal');
    s.setAck(true);
    await snap(tester, s, '12_verify_ack');
    s.confirmEnergize();
    await waitUntil(tester, () => s.running != null && s.insulRowsLive.length >= 9, ms: 8000);
    await snap(tester, s, '13_hazard_running');
    await waitUntil(tester, () => s.running == null && s.R['hv'] != null);
    await snap(tester, s, '14_insulation_done', h: 1700);

    s.go('results');
    await snap(tester, s, '15_results', h: 1300);
    s.go('program');
    await snap(tester, s, '16_netlist_screen', h: 1500);
    s.toggleLog();
    s.go('run');
    await snap(tester, s, '22_log_expanded');
  });

  testWidgets('auto scan', (tester) async {
    addTearDown(tester.view.reset);
    final r = await newRig(tester, nets: 12);
    final s = r.s;
    s.go('auto');
    await snap(tester, s, '17_autoscan_idle', h: 900);
    await tester.runAsync(() => s.runAutoScan());
    await waitUntil(tester, () => s.running == null && s.discoveredPairs.isNotEmpty);
    await snap(tester, s, '18_autoscan_done', h: 1300);
  });

  testWidgets('prerequisite prompt and states', (tester) async {
    addTearDown(tester.view.reset);
    final r = await newRig(tester);
    final s = r.s;
    s.runInsulation();
    await snap(tester, s, '19_pretest_prompt');

    final off = await newRig(tester, connect: false);
    await snap(tester, off.s, '24_disconnected');
    final light = await newRig(tester);
    await snap(tester, light.s, '23_run_light', dark: false);
  });

  testWidgets('faulty harness', (tester) async {
    addTearDown(tester.view.reset);
    final r = await newRig(tester, scenario: 'opens_shorts');
    final s = r.s;
    await tester.runAsync(() => s.browseMtxNetlist());
    s.confirmFixtureGuess(List<ConnectorDef>.of(kFix.connectors));
    await tester.runAsync(() => s.runCont());
    await waitUntil(tester, () => s.running == null && s.R['cont'] != null);
    await snap(tester, s, '20_run_fail');
    s.go('cont');
    await snap(tester, s, '21_continuity_fail', h: 2700);
  });
}
