/// GUI-21: the demo simulator used to compare an uploaded netlist's `(hi,
/// lo)` pairs against its own fixed fake-harness pairing (`1↔2, 3↔4, …`) by
/// literal value — any netlist using a different (but equally valid)
/// pairing convention, like real hardware's straight-through `Src Pin # ==
/// Dst Pin #` (`required_format/netlist_full_256x256.xlsx`), could never
/// match, so every net read NOT CONNECTED regardless of `--nets`. Fixed by
/// applying the scenario's scripted pass/fail pattern *positionally*
/// (`InstrumentSim._effectiveNets`) instead of by literal pin match. This
/// file proves it end to end against a real `SimulatorServer`, not just by
/// reading the code.
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

Future<void> waitUntil(bool Function() cond,
    {Duration timeout = const Duration(seconds: 5)}) async {
  final deadline = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('waitUntil timed out');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  group('simulator honours an uploaded straight-through netlist', () {
    late SimulatorServer sim;
    late ConnectionManager cm;
    late AppState s;

    Future<void> boot(String scenario,
        {required Future<(String, Uint8List)?> Function()
            pickNetlistFile}) async {
      sim = await SimulatorServer.start(
        makeScenario(scenario, nets: 4),
        port: 0,
        interval: Duration.zero,
      );
      cm = ConnectionManager(
        onEvent: (m) => s.onEvent(m),
        onLinkState: (st, d) => s.onLinkState(st, d),
        logDir: Directory.systemTemp,
      );
      s = AppState(
        cm: cm,
        host: '127.0.0.1',
        port: sim.port,
        pickNetlistFile: pickNetlistFile,
      );
      await s.connect();
    }

    tearDown(() async {
      await cm.disconnect();
      await sim.stop();
    });

    test("'pass' scenario passes a straight-through netlist "
        '(pin N <-> pin N), not just the simulator\'s own 1-2/3-4 pairing',
        () async {
      // Same convention as required_format/netlist_full_256x256.xlsx: Src
      // Pin # == Dst Pin # (HI and LO are separate independently-addressed
      // banks on real hardware, GUI-08) - the exact shape that used to read
      // 0 pass against the demo.
      final bytes = _workbook([
        [TextCellValue('NET'), TextCellValue('HI'), TextCellValue('LO')],
        [TextCellValue('NET_001'), IntCellValue(1), IntCellValue(1)],
        [TextCellValue('NET_002'), IntCellValue(2), IntCellValue(2)],
        [TextCellValue('NET_003'), IntCellValue(3), IntCellValue(3)],
        [TextCellValue('NET_004'), IntCellValue(4), IntCellValue(4)],
      ]);
      await boot('pass', pickNetlistFile: () async => ('straight.xlsx', bytes));

      await s.browseMtxNetlist();
      s.setMode('net');
      await s.runCont();
      await waitUntil(() => s.running == null);

      expect(s.R['cont'], 'pass');
      final r = s.lastContReport;
      expect(r, isNotNull);
      expect(r!.rows.length, 4);
      expect(r.rows.every((row) => row.status == 'CONNECTED'), isTrue);
      expect(r.rows.map((row) => (row.srcPin, row.dstPin)),
          [(1, 1), (2, 2), (3, 3), (4, 4)]);
    });

    test("'opens_shorts' scenario still injects faults positionally against "
        'a straight-through netlist, not by literal pin match', () async {
      final bytes = _workbook([
        [TextCellValue('NET'), TextCellValue('HI'), TextCellValue('LO')],
        [TextCellValue('NET_001'), IntCellValue(1), IntCellValue(1)],
        [TextCellValue('NET_002'), IntCellValue(2), IntCellValue(2)],
        [TextCellValue('NET_003'), IntCellValue(3), IntCellValue(3)],
        [TextCellValue('NET_004'), IntCellValue(4), IntCellValue(4)],
      ]);
      await boot('opens_shorts',
          pickNetlistFile: () async => ('straight.xlsx', bytes));

      await s.browseMtxNetlist();
      s.setMode('net');
      await s.runCont();
      await waitUntil(() => s.running == null);

      expect(s.R['cont'], 'fail');
      final r = s.lastContReport!;
      // scenario 'opens_shorts' scripts positions 0/1 open, 2 short, per
      // makeScenario() - applied positionally to whichever pins were
      // actually uploaded (1,2,3 here), not to the literal pins 1/3/5 the
      // scenario's own internal _goodNets(4) pairing would otherwise name.
      expect(r.rows[0].status, 'NOT CONNECTED');
      expect(r.rows[1].status, 'NOT CONNECTED');
      expect(r.rows[2].status, 'NOT CONNECTED');
      expect(r.rows[3].status, 'CONNECTED');
    });

    test("a netlist bigger than --nets 'passes' fully too - verify mode no "
        "longer needs --nets to match the loaded file's net count",
        () async {
      // makeScenario('pass', nets: 4) - 4 is the smallest scenarios allow
      // (ArgumentError below that) - deliberately smaller than the 10-row
      // netlist below, the old "--nets must match or CONT RUN FAILs"
      // constraint (test_netlists/README.md, pre-GUI-21).
      final rows = <List<CellValue?>>[
        [TextCellValue('NET'), TextCellValue('HI'), TextCellValue('LO')],
      ];
      for (var i = 1; i <= 10; i++) {
        rows.add([TextCellValue('N$i'), IntCellValue(i), IntCellValue(i)]);
      }
      final bytes = _workbook(rows);
      await boot('pass', pickNetlistFile: () async => ('big.xlsx', bytes));

      await s.browseMtxNetlist();
      s.setMode('net');
      await s.runCont();
      await waitUntil(() => s.running == null);

      expect(s.R['cont'], 'pass');
      final r = s.lastContReport!;
      expect(r.rows.length, 10);
      expect(r.rows.every((row) => row.status == 'CONNECTED'), isTrue);
    });
  });
}
