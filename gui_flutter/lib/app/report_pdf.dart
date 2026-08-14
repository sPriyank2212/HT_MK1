/// PDF rendering for the reports in `report.dart`, matching the layout of
/// `required_format/report_*.pdf` (metadata block, Summary, Results table) —
/// not a pixel match (that sample's extra Profile/Test Duration rows track
/// nothing this app has), but the same sections, same column set as the CSV
/// twin, and readable as the same report.
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'report.dart';

final _title = pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold);
final _verdict = pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold);
final _metaLabel = pw.TextStyle(fontSize: 9, color: PdfColors.grey700);
final _metaValue = pw.TextStyle(fontSize: 9);
final _section = pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold);

pw.Widget _header(String titleText, ReportMeta meta) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(titleText, style: _title),
            pw.Text('DUT: ${meta.dutId.isEmpty ? "—" : meta.dutId}',
                style: _verdict),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Text('VERDICT: ${meta.pass ? "PASS" : "FAIL"}',
            style: _verdict.copyWith(
                color: meta.pass ? PdfColors.green800 : PdfColors.red800)),
        pw.SizedBox(height: 10),
      ],
    );

pw.Widget _metaRow(String label, String value) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Row(children: [
        pw.SizedBox(width: 140, child: pw.Text(label, style: _metaLabel)),
        pw.Text(value, style: _metaValue),
      ]),
    );

pw.Widget _sectionTitle(String text) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
      child: pw.Text(text, style: _section),
    );

Future<Uint8List> buildContReportPdf(ContReport r) async {
  final doc = pw.Document();
  doc.addPage(pw.MultiPage(
    build: (context) => [
      _header('Harness Tester Test Report', r.meta),
      _metaRow('Date/Time:', ReportMeta.stampDateTime(r.meta.when)),
      _metaRow('Operator:', r.meta.operatorName),
      _metaRow('Netlist:', r.meta.netlistName ?? '(none / auto-scan)'),
      _metaRow('Total Pins Tested:', '${r.rows.length}'),
      _sectionTitle('Summary'),
      pw.TableHelper.fromTextArray(headers: const [
        'Total', 'CONNECTED', 'NOT CONNECTED', //
      ], data: [
        ['${r.rows.length}', '${r.connected}', '${r.rows.length - r.connected}'],
      ]),
      _sectionTitle('Results'),
      pw.TableHelper.fromTextArray(
        headers: const [
          'Test #', 'Src Pin Label', 'Src Pin #', 'Status', 'Dst Pin #',
          'Dst Pin Label', //
        ],
        data: [
          for (final row in r.rows)
            [
              '${row.testNum}', 'Pin ${row.srcPin}', '${row.srcPin}',
              row.status, '${row.dstPin}', 'Pin ${row.dstPin}', //
            ],
        ],
        cellStyle: pw.TextStyle(fontSize: 8),
        headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
      ),
    ],
  ));
  return doc.save();
}

Future<Uint8List> buildResReportPdf(ResReport r) async {
  final doc = pw.Document();
  final passCount = r.rows.where((x) => x.status == 'PASS').length;
  final failHigh = r.rows.where((x) => x.status == 'FAIL_HIGH').length;
  final failLow = r.rows.where((x) => x.status == 'FAIL_LOW').length;
  doc.addPage(pw.MultiPage(
    build: (context) => [
      _header('Harness Tester Test Report -- Resistance', r.meta),
      _metaRow('Date/Time:', ReportMeta.stampDateTime(r.meta.when)),
      _metaRow('Operator:', r.meta.operatorName),
      _metaRow('Netlist:', r.meta.netlistName ?? '(none / auto-scan)'),
      _metaRow('Excitation Current (mA):', r.excitationMa),
      _metaRow('Resistance Limit (mOhm):', r.limitMohm),
      _metaRow('Total Nets Tested:', '${r.rows.length}'),
      _sectionTitle('Summary'),
      pw.TableHelper.fromTextArray(headers: const [
        'Total', 'PASS', 'FAIL HIGH', 'FAIL LOW', //
      ], data: [
        ['${r.rows.length}', '$passCount', '$failHigh', '$failLow'],
      ]),
      _sectionTitle('Results'),
      pw.TableHelper.fromTextArray(
        headers: const [
          'Test #', 'Src Pin Label', 'Src Pin #', 'R (mOhm)', 'Limit (mOhm)',
          'Status', 'Dst Pin #', 'Dst Pin Label', //
        ],
        data: [
          for (final row in r.rows)
            [
              '${row.testNum}', 'Pin ${row.srcPin}', '${row.srcPin}',
              row.resistanceMohm.toStringAsFixed(1), r.limitMohm, row.status,
              '${row.dstPin}', 'Pin ${row.dstPin}', //
            ],
        ],
        cellStyle: pw.TextStyle(fontSize: 8),
        headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
      ),
    ],
  ));
  return doc.save();
}

Future<Uint8List> buildInsulReportPdf(InsulReport r) async {
  final doc = pw.Document();
  final passCount = r.rows.where((x) => x.status == 'PASS').length;
  doc.addPage(pw.MultiPage(
    build: (context) => [
      _header('Harness Tester Test Report -- HV Insulation', r.meta),
      _metaRow('Date/Time:', ReportMeta.stampDateTime(r.meta.when)),
      _metaRow('Operator:', r.meta.operatorName),
      _metaRow('Netlist:', r.meta.netlistName ?? '(none / auto-scan)'),
      _metaRow('HV Applied (V):', r.hvAppliedV),
      _metaRow('Insulation Limit (MOhm):', r.limitMohm),
      _metaRow('Total Nets Tested:', '${r.rows.length}'),
      _sectionTitle('Summary'),
      pw.TableHelper.fromTextArray(headers: const [
        'Total', 'PASS', 'FAIL', //
      ], data: [
        ['${r.rows.length}', '$passCount', '${r.rows.length - passCount}'],
      ]),
      _sectionTitle('Results'),
      pw.TableHelper.fromTextArray(
        headers: const [
          'Test #', 'Net', 'HV Card', 'HS Pin', 'Leak V', 'Insulation (MOhm)',
          'Limit (MOhm)', 'Status', //
        ],
        data: [
          for (final row in r.rows)
            [
              '${row.testNum}', row.net, row.hvCard, row.hsPin,
              row.leakV.toStringAsFixed(3),
              row.insulationMohm.toStringAsFixed(1), r.limitMohm, row.status, //
            ],
        ],
        cellStyle: pw.TextStyle(fontSize: 8),
        headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
      ),
    ],
  ));
  return doc.save();
}
