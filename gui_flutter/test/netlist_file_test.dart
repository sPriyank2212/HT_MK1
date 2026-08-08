/// `parseNetlistWorkbook` regression tests — the actual blocker the
/// `Doc/GUI_protocol_command_coverage.md` audit called out for "Browse the
/// file system…": there was no `.hnl`/spreadsheet parser anywhere in this
/// codebase. Builds real `.xlsx` bytes with the `excel` package itself (the
/// same library the parser reads with) rather than checking in a binary
/// fixture, so the test data is readable in a diff.
library;

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

    test('rejects HI and LO both naming the same pin', () {
      final bytes = _workbook([
        [TextCellValue('HI'), TextCellValue('LO')],
        [IntCellValue(5), IntCellValue(5)],
      ]);

      expect(
        () => parseNetlistWorkbook(bytes, fileName: 'bad.xlsx'),
        throwsA(isA<NetlistFileFormatException>()),
      );
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
}
