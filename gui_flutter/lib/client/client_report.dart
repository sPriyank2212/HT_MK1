/// The client's report format — CSV and PDF — reproduced from the customer's
/// own Harness Tester (`gui_client_required/core/report.py` and
/// `ui/main_window.py::_write_results_csv`), for the MK1 tests.
///
/// **Continuity** is identical to the client's: the same `# Harness Tester
/// Results` metadata block, the same 16 columns (`Test #` … `Harness No`),
/// `CONNECTED` / `NOT CONNECTED`, CRLF line ends; the PDF is landscape letter
/// with the square logo, `DUT:` line, `VERDICT:` banner, the Date/Time,
/// Operator, Profile, Netlist, Test Duration and Total Pins Tested block, the
/// Summary table, the Results table with the status cell tinted, "Page n of
/// N" on every page and "End of the report" at the end.
///
/// **Resistance** and **Insulation** do not exist in the client's product
/// (they are MK1 features). They use the same page, colours, metadata block
/// and table styling, with the columns those tests actually measure — the
/// ones `report.dart` already traces to the wire protocol.
library;

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../app/report.dart';
import '../app/pdf_fonts.dart';
import '../app/report_format.dart';
import '../htproto/netlist_file.dart' show WireMeta;

// ---------------------------------------------------------------------------
// shared
// ---------------------------------------------------------------------------

/// The client's colours (`report.py`).
final PdfColor kRptNavy = PdfColor.fromHex('#1F4E79');
final PdfColor kRptSubtitle = PdfColor.fromHex('#4472C4');
final PdfColor kRptPassBg = PdfColor.fromHex('#D5E8D4');
final PdfColor kRptFailBg = PdfColor.fromHex('#F8CECC');

/// The model's "unknown" placeholder is an em dash; the client's report prints
/// a blank for a field it has no value for.
String _blank(String s) => s == '—' ? '' : s;

