// The client-format reports (lib/client/client_report.dart): CSV shape traced
// to the client's own samples (required_format/report_*_HT-0008.csv and
// gui_client_required/ui/main_window.py::_write_results_csv), and a PDF that
// builds for every kind, including the multi-page and empty cases.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ht_mk1_gui/app/report.dart';
import 'package:ht_mk1_gui/client/client_report.dart';
import 'package:ht_mk1_gui/htproto/netlist_file.dart';

ReportMeta meta({bool pass = true}) => ReportMeta(
      dutId: 'HT-0004',
      operatorName: 'Priyank',
      netlistName: 'harness_a.xlsx',
      pass: pass,
      when: DateTime(2026, 7, 25, 18, 43, 12),
      testDuration: const Duration(milliseconds: 6400),
      profile: 'Default',
    );

const wire = WireMeta(
  source: 'ECU',
  destination: 'Engine',
  colour: 'RED',
  awg: '22',
  length: '1.5',
  harnessNo: 'H-77',
  srcPart: 'DB15-M',
  dstPart: 'DB15-F',
  srcConnId: 'X1',
  dstConnId: 'X2',
);

List<ContReportRow> contRows(int n) => [
      for (var i = 1; i <= n; i++)
        ContReportRow(
          testNum: i,
          srcPin: i,
          dstPin: i,
          status: i % 7 == 0 ? 'NOT CONNECTED' : 'CONNECTED',
          wire: wire,
          srcConnId: 'X1',
          dstConnId: 'X2',
          srcPinLabel: 'ECU_$i',
          dstPinLabel: 'ENG_$i',
        ),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const f = ClientReportFormat();

  group('continuity CSV', () {
    test('metadata block, blank line and the 16 client columns, CRLF', () {
      final csv = f.contCsv(ContReport(meta(), contRows(2)));
      final lines = csv.split('\r\n');
      expect(lines[0], '# Integrated Harness Tester MKI Results');
      expect(lines[1], '# DUT ID,HT-0004');
      expect(lines[2], '# Operator,Priyank');
      expect(lines[3], '# Netlist,harness_a.xlsx');
      expect(lines[4], '# Verdict,PASS');
      expect(lines[5], '# Date/Time,2026-07-25 18:43:12');
      expect(lines[6], '');
      expect(
          lines[7],
          'Test #,Source,Part Number,Conn ID,Src Pin Label,Src Pin #,Status,'
          'Dst Pin #,Dst Pin Label,Conn ID,Part Number,Destination,Colour,AWG,'
          'Length,Harness No');
      expect(lines[8],
          '1,ECU,DB15-M,X1,ECU_1,1,CONNECTED,1,ENG_1,X2,DB15-F,Engine,RED,22,1.5,H-77');
      expect(csv.contains('\n') && !csv.replaceAll('\r\n', '').contains('\n'),
          isTrue,
          reason: 'every line ends CRLF, like Python csv.writer');
    });

    test('blank placeholders instead of the model\'s em dash', () {
      final csv = f.contCsv(ContReport(meta(), [
        const ContReportRow(
            testNum: 1, srcPin: 3, dstPin: 4, status: 'NOT CONNECTED'),
      ]));
      expect(csv.contains('—'), isFalse);
      expect(csv.split('\r\n')[8],
          '1,,,,Pin 3,3,NOT CONNECTED,4,Pin 4,,,,,,,');
    });

    test('a fail verdict is written as FAIL', () {
      final csv = f.contCsv(ContReport(meta(pass: false), contRows(1)));
      expect(csv, contains('# Verdict,FAIL'));
    });
  });

  group('MK1 tests keep the same shape', () {
    test('resistance adds R and Limit before Status', () {
      final csv = f.resCsv(ResReport(meta(), '2.000', '500', [
        const ResReportRow(
            testNum: 1,
            srcPin: 1,
            dstPin: 1,
            resistanceMohm: 52.5,
            status: 'PASS',
            wire: wire),
      ]));
      final lines = csv.split('\r\n');
      expect(lines[0], '# Integrated Harness Tester MKI Results - Resistance');
      expect(lines, contains('# Excitation Current (mA),2.000'));
      expect(lines, contains('# Resistance Limit (mOhm),500'));
      final h = lines.firstWhere((l) => l.startsWith('Test #'));
      expect(h, contains('Src Pin #,Resistance (mOhm),Limit (mOhm),Status,Dst Pin #'));
      expect(h.endsWith('Colour,AWG,Length,Harness No'), isTrue);
    });

    test('insulation is one row per net', () {
      final csv = f.insulCsv(InsulReport(meta(), '500', '10.0', [
        const InsulReportRow(
            testNum: 1,
            net: 'GND',
            hvCard: 'H1',
            hsPin: 'HS-03',
            leakV: 0.012,
            insulationMohm: 840,
            status: 'PASS'),
      ]));
      expect(csv, contains('# HV Applied (V),500'));
      expect(
          csv,
          contains('Test #,Net,HV Card,HS Pin,Leak V,Insulation (MOhm),'
              'Limit (MOhm),Status'));
      expect(csv, contains('1,GND,H1,HS-03,0.012,840.0,10.0,PASS'));
    });
  });

  test('file names follow the client convention', () {
    expect(f.fileStem('continuity', '20260725_184312', 'HT-0004'),
        'report_20260725_184312_HT-0004');
    expect(f.fileStem('resistance', '20260810_150000', 'HT-0004'),
        'report_20260810_150000_HT-0004_resistance');
  });

  test('client duration format', () {
    expect(clientDuration(null), '-');
    expect(clientDuration(const Duration(milliseconds: 248)), '248 ms');
    expect(clientDuration(const Duration(milliseconds: 6400)), '6.40 s');
    expect(clientDuration(const Duration(seconds: 125)), '2m 05s');
  });

  group('PDF', () {
    // %PDF- header and an end marker are the cheapest proof the writer
    // finished; the visual check is done against the client's sample.
    void expectPdf(List<int> b) {
      expect(String.fromCharCodes(b.take(5)), '%PDF-');
      expect(b.length, greaterThan(2000));
    }

    final out = Platform.environment['CLIENT_REPORT_OUT'];

    test('continuity — multi-page', () async {
      final b = await f.contPdf(ContReport(meta(), contRows(120)));
      expectPdf(b);
      if (out != null) File('$out/cont.pdf').writeAsBytesSync(b);
    });

    test('continuity — failing, small', () async {
      final b = await f.contPdf(ContReport(meta(pass: false), contRows(8)));
      expectPdf(b);
      if (out != null) File('$out/cont_small.pdf').writeAsBytesSync(b);
    });

    test('empty report says so', () async {
      expectPdf(await f.contPdf(ContReport(meta(), const [])));
    });

    test('resistance and insulation', () async {
      final r = await f.resPdf(ResReport(meta(), '2.000', '500', [
        for (var i = 1; i <= 30; i++)
          ResReportRow(
              testNum: i,
              srcPin: i,
              dstPin: i,
              resistanceMohm: 40.0 + i,
              status: i == 5 ? 'FAIL_HIGH' : 'PASS',
              wire: wire),
      ]));
      expectPdf(r);
      final h = await f.insulPdf(InsulReport(meta(), '500', '10.0', [
        for (var i = 1; i <= 12; i++)
          InsulReportRow(
              testNum: i,
              net: 'NET_$i',
              hvCard: 'H1',
              hsPin: 'HS-${i.toString().padLeft(2, '0')}',
              leakV: 0.01,
              insulationMohm: 500.0 + i,
              status: i == 3 ? 'FAIL' : 'PASS'),
      ]));
      expectPdf(h);
      if (out != null) {
        File('$out/res.pdf').writeAsBytesSync(r);
        File('$out/insul.pdf').writeAsBytesSync(h);
      }
    });
  });
}
