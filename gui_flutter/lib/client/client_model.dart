/// The client app's view of a run: the test modes, the rows the Results Table
/// shows for each, the verdict and the summary chips. Everything here is a
/// pure function of [AppState] (and the loaded netlist), so it is testable
/// without a widget tree.
///
/// Terminology is the client's: *Continuity (one-to-one)*, *Cross Continuity
/// (one-to-many)*, *Auto-Scan*, status `CONNECTED` / `NOT CONNECTED` /
/// `MISWIRE`, summary chips `Total / PASS / FAIL / OPEN / MISWIRE`. The MK1
/// tests — *Resistance (4-wire Kelvin)* and *HV Insulation* — are added to the
/// same Mode list and use the same table, chips and verdict box.
library;

import '../app/app_state.dart';
import '../app/report.dart';
import '../design/model.dart';
import '../htproto/netlist_file.dart' show WireMeta;

/// The Mode combo of the control bar.
enum ClientMode {
  continuity('Continuity (one-to-one)', 'cont'),
  cross('Cross Continuity (one-to-many)', 'cross'),
  resistance('Resistance (4-wire Kelvin)', 'res'),
  insulation('HV Insulation (500 V DC)', 'hv'),
  multi('Multi-Test Run', 'multi');

  final String label;
  final String key;
  const ClientMode(this.label, this.key);
}

/// The tests a Multi-Test Run can perform, in the order they run.
const List<ClientMode> kMultiOrder = [
  ClientMode.continuity,
  ClientMode.cross,
  ClientMode.resistance,
  ClientMode.insulation,
];

/// A row's outcome, in the client's words.
enum RowStatus {
  connected('CONNECTED'),
  notConnected('NOT CONNECTED'),
  miswire('MISWIRE'),
  pass('PASS'),
  failHigh('FAIL HIGH'),
  failLow('FAIL LOW'),
  fail('FAIL');

  final String label;
  const RowStatus(this.label);

  bool get good => this == connected || this == pass;
}

/// One line of the Results Table. Only the fields a mode uses are filled.
class CRow {
  final int test;
  final String source, connA, labelA, destination, connB, labelB;
  final String partA, partB, colour, awg, length, harnessNo;
  final int pinA, pinB;
  final RowStatus status;

  /// Resistance (mΩ) / insulation (MΩ) and the limit it was judged against.
  final String value, limit;

  /// Insulation rows: net name, HV card, HS pin, leakage voltage.
  final String net, card, hsPin, leakV;

  const CRow({
    required this.test,
    required this.status,
    this.source = '',
    this.connA = '',
    this.labelA = '',
    this.pinA = 0,
    this.pinB = 0,
    this.labelB = '',
    this.connB = '',
    this.destination = '',
    this.partA = '',
    this.partB = '',
    this.colour = '',
    this.awg = '',
    this.length = '',
    this.harnessNo = '',
    this.value = '',
    this.limit = '',
    this.net = '',
    this.card = '',
    this.hsPin = '',
    this.leakV = '',
  });

  CRow withTest(int n) => CRow(
        test: n,
        status: status,
        source: source,
        connA: connA,
        labelA: labelA,
        pinA: pinA,
        pinB: pinB,
        labelB: labelB,
        connB: connB,
        destination: destination,
        partA: partA,
        partB: partB,
        colour: colour,
        awg: awg,
        length: length,
        harnessNo: harnessNo,
        value: value,
        limit: limit,
        net: net,
        card: card,
        hsPin: hsPin,
        leakV: leakV,
      );
}

String _dash(String s) => s == '—' ? '' : s;

CRow _fromWire({
  required int test,
  required RowStatus status,
  required int hi,
  required int lo,
  required String connA,
  required String labelA,
  required String partA,
  required String connB,
  required String labelB,
  required String partB,
  WireMeta? w,
  String value = '',
  String limit = '',
}) =>
    CRow(
      test: test,
      status: status,
      pinA: hi,
      pinB: lo,
      source: w?.source ?? '',
      connA: _dash(connA).isNotEmpty ? connA : (w?.srcConnId ?? ''),
      labelA: labelA,
      partA: partA.isNotEmpty ? partA : (w?.srcPart ?? ''),
      connB: _dash(connB).isNotEmpty ? connB : (w?.dstConnId ?? ''),
      labelB: labelB,
      partB: partB.isNotEmpty ? partB : (w?.dstPart ?? ''),
      destination: w?.destination ?? '',
      colour: w?.colour ?? '',
      awg: w?.awg ?? '',
      length: w?.length ?? '',
      harnessNo: w?.harnessNo ?? '',
      value: value,
      limit: limit,
    );

/// A pair that is (or is not) in the loaded netlist, as the table shows it.
class _Expected {
  final NetPair p;
  final Net net;
  const _Expected(this.p, this.net);
}

