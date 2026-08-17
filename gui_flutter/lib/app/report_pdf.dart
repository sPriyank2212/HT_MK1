/// PDF rendering for the reports in `report.dart`, matching the layout of
/// `required_format/report_*.pdf` (logo, metadata block, Summary, Results) —
/// same sections, same column set as the CSV twin (including the columns
/// the wire protocol never populates, `Source`/`Part Number`/`Destination`,
/// blank here exactly as they are in the CSV), and the same colour language
/// (dark header band, green/red row tint by status). "Profile" is the one
/// row in the sample this deliberately omits — there is no profile/preset
/// concept anywhere in this app to draw a real value from, and the last
/// thing a fault-finding report should do is print a field that looks real
/// but isn't (see "GUI Reality Check", PROJECT_LOG.md). "Test Duration" is
/// real (`AppState._runStart` to `_onDone`), not the fabrication it was
/// before that wiring existed.
library;

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'report.dart';

final _title = pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800);
final _dut = pw.TextStyle(fontSize: 12, color: PdfColors.blue700);
final _verdict = pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold);
final _metaLabel = pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.grey900);
final _metaValue = pw.TextStyle(fontSize: 9);
final _section = pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800);
final _tableHeaderStyle = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white);
final _tableCellStyle = pw.TextStyle(fontSize: 8);
const _headerBg = PdfColors.blueGrey800;
const _passBg = PdfColors.green100;
const _failBg = PdfColors.red100;

/// `report.dart`'s "unknown" placeholder is the em dash (`—`) everywhere —
/// matches the CSV byte-for-byte and Flutter's own text renderer draws it
/// fine on screen. The `pdf` package's default core font (Helvetica) has no
/// glyph for it though, so it prints as a missing-glyph box; a plain hyphen
/// is the PDF-safe equivalent of the same "unknown" meaning.
String _pdfSafe(String s) => s == '—' ? '-' : s;

/// The `pdf` package is a pure-Dart PDF writer with no Flutter dependency of
/// its own — `rootBundle` is the one piece of Flutter machinery this file
/// needs, purely to read the bundled logo's bytes. Missing/unbundled asset
/// (e.g. a `flutter test` that never called `TestWidgetsFlutterBinding
/// .ensureInitialized()`) degrades to no logo rather than throwing — a
/// report without a logo is still a complete, correct report.
Future<pw.MemoryImage?> _loadLogo() async {
  try {
    final data = await rootBundle.load('assets/company_logo.jpeg');
    return pw.MemoryImage(data.buffer.asUint8List());
  } catch (_) {
    return null;
  }
}

pw.Widget _header(String titleText, ReportMeta meta, pw.MemoryImage? logo) =>
    pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        if (logo != null) ...[
          pw.Image(logo, height: 46),
          pw.SizedBox(height: 8),
        ],
        pw.Text(titleText, style: _title, textAlign: pw.TextAlign.center),
        pw.SizedBox(height: 6),
        pw.Text('DUT: ${meta.dutId.isEmpty ? "-" : meta.dutId}', style: _dut),
        pw.SizedBox(height: 4),
        pw.Text('VERDICT: ${meta.pass ? "PASS" : "FAIL"}',
            style: _verdict.copyWith(
                color: meta.pass ? PdfColors.green800 : PdfColors.red800)),
        pw.SizedBox(height: 14),
      ],
    );

pw.Widget _metaRow(String label, String value) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Row(children: [
        pw.SizedBox(width: 150, child: pw.Text(label, style: _metaLabel)),
        pw.Text(value, style: _metaValue),
      ]),
    );

pw.Widget _sectionTitle(String text) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
      child: pw.Text(text, style: _section),
    );

/// True for a row/column value that reads as "the good outcome" — drives the
/// green/red tint shared by every Summary and Results table.
bool _isGood(String status) => status == 'CONNECTED' || status == 'PASS';

PdfColor _statusBg(String status) => _isGood(status) ? _passBg : _failBg;

