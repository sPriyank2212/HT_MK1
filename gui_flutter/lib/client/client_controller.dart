/// UI state of the client app, on top of the shared [AppState]: the selected
/// test mode, Standard vs Auto-Scan, the active tab, the theme, the Test
/// Profile (operator, harness id, DUT id, connection defaults) and toasts.
///
/// The run itself — gating, the two-stage HV sequence, the instrument link —
/// is [AppState]'s; this class only decides *which* of its runs the client's
/// START button means, and mirrors the client's rules (DUT ID auto-increment
/// after each test, START disabled without a netlist, one report per run).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../app/app_state.dart';
import '../app/report.dart';
import '../design/model.dart' show kFix;
import '../htproto/netlist_file.dart' show WireMeta;
import '../htproto/netlist_formats.dart';
import 'client_model.dart';
import 'client_report.dart';
import 'netlist_doc.dart';

/// Tabs of the centre panel, in the client's order.
enum ClientTab {
  connector('Connector View'),
  results('Results Table'),
  log('Log'),
  info('Info'),
  config('Configuration');

  final String title;
  const ClientTab(this.title);
}

class ClientToast {
  final String text;
  final String kind; // info | success | warning | error
  const ClientToast(this.text, this.kind);
}

class ClientController extends ChangeNotifier {
  final AppState s;

  /// Where profiles and settings live (`…/HT_MK1/client`). Null = in memory
  /// only (tests).
  final Directory? dataDir;

  ClientMode mode = ClientMode.continuity;
  bool autoScan = false;
  ClientTab tab = ClientTab.connector;
  bool dark;

  // ---- Test Profile -------------------------------------------------------
  String profile = 'Default';
  List<String> profiles = ['Default'];
  String harnessId = '';
  String connector = '';
  String source = '';
  String destination = '';
  bool profileDirty = false;

  // ---- results-table filters ---------------------------------------------
  String statusFilter = 'All';
  String search = '';

  // ---- toast --------------------------------------------------------------
  ClientToast? toast;
  Timer? _toastTimer;

  bool _wasRunning = false;
  bool _wasConnected = false;

  /// Set by the app to copy the session's log / results / netlists into the
  /// GUI folder (`client_output.dart`); null in tests.
  void Function()? saveOutputs;
  Timer? _outputTimer;

  /// The folder Auto-Scan's Export writes into (the GUI folder's `Netlists`);
  /// null in tests that do not set one.
  Directory Function()? netlistsDir;

  /// A moment after a run ends, once its report files are on disk.
  void _scheduleOutputSave() {
    if (saveOutputs == null) return;
    _outputTimer?.cancel();
    _outputTimer = Timer(const Duration(seconds: 2), () => saveOutputs?.call());
  }

  // ---- Multi-Test Run: continuity → resistance → insulation ---------------
  /// The stage that ran last (or is running now). The table, verdict and
  /// manual export show this stage.
  ClientMode? _stage;
  final List<ClientMode> _multiQueue = [];

  /// The tests a Multi-Test Run performs (chosen in its pop-up), run in the
  /// order of [kMultiOrder].
  Set<ClientMode> multiSelection = {...kMultiOrder};
  int _multiTotal = 0;

  /// The selected tests in the order they run.
  List<ClientMode> get multiStages =>
      [for (final m in kMultiOrder) if (multiSelection.contains(m)) m];

  void setMultiSelection(Set<ClientMode> sel) {
    multiSelection = {...sel};
    notifyListeners();
  }
  final Map<ClientMode, String> _multiVerdicts = {};
  bool _multiActive = false;
  bool _multiAborted = false;

  /// True once every stage of the last Multi-Test Run has run and none failed.
  bool multiCompleted = false;

  // ---- duration (the control bar's "Duration:") ---------------------------
  DateTime? _runStart;
  Duration? lastDuration;
  Timer? _ticker;

