/// Per-run test reports in the `required_format/` shape (see
/// `gui_flutter/required_format/README.md`) — one report per completed
/// continuity, resistance, or insulation run, built from the real per-pin/
/// per-net results that stream in while the run executes.
///
/// Not persisted: the decision (2026-08-14) was to generate a report
/// immediately from a live snapshot rather than grow `RunHistoryEntry` to
/// carry full row detail — a report is available for export only until the
/// next run of the same kind starts, same lifetime as `AppState.nets`
/// itself already has.
library;

String _csvField(Object? v) {
  final s = v?.toString() ?? '';
  if (s.contains(',') || s.contains('"') || s.contains('\n')) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

String _csvRow(List<Object?> cells) => cells.map(_csvField).join(',');

/// The metadata block every report kind shares (`# key,value` lines), plus
/// whichever kind-specific extra lines that kind's `required_format` sample
/// adds between `Netlist` and `Verdict`.
class ReportMeta {
  final String dutId;
  final String operatorName;
  final String? netlistName;
  final bool pass;
  final DateTime when;

  /// Wall-clock time from `_beginRun` to `_onDone` (`AppState`) — null when
  /// a report is built without a live run behind it (e.g. straight from a
  /// test's synthetic `ReportMeta`). PDF-only, like the sample's own "Test
  /// Duration" row: not part of the CSV column shape.
  final Duration? testDuration;

  const ReportMeta({
    required this.dutId,
    required this.operatorName,
    required this.netlistName,
    required this.pass,
    required this.when,
    this.testDuration,
  });

  static String stampDateTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  /// "248 ms" under a second, "6.4 s" at or above — same convention as the
  /// `required_format` PDF samples.
  static String stampDuration(Duration d) {
    if (d.inMilliseconds < 1000) return '${d.inMilliseconds} ms';
    return '${(d.inMilliseconds / 1000).toStringAsFixed(1)} s';
  }

  List<String> _lines(String title, List<List<String>> extra) => [
        '# Harness Tester Results$title',
        '# ${_csvRow(['DUT ID', dutId])}',
        '# ${_csvRow(['Operator', operatorName])}',
        '# ${_csvRow(['Netlist', netlistName ?? ''])}',
        for (final e in extra) '# ${_csvRow(e)}',
        '# ${_csvRow(['Verdict', pass ? 'PASS' : 'FAIL'])}',
        '# ${_csvRow(['Date/Time', stampDateTime(when)])}',
      ];
}

/// One continuity result row — `Test #, Source, Part Number, Conn ID, Src Pin
/// Label, Src Pin #, Status, Dst Pin #, Dst Pin Label, Conn ID, Part Number,
/// Destination`. `Source`/`Destination` stay blank — the wire protocol
/// (`!CONT <hi> <lo> <status>`) carries pins only, never that free-text
/// metadata, and it isn't parsed from the netlist file either (unlike `Conn
/// ID`/`Part Number`, `netlist_file.dart` never reads a `Source`/
/// `Destination` column). `Conn ID`/pin label/`Part Number` are real once
/// GUI-11's connector mapping resolves the pin (`AppState._onCont`) — `'—'`/
/// the raw flat pin number/blank otherwise (no netlist loaded, or a pin the
/// active fixture doesn't cover).
class ContReportRow {
  final int testNum;
  final int srcPin;
  final int dstPin;
  final String srcConnId;
  final String srcPinLabel;
  final String srcPartNumber;
  final String dstConnId;
  final String dstPinLabel;
  final String dstPartNumber;

  /// 'CONNECTED' | 'NOT CONNECTED' — the wire's three-state pass/open/short
  /// collapses to this report's two-state column, same as the Summary block
  /// (Total/CONNECTED/NOT CONNECTED — see required_format/README.md).
  final String status;

  const ContReportRow({
    required this.testNum,
    required this.srcPin,
    required this.dstPin,
    required this.status,
    this.srcConnId = '—',
    String? srcPinLabel,
    this.srcPartNumber = '',
    this.dstConnId = '—',
    String? dstPinLabel,
    this.dstPartNumber = '',
  })  : srcPinLabel = srcPinLabel ?? 'Pin $srcPin',
        dstPinLabel = dstPinLabel ?? 'Pin $dstPin';
}

class ContReport {
  final ReportMeta meta;
  final List<ContReportRow> rows;
  const ContReport(this.meta, this.rows);

  int get connected => rows.where((r) => r.status == 'CONNECTED').length;

  String toCsv() {
    final buf = StringBuffer();
    for (final l in meta._lines('', const [])) {
      buf.writeln(l);
    }
    buf.writeln();
    buf.writeln(_csvRow(const [
      'Test #', 'Source', 'Part Number', 'Conn ID', 'Src Pin Label',
      'Src Pin #', 'Status', 'Dst Pin #', 'Dst Pin Label', 'Conn ID',
      'Part Number', 'Destination', //
    ]));
    for (final r in rows) {
      buf.writeln(_csvRow([
        r.testNum, '', r.srcPartNumber, r.srcConnId, r.srcPinLabel, r.srcPin,
        r.status, r.dstPin, r.dstPinLabel, r.dstConnId, r.dstPartNumber, '', //
      ]));
    }
    return buf.toString();
  }
}

/// `Test #, Source, Part Number, Conn ID, Src Pin Label, Src Pin #,
/// Resistance (mOhm), Limit (mOhm), Status, Dst Pin #, Dst Pin Label, Conn
/// ID, Part Number, Destination`. `status` is the wire's own three-state
/// enum (`PASS`/`FAIL_HIGH`/`FAIL_LOW`) uppercased, not collapsed. `Conn ID`/
/// pin label/`Part Number` are real once GUI-11's connector mapping resolves
/// the pin — see `ContReportRow`.
class ResReportRow {
  final int testNum;
  final int srcPin;
  final int dstPin;
  final double resistanceMohm;
  final String status;
  final String srcConnId;
  final String srcPinLabel;
  final String srcPartNumber;
  final String dstConnId;
  final String dstPinLabel;
  final String dstPartNumber;

  const ResReportRow({
    required this.testNum,
    required this.srcPin,
    required this.dstPin,
    required this.resistanceMohm,
    required this.status,
    this.srcConnId = '—',
    String? srcPinLabel,
    this.srcPartNumber = '',
    this.dstConnId = '—',
    String? dstPinLabel,
    this.dstPartNumber = '',
  })  : srcPinLabel = srcPinLabel ?? 'Pin $srcPin',
        dstPinLabel = dstPinLabel ?? 'Pin $dstPin';
}

class ResReport {
  final ReportMeta meta;
  final String excitationMa;
  final String limitMohm;
  final List<ResReportRow> rows;
  const ResReport(this.meta, this.excitationMa, this.limitMohm, this.rows);

  String toCsv() {
    final buf = StringBuffer();
    for (final l in meta._lines(' — Resistance', [
      ['Excitation Current (mA)', excitationMa],
      ['Resistance Limit (mOhm)', limitMohm],
    ])) {
      buf.writeln(l);
    }
    buf.writeln();
    buf.writeln(_csvRow(const [
      'Test #', 'Source', 'Part Number', 'Conn ID', 'Src Pin Label',
      'Src Pin #', 'Resistance (mOhm)', 'Limit (mOhm)', 'Status', 'Dst Pin #',
      'Dst Pin Label', 'Conn ID', 'Part Number', 'Destination', //
    ]));
    for (final r in rows) {
      buf.writeln(_csvRow([
        r.testNum, '', r.srcPartNumber, r.srcConnId, r.srcPinLabel, r.srcPin,
        r.resistanceMohm.toStringAsFixed(1), limitMohm, r.status, r.dstPin,
        r.dstPinLabel, r.dstConnId, r.dstPartNumber, '', //
      ]));
    }
    return buf.toString();
  }
}

/// `Test #, Net, HV Card, HS Pin, Leak V, Insulation (MOhm), Limit (MOhm),
/// Status`. `leakV` is a derived estimate (rail voltage through the
/// documented R3002/R3004 sense divider in series with the net's own
/// measured insulation resistance), not a directly-sensed value — the wire
/// protocol carries no per-net voltage, only `leak_mohm`. Same formula
/// `AppState.paintLink()` uses for the live "Leakage" meter.
class InsulReportRow {
  final int testNum;
  final String net;
  final String hvCard;
  final String hsPin;
  final double leakV;
  final double insulationMohm;
  final String status;

  const InsulReportRow({
    required this.testNum,
    required this.net,
    required this.hvCard,
    required this.hsPin,
    required this.leakV,
    required this.insulationMohm,
    required this.status,
  });
}

class InsulReport {
  final ReportMeta meta;
  final String hvAppliedV;
  final String limitMohm;
  final List<InsulReportRow> rows;
  const InsulReport(this.meta, this.hvAppliedV, this.limitMohm, this.rows);

  String toCsv() {
    final buf = StringBuffer();
    for (final l in meta._lines(' — HV Insulation', [
      ['HV Applied (V)', hvAppliedV],
      ['Insulation Limit (MOhm)', limitMohm],
    ])) {
      buf.writeln(l);
    }
    buf.writeln();
    buf.writeln(_csvRow(const [
      'Test #', 'Net', 'HV Card', 'HS Pin', 'Leak V', 'Insulation (MOhm)',
      'Limit (MOhm)', 'Status', //
    ]));
    for (final r in rows) {
      buf.writeln(_csvRow([
        r.testNum, r.net, r.hvCard, r.hsPin, r.leakV.toStringAsFixed(3),
        r.insulationMohm.toStringAsFixed(1), limitMohm, r.status, //
      ]));
    }
    return buf.toString();
  }
}