Future<Uint8List> buildContReportPdf(ContReport r) async {
  final logo = await _loadLogo();
  final doc = pw.Document();
  doc.addPage(pw.MultiPage(
    build: (context) => [
      _header('Harness Tester Test Report', r.meta, logo),
      _metaRow('Date/Time:', ReportMeta.stampDateTime(r.meta.when)),
      _metaRow('Operator:', r.meta.operatorName),
      _metaRow('Netlist:', r.meta.netlistName ?? '(none / auto-scan)'),
      if (r.meta.testDuration != null)
        _metaRow(
            'Test Duration:', ReportMeta.stampDuration(r.meta.testDuration!)),
      _metaRow('Total Pins Tested:', '${r.rows.length}'),
      _sectionTitle('Summary'),
      pw.TableHelper.fromTextArray(
        headers: const ['Total', 'CONNECTED', 'NOT CONNECTED'],
        data: [
          ['${r.rows.length}', '${r.connected}', '${r.rows.length - r.connected}'],
        ],
        headerStyle: _tableHeaderStyle,
        headerDecoration: const pw.BoxDecoration(color: _headerBg),
        cellStyle: _tableCellStyle,
        cellAlignment: pw.Alignment.center,
        cellDecoration: (col, data, rowNum) => pw.BoxDecoration(
            color: col == 1 ? _passBg : (col == 2 ? _failBg : null)),
      ),
      _sectionTitle('Results'),
      pw.TableHelper.fromTextArray(
        headers: const [
          'Test #', 'Source', 'Part Number', 'Conn ID', 'Src Pin Label',
          'Src Pin #', 'Status', 'Dst Pin #', 'Dst Pin Label', 'Conn ID',
          'Part Number', 'Destination', //
        ],
        data: [
          for (final row in r.rows)
            [
              '${row.testNum}', '', row.srcPartNumber, _pdfSafe(row.srcConnId),
              row.srcPinLabel, '${row.srcPin}', row.status, '${row.dstPin}',
              row.dstPinLabel, _pdfSafe(row.dstConnId), row.dstPartNumber,
              '', //
            ],
        ],
        cellStyle: _tableCellStyle,
        headerStyle: _tableHeaderStyle,
        headerDecoration: const pw.BoxDecoration(color: _headerBg),
        cellDecoration: (col, data, rowNum) =>
            pw.BoxDecoration(color: _statusBg(r.rows[rowNum - 1].status)),
      ),
    ],
  ));
  return doc.save();
}

Future<Uint8List> buildResReportPdf(ResReport r) async {
  final logo = await _loadLogo();
  final doc = pw.Document();
  final passCount = r.rows.where((x) => x.status == 'PASS').length;
  final failHigh = r.rows.where((x) => x.status == 'FAIL_HIGH').length;
  final failLow = r.rows.where((x) => x.status == 'FAIL_LOW').length;
  doc.addPage(pw.MultiPage(
    build: (context) => [
      _header('Harness Tester Test Report -- Resistance', r.meta, logo),
      _metaRow('Date/Time:', ReportMeta.stampDateTime(r.meta.when)),
      _metaRow('Operator:', r.meta.operatorName),
      _metaRow('Netlist:', r.meta.netlistName ?? '(none / auto-scan)'),
      _metaRow('Excitation Current (mA):', r.excitationMa),
      _metaRow('Resistance Limit (mOhm):', r.limitMohm),
      if (r.meta.testDuration != null)
        _metaRow(
            'Test Duration:', ReportMeta.stampDuration(r.meta.testDuration!)),
      _metaRow('Total Nets Tested:', '${r.rows.length}'),
      _sectionTitle('Summary'),
      pw.TableHelper.fromTextArray(
        headers: const ['Total', 'PASS', 'FAIL HIGH', 'FAIL LOW'],
        data: [
          ['${r.rows.length}', '$passCount', '$failHigh', '$failLow'],
        ],
        headerStyle: _tableHeaderStyle,
        headerDecoration: const pw.BoxDecoration(color: _headerBg),
        cellStyle: _tableCellStyle,
        cellAlignment: pw.Alignment.center,
        cellDecoration: (col, data, rowNum) => pw.BoxDecoration(
            color: col == 1 ? _passBg : (col == 2 || col == 3 ? _failBg : null)),
      ),
      _sectionTitle('Results'),
      pw.TableHelper.fromTextArray(
        headers: const [
          'Test #', 'Source', 'Part Number', 'Conn ID', 'Src Pin Label',
          'Src Pin #', 'R (mOhm)', 'Limit (mOhm)', 'Status', 'Dst Pin #',
          'Dst Pin Label', 'Conn ID', 'Part Number', 'Destination', //
        ],
        data: [
          for (final row in r.rows)
            [
              '${row.testNum}', '', row.srcPartNumber, _pdfSafe(row.srcConnId),
              row.srcPinLabel, '${row.srcPin}',
              row.resistanceMohm.toStringAsFixed(1), r.limitMohm, row.status,
              '${row.dstPin}', row.dstPinLabel, _pdfSafe(row.dstConnId),
              row.dstPartNumber, '', //
            ],
        ],
        cellStyle: _tableCellStyle,
        headerStyle: _tableHeaderStyle,
        headerDecoration: const pw.BoxDecoration(color: _headerBg),
        cellDecoration: (col, data, rowNum) =>
            pw.BoxDecoration(color: _statusBg(r.rows[rowNum - 1].status)),
      ),
    ],
  ));
  return doc.save();
}

