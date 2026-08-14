/// `parseNetlistWorkbook` regression tests — the actual blocker the
/// `Doc/GUI_protocol_command_coverage.md` audit called out for "Browse the
/// file system…": there was no `.hnl`/spreadsheet parser anywhere in this
/// codebase. Builds real `.xlsx` bytes with the `excel` package itself (the
/// same library the parser reads with) rather than checking in a binary
/// fixture, so the test data is readable in a diff.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ht_mk1_gui/htproto/netlist_file.dart';

Uint8List _workbook(List<List<CellValue?>> rows) {
  final book = Excel.createExcel();
  final sheet = book.getDefaultSheet()!;
  for (final row in rows) {
    book.appendRow(sheet, row);
  }
  return Uint8List.fromList(book.encode()!);
}

void main() {
  group('parseNetlistWorkbook', () {
    test('reads HI/LO pairs and an optional NET name column', () {
      final bytes = _workbook([
        [TextCellValue('NET'), TextCellValue('HI'), TextCellValue('LO')],
        [TextCellValue('PWR_28V_A'), IntCellValue(1), IntCellValue(2)],
        [TextCellValue('GND_RET'), IntCellValue(3), IntCellValue(4)],
      ]);

      final parsed = parseNetlistWorkbook(bytes, fileName: 'x.xlsx');

      expect(parsed.pairs.length, 2);
      expect(parsed.pairs[0].hi, 1);
      expect(parsed.pairs[0].lo, 2);
      expect(parsed.pairs[0].name, 'PWR_28V_A');
      expect(parsed.pairs[1].hi, 3);
      expect(parsed.pairs[1].lo, 4);
      expect(parsed.cards, isNull,
          reason: 'no CARDS column in this sheet');
    });

    test('accepts header spelling variants and a CARDS column, taking the '
        'max declared value', () {
      final bytes = _workbook([
        [TextCellValue('HS PIN'), TextCellValue('LS PIN'), TextCellValue('CARDS')],
        [IntCellValue(5), IntCellValue(6), IntCellValue(3)],
        [IntCellValue(7), IntCellValue(8), IntCellValue(4)],
      ]);

      final parsed = parseNetlistWorkbook(bytes, fileName: 'x.xlsx');

      expect(parsed.pairs.length, 2);
      expect(parsed.cards, 4);
    });

    test('recognises the required_format header spellings (Src Pin #/Dst '
        'Pin #), plus columns the parser does not use', () {
      // Header set from gui_flutter/required_format/example_netlist27072026
      // .xlsx, with two DIFFERENT pin numbers so this test isolates the
      // header-recognition fix from the connector-numbering gap covered by
      // the next test.
      final bytes = _workbook([
        [
          TextCellValue('Net'), TextCellValue('Source'),
          TextCellValue('Conn ID'), TextCellValue('Part Number'),
          TextCellValue('Src Pin Label'), TextCellValue('Src Pin #'),
          TextCellValue('Dst Pin #'), TextCellValue('Dst Pin Label'),
          TextCellValue('Conn ID B'), TextCellValue('Part Number B'),
          TextCellValue('Destination'), TextCellValue('Connector Detail'),
          TextCellValue('Harness ID'),
        ],
        [
          TextCellValue('W_PWR_24V'), TextCellValue('Side-A'),
          TextCellValue('DB15-1'), TextCellValue('DB15-M-15P'),
          TextCellValue('PWR_24V'), IntCellValue(1),
          IntCellValue(16), TextCellValue('PWR_24V'),
          TextCellValue('DB15-2'), TextCellValue('DB15-F-15S'),
          TextCellValue('Side-B'), TextCellValue('straight'),
          TextCellValue('POC-HT-EXAMPLE-3CONN-v1'),
        ],
      ]);

      final parsed = parseNetlistWorkbook(bytes, fileName: 'x.xlsx');

      expect(parsed.pairs.length, 1);
      expect(parsed.pairs[0].hi, 1);
      expect(parsed.pairs[0].lo, 16);
      expect(parsed.pairs[0].name, 'W_PWR_24V');
      expect(parsed.cards, isNull, reason: 'no CARD/CARDS column in this sheet');
    });

    test('GUI-08 resolved: HI == LO is an ordinary straight-through wire, '
        'not a routing collision — the real required_format netlist loads', () {
      // example_netlist27072026.xlsx's straight-through rows (Src Pin # ==
      // Dst Pin #, e.g. Conn ID "DB15-1" pin 1 on both sides) were rejected
      // by an earlier version of this parser under the assumption that HI
      // and LO share one flat 1..256 address space, so a matching number
      // meant "wired to itself." That assumption was wrong: matrix_card.h
      // routes HI and LO through entirely separate mux/expander banks
      // (hi_en[]/hi_sns[] vs lo_en[]/lo_sns[], different physical chips),
      // each independently addressed 1..256 — "HI pin 5 -> LO pin 5" is the
      // same pin *label* on two different physical paths, exactly what a
      // symmetric male/female connector pair looks like. See PROJECT_LOG.md
      // GUI-08/CL-41. Also confirms the pin numbers in this file are already
      // globally flat (DB15-1 -> 1..15, DB15-2 -> 16..30, DB9 -> 31..39, by
      // connector order) — no Conn ID -> offset translation is needed.
      final bytes = _workbook([
        [
          TextCellValue('Net'), TextCellValue('Conn ID'),
          TextCellValue('Src Pin #'), TextCellValue('Dst Pin #'),
        ],
        [TextCellValue('W_PWR_24V'), TextCellValue('DB15-1'), IntCellValue(1), IntCellValue(1)],
      ]);

      final parsed =
          parseNetlistWorkbook(bytes, fileName: 'example_netlist.xlsx');

      expect(parsed.pairs.single.hi, 1);
      expect(parsed.pairs.single.lo, 1);
    });

    test('reads the real required_format/example_netlist27072026.xlsx file '
        'end to end, bytes off disk', () {
      // Also locks in a second, independent fix (CL-41):
      // required_format/example_netlist27072026.xlsx was generated by
      // openpyxl, whose default writer emits a package-absolute worksheet
      // relationship target ("/xl/worksheets/sheet1.xml") - legal OOXML, but
      // the excel package (4.0.6) only handles the relative form and used to
      // crash decoding this file entirely ("Null check operator used on a
      // null value" from excel's Parser._parseTable), before parsing ever
      // got far enough to see a single HI/LO pair. Confirmed openpyxl always
      // writes the file this way (a fresh `openpyxl.Workbook().save()` was
      // inspected directly), so this is a real compatibility gap for any
      // openpyxl-authored netlist, not just this one sample -
      // _normalizeRelationshipTargets patches it before decoding.
      final bytes = File('required_format/example_netlist27072026.xlsx')
          .readAsBytesSync();

      final parsed = parseNetlistWorkbook(bytes,
          fileName: 'example_netlist27072026.xlsx');

      expect(parsed.pairs.length, 20);
      expect(parsed.pairs.first.name, 'W_PWR_24V');
      expect(parsed.pairs.first.hi, 1);
      expect(parsed.pairs.first.lo, 1);
      // Y_SENSE_BUS branches HI pin 10 out to three different LO connectors.
      final senseBranches =
          parsed.pairs.where((p) => p.name == 'Y_SENSE_BUS').toList();
      expect(senseBranches.map((p) => p.lo), [12, 25, 36]);
    });

    test('header lookup is case-insensitive and ignores surrounding '
        'whitespace', () {
      final bytes = _workbook([
        [TextCellValue(' hi '), TextCellValue(' Lo')],
        [IntCellValue(9), IntCellValue(10)],
      ]);

      final parsed = parseNetlistWorkbook(bytes, fileName: 'x.xlsx');

      expect(parsed.pairs.single.hi, 9);
      expect(parsed.pairs.single.lo, 10);
    });

    test('skips blank rows between data rows', () {
      final bytes = _workbook([
        [TextCellValue('HI'), TextCellValue('LO')],
        [IntCellValue(1), IntCellValue(2)],
        [null, null],
        [IntCellValue(3), IntCellValue(4)],
      ]);

      final parsed = parseNetlistWorkbook(bytes, fileName: 'x.xlsx');

      expect(parsed.pairs.length, 2);
    });

    test('rejects a sheet with no recognisable HI/LO header', () {
      final bytes = _workbook([
        [TextCellValue('FOO'), TextCellValue('BAR')],
        [IntCellValue(1), IntCellValue(2)],
      ]);

      expect(
        () => parseNetlistWorkbook(bytes, fileName: 'bad.xlsx'),
        throwsA(isA<NetlistFileFormatException>().having(
          (e) => e.message,
          'message',
          contains('HI/HS pin column'),
        )),
      );
    });

    test('rejects a pin outside 1..256', () {
      final bytes = _workbook([
        [TextCellValue('HI'), TextCellValue('LO')],
        [IntCellValue(999), IntCellValue(2)],
      ]);

      expect(
        () => parseNetlistWorkbook(bytes, fileName: 'bad.xlsx'),
        throwsA(isA<NetlistFileFormatException>().having(
          (e) => e.message,
          'message',
          contains('outside 1..256'),
        )),
      );
    });

    test('accepts HI and LO naming the same pin number (straight-through '
        'wire, separate banks)', () {
      final bytes = _workbook([
        [TextCellValue('HI'), TextCellValue('LO')],
        [IntCellValue(5), IntCellValue(5)],
      ]);

      final parsed = parseNetlistWorkbook(bytes, fileName: 'ok.xlsx');

      expect(parsed.pairs.single.hi, 5);
      expect(parsed.pairs.single.lo, 5);
    });

    test('rejects a duplicate pin pair', () {
      final bytes = _workbook([
        [TextCellValue('HI'), TextCellValue('LO')],
        [IntCellValue(1), IntCellValue(2)],
        [IntCellValue(1), IntCellValue(2)],
      ]);

      expect(
        () => parseNetlistWorkbook(bytes, fileName: 'bad.xlsx'),
        throwsA(isA<NetlistFileFormatException>().having(
          (e) => e.message,
          'message',
          contains('duplicate'),
        )),
      );
    });

    test('rejects a header row with no data rows under it', () {
      final bytes = _workbook([
        [TextCellValue('HI'), TextCellValue('LO')],
      ]);

      expect(
        () => parseNetlistWorkbook(bytes, fileName: 'bad.xlsx'),
        throwsA(isA<NetlistFileFormatException>()),
      );
    });

    test('rejects bytes that are not a readable .xlsx file at all', () {
      expect(
        () => parseNetlistWorkbook(Uint8List.fromList([1, 2, 3, 4]),
            fileName: 'not-excel.txt'),
        throwsA(isA<NetlistFileFormatException>()),
      );
    });
  });

  // ===========================================================================
  // GUI-11: connector layout guessed from Conn ID/Part Number columns
  // ===========================================================================
  group('connector layout guess', () {
    test('is null when the sheet has no Conn ID columns', () {
      final bytes = _workbook([
        [TextCellValue('HI'), TextCellValue('LO')],
        [IntCellValue(1), IntCellValue(2)],
      ]);
      final parsed = parseNetlistWorkbook(bytes, fileName: 'x.xlsx');
      expect(parsed.fixture, isNull);
    });

    test('groups by Conn ID, orders by lowest pin seen, guesses shape from '
        'Part Number', () {
      final bytes = _workbook([
        [
          TextCellValue('Net'), TextCellValue('Conn ID'),
          TextCellValue('Part Number'), TextCellValue('Src Pin #'),
          TextCellValue('Dst Pin #'), TextCellValue('Conn ID B'),
          TextCellValue('Part Number B'),
        ],
        [
          TextCellValue('A'), TextCellValue('J1'), TextCellValue('DB37-M'),
          IntCellValue(1), IntCellValue(1), TextCellValue('J1'),
          TextCellValue('DB37-M'),
        ],
        [
          TextCellValue('B'), TextCellValue('J1'), TextCellValue('DB37-M'),
          IntCellValue(2), IntCellValue(38), TextCellValue('J2'),
          TextCellValue('MS3116F-Circular'),
        ],
        [
          TextCellValue('C'), TextCellValue('J2'), TextCellValue('MS3116F-Circular'),
          IntCellValue(39), IntCellValue(3), TextCellValue('J1'),
          TextCellValue('DB37-M'),
        ],
      ]);

      final parsed = parseNetlistWorkbook(bytes, fileName: 'x.xlsx');
      final fixture = parsed.fixture;
      expect(fixture, isNotNull);
      expect(fixture!.length, 2);
      expect(fixture[0].id, 'J1');
      expect(fixture[0].shapeGuess, 'dsub');
      // J1's pins observed: 1 (row A src), 3 (row C dst) — block runs from
      // its own lowest observed pin (1) to just before J2's lowest (38), so
      // 1..37 -> 37 pins, even though only 1 and 3 were actually seen wired.
      expect(fixture[0].pins, 37);
      expect(fixture[1].id, 'J2');
      expect(fixture[1].shapeGuess, 'circ');
      // Last connector: runs from its own lowest (38) to its own highest
      // observed pin (39) -> 2 pins.
      expect(fixture[1].pins, 2);
    });

    test('rect is the fallback shape for an unrecognised part number', () {
      final bytes = _workbook([
        [
          TextCellValue('Conn ID'), TextCellValue('Part Number'),
          TextCellValue('HI'), TextCellValue('LO'),
        ],
        [
          TextCellValue('P1'), TextCellValue('AMP-RECT-9'), IntCellValue(1),
          IntCellValue(2),
        ],
      ]);
      final parsed = parseNetlistWorkbook(bytes, fileName: 'x.xlsx');
      expect(parsed.fixture!.single.shapeGuess, 'rect');
    });
  });
}
