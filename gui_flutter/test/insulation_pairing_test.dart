/// GUI-25: insulation testing shares the MTX netlist with continuity/
/// resistance on real hardware — `run_insulation_all()` (`Core/Src/app/
/// tasks.c`) iterates `Proto_NetlistCount()`/`Proto_NetlistGet()`, the same
/// uploaded pairs, and reports each result against the real hi pin
/// (`Proto_EvtInsul(hi, ...)`). The demo simulator's `_runInsul` didn't know
/// that — it always ran exactly `--nets` (12 by default) fake nets,
/// identified `1..12` by sequential index rather than by real pin number,
/// regardless of what netlist was actually loaded. A user with more than 12
/// nets loaded saw insulation results for only the first 12 (or the wrong
/// 12, since the index rarely lines up with a real pin). Fixed the same way
/// GUI-21 fixed continuity/resistance: `InstrumentSim._effectiveNets`.
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
  test('insulation tests every net in a 20-row netlist, not just the '
      "simulator's --nets default of 12", () async {
    final sim = await SimulatorServer.start(makeScenario('pass', nets: 12),
        port: 0, interval: Duration.zero);
    late AppState s;
    final cm = ConnectionManager(
      onEvent: (m) => s.onEvent(m),
      onLinkState: (st, d) => s.onLinkState(st, d),
      logDir: Directory.systemTemp,
    );

    final rows = <List<CellValue?>>[
      [TextCellValue('NET'), TextCellValue('HI'), TextCellValue('LO')],
    ];
    for (var i = 1; i <= 20; i++) {
      rows.add([TextCellValue('N$i'), IntCellValue(i), IntCellValue(i)]);
    }
    final bytes = _workbook(rows);

    s = AppState(
      cm: cm,
      host: '127.0.0.1',
      port: sim.port,
      pickNetlistFile: () async => ('twenty.xlsx', bytes),
    );
    await s.connect();

    // Upload the netlist on J-MTX first (real hardware: insulation shares
    // it), then move to J-HV and arm.
    await s.browseMtxNetlist();
    await s.confirmHandover();
    await s.runHv();
    await waitUntil(() => s.running == null);

    expect(s.R['hv'], 'pass');
    final r = s.lastInsulReport;
    expect(r, isNotNull);
    expect(r!.rows.length, 20);
    // Every one of the 20 real nets resolved, not just the first/some 12.
    expect(r.rows.map((row) => row.net).toSet().length, 20);

    await cm.disconnect();
    await sim.stop();
  });
}