  /// The client's `_fmt_duration`: µs, ms or s as appropriate; `—` when no
  /// test has run.
  String get durationText {
    final d = _runStart != null ? DateTime.now().difference(_runStart!) : lastDuration;
    if (d == null) return '—';
    final us = d.inMicroseconds;
    if (us < 1000) return '$us µs';
    if (us < 1000000) return '${(us / 1000).toStringAsFixed(1)} ms';
    return '${(us / 1e6).toStringAsFixed(2)} s';
  }

  ClientController(this.s, {this.dataDir, this.dark = true}) {
    s.reportFormat = const ClientReportFormat();
    // The client's HV netlist is a real, separate netlist: send it to the
    // instrument for the insulation run (see AppState.uploadHvNetlist).
    s.uploadHvNetlist = true;
    _loadSettings();
    _loadProfiles();
    _applyProfileToState();
    s.addListener(_onState);
  }

  @override
  void dispose() {
    s.removeListener(_onState);
    _toastTimer?.cancel();
    _outputTimer?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // derived
  // -------------------------------------------------------------------------

  bool get running => s.running != null;

  /// The test whose rows, verdict and report are shown. A Multi-Test Run shows
  /// the stage that ran last.
  ClientMode get viewMode =>
      mode == ClientMode.multi ? (_stage ?? ClientMode.continuity) : mode;

  /// Why START is disabled, or null when it can start. The client's rule
  /// (GUI-ACT-001): a connected instrument and a netlist (Standard) — Auto-Scan
  /// needs no netlist.
  String? get startBlocked {
    if (running) return 'A test is already running';
    if (!s.link) return 'Connect to the tester first';
    if (s.inFault) return 'Clear the fault first';
    if (autoScan) return s.canAutoScan.$1 ? null : s.canAutoScan.$2;
    switch (mode) {
      case ClientMode.multi:
        // The first stage's gate; the rest are checked as each one starts.
        return multiStages.isEmpty
            ? 'Select the tests for the Multi-Test Run (Tests…)'
            : _stageBlocked(multiStages.first);
      case ClientMode.continuity:
        if (!s.nlMtx.loaded) return 'Load a netlist first (Browse…)';
        return s.can('cont').$1 ? null : s.can('cont').$2;
      case ClientMode.cross:
        if (!s.nlMtx.loaded) return 'Load a netlist first (Browse…)';
        return s.canAutoScan.$1 ? null : s.canAutoScan.$2;
      case ClientMode.resistance:
        if (!s.nlMtx.loaded) return 'Load a netlist first (Browse…)';
        return s.can('res').$1 ? null : s.can('res').$2;
      case ClientMode.insulation:
        // Always startable: AppState walks the prerequisites / HV prompts.
        return null;
    }
  }

  List<CRow> get rows =>
      rowsFor(s, viewMode, autoScan: autoScan);

  String get verdict {
    if (mode != ClientMode.multi || autoScan) {
      return verdictFor(s, mode, autoScan: autoScan);
    }
    if (s.inFault) return 'FAULT';
    if (_multiActive) return '—';
    if (_multiVerdicts.values.contains('FAIL')) return 'FAIL';
    return multiCompleted ? 'DONE' : '—';
  }

  /// Rows after the Status filter and the search box.
  List<CRow> get filteredRows {
    final q = search.trim().toLowerCase();
    return [
      for (final r in rows)
        if ((statusFilter == 'All' || r.status.label == statusFilter) &&
            (q.isEmpty ||
                [
                  r.labelA, r.labelB, r.source, r.destination, r.connA,
                  r.connB, r.net, r.partA, r.partB, //
                ].any((t) => t.toLowerCase().contains(q))))
          r,
    ];
  }

  // -------------------------------------------------------------------------
  // actions
  // -------------------------------------------------------------------------

  void setMode(ClientMode m) {
    if (running) return;
    mode = m;
    if (m == ClientMode.continuity) s.setMode('net', quiet: true);
    notifyListeners();
  }

  void setAutoScan(bool v) {
    if (running) return;
    autoScan = v;
    notifyListeners();
  }

  void setFilter({String? status, String? query}) {
    statusFilter = status ?? statusFilter;
    search = query ?? search;
    notifyListeners();
  }

  void clearFilters() {
    statusFilter = 'All';
    search = '';
    notifyListeners();
  }

  void showTab(ClientTab t) {
    tab = t;
    notifyListeners();
  }

  void setTheme(bool isDark) {
    dark = isDark;
    _saveSettings();
    notifyListeners();
  }

  void showToast(String text, {String kind = 'info'}) {
    toast = ClientToast(text, kind);
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(seconds: 5), () {
      toast = null;
      notifyListeners();
    });
    notifyListeners();
  }

