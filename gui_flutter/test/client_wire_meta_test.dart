// The wire-metadata columns the client's reports need (Source, Destination,
// Colour, AWG, Length, Harness No, Harness ID, connector ids and part numbers):
// parsed from the netlist workbook, carried to the report rows, and — the
// regression behind lib/app/app_state.dart `_prepareRun` — not lost when the
// instrument streams results straight after its `<OK`.
import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ht_mk1_gui/app/app_state.dart';
import 'package:ht_mk1_gui/client/client_report.dart';
import 'package:ht_mk1_gui/design/model.dart';
import 'package:ht_mk1_gui/htproto/connection.dart';
import 'package:ht_mk1_gui/htproto/netlist_file.dart';
import 'package:ht_mk1_gui/htproto/simulator.dart';

Uint8List _workbook(List<List<CellValue?>> rows) {
  final book = Excel.createExcel();
  final sheet = book.getDefaultSheet()!;
  for (final row in rows) {
    book.appendRow(sheet, row);
  }
  return Uint8List.fromList(book.encode()!);
}

TextCellValue t(String s) => TextCellValue(s);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WireMeta from the netlist workbook', () {
    final bytes = _workbook([
      [
        t('Net'), t('Source'), t('Conn ID'), t('Part Number'),
        t('Src Pin Label'), t('Src Pin #'), t('Dst Pin #'), t('Dst Pin Label'),
        t('Conn ID B'), t('Part Number B'), t('Destination'), t('Colour'),
        t('AWG'), t('Length'), t('Harness No'), t('Harness ID'), //
      ],
      [
        t('PWR'), t('ECU'), t('X1'), t('DB15-M'), t('PWR_24V'), IntCellValue(1),
        IntCellValue(2), t('ENG_VCC'), t('X2'), t('DB15-F'), t('Engine'),
        t('RED'), IntCellValue(22), DoubleCellValue(1.5), t('H-77'),
        t('HRN-2026-001'), //
      ],
      [
        t('GND'), t('ECU'), t('X1'), t('DB15-M'), t('GND'), IntCellValue(3),
        IntCellValue(4), t('ENG_GND'), t('X2'), t('DB15-F'), t('Engine'),
        t('BLK'), IntCellValue(20), DoubleCellValue(2.0), t('H-78'), null, //
      ],
    ]);
    final parsed = parseNetlistWorkbook(bytes, fileName: 'm.xlsx');

    test('every descriptive column reaches its pair', () {
      final w = parsed.pairs[0].meta!;
      expect(w.source, 'ECU');
      expect(w.destination, 'Engine');
      expect(w.srcConnId, 'X1');
      expect(w.dstConnId, 'X2');
      expect(w.srcPart, 'DB15-M');
      expect(w.dstPart, 'DB15-F');
      expect(w.colour, 'RED');
      expect(w.awg, '22', reason: 'an integer cell reads as typed, not 22.0');
      expect(w.length, '1.5');
      expect(w.harnessNo, 'H-77');
      expect(parsed.pairs[1].meta!.colour, 'BLK');
    });

    test('the Harness ID column is read once for the whole file', () {
      expect(parsed.harnessId, 'HRN-2026-001');
    });

    test('a sheet without those columns still loads, with blanks', () {
      final p = parseNetlistWorkbook(
          _workbook([
            [t('HI'), t('LO')],
            [IntCellValue(1), IntCellValue(2)],
          ]),
          fileName: 'min.xlsx');
      final w = p.pairs.single.meta!;
      expect([w.source, w.destination, w.colour, w.awg, w.length, w.harnessNo],
          everyElement(''));
      expect(p.harnessId, isNull);
    });

    test('the metadata is what the client CSV prints', () {
      const f = ClientReportFormat();
      // the wire columns feed the 16-column row
      final w = parsed.pairs[0].meta!;
      expect([w.colour, w.awg, w.length, w.harnessNo].join(','),
          'RED,22,1.5,H-77');
      expect(f.fileStem('continuity', 's', 'D'), 'report_s_D');
    });
  });

  group('results that arrive with the start acknowledgement are kept', () {
    // interval zero: the simulator streams every result back to back, straight
    // after `<OK`, so several arrive before the GUI has processed the OK.
    Future<AppState> run(WidgetTester tester, String scenario) async {
      late AppState s;
      late SimulatorServer sim;
      late ConnectionManager cm;
      await tester.runAsync(() async {
        sim = await SimulatorServer.start(makeScenario(scenario, nets: 20),
            port: 0, interval: Duration.zero);
        cm = ConnectionManager(
          onEvent: (m) => s.onEvent(m),
          onLinkState: (st, d) => s.onLinkState(st, d),
          logDir: Directory.systemTemp,
        );
        s = AppState(
          cm: cm,
          host: '127.0.0.1',
          port: sim.port,
          serialLink: false,
          pickNetlistFile: () async => (
                'n.xlsx',
                File('required_format/example_netlist27072026.xlsx')
                    .readAsBytesSync()
              ),
        );
        await s.connect();
        await s.browseMtxNetlist();
        await s.runCont();
      });
      final sw = Stopwatch()..start();
      while (s.running != null || s.R['cont'] == null) {
        if (sw.elapsedMilliseconds > 15000) fail('run did not finish');
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)));
        await tester.pump();
      }
      addTearDown(() async {
        await cm.disconnect();
        await sim.stop();
        setActiveFixture(buildDefaultFixture());
      });
      return s;
    }

    testWidgets('a clean run has one row per pair', (tester) async {
      final s = await run(tester, 'pass');
      expect(s.contRowsLive.length, 20);
      expect(s.contRowsLive.map((r) => r.testNum), List.generate(20, (i) => i + 1));
    });

    testWidgets('a run whose FIRST results fail keeps those rows',
        (tester) async {
      final s = await run(tester, 'opens_shorts');
      // the scenario puts its two opens and one short on the first three pairs
      expect(s.contRowsLive.length, 20,
          reason: 'the first results must not be wiped by the run starting');
      expect(s.contRowsLive.where((r) => r.status == 'NOT CONNECTED').length, 3);
      expect(s.contRowsLive.take(3).every((r) => r.status == 'NOT CONNECTED'),
          isTrue);
      // and the wiring diagram agrees with the table
      final open = s.nets.expand((n) => n.openPairs).length;
      expect(open, 3);
    });
  });
}