Future<Uint8List> buildInsulReportPdf(InsulReport r) async {
  final logo = await _loadLogo();
  final doc = pw.Document();
  final passCount = r.rows.where((x) => x.status == 'PASS').length;
  doc.addPage(pw.MultiPage(
    build: (context) => [
      _header('Harness Tester Test Report -- HV Insulation', r.meta, logo),
      _metaRow('Date/Time:', ReportMeta.stampDateTime(r.meta.when)),
      _metaRow('Operator:', r.meta.operatorName),
      _metaRow('Netlist:', r.meta.netlistName ?? '(none / auto-scan)'),
      _metaRow('HV Applied (V):', r.hvAppliedV),
      _metaRow('Insulation Limit (MOhm):', r.limitMohm),
      if (r.meta.testDuration != null)
        _metaRow(
            'Test Duration:', ReportMeta.stampDuration(r.meta.testDuration!)),
      _metaRow('Total Nets Tested:', '${r.rows.length}'),
      _sectionTitle('Summary'),
      pw.TableHelper.fromTextArray(
        headers: const ['Total', 'PASS', 'FAIL'],
        data: [
          ['${r.rows.length}', '$passCount', '${r.rows.length - passCount}'],
        ],
        headerStyle: _tableHeaderStyle,
        headerDecoration: const pw.BoxDecoration(color: _headerBg),
        cellStyle: _tableCellStyle,
        cellAlignment: pw.Alignment.center,
        cellDecoration: (col, data, rowNum) => pw.BoxDecoration(
            color: col == 1 ? _passBg : (col == 2 ? _failBg : null)),
      ),
      _sectionTitle('Results'),
      pw.TableHelper.fromTextArray(
        headers: const [
          'Test #', 'Net', 'HV Card', 'HS Pin', 'Leak V', 'Insulation (MOhm)',
          'Limit (MOhm)', 'Status', //
        ],
        data: [
          for (final row in r.rows)
            [
              '${row.testNum}', _pdfSafe(row.net), _pdfSafe(row.hvCard),
              _pdfSafe(row.hsPin), row.leakV.toStringAsFixed(3),
              row.insulationMohm.toStringAsFixed(1), r.limitMohm, row.status, //
            ],
        ],
        cellStyle: _tableCellStyle,
        headerStyle: _tableHeaderStyle,
        headerDecoration: const pw.BoxDecoration(color: _headerBg),
        cellDecoration: (col, data, rowNum) =>
            pw.BoxDecoration(color: _statusBg(r.rows[rowNum - 1].status)),
      ),
    ],
  ));
  return doc.save();
}