  /// START TEST (F5).
  void start() {
    final why = startBlocked;
    if (why != null) {
      showToast(why, kind: 'warning');
      return;
    }
    showTab(autoScan || mode == ClientMode.cross
        ? ClientTab.results
        : ClientTab.connector);
    if (autoScan) {
      s.runAutoScan();
      return;
    }
    if (mode == ClientMode.cross) {
      s.runCrossContinuity();
      return;
    }
    switch (mode) {
      case ClientMode.multi:
        _startMulti();
      case ClientMode.continuity:
        s.setMode('net');
        s.runTest('cont');
      case ClientMode.resistance:
        s.runTest('res');
      case ClientMode.insulation:
        s.runInsulation();
      case ClientMode.cross:
        break;
    }
  }

  /// STOP / ABORT (F6). The instrument is told; AppState owns the rest. An
  /// abort also ends a Multi-Test Run: no further stage starts.
  void stop() {
    if (_multiActive) {
      _multiAborted = true;
      _multiQueue.clear();
      if (!running) {
        // between stages (or waiting on a prompt): nothing to abort on the
        // instrument, the sequence just ends
        _multiActive = false;
        notifyListeners();
        return;
      }
    }
    if (running) s.actButtonPressed();
  }

  /// True while a Multi-Test Run is in progress, including the moments between
  /// two of its tests.
  bool get multiActive => _multiActive;

  // -------------------------------------------------------------------------
  // Multi-Test Run
  // -------------------------------------------------------------------------

  /// Runs the tests picked in the Multi-Test pop-up — continuity, cross
  /// continuity, resistance, HV insulation, in that order — one after another,
  /// the same tests the modes run on their own. A stage that fails ends the
  /// sequence (insulation is not run on a harness that failed continuity).
  void _startMulti() {
    final stages = multiStages;
    if (stages.isEmpty) return;
    _multiQueue
      ..clear()
      ..addAll(stages);
    _multiTotal = stages.length;
    _multiVerdicts.clear();
    _multiActive = true;
    _multiAborted = false;
    multiCompleted = false;
    _stage = null;
    _runNextStage();
  }

  /// Gate for one stage, the same rule its own START uses.
  String? _stageBlocked(ClientMode m) {
    if (!s.link) return 'not connected';
    if (s.inFault) return 'clear the fault first';
    switch (m) {
      case ClientMode.continuity:
      case ClientMode.resistance:
        final key = m == ClientMode.continuity ? 'cont' : 'res';
        if (!s.nlMtx.loaded) return 'load a netlist first';
        return s.can(key).$1 ? null : s.can(key).$2;
      case ClientMode.cross:
        if (!s.nlMtx.loaded) return 'load a netlist first';
        return s.canAutoScan.$1 ? null : s.canAutoScan.$2;
      default:
        return null; // insulation walks its own prerequisites and prompts
    }
  }