List<_Expected> _expected(AppState s) => [
      for (final n in s.nets)
        for (final p in n.pairs) _Expected(p, n),
    ];

/// The rows the Results Table shows for [mode] right now.
List<CRow> rowsFor(AppState s, ClientMode mode, {required bool autoScan}) {
  if (autoScan) return _discoveredRows(s);
  switch (mode) {
    case ClientMode.continuity:
      return [
        for (final r in s.contRowsLive)
          _fromWire(
            test: r.testNum,
            status: r.status == 'CONNECTED'
                ? RowStatus.connected
                : RowStatus.notConnected,
            hi: r.srcPin,
            lo: r.dstPin,
            connA: r.srcConnId,
            labelA: r.srcPinLabel,
            partA: r.srcPartNumber,
            connB: r.dstConnId,
            labelB: r.dstPinLabel,
            partB: r.dstPartNumber,
            w: r.wire,
          ),
      ];
    case ClientMode.cross:
      return _crossRows(s);
    case ClientMode.resistance:
      final limit = s.limits == null ? '' : '${s.limits!.rMaxMohm}';
      return [
        for (final r in s.resRowsLive)
          _fromWire(
            test: r.testNum,
            status: switch (r.status) {
              'PASS' => RowStatus.pass,
              'FAIL_HIGH' => RowStatus.failHigh,
              'FAIL_LOW' => RowStatus.failLow,
              _ => RowStatus.fail,
            },
            hi: r.srcPin,
            lo: r.dstPin,
            connA: r.srcConnId,
            labelA: r.srcPinLabel,
            partA: r.srcPartNumber,
            connB: r.dstConnId,
            labelB: r.dstPinLabel,
            partB: r.dstPartNumber,
            w: r.wire,
            value: r.resistanceMohm.toStringAsFixed(1),
            limit: limit,
          ),
      ];
    case ClientMode.multi:
      // The controller resolves a Multi-Test Run to the stage on screen; this
      // is only a safe fallback.
      return rowsFor(s, ClientMode.continuity, autoScan: false);
    case ClientMode.insulation:
      final limit = s.limits == null
          ? ''
          : (s.limits!.insMinMohm / 1.0e9).toStringAsFixed(1);
      return [
        for (final r in s.insulRowsLive)
          CRow(
            test: r.testNum,
            status: r.status == 'PASS' ? RowStatus.pass : RowStatus.fail,
            net: _dash(r.net),
            card: _dash(r.hvCard),
            hsPin: _dash(r.hsPin),
            leakV: r.leakV.toStringAsFixed(3),
            value: r.insulationMohm.toStringAsFixed(1),
            limit: limit,
          ),
      ];
  }
}

/// Auto-Scan: only the connections that are present, as the client shows them.
List<CRow> _discoveredRows(AppState s) {
  var i = 0;
  return [
    for (final (hi, lo) in s.discoveredPairs)
      CRow(
        test: ++i,
        status: RowStatus.connected,
        pinA: hi,
        pinB: lo,
        labelA: 'Pin $hi',
        labelB: 'Pin $lo',
      ),
  ];
}

/// Cross Continuity (one-to-many): drive every Side-A pin, read every Side-B
/// pin, then judge the sweep against the netlist — a listed pair that was not
/// found is `NOT CONNECTED`, a connection found that the netlist does not
/// list is a `MISWIRE`. The firmware's cross scan is a discovery sweep; the
/// comparison is the client's rule applied on the PC.
List<CRow> _crossRows(AppState s) {
  final found = {for (final (hi, lo) in s.discoveredPairs) '$hi:$lo'};
  final exp = _expected(s);
  final listed = {for (final e in exp) e.p.key};
  final rows = <CRow>[];
  var i = 0;
  if (s.nets.isEmpty || exp.isEmpty) {
    return _discoveredRows(s);
  }
  for (final e in exp) {
    final ok = found.contains(e.p.key);
    // Until the sweep has produced anything, nothing is "not connected" yet.
    if (!ok && s.discoveredPairs.isEmpty && s.running != null) continue;
    rows.add(CRow(
      test: ++i,
      status: ok ? RowStatus.connected : RowStatus.notConnected,
      pinA: e.p.hi,
      pinB: e.p.lo,
      connA: connName(e.p.src.c),
      connB: connName(e.p.dst.c),
      labelA: e.p.srcLabel ?? 'Pin ${e.p.hi}',
      labelB: e.p.dstLabel ?? 'Pin ${e.p.lo}',
    ));
  }
  for (final (hi, lo) in s.discoveredPairs) {
    if (listed.contains('$hi:$lo')) continue;
    rows.add(CRow(
      test: ++i,
      status: RowStatus.miswire,
      pinA: hi,
      pinB: lo,
      labelA: 'Pin $hi',
      labelB: 'Pin $lo',
    ));
  }
  return rows;
}

