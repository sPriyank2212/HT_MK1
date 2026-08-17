/// Smoke test: the PDF builders in `report_pdf.dart` produce non-empty
/// bytes and the bundled logo asset actually loads via `rootBundle` under
/// the test binding — not exercised by `report_test.dart`, which only
/// checks the CSV side.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ht_mk1_gui/app/report.dart';
import 'package:ht_mk1_gui/app/report_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('buildContReportPdf produces a non-empty PDF', () async {
    final meta = ReportMeta(
      dutId: 'HT-0004',
      operatorName: '',
      netlistName: null,
      pass: true,
      when: DateTime(2026, 7, 25, 18, 43, 14),
      testDuration: const Duration(milliseconds: 248),
    );
    final r = ContReport(meta, const [
      // No srcConnId/dstConnId given - GUI-11's '—' default (unresolved
      // connector), exercising the PDF's Helvetica-safe substitution for
      // report_pdf.dart's own Conn ID column.
      ContReportRow(testNum: 1, srcPin: 1, dstPin: 14, status: 'CONNECTED'),
    ]);

    final bytes = await buildContReportPdf(r);
    expect(bytes, isNotEmpty);
    // %PDF magic bytes.
    expect(bytes.sublist(0, 4), [0x25, 0x50, 0x44, 0x46]);
  });
}