  /// Starts the next stage, or ends the sequence when none is left.
  void _runNextStage() {
    if (_multiAborted) {
      _multiActive = false;
      notifyListeners();
      return;
    }
    if (_multiQueue.isEmpty) {
      _multiActive = false;
      multiCompleted = _multiVerdicts.length == _multiTotal &&
          !_multiVerdicts.values.contains('FAIL');
      _finishDutId();
      notifyListeners();
      return;
    }
    final next = _multiQueue.removeAt(0);
    _stage = next;
    final why = _stageBlocked(next);
    if (why != null) {
      showToast('Multi-Test Run stopped: $why', kind: 'warning');
      _multiQueue.clear();
      _multiActive = false;
      notifyListeners();
      return;
    }
    switch (next) {
      case ClientMode.continuity:
        s.setMode('net');
        s.runTest('cont');
      case ClientMode.cross:
        s.runCrossContinuity();
      case ClientMode.resistance:
        s.runTest('res');
      case ClientMode.insulation:
        s.runInsulation();
      default:
        break;
    }
    notifyListeners();
  }

  /// Records the verdict of the stage that just ended.
  void _recordStage() {
    final stage = _stage;
    if (stage == null) return;
    final bool passed;
    switch (stage) {
      case ClientMode.continuity:
        passed = s.R['cont'] == 'pass';
      case ClientMode.resistance:
        passed = s.R['res'] == 'pass';
      case ClientMode.insulation:
        passed = s.R['hv'] == 'pass';
      case ClientMode.cross:
        final rs = rowsFor(s, ClientMode.cross, autoScan: false);
        passed =
            rs.isNotEmpty && rs.every((r) => r.status == RowStatus.connected);
      default:
        return;
    }
    _multiVerdicts[stage] = passed ? 'PASS' : 'FAIL';
    if (!passed) {
      _multiQueue.clear();
      showToast('Multi-Test Run stopped: ${stage.label} failed',
          kind: 'warning');
    }
  }

  /// "Use as Netlist": the connections the last Auto-Scan found become the
  /// active netlist, ready to test the next harness.
  Future<void> useAutoScanAsNetlist() async {
    if (s.discoveredPairs.isEmpty) {
      showToast('Run an Auto-Scan first', kind: 'warning');
      return;
    }
    await s.saveDiscoveredNetlist();
    autoScan = false;
    mode = ClientMode.continuity;
    showToast('Auto-Scan result loaded as the netlist', kind: 'success');
    notifyListeners();
  }

  /// Auto-Scan mode → Export: the connections the last scan found, saved as an
  /// `.xlsx` netlist in the `Netlists` folder with no dialog (the name carries
  /// the date and time). Returns the file written, or null.
  ///
  /// The pins are the real connector pins when the connector layout is known
  /// (see [NetlistDoc.fromDiscovered]); the tester channels stay in the
  /// `Src Pin #` / `Dst Pin #` columns so the file loads back.
  Future<String?> exportAutoScanNetlist() async {
    final pairs = s.discoveredPairs;
    if (pairs.isEmpty) {
      showToast('Run an Auto-Scan first', kind: 'warning');
      return null;
    }
    final dirOf = netlistsDir;
    if (dirOf == null) {
      showToast('No netlist folder is set up', kind: 'warning');
      return null;
    }
    final layout = s.nlFix.loaded;
    final doc = NetlistDoc.fromDiscovered(
      pairs,
      name: 'autoscan_netlist_${_stamp(DateTime.now())}.xlsx',
      connectors: layout ? kFix.connectors : null,
      source: source.isEmpty ? 'Side A' : source,
      destination: destination.isEmpty ? 'Side B' : destination,
      connector: connector,
    );
    try {
      final dir = dirOf()..createSync(recursive: true);
      final file = File('${dir.path}${Platform.pathSeparator}${doc.name}');
      file.writeAsBytesSync(doc.toBytes('xlsx'));
      s.log('ok', 'nl', 'Auto-Scan netlist saved: ${file.path}');
      showToast(
          layout
              ? 'Auto-Scan netlist saved: ${doc.name}'
              : 'Auto-Scan netlist saved: ${doc.name} (no connector layout '
                  'loaded, so pins are tester channels)',
          kind: 'success');
      return file.path;
    } on Object catch (e) {
      showToast('Could not save the Auto-Scan netlist: $e', kind: 'error');
      return null;
    }
  }