/// The verdict box: `—`, `PASS`, `FAIL`, `FAULT`, or `DONE` for a discovery.
String verdictFor(AppState s, ClientMode mode, {required bool autoScan}) {
  if (s.inFault) return 'FAULT';
  if (s.running != null) return '—';
  if (autoScan) return s.discoveredPairs.isEmpty ? '—' : 'DONE';
  switch (mode) {
    case ClientMode.continuity:
      return _verdict(s.R['cont']);
    case ClientMode.resistance:
      return _verdict(s.R['res']);
    case ClientMode.insulation:
      return _verdict(s.R['hv']);
    case ClientMode.cross:
      final rows = _crossRows(s);
      if (rows.isEmpty) return '—';
      return rows.every((r) => r.status == RowStatus.connected)
          ? 'PASS'
          : 'FAIL';
    case ClientMode.multi:
      // Resolved by ClientController (the verdict of a whole sequence).
      return '—';
  }
}

String _verdict(String? r) => switch (r) {
      'pass' => 'PASS',
      'fail' => 'FAIL',
      _ => '—',
    };

/// The summary chips under the table.
class Summary {
  final int total, pass, fail, open, miswire;
  const Summary(this.total, this.pass, this.fail, this.open, this.miswire);

  factory Summary.of(List<CRow> rows) {
    var pass = 0, fail = 0, open = 0, mis = 0;
    for (final r in rows) {
      switch (r.status) {
        case RowStatus.connected:
        case RowStatus.pass:
          pass++;
        case RowStatus.notConnected:
          open++;
        case RowStatus.miswire:
          mis++;
        case RowStatus.failHigh:
        case RowStatus.failLow:
        case RowStatus.fail:
          fail++;
      }
    }
    return Summary(rows.length, pass, fail, open, mis);
  }
}

/// The columns each mode's table has, in the client's order.
enum Col {
  test('Test #'),
  source('Source'),
  partA('Part Number'),
  connA('Conn ID'),
  labelA('Src Pin Label'),
  pinA('Src Pin #'),
  value('Resistance (mΩ)'),
  limit('Limit (mΩ)'),
  limitIns('Limit (MΩ)'),
  status('Status'),
  pinB('Dst Pin #'),
  labelB('Dst Pin Label'),
  connB('Conn ID'),
  partB('Part Number'),
  destination('Destination'),
  net('Net'),
  card('HV Card'),
  hsPin('HS Pin'),
  leakV('Leak V'),
  insulation('Insulation (MΩ)');

  final String title;
  const Col(this.title);
}

List<Col> columnsFor(ClientMode mode, {required bool autoScan}) {
  if (autoScan) {
    return const [Col.test, Col.pinA, Col.labelA, Col.status, Col.pinB, Col.labelB];
  }
  switch (mode) {
    case ClientMode.continuity:
      return const [
        Col.test, Col.source, Col.connA, Col.labelA, Col.pinA, Col.status,
        Col.pinB, Col.labelB, Col.connB, Col.destination, //
      ];
    case ClientMode.cross:
      // The client hides the redundant pin/connector columns in cross mode.
      return const [Col.test, Col.source, Col.status, Col.destination];
    case ClientMode.resistance:
      return const [
        Col.test, Col.source, Col.connA, Col.labelA, Col.pinA, Col.value,
        Col.limit, Col.status, Col.pinB, Col.labelB, Col.connB,
        Col.destination, //
      ];
    case ClientMode.multi:
      return columnsFor(ClientMode.continuity, autoScan: false);
    case ClientMode.insulation:
      return const [
        Col.test, Col.net, Col.card, Col.hsPin, Col.leakV, Col.insulation,
        Col.limitIns, Col.status, //
      ];
  }
}

String cell(CRow r, Col c) => switch (c) {
      Col.test => '${r.test}',
      Col.source => r.source,
      Col.partA => r.partA,
      Col.connA => r.connA,
      Col.labelA => r.labelA,
      Col.pinA => '${r.pinA}',
      Col.value || Col.insulation => r.value,
      Col.limit || Col.limitIns => r.limit,
      Col.status => r.status.label,
      Col.pinB => '${r.pinB}',
      Col.labelB => r.labelB,
      Col.connB => r.connB,
      Col.partB => r.partB,
      Col.destination => r.destination,
      Col.net => r.net,
      Col.card => r.card,
      Col.hsPin => r.hsPin,
      Col.leakV => r.leakV,
    };

/// `ReportMeta` for a client-format report of the rows currently on screen.
ReportMeta metaFor(AppState s, {required bool pass, Duration? duration}) =>
    ReportMeta(
      dutId: s.dutId,
      operatorName: s.operatorName,
      netlistName: s.nlMtx.loaded ? s.nlMtx.name : null,
      pass: pass,
      when: DateTime.now(),
      testDuration: duration,
      profile: s.profileName,
    );
