/// GUI-23: two real bugs found together, both from a user report that
/// Continuity's connector labels/report fields looked wrong once a netlist
/// with distinct Source/Destination connector ids was loaded.
///
/// 1. `AppState.rebuildNets`'s `pinNode` searched the *same* connector list
///    for both `hi` and `lo` — HI and LO are the instrument's two
///    independently-addressed 1..256 spaces (matrix_card.h), so a
///    straight-through net (equal pin numbers, the ordinary case per
///    GUI-08) always resolved src and dst to the *same* connector whenever
///    that number fell inside one connector's range. Every net in
///    `required_format/netlist_full_256x256.xlsx` showed "MTX-A1 pin 5" on
///    both ends instead of "MTX-A1 pin 5" -> "MTX-B1 pin 5".
/// 2. The report/GUI's "Part Number" column was hardcoded blank even
///    though the netlist file's own `Part Number`/`Part Number B` columns
///    were already parsed and available (`GuessedConnector.partNumber`) —
///    just never carried through to `ConnectorDef` or the report rows.
///
/// This file proves both fixes end to end against a real `SimulatorServer`
/// and a real uploaded netlist, not just by reading the code.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ht_mk1_gui/app/app_state.dart';
import 'package:ht_mk1_gui/htproto/connection.dart';
import 'package:ht_mk1_gui/htproto/simulator.dart';

Uint8List _workbook(List<List<CellValue?>> rows) {
  final book = Excel.createExcel();
  final sheet = book.getDefaultSheet()!;
  for (final row in rows) {
    book.appendRow(sheet, row);
  }
  return Uint8List.fromList(book.encode()!);
}

Future<void> waitUntil(bool Function() cond) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!cond()) {
    if (DateTime.now().isAfter(deadline)) fail('waitUntil timed out');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  group('a straight-through netlist with distinct Source/Destination ids '
      'and real part numbers', () {
    late SimulatorServer sim;
    late ConnectionManager cm;
    late AppState s;

    Future<void> boot(Uint8List bytes) async {
      sim = await SimulatorServer.start(makeScenario('pass', nets: 4),
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
        pickNetlistFile: () async => ('sided.xlsx', bytes),
      );
      await s.connect();
      await s.browseMtxNetlist();
      s.setMode('net');
      await s.runCont();
      await waitUntil(() => s.running == null);
    }

    tearDown(() async {
      await cm.disconnect();
      await sim.stop();
    });

    test('resolves src and dst to different connectors, with real part '
        'numbers on both ends', () async {
      final bytes = _workbook([
        [
          TextCellValue('Conn ID'), TextCellValue('Part Number'),
          TextCellValue('HI'), TextCellValue('LO'),
          TextCellValue('Conn ID B'), TextCellValue('Part Number B'),
        ],
        [
          TextCellValue('A1'), TextCellValue('DB37-M-37P'), IntCellValue(1),
          IntCellValue(1), TextCellValue('B1'), TextCellValue('DB37-F-37S'),
        ],
      ]);
      await boot(bytes);

      expect(s.R['cont'], 'pass');
      final r = s.lastContReport!;
      expect(r.rows.single.status, 'CONNECTED');

      // Bug 1: src and dst must resolve to different connectors.
      expect(s.nets.single.src.c, 'A1');
      expect(s.nets.single.dsts[0].c, 'B1');

      // Bug 2: Part Number is real on both ends, not blank.
      expect(r.rows.single.srcPartNumber, 'DB37-M-37P');
      expect(r.rows.single.dstPartNumber, 'DB37-F-37S');
      expect(r.toCsv(), contains('DB37-M-37P'));
      expect(r.toCsv(), contains('DB37-F-37S'));
    });

    test('Part Number is blank, not fabricated, when the netlist has none',
        () async {
      final bytes = _workbook([
        [
          TextCellValue('Conn ID'), TextCellValue('HI'), TextCellValue('LO'),
          TextCellValue('Conn ID B'),
        ],
        [TextCellValue('A1'), IntCellValue(1), IntCellValue(1), TextCellValue('B1')],
      ]);
      await boot(bytes);

      final r = s.lastContReport!;
      expect(r.rows.single.srcPartNumber, '');
      expect(r.rows.single.dstPartNumber, '');
    });
  });
}