  Future<void> browseNetlist() async {
    await s.browseMtxNetlist();
    if (s.nlMtx.loaded) {
      autoScan = false;
      showToast('Netlist loaded: ${s.nlMtx.name}', kind: 'success');
    }
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // react to AppState: DUT ID auto-increment, report for sweeps, toasts
  // -------------------------------------------------------------------------

  void _onState() {
    // Latch the new run state FIRST: finishing a run changes the DUT ID, which
    // notifies this listener again, and that re-entry must see "not running".
    final was = _wasRunning;
    final now = s.running != null;
    _wasRunning = now;

    if (!was && now) {
      _runStart = DateTime.now();
      lastDuration = null;
      _ticker?.cancel();
      _ticker = Timer.periodic(
          const Duration(milliseconds: 100), (_) => notifyListeners());
    }
    if (was && !now) {
      lastDuration =
          _runStart == null ? null : DateTime.now().difference(_runStart!);
      _runStart = null;
      _ticker?.cancel();
      _onRunFinished();
    }

    if (_wasConnected && !s.link) {
      showToast('Connection lost', kind: 'error');
    }
    _wasConnected = s.link;
    notifyListeners();
  }

  /// Auto-increments the trailing number of the DUT ID after every test
  /// (`HT-0001` → `HT-0002`), as the client does, and writes the report for
  /// the sweeps AppState does not snapshot itself (Cross Continuity,
  /// Auto-Scan).
  void _onRunFinished() {
    if (_multiActive) {
      // One stage of a Multi-Test Run: judge it, then start the next one on
      // the next turn of the event loop. The DUT ID moves once, at the end.
      if (_stage == ClientMode.cross) unawaited(_saveSweepReport());
      _recordStage();
      Timer.run(_runNextStage);
      _scheduleOutputSave();
      return;
    }
    final wasSweep = autoScan || mode == ClientMode.cross;
    if (wasSweep) unawaited(_saveSweepReport());
    _finishDutId();
    _scheduleOutputSave();
  }

  void _finishDutId() {
    final next = nextDutId(s.dutId);
    if (next != s.dutId) s.setDutId(next);
  }

  Future<void> _saveSweepReport() async {
    final dir = s.reportsDir;
    final rs = rows;
    if (dir == null || rs.isEmpty) return;
    try {
      final r = sweepReport();
      if (r == null) return;
      dir.createSync(recursive: true);
      final stamp = _stamp(DateTime.now());
      final stem =
          '${dir.path}${Platform.pathSeparator}${s.reportFormat.fileStem('continuity', stamp, s.dutId)}';
      await File('$stem.csv').writeAsString(s.reportFormat.contCsv(r));
      await File('$stem.pdf').writeAsBytes(await s.reportFormat.contPdf(r));
      s.log('ok', 'rpt', 'report saved to $stem.(csv|pdf)');
    } on Object catch (e) {
      s.log('warn', 'rpt', 'could not save the report automatically: $e');
    }
  }

  /// A client-format continuity report of the sweep currently on screen.
  ContReport? sweepReport() {
    final rs = rows;
    if (rs.isEmpty) return null;
    final pass = rs.every((r) => r.status == RowStatus.connected);
    return ContReport(
      metaFor(s, pass: pass),
      [
        for (final r in rs)
          ContReportRow(
            testNum: r.test,
            srcPin: r.pinA,
            dstPin: r.pinB,
            status: switch (r.status) {
              RowStatus.connected => 'CONNECTED',
              RowStatus.miswire => 'MISWIRE',
              _ => 'NOT CONNECTED',
            },
            srcConnId: r.connA,
            srcPinLabel: r.labelA,
            srcPartNumber: r.partA,
            dstConnId: r.connB,
            dstPinLabel: r.labelB,
            dstPartNumber: r.partB,
            wire: WireMeta(
              source: r.source,
              destination: r.destination,
              colour: r.colour,
              awg: r.awg,
              length: r.length,
              harnessNo: r.harnessNo,
            ),
          ),
      ],
      label: autoScan ? 'Auto-Scan' : 'Cross Continuity',
    );
  }

  /// `HT-0001` → `HT-0002`; no trailing number → append `-2`; blank → blank.
  static String nextDutId(String id) {
    final t = id.trim();
    if (t.isEmpty) return t;
    var i = t.length;
    while (i > 0 && _isDigit(t.codeUnitAt(i - 1))) {
      i--;
    }
    final num = t.substring(i);
    if (num.isEmpty) return '$t-2';
    final n = int.parse(num) + 1;
    return '${t.substring(0, i)}${n.toString().padLeft(num.length, '0')}';
  }

  static bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

  static String _stamp(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}_'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }

  // -------------------------------------------------------------------------
  // exports (File menu)
  // -------------------------------------------------------------------------

  /// File → Save Results as CSV…
  Future<void> exportCsv() async {
    final ok = await _export(pdf: false);
    if (!ok) showToast('No results to save yet', kind: 'warning');
  }

  /// File → Export PDF Report…
  Future<void> exportPdf() async {
    final ok = await _export(pdf: true);
    if (!ok) showToast('No results to export yet', kind: 'warning');
  }

  Future<bool> _export({required bool pdf}) async {
    if (autoScan || mode == ClientMode.cross) {
      final r = sweepReport();
      if (r == null) return false;
      final path = await s.pickSavePath(
        dialogTitle: pdf ? 'Export PDF report' : 'Save results as CSV',
        fileName:
            '${s.reportFormat.fileStem('continuity', _stamp(DateTime.now()), s.dutId)}.${pdf ? 'pdf' : 'csv'}',
        allowedExtensions: [pdf ? 'pdf' : 'csv'],
      );
      if (path == null) return true; // cancelled is not "nothing to save"
      if (pdf) {
        await File(path).writeAsBytes(await s.reportFormat.contPdf(r));
      } else {
        await File(path).writeAsString(s.reportFormat.contCsv(r));
      }
      showToast('Saved ${File(path).uri.pathSegments.last}', kind: 'success');
      return true;
    }
    final bool has = switch (viewMode) {
      ClientMode.continuity => s.lastContReport != null,
      ClientMode.resistance => s.lastResReport != null,
      ClientMode.insulation => s.lastInsulReport != null,
      ClientMode.cross || ClientMode.multi => false,
    };
    if (!has) return false;
    final done = switch (viewMode) {
      ClientMode.continuity =>
        pdf ? s.exportContReportPdf() : s.exportContReportCsv(),
      ClientMode.resistance =>
        pdf ? s.exportResReportPdf() : s.exportResReportCsv(),
      ClientMode.insulation =>
        pdf ? s.exportInsulReportPdf() : s.exportInsulReportCsv(),
      ClientMode.cross || ClientMode.multi => Future<bool>.value(false),
    };
    if (await done) showToast('Report saved', kind: 'success');
    return true;
  }

  /// A client-format PDF of the report for the current mode (used by tests and
  /// the Results tab's "Export" buttons).
  Future<Uint8List?> currentPdf() async {
    if (autoScan || mode == ClientMode.cross) {
      final r = sweepReport();
      return r == null ? null : s.reportFormat.contPdf(r);
    }
    return switch (viewMode) {
      ClientMode.continuity => s.lastContReport == null
          ? null
          : await s.reportFormat.contPdf(s.lastContReport!),
      ClientMode.resistance => s.lastResReport == null
          ? null
          : await s.reportFormat.resPdf(s.lastResReport!),
      ClientMode.insulation => s.lastInsulReport == null
          ? null
          : await s.reportFormat.insulPdf(s.lastInsulReport!),
      ClientMode.cross || ClientMode.multi => null,
    };
  }

  // -------------------------------------------------------------------------
  // File / Netlist actions added for the customer's layout
  // -------------------------------------------------------------------------

  /// File → Open Result Folder: where every completed run's CSV and PDF are
  /// written automatically.
  Future<void> openResultFolder() async {
    final dir = s.reportsDir;
    if (dir == null) {
      showToast('No result folder is set up', kind: 'warning');
      return;
    }
    try {
      dir.createSync(recursive: true);
      await Process.run('explorer.exe', [dir.path]);
    } on Object catch (e) {
      showToast('Could not open the result folder: $e', kind: 'error');
    }
  }

  /// The loaded netlist of [kind] as an editable document (the same rows the
  /// netlist editor shows), or null when none is loaded.
  NetlistDoc? loadedNetlistDoc(NetlistKind kind) {
    if (kind == NetlistKind.mtx && s.nlMtx.loaded && s.mtxRows.isNotEmpty) {
      return NetlistDoc.fromParsed(kind, s.mtxRows,
          name: s.nlMtx.name ?? 'netlist.xlsx', harnessId: s.nlHarnessId);
    }
    if (kind == NetlistKind.hv && s.nlHv.loaded && s.hvRows.isNotEmpty) {
      return NetlistDoc.fromParsed(kind, s.hvRows,
          name: s.nlHv.name ?? 'hv_netlist.xlsx');
    }
    return null;
  }

  /// Netlist / Test Mode → Export, and Configuration → HV netlist → Export:
  /// the loaded netlist saved as `.xlsx`, `.xls` or `.csv` (the extension the
  /// operator types or picks decides), in the same columns the loader reads
  /// back.
  Future<void> exportNetlist({NetlistKind kind = NetlistKind.mtx}) async {
    final hv = kind == NetlistKind.hv;
    final doc = loadedNetlistDoc(kind);
    if (doc == null) {
      showToast(hv ? 'No HV netlist loaded' : 'No netlist loaded',
          kind: 'warning');
      return;
    }
    final base = doc.name.replaceAll(RegExp(r'\.[^.]*$'), '');
    final path = await s.pickSavePath(
      dialogTitle: hv ? 'Export HV netlist' : 'Export netlist',
      fileName: '$base.xlsx',
      allowedExtensions: kNetlistExtensions,
    );
    if (path == null) return;
    try {
      final target = withNetlistExtension(path);
      await File(target).writeAsBytes(doc.toBytes(extensionOf(target)));
      showToast('Netlist exported: ${File(target).uri.pathSegments.last}',
          kind: 'success');
    } on Object catch (e) {
      showToast('Could not export the netlist: $e', kind: 'error');
    }
  }

  // -------------------------------------------------------------------------
  // Test Profile
  // -------------------------------------------------------------------------

  Directory? get _profilesDir =>
      dataDir == null ? null : Directory('${dataDir!.path}/profiles');

  File? get _settingsFile =>
      dataDir == null ? null : File('${dataDir!.path}/settings.json');

  void _loadSettings() {
    try {
      final f = _settingsFile;
      if (f == null || !f.existsSync()) return;
      final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      dark = (j['theme'] ?? (dark ? 'dark' : 'light')) != 'light';
      profile = (j['profile'] as String?) ?? profile;
    } on Object {
      // A bad settings file must not stop the app.
    }
  }

  void _saveSettings() {
    try {
      final f = _settingsFile;
      if (f == null) return;
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(
          jsonEncode({'theme': dark ? 'dark' : 'light', 'profile': profile}));
    } on Object {
      // read-only profile directory: the preference simply is not kept
    }
  }

  void _loadProfiles() {
    final d = _profilesDir;
    final names = <String>{'Default'};
    try {
      if (d != null && d.existsSync()) {
        for (final f in d.listSync().whereType<File>()) {
          if (f.path.toLowerCase().endsWith('.json')) {
            names.add(f.uri.pathSegments.last.replaceAll(RegExp(r'\.json$'), ''));
          }
        }
      }
    } on Object {
      // fall through with just Default
    }
    profiles = names.toList()..sort();
    if (!profiles.contains(profile)) profile = 'Default';
    _readProfile(profile);
  }

  void _readProfile(String name) {
    final d = _profilesDir;
    harnessId = '';
    connector = '';
    source = '';
    destination = '';
    String operator = '';
    String dut = s.dutId.isEmpty ? 'HT-0001' : s.dutId;
    try {
      final f = d == null ? null : File('${d.path}/$name.json');
      if (f != null && f.existsSync()) {
        final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        operator = (j['operator'] as String?) ?? '';
        harnessId = (j['harness_id'] as String?) ?? '';
        dut = (j['dut_id'] as String?) ?? dut;
        connector = (j['connector'] as String?) ?? '';
        source = (j['source'] as String?) ?? '';
        destination = (j['destination'] as String?) ?? '';
      }
    } on Object {
      // unreadable profile: start blank
    }
    s.setOperatorName(operator);
    s.setDutId(dut);
    profileDirty = false;
  }

  void _applyProfileToState() {
    s.profileName = profile;
    s.wireDefaults = WireMeta(
      srcConnId: connector,
      dstConnId: connector,
      source: source,
      destination: destination,
    );
  }

  void selectProfile(String name) {
    profile = name;
    _readProfile(name);
    _applyProfileToState();
    _saveSettings();
    notifyListeners();
  }

  void setOperator(String v) {
    s.setOperatorName(v);
    profileDirty = true;
    notifyListeners();
  }

  void setDutId(String v) {
    s.setDutId(v);
    profileDirty = true;
    notifyListeners();
  }

  void setHarnessId(String v) {
    harnessId = v;
    profileDirty = true;
    notifyListeners();
  }

  void setDefaults({String? connector, String? source, String? destination}) {
    this.connector = connector ?? this.connector;
    this.source = source ?? this.source;
    this.destination = destination ?? this.destination;
    profileDirty = true;
    _applyProfileToState();
    notifyListeners();
  }

  void saveProfile() {
    final d = _profilesDir;
    if (d == null) {
      profileDirty = false;
      notifyListeners();
      return;
    }
    try {
      d.createSync(recursive: true);
      File('${d.path}/$profile.json').writeAsStringSync(jsonEncode({
        'operator': s.operatorName,
        'harness_id': harnessId,
        'dut_id': s.dutId,
        'connector': connector,
        'source': source,
        'destination': destination,
      }));
      profileDirty = false;
      showToast('Profile "$profile" saved', kind: 'success');
    } on Object catch (e) {
      showToast('Could not save the profile: $e', kind: 'error');
    }
    _saveSettings();
    notifyListeners();
  }

  /// Creates [name] from the current fields and selects it.
  bool newProfile(String name) {
    final n = name.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (n.isEmpty || profiles.contains(n)) return false;
    profiles = [...profiles, n]..sort();
    profile = n;
    saveProfile();
    _applyProfileToState();
    return true;
  }

  void deleteProfile() {
    if (profile == 'Default') {
      showToast('The Default profile cannot be deleted', kind: 'warning');
      return;
    }
    try {
      final d = _profilesDir;
      if (d != null) {
        final f = File('${d.path}/$profile.json');
        if (f.existsSync()) f.deleteSync();
      }
    } on Object {
      // already gone
    }
    profiles = profiles.where((p) => p != profile).toList();
    selectProfile('Default');
  }
}