String _csvField(Object? v) {
  final s = v?.toString() ?? '';
  if (s.contains(',') || s.contains('"') || s.contains('\n') || s.contains('\r')) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

String _csvLine(List<Object?> cells) => cells.map(_csvField).join(',');

/// Python's `csv.writer` ends rows with CRLF — so do the client's files.
String _csv(List<List<Object?>> rows) =>
    rows.map((r) => '${_csvLine(r)}\r\n').join();

/// The client's `_fmt_duration` shape, as used in its PDF: `—` when unknown.
String clientDuration(Duration? d) {
  if (d == null || d.inMicroseconds <= 0) return '-';
  final s = d.inMicroseconds / 1e6;
  if (s < 1) return '${(s * 1000).floor()} ms';
  if (s < 60) return '${s.toStringAsFixed(2)} s';
  final m = d.inSeconds ~/ 60;
  final sec = d.inSeconds % 60;
  return '${m}m ${sec.toString().padLeft(2, '0')}s';
}

String _meta(WireMeta? w, String Function(WireMeta) pick) =>
    w == null ? '' : pick(w);

/// The 16-column wire row of the client's table, around a [middle] that is
/// `[Status]` for continuity and `[R, Limit, Status]` for resistance.
List<Object?> _wireRow({
  required int testNum,
  required String srcPart,
  required String srcConn,
  required String srcLabel,
  required int srcPin,
  required List<Object?> middle,
  required int dstPin,
  required String dstLabel,
  required String dstConn,
  required String dstPart,
  required WireMeta? w,
}) =>
    [
      testNum,
      _meta(w, (m) => m.source),
      srcPart.isNotEmpty ? srcPart : _meta(w, (m) => m.srcPart),
      _blank(srcConn).isNotEmpty ? srcConn : _meta(w, (m) => m.srcConnId),
      srcLabel,
      srcPin,
      ...middle,
      dstPin,
      dstLabel,
      _blank(dstConn).isNotEmpty ? dstConn : _meta(w, (m) => m.dstConnId),
      dstPart.isNotEmpty ? dstPart : _meta(w, (m) => m.dstPart),
      _meta(w, (m) => m.destination),
      _meta(w, (m) => m.colour),
      _meta(w, (m) => m.awg),
      _meta(w, (m) => m.length),
      _meta(w, (m) => m.harnessNo),
    ];

List<List<Object?>> _csvHead(String title, ReportMeta m, List<List<Object?>> extra) => [
      ['# Integrated Harness Tester MKI Results$title'],
      ['# DUT ID', m.dutId],
      ['# Operator', m.operatorName],
      ['# Netlist', m.netlistName ?? ''],
      for (final e in extra) ['# ${e[0]}', e[1]],
      ['# Verdict', m.pass ? 'PASS' : 'FAIL'],
      ['# Date/Time', ReportMeta.stampDateTime(m.when)],
      [],
    ];

const List<String> _tail = ['Colour', 'AWG', 'Length', 'Harness No'];

// ---------------------------------------------------------------------------
// the format
// ---------------------------------------------------------------------------

class ClientReportFormat extends ReportFormat {
  const ClientReportFormat();

  /// `report_{ts}_{dut}` — the client's name for a continuity report; the
  /// other tests append their kind (matching `required_format/`'s samples).
  @override
  String fileStem(String kind, String stamp, String dutId) {
    final dut = dutId.trim().isEmpty ? 'HT' : dutId.trim();
    return kind == 'continuity'
        ? 'report_${stamp}_$dut'
        : 'report_${stamp}_${dut}_$kind';
  }

  // ---- CSV ---------------------------------------------------------------

  @override
  String contCsv(ContReport r) => _csv([
        ..._csvHead('', r.meta, const []),
        [
          'Test #', 'Source', 'Part Number', 'Conn ID', 'Src Pin Label',
          'Src Pin #', 'Status', 'Dst Pin #', 'Dst Pin Label', 'Conn ID',
          'Part Number', 'Destination', ..._tail, //
        ],
        for (final x in r.rows)
          _wireRow(
            testNum: x.testNum,
            srcPart: x.srcPartNumber,
            srcConn: x.srcConnId,
            srcLabel: x.srcPinLabel,
            srcPin: x.srcPin,
            middle: [x.status],
            dstPin: x.dstPin,
            dstLabel: x.dstPinLabel,
            dstConn: x.dstConnId,
            dstPart: x.dstPartNumber,
            w: x.wire,
          ),
      ]);

  @override
  String resCsv(ResReport r) => _csv([
        ..._csvHead(' - Resistance', r.meta, [
          ['Excitation Current (mA)', r.excitationMa],
          ['Resistance Limit (mOhm)', r.limitMohm],
        ]),
        [
          'Test #', 'Source', 'Part Number', 'Conn ID', 'Src Pin Label',
          'Src Pin #', 'Resistance (mOhm)', 'Limit (mOhm)', 'Status',
          'Dst Pin #', 'Dst Pin Label', 'Conn ID', 'Part Number',
          'Destination', ..._tail, //
        ],
        for (final x in r.rows)
          _wireRow(
            testNum: x.testNum,
            srcPart: x.srcPartNumber,
            srcConn: x.srcConnId,
            srcLabel: x.srcPinLabel,
            srcPin: x.srcPin,
            middle: [x.resistanceMohm.toStringAsFixed(1), r.limitMohm, x.status],
            dstPin: x.dstPin,
            dstLabel: x.dstPinLabel,
            dstConn: x.dstConnId,
            dstPart: x.dstPartNumber,
            w: x.wire,
          ),
      ]);

  @override
  String insulCsv(InsulReport r) => _csv([
        ..._csvHead(' - HV Insulation', r.meta, [
          ['HV Applied (V)', r.hvAppliedV],
          ['Insulation Limit (MOhm)', r.limitMohm],
        ]),
        [
          'Test #', 'Net', 'HV Card', 'HS Pin', 'Leak V',
          'Insulation (MOhm)', 'Limit (MOhm)', 'Status', //
        ],
        for (final x in r.rows)
          [
            x.testNum, _blank(x.net), _blank(x.hvCard), _blank(x.hsPin),
            x.leakV.toStringAsFixed(3), x.insulationMohm.toStringAsFixed(1),
            r.limitMohm, x.status, //
          ],
      ]);

  // ---- PDF ---------------------------------------------------------------

  @override
  Future<Uint8List> contPdf(ContReport r) {
    final good = r.rows.where((x) => x.status == 'CONNECTED').length;
    return _pdf(
      title:
          'Integrated Harness Tester MKI Test Report - ${r.label.isEmpty ? 'Continuity' : r.label}',
      meta: r.meta,
      totalLabel: 'Total Pins Tested:',
      total: r.rows.length,
      extraMeta: const [],
      summaryHeaders: const ['Total', 'CONNECTED', 'NOT CONNECTED'],
      summaryValues: ['${r.rows.length}', '$good', '${r.rows.length - good}'],
      summaryTints: const [null, true, false],
      headers: const [
        'Test #', 'Source', 'Part Number', 'Conn ID', 'Src Pin Label',
        'Src Pin #', 'Status', 'Dst Pin #', 'Dst Pin Label', 'Conn ID',
        'Part Number', 'Destination', ..._tail, //
      ],
      widths: const [
        0.40, 0.55, 1.00, 0.50, 0.85, 0.45, 0.95, 0.45, 0.85, 0.50, 1.00,
        0.60, 0.55, 0.40, 0.50, 0.65, //
      ],
      statusCol: 6,
      rows: [
        for (final x in r.rows)
          _wireRow(
            testNum: x.testNum,
            srcPart: x.srcPartNumber,
            srcConn: x.srcConnId,
            srcLabel: x.srcPinLabel,
            srcPin: x.srcPin,
            middle: [x.status],
            dstPin: x.dstPin,
            dstLabel: x.dstPinLabel,
            dstConn: x.dstConnId,
            dstPart: x.dstPartNumber,
            w: x.wire,
          ).map((c) => '$c').toList(),
      ],
      isGood: (row) => row[6] == 'CONNECTED',
    );
  }

  @override
  Future<Uint8List> resPdf(ResReport r) {
    final pass = r.rows.where((x) => x.status == 'PASS').length;
    final high = r.rows.where((x) => x.status == 'FAIL_HIGH').length;
    final low = r.rows.where((x) => x.status == 'FAIL_LOW').length;
    return _pdf(
      title: 'Integrated Harness Tester MKI Test Report - Resistance',
      meta: r.meta,
      totalLabel: 'Total Pins Tested:',
      total: r.rows.length,
      extraMeta: [
        ['Excitation Current (mA):', r.excitationMa],
        ['Resistance Limit (mΩ):', r.limitMohm],
      ],
      summaryHeaders: const ['Total', 'PASS', 'FAIL HIGH', 'FAIL LOW'],
      summaryValues: ['${r.rows.length}', '$pass', '$high', '$low'],
      summaryTints: const [null, true, false, false],
      headers: const [
        'Test #', 'Source', 'Part Number', 'Conn ID', 'Src Pin Label',
        'Src Pin #', 'R (mΩ)', 'Limit (mΩ)', 'Status', 'Dst Pin #',
        'Dst Pin Label', 'Conn ID', 'Part Number', 'Destination', ..._tail, //
      ],
      widths: const [
        0.38, 0.50, 0.90, 0.46, 0.78, 0.42, 0.52, 0.52, 0.70, 0.42, 0.78,
        0.46, 0.90, 0.56, 0.50, 0.36, 0.46, 0.58, //
      ],
      statusCol: 8,
      rows: [
        for (final x in r.rows)
          _wireRow(
            testNum: x.testNum,
            srcPart: x.srcPartNumber,
            srcConn: x.srcConnId,
            srcLabel: x.srcPinLabel,
            srcPin: x.srcPin,
            middle: [x.resistanceMohm.toStringAsFixed(1), r.limitMohm, x.status],
            dstPin: x.dstPin,
            dstLabel: x.dstPinLabel,
            dstConn: x.dstConnId,
            dstPart: x.dstPartNumber,
            w: x.wire,
          ).map((c) => '$c').toList(),
      ],
      isGood: (row) => row[8] == 'PASS',
    );
  }

  @override
  Future<Uint8List> insulPdf(InsulReport r) {
    final pass = r.rows.where((x) => x.status == 'PASS').length;
    return _pdf(
      title: 'Integrated Harness Tester MKI Test Report - HV Insulation',
      meta: r.meta,
      totalLabel: 'Total Nets Tested:',
      total: r.rows.length,
      extraMeta: [
        ['HV Applied (V):', r.hvAppliedV],
        ['Insulation Limit (MOhm):', r.limitMohm],
      ],
      summaryHeaders: const ['Total', 'PASS', 'FAIL'],
      summaryValues: ['${r.rows.length}', '$pass', '${r.rows.length - pass}'],
      summaryTints: const [null, true, false],
      headers: const [
        'Test #', 'Net', 'HV Card', 'HS Pin', 'Leak V', 'Insulation (MOhm)',
        'Limit (MOhm)', 'Status', //
      ],
      widths: const [0.7, 2.6, 1.0, 1.0, 1.0, 1.4, 1.2, 1.3],
      statusCol: 7,
      rows: [
        for (final x in r.rows)
          [
            '${x.testNum}', _blank(x.net), _blank(x.hvCard), _blank(x.hsPin),
            x.leakV.toStringAsFixed(3), x.insulationMohm.toStringAsFixed(1),
            r.limitMohm, x.status, //
          ],
      ],
      isGood: (row) => row[7] == 'PASS',
    );
  }
}

// ---------------------------------------------------------------------------
// the client's page
// ---------------------------------------------------------------------------

/// `assets/company_logo.jpeg` — the client's 1600 x 1600 logo. Missing asset
/// (a bare `flutter test`) degrades to no logo, not an exception.
Future<pw.MemoryImage?> _logo() async {
  try {
    final d = await rootBundle.load('assets/company_logo.jpeg');
    return pw.MemoryImage(d.buffer.asUint8List());
  } catch (_) {
    return null;
  }
}

const double _in = PdfPageFormat.inch;

pw.Widget _centredTable(List<List<String>> rows, List<double> colIn,
    {double fontSize = 10, bool boldFirstCol = true}) {
  return pw.Center(
    child: pw.Table(
      tableWidth: pw.TableWidth.min,
      columnWidths: {
        for (var i = 0; i < colIn.length; i++)
          i: pw.FixedColumnWidth(colIn[i] * _in),
      },
      children: [
        for (final r in rows)
          pw.TableRow(children: [
            for (var i = 0; i < r.length; i++)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 6),
                child: pw.Text(
                  r[i],
                  style: pw.TextStyle(
                    fontSize: fontSize,
                    fontWeight: i == 0 && boldFirstCol
                        ? pw.FontWeight.bold
                        : pw.FontWeight.normal,
                  ),
                ),
              ),
          ]),
      ],
    ),
  );
}

