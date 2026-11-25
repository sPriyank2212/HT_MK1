/// How a finished run's report is written to disk.
///
/// `AppState` decides *when* a report is produced (after every completed run,
/// and on "Export"); a [ReportFormat] decides *what it looks like*. The
/// engineering console uses [ConsoleReportFormat] (the `required_format/`
/// samples, `report.dart` / `report_pdf.dart`). The client-styled app installs
/// its own (`client/client_report.dart`) that reproduces the customer's
/// original PDF/CSV exactly. Nothing else about a run differs between them.
library;

import 'dart:typed_data';

import 'report.dart';
import 'report_pdf.dart';

abstract class ReportFormat {
  const ReportFormat();

  String contCsv(ContReport r);
  Future<Uint8List> contPdf(ContReport r);
  String resCsv(ResReport r);
  Future<Uint8List> resPdf(ResReport r);
  String insulCsv(InsulReport r);
  Future<Uint8List> insulPdf(InsulReport r);

  /// File name without extension. [kind] is `continuity` | `resistance` |
  /// `insulation`; [stamp] is `yyyyMMdd_HHmmss`.
  String fileStem(String kind, String stamp, String dutId) =>
      'report_${stamp}_$kind';
}

class ConsoleReportFormat extends ReportFormat {
  const ConsoleReportFormat();

  @override
  String contCsv(ContReport r) => r.toCsv();
  @override
  Future<Uint8List> contPdf(ContReport r) => buildContReportPdf(r);
  @override
  String resCsv(ResReport r) => r.toCsv();
  @override
  Future<Uint8List> resPdf(ResReport r) => buildResReportPdf(r);
  @override
  String insulCsv(InsulReport r) => r.toCsv();
  @override
  Future<Uint8List> insulPdf(InsulReport r) => buildInsulReportPdf(r);
}
