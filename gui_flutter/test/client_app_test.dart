// The client-styled app against the built-in simulator: connect, load a
// netlist, run each mode, check the Results Table, the verdict, the summary
// chips, the two-stage HV prompts and the DUT ID auto-increment.
//
// Set CLIENT_SHOTS_OUT=<dir> to also write a PNG of each state.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ht_mk1_gui/app/app_state.dart';
import 'package:ht_mk1_gui/client/client_app.dart';
import 'package:ht_mk1_gui/client/client_controller.dart';
import 'package:ht_mk1_gui/client/client_dialogs.dart';
import 'package:ht_mk1_gui/client/client_output.dart';
import 'package:ht_mk1_gui/client/client_model.dart';
import 'package:ht_mk1_gui/design/model.dart';
import 'package:ht_mk1_gui/htproto/connection.dart';
import 'package:ht_mk1_gui/htproto/simulator.dart';

const String kNetlistPath = 'required_format/example_netlist27072026.xlsx';

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
  await load('Consolas', ['consola.ttf', 'consolab.ttf']);
}

class Rig {
  late SimulatorServer sim;
  late ConnectionManager cm;
  late AppState s;
}

Future<Rig> newRig(WidgetTester tester,
    {String scenario = 'pass', int nets = 22, bool connect = true}) async {
  final r = Rig();
  await tester.runAsync(() async {
    r.sim = await SimulatorServer.start(makeScenario(scenario, nets: nets),
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
      pickNetlistFile: () async =>
          ('example_netlist27072026.xlsx', File(kNetlistPath).readAsBytesSync()),
      pickSavePath: ({required dialogTitle, required fileName, required allowedExtensions}) async => null,
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

/// Waits for [cond], pumping as it goes: a run started from the test body
/// lives in the fake-async zone, and its continuations only advance when the
/// test pumps — socket I/O only advances in real time.
Future<void> waitUntil(WidgetTester tester, bool Function() cond,
    {int ms = 15000}) async {
  final sw = Stopwatch()..start();
  while (!cond()) {
    if (sw.elapsedMilliseconds > ms) fail('timed out waiting');
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump();
  }
}

Future<void> boot(WidgetTester tester, AppState s,
    {double w = 1600, double h = 900}) async {
  tester.view.physicalSize = Size(w, h);
  tester.view.devicePixelRatio = 1.0;
  await tester.pumpWidget(
      RepaintBoundary(key: _boundary, child: ClientApp(state: s)));
  await tester.pump(const Duration(milliseconds: 300));
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

ClientController ctlOf(WidgetTester tester) {
  final st = tester.state<State>(find.byType(ClientApp));
  // ignore: avoid_dynamic_calls
  return (st as dynamic).ctl as ClientController;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadFonts);
  tearDown(() => setActiveFixture(buildDefaultFixture()));

  testWidgets('starts disconnected with the client layout', (tester) async {
    addTearDown(tester.view.reset);
    final r = await newRig(tester, connect: false);
    await boot(tester, r.s);

    expect(find.text('Mode:'), findsOneWidget);
    expect(find.text('Continuity (one-to-one)'), findsOneWidget);
    expect(find.text('START TEST'), findsOneWidget);
    expect(find.text('STOP / ABORT'), findsOneWidget);
    for (final t in ['Connector View', 'Results Table', 'Log', 'Info', 'Configuration']) {
      expect(find.text(t), findsWidgets, reason: 'tab $t');
    }
    expect(find.text('CONNECTION'), findsOneWidget);
    expect(find.text('NETLIST / TEST MODE'), findsOneWidget);
    expect(find.text('TEST PROFILE'), findsOneWidget);
    expect(find.text('Not connected'), findsWidgets);
    expect(find.text('Designed and developed by Infinity Integrations Private Limited'),
        findsOneWidget);
    await shot(tester, '01_idle');
  });

  testWidgets('START is refused with a reason until connected and a netlist is loaded',
      (tester) async {
    addTearDown(tester.view.reset);
    final r = await newRig(tester, connect: false);
    await boot(tester, r.s);
    final ctl = ctlOf(tester);
    expect(ctl.startBlocked, 'Connect to the tester first');
    ctl.start();
    await tester.pump();
    expect(find.text('Connect to the tester first'), findsOneWidget);

    await tester.runAsync(() => r.s.connect());
    await tester.pump();
    expect(ctl.startBlocked, 'Load a netlist first (Browse…)');
    // Auto-Scan needs no netlist.
    ctl.setAutoScan(true);
    expect(ctl.startBlocked, isNull);
    await tester.pumpAndSettle(const Duration(seconds: 6));
  });

  testWidgets('continuity: load netlist, run, table + verdict + chips + DUT++',
      (tester) async {
    addTearDown(tester.view.reset);
    final r = await newRig(tester);
    await boot(tester, r.s);
    final ctl = ctlOf(tester);
    ctl.setDutId('HT-0007');

    await tester.runAsync(() => ctl.browseNetlist());
    await tester.pump();
    expect(r.s.nlMtx.loaded, isTrue);
    expect(find.text('CONNECTED — FW v${r.s.fwVersion}'), findsOneWidget);
    expect(ctl.startBlocked, isNull);
    await shot(tester, '02_netlist_loaded');

    ctl.start();
    await waitUntil(tester, () => r.s.running == null && r.s.R['cont'] != null);
    await tester.pump(const Duration(milliseconds: 100));

    expect(ctl.verdict, 'PASS');
    expect(ctl.rows, isNotEmpty);
    expect(ctl.rows.every((x) => x.status == RowStatus.connected), isTrue);
    expect(r.s.dutId, 'HT-0008', reason: 'DUT ID auto-increments after a test');
    await shot(tester, '03_continuity_pass');

    ctl.showTab(ClientTab.results);
    await tester.pump();
    expect(find.text('CONNECTED'), findsWidgets);
    expect(find.textContaining('Total: ${ctl.rows.length}'), findsOneWidget);
    await shot(tester, '04_results_table');

    // filter: only NOT CONNECTED → nothing
    ctl.setFilter(status: 'NOT CONNECTED');
    await tester.pump();
    expect(ctl.filteredRows, isEmpty);
    expect(find.text('No rows match the filters'), findsOneWidget);
    ctl.clearFilters();
  });

  testWidgets('faulty harness: FAIL verdict and NOT CONNECTED rows', (tester) async {
    addTearDown(tester.view.reset);
    // the simulator's net count must match the netlist's pair count (20)
    final r = await newRig(tester, scenario: 'opens_shorts', nets: 20);
    await boot(tester, r.s);
    final ctl = ctlOf(tester);
    await tester.runAsync(() => ctl.browseNetlist());
    ctl.start();
    await waitUntil(tester, () => r.s.running == null && r.s.R['cont'] != null);
    await tester.pump(const Duration(milliseconds: 100));

    // ignore: avoid_print
    print('DBG rows=${ctl.rows.length} statuses=${ctl.rows.map((x) => x.status.label).toSet()} last=${r.s.logs.last.message}');
    expect(ctl.verdict, 'FAIL');
    final sum = Summary.of(ctl.rows);
    expect(sum.open, greaterThan(0));
    expect(sum.pass + sum.open, sum.total);
    await shot(tester, '05_continuity_fail');
    ctl.showTab(ClientTab.results);
    await tester.pump();
    await shot(tester, '06_results_fail');
  });

  testWidgets('resistance runs after a netlist and fills the R column',
      (tester) async {
    addTearDown(tester.view.reset);
    final r = await newRig(tester);
    await boot(tester, r.s);
    final ctl = ctlOf(tester);
    await tester.runAsync(() => ctl.browseNetlist());
    ctl.setMode(ClientMode.resistance);
    ctl.start();
    await waitUntil(tester, () => r.s.running == null && r.s.R['res'] != null);
    await tester.pump(const Duration(milliseconds: 100));
    expect(ctl.verdict, 'PASS');
    expect(ctl.rows.first.value, isNotEmpty);
    ctl.showTab(ClientTab.results);
    await tester.pump();
    expect(find.text('Resistance (mΩ)'), findsOneWidget);
    await shot(tester, '07_resistance');
    ctl.showTab(ClientTab.connector);
    await tester.pump();
    await shot(tester, '08_resistance_connector');
  });

  testWidgets('ui walkthrough: the sections changed in this round (screenshots)',
      (tester) async {
    addTearDown(tester.view.reset);
    final r = await newRig(tester);
    await boot(tester, r.s);
    final ctl = ctlOf(tester);
    await tester.runAsync(() => ctl.browseNetlist());
    await tester.pump();
    await shot(tester, 'a_netlist_panel_export_button');

    await tester.tap(find.text('File'));
    await tester.pump(const Duration(milliseconds: 300));
    await shot(tester, 'b_file_menu_open_result_folder');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Help'));
    await tester.pumpAndSettle();
    expect(find.text('About'), findsOneWidget);
    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();
    expect(find.text('Integrated Harness Tester MKI'), findsWidgets);
    await shot(tester, 'c_about_integrated_mki');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    ctl.showTab(ClientTab.log);
    await tester.pump();
    await shot(tester, 'd_log_clear_log_moved_apart');

    ctl.setMode(ClientMode.resistance);
    ctl.start();
    await waitUntil(tester, () => r.s.running == null && r.s.R['res'] != null);
    ctl.showTab(ClientTab.results);
    await tester.pump();
    await shot(tester, 'e_results_limit_mohm_header');

    ctl.setMode(ClientMode.multi);
    ctl.showTab(ClientTab.connector);
    await tester.pump();
    await shot(tester, 'f_mode_multi_test_run_selected');
  });

  testWidgets('Multi-Test Run pop-up: pick the tests, Confirm & Exit',
      (tester) async {
    addTearDown(tester.view.reset);
    final r = await newRig(tester);
    await boot(tester, r.s);
    final ctl = ctlOf(tester);
    expect(ctl.multiStages, kMultiOrder); // all four by default
    ctl.setMode(ClientMode.multi);
    showMultiTestDialog(tester.element(find.byType(ClientHome)), ctl);
    await tester.pumpAndSettle();
    expect(find.text('Confirm & Exit'), findsOneWidget);
    expect(find.text('Continuity (one-to-one)'), findsWidgets);
    expect(find.text('Cross Continuity (one-to-many)'), findsWidgets);
    expect(find.text('Resistance (4-wire Kelvin)'), findsWidgets);
    expect(find.text('HV Insulation (IR) Test (500 V DC)'), findsOneWidget);
    await shot(tester, 'g_multi_test_popup');
    // untick Cross Continuity inside the pop-up, then confirm
    await tester.tap(find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Cross Continuity (one-to-many)')));
    await tester.pump();
    await tester.tap(find.text('Confirm & Exit'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm & Exit'), findsNothing);
    expect(ctl.multiStages, [
      ClientMode.continuity,
      ClientMode.resistance,
      ClientMode.insulation,
    ]);
    await shot(tester, 'h_control_bar_after_popup');
  });

  testWidgets('logs, results and netlists are copied into separate folders',
      (tester) async {
    addTearDown(tester.view.reset);
    final r = await newRig(tester);
    await boot(tester, r.s);
    final ctl = ctlOf(tester);
    await tester.runAsync(() => ctl.browseNetlist());
    final root = Directory.systemTemp.createTempSync('ht_out_');
    addTearDown(() => root.deleteSync(recursive: true));
    final out = ClientOutput(ctl, rootOf: () => root);
    final n = out.save();
    expect(n, greaterThanOrEqualTo(2));
    String at(String leaf) => '${root.path}${Platform.pathSeparator}$leaf';
    expect(Directory(at('Logs')).listSync().map((e) => e.path),
        contains(endsWith('.txt')));
    expect(Directory(at('Netlists')).listSync().map((e) => e.path),
        contains(endsWith('.xlsx')));
  });

  testWidgets('multi-test run chains continuity into resistance, in order',
      (tester) async {
    addTearDown(tester.view.reset);
    final r = await newRig(tester);
    await boot(tester, r.s);
    final ctl = ctlOf(tester);
    await tester.runAsync(() => ctl.browseNetlist());
    ctl.setMode(ClientMode.multi);
    // continuity -> resistance -> insulation (cross continuity has its own
    // test below: aborting a 256 x 256 sweep is not what this one is about)
    ctl.setMultiSelection({
      ClientMode.continuity,
      ClientMode.resistance,
      ClientMode.insulation,
    });
    expect(ctl.startBlocked, isNull);
    ctl.start();
    await tester.pump();
    // stage 1 on screen while it runs
    expect(ctl.viewMode, ClientMode.continuity);
    expect(ctl.verdict, '—');
    await waitUntil(tester, () => r.s.R['cont'] != null && r.s.running == null);
    // the next stage starts on its own after continuity ends. The simulator is
    // fast, so resistance may already be done: accept any stage after it.
    await waitUntil(tester, () => ctl.viewMode != ClientMode.continuity);
    expect(
        ctl.viewMode == ClientMode.resistance ||
            ctl.viewMode == ClientMode.insulation,
        isTrue);
    // stop before the HV stage: it needs the operator's safety prompts
    ctl.stop();
    await waitUntil(tester, () => r.s.running == null && !ctl.multiActive);
    expect(ctl.verdict, isNot('DONE'));
  });

  testWidgets('multi-test run with only Cross Continuity runs the sweep',
      (tester) async {
    addTearDown(tester.view.reset);
    final r = await newRig(tester);
    await boot(tester, r.s);
    final ctl = ctlOf(tester);
    await tester.runAsync(() => ctl.browseNetlist());
    ctl.setMode(ClientMode.multi);
    ctl.setMultiSelection({ClientMode.cross});
    expect(ctl.startBlocked, isNull);
    ctl.start();
    await tester.pump();
    expect(ctl.viewMode, ClientMode.cross);
    await waitUntil(tester, () => ctl.verdict != '—', ms: 60000);
    // the stage ran and was judged: DONE if the sweep matched the netlist
    expect(ctl.verdict, anyOf('DONE', 'FAIL'));
    expect(r.s.discoveredPairs, isNotEmpty);
  });

  testWidgets('insulation without pre-tests asks, then needs every box ticked',
      (tester) async {
    addTearDown(tester.view.reset);
    final r = await newRig(tester);
    await boot(tester, r.s);
    final ctl = ctlOf(tester);
    ctl.setMode(ClientMode.insulation);
    expect(ctl.startBlocked, isNull);
    ctl.start();
    await tester.pump();
    expect(find.text('Run continuity and resistance first?'), findsOneWidget);
    await shot(tester, '09_prerequisite_prompt');

    await tester.runAsync(() => r.s.continueToInsulation(skipped: true));
    await tester.pump();
    // no HV netlist yet → asks for one
    expect(find.text('Select the HV netlist'), findsOneWidget);
    await shot(tester, '10_hv_netlist');
    r.s.loadHv('hv.xlsx', 3, 10);
    r.s.mdNlOpen = false;
    r.s.openVerify();
    await tester.pump();

    expect(find.text('HIGH VOLTAGE TEST — SAFETY WARNING'), findsOneWidget);
    // GUI-DLG-HV-003: CONFIRM is disabled until all three boxes are ticked.
    Finder confirm() => find.text('CONFIRM AND START');
    await tester.tap(confirm());
    await tester.pump();
    expect(r.s.running, isNull, reason: 'must not energise with no boxes ticked');
    await shot(tester, '11_hv_confirm_unticked');

    for (final label in [
      'Safety enclosure lid is fully closed and latched',
      'No personnel are in contact with the DUT or connectors',
    ]) {
      await tester.tap(find.text(label));
      await tester.pump();
    }
    await tester.tap(confirm());
    await tester.pump();
    expect(r.s.running, isNull, reason: 'two of three boxes is not enough');

    await tester.tap(find.text('DUT is fully isolated from external power supplies'));
    await tester.pump();
    await shot(tester, '12_hv_confirm_ticked');
    await tester.tap(confirm());
    await waitUntil(tester, () => r.s.running == null && r.s.R['hv'] != null);
    await tester.pump(const Duration(milliseconds: 100));
    expect(ctl.verdict, anyOf('PASS', 'FAIL'));
    expect(r.s.insulRowsLive, isNotEmpty);
    await shot(tester, '13_insulation_done');
    ctl.showTab(ClientTab.results);
    await tester.pump();
    expect(find.text('Insulation (MΩ)'), findsOneWidget);
    await shot(tester, '14_insulation_results');
  });

  testWidgets('auto-scan lists only present connections; Use as Netlist works',
      (tester) async {
    addTearDown(tester.view.reset);
    final r = await newRig(tester, nets: 12);
    await boot(tester, r.s);
    final ctl = ctlOf(tester);
    ctl.setAutoScan(true);
    ctl.start();
    await waitUntil(tester, () => r.s.running == null && r.s.discoveredPairs.isNotEmpty);
    await tester.pump(const Duration(milliseconds: 100));
    expect(ctl.verdict, 'DONE');
    expect(ctl.rows.length, r.s.discoveredPairs.length);
    await shot(tester, '15_autoscan');
    await tester.runAsync(() => ctl.useAutoScanAsNetlist());
    await tester.pump();
    expect(ctl.autoScan, isFalse);
    expect(r.s.nlMtx.loaded, isTrue);
    await tester.pumpAndSettle(const Duration(seconds: 6));
  });

  testWidgets('light theme and the other tabs render', (tester) async {
    addTearDown(tester.view.reset);
    final r = await newRig(tester);
    await boot(tester, r.s);
    final ctl = ctlOf(tester);
    for (final t in [ClientTab.log, ClientTab.info, ClientTab.config]) {
      ctl.showTab(t);
      await tester.pump();
      await shot(tester, '20_tab_${t.name}');
    }
    ctl.setTheme(false);
    ctl.showTab(ClientTab.connector);
    await tester.pump();
    await shot(tester, '21_light');
    await tester.pumpAndSettle(const Duration(seconds: 6));
  });

  test('DUT id increments its trailing number like the client', () {
    expect(ClientController.nextDutId('HT-0001'), 'HT-0002');
    expect(ClientController.nextDutId('HT-0099'), 'HT-0100');
    expect(ClientController.nextDutId('HRN9'), 'HRN10');
    expect(ClientController.nextDutId('ABC'), 'ABC-2');
    expect(ClientController.nextDutId(''), '');
  });
}