pw.Widget _cell(String text, double size,
    {PdfColor? bg,
    PdfColor? fg,
    bool bold = false,
    bool wrap = true}) {
  return pw.Container(
    color: bg,
    padding: const pw.EdgeInsets.all(3),
    alignment: pw.Alignment.center,
    child: pw.Text(
      text,
      softWrap: wrap,
      textAlign: pw.TextAlign.center,
      style: pw.TextStyle(
        fontSize: size,
        color: fg,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    ),
  );
}

Future<Uint8List> _pdf({
  required String title,
  required ReportMeta meta,
  required String totalLabel,
  required int total,
  required List<List<String>> extraMeta,
  required List<String> summaryHeaders,
  required List<String> summaryValues,

  /// per summary column: true = green tint, false = red tint, null = none
  required List<bool?> summaryTints,
  required List<String> headers,

  /// column widths in inches, scaled to the 10.2 in the margins leave
  required List<double> widths,
  required int statusCol,
  required List<List<String>> rows,
  required bool Function(List<String> row) isGood,
}) async {
  final logo = await _logo();
  final doc = pw.Document(theme: await loadPdfTheme());
  final navy = kRptNavy;

  // reportlab: landscape(letter), margins 0.4in left/right, 0.8in top/bottom.
  final pageFormat = PdfPageFormat.letter.landscape;
  const usable = 11.0 - 0.8;
  final sum = widths.fold<double>(0, (a, b) => a + b);
  final scale = sum > usable ? usable / sum : 1.0;

  pw.Widget results() => pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey, width: 0.5),
        columnWidths: {
          for (var i = 0; i < widths.length; i++)
            i: pw.FixedColumnWidth(widths[i] * scale * _in),
        },
        children: [
          pw.TableRow(
            repeat: true,
            decoration: pw.BoxDecoration(color: navy),
            children: [
              // reportlab never wraps a plain-string header cell — it runs on
              // within its column — so neither do these ("Src Pin #").
              for (final h in headers)
                _cell(h, 6.5, fg: PdfColors.grey100, bold: true, wrap: false),
            ],
          ),
          for (final row in rows)
            pw.TableRow(children: [
              for (var c = 0; c < row.length; c++)
                _cell(
                  row[c],
                  7.5,
                  bold: c == statusCol,
                  bg: c == statusCol
                      ? (isGood(row) ? kRptPassBg : kRptFailBg)
                      : null,
                ),
            ]),
        ],
      );

  pw.Widget heading(String t) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 14, bottom: 8),
        child: pw.Text(t,
            style: pw.TextStyle(
                fontSize: 13, fontWeight: pw.FontWeight.bold, color: navy)),
      );

  final ts = meta.when;
  final metaRows = <List<String>>[
    ['Date/Time:', ReportMeta.stampDateTime(ts)],
    ['Operator:', meta.operatorName],
    ['Profile:', meta.profile],
    ['Netlist:', meta.netlistName ?? '(none / auto-scan)'],
    ...extraMeta,
    ['Test Duration:', clientDuration(meta.testDuration)],
    [totalLabel, '$total'],
  ];

  doc.addPage(pw.MultiPage(
    pageFormat: pageFormat,
    margin: const pw.EdgeInsets.fromLTRB(0.4 * _in, 0.8 * _in, 0.4 * _in, 0.8 * _in),
    footer: (ctx) => pw.Container(
      alignment: pw.Alignment.center,
      child: pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
    ),
    build: (ctx) => [
      if (logo != null)
        pw.Center(child: pw.Image(logo, width: 1.2 * _in, height: 1.2 * _in)),
      pw.SizedBox(height: 0.2 * _in),
      pw.Center(
        child: pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 16),
          child: pw.Text(title,
              style: pw.TextStyle(
                  fontSize: 20, fontWeight: pw.FontWeight.bold, color: navy)),
        ),
      ),
      pw.Center(
        child: pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 20),
          child: pw.Text('DUT: ${meta.dutId}',
              style: pw.TextStyle(fontSize: 12, color: kRptSubtitle)),
        ),
      ),
      pw.Center(
        child: pw.Text(
          'VERDICT: ${meta.pass ? 'PASS' : 'FAIL'}',
          style: pw.TextStyle(
            fontSize: 14,
            color: meta.pass ? PdfColor.fromHex('#008000') : PdfColors.red,
          ),
        ),
      ),
      pw.SizedBox(height: 0.2 * _in),
      // 1.6 / 4.5 in is the client's; the MK1 reports' longer labels
      // ("Excitation Current (mA):") need a wider label column.
      _centredTable(
          metaRows, extraMeta.isEmpty ? const [1.6, 4.5] : const [2.3, 3.8]),
      heading('Summary'),
      pw.Center(
        child: pw.Table(
          tableWidth: pw.TableWidth.min,
          border: pw.TableBorder.all(color: PdfColors.grey, width: 0.5),
          columnWidths: {
            for (var i = 0; i < summaryHeaders.length; i++)
              i: pw.FixedColumnWidth(
                  (summaryHeaders.length == 3 ? 1.73 : 1.3) * _in),
          },
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(color: navy),
              children: [
                for (final h in summaryHeaders)
                  _cell(h, 11, fg: PdfColors.grey100, bold: true),
              ],
            ),
            pw.TableRow(children: [
              for (var i = 0; i < summaryValues.length; i++)
                _cell(
                  summaryValues[i],
                  11,
                  bg: summaryTints[i] == null
                      ? null
                      : (summaryTints[i]! ? kRptPassBg : kRptFailBg),
                ),
            ]),
          ],
        ),
      ),
      if (rows.isEmpty) ...[
        pw.SizedBox(height: 0.3 * _in),
        pw.Text('No results to display.', style: const pw.TextStyle(fontSize: 10)),
      ] else ...[
        heading('Results'),
        results(),
      ],
      pw.SizedBox(height: 0.25 * _in),
      pw.Center(
        child: pw.Text('End of the report',
            style: pw.TextStyle(
                fontSize: 9, fontWeight: pw.FontWeight.bold, color: navy)),
      ),
    ],
  ));
  return doc.save();
}
