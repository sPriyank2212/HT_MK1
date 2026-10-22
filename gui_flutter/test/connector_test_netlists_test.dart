/// Reads the `test_netlists/TN-*.xlsx` connector-variety samples
/// (`test_netlists/generate_connector_test_netlists.py`) off disk through
/// the real parser, and checks `_guessFixture`/`_guessShape`'s output
/// (`netlist_file.dart`) lands where each file was built to land. Same
/// "read the real bundled file end to end" discipline as
/// `netlist_file_test.dart`'s `required_format/` cases — these are
/// generated fixtures, but the parser doesn't know that, and neither should
/// this test pretend to.
///
/// The guess is per harness END: every `Conn ID` (Side-A, the HI pins) and
/// every `Conn ID B` (Side-B, the LO pins) is its own connector, so a
/// designator used at both ends (a mated pair's `DB9-1`) appears twice.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ht_mk1_gui/htproto/netlist_file.dart';

GuessedConnector _at(List<GuessedConnector> fixture, String side, String id) =>
    fixture.firstWhere((c) => c.side == side && c.id == id,
        orElse: () => throw StateError('no $side connector "$id" in $fixture'));

ParsedNetlist _load(String file) => parseNetlistWorkbook(
      File('${Directory.current.path}/../test_netlists/$file')
          .readAsBytesSync(),
      fileName: file,
    );

void main() {
  group('connector-layout guess, against test_netlists/TN-*.xlsx', () {
    test('TN-01: a mated pair (same Conn ID at both ends) is one connector '
        'PER END, not one merged connector', () {
      final parsed = _load('TN-01_symmetric_dsub_pair.xlsx');

      expect(parsed.pairs.length, 46);
      final fixture = parsed.fixture!;
      expect(fixture.length, 4, reason: 'two connectors on each of two ends');
      for (final side in ['src', 'dst']) {
        final db9 = _at(fixture, side, 'DB9-1');
        expect(db9.pins, 9);
        expect(db9.shapeGuess, 'dsub');
        final db37 = _at(fixture, side, 'DB37-1');
        expect(db37.pins, 37);
        expect(db37.shapeGuess, 'dsub');
      }
    });

    test('TN-02: distinct Source/Destination connectors resolve all three '
        'original shape guesses on the right ends', () {
      final parsed = _load('TN-02_distinct_src_dst_connectors.xlsx');

      expect(parsed.pairs.length, 46);
      final fixture = parsed.fixture!;
      expect(fixture.length, 3);

      final dsub = _at(fixture, 'src', 'J1-DB9');
      expect(dsub.pins, 9);
      expect(dsub.shapeGuess, 'dsub');

      final circ = _at(fixture, 'src', 'J2-CIRC');
      expect(circ.pins, 37);
      expect(circ.shapeGuess, 'circ');

      final rect = _at(fixture, 'dst', 'J3-RECT');
      expect(rect.pins, 46);
      expect(rect.shapeGuess, 'rect',
          reason: 'TE-CPC-46S says CPC, which is rectangular');
    });

    test('TN-03: six small mating pairs each guess their own 9-pin dsub '
        'block on each end, not one merged connector', () {
      final parsed = _load('TN-03_many_small_connectors.xlsx');

      expect(parsed.pairs.length, 54);
      final fixture = parsed.fixture!;
      expect(fixture.length, 12);
      for (final side in ['src', 'dst']) {
        for (var i = 1; i <= 6; i++) {
          final c = _at(fixture, side, 'DB9-$i');
          expect(c.pins, 9, reason: '$side DB9-$i');
          expect(c.shapeGuess, 'dsub', reason: '$side DB9-$i');
        }
      }
    });

    test('TN-04: a single 100-pin connector is one block per end, no '
        'boundary inference needed', () {
      final parsed = _load('TN-04_single_large_connector.xlsx');

      expect(parsed.pairs.length, 100);
      final fixture = parsed.fixture!;
      expect(fixture.length, 2);
      for (final side in ['src', 'dst']) {
        final big = _at(fixture, side, 'J1-BIG');
        expect(big.pins, 100);
        expect(big.shapeGuess, 'rect');
      }
    });

    test('TN-05: an earlier connector with unused trailing pins is '
        'extended to the next connector\'s start, but the last connector '
        'on an end is not — a real limit of the guess, not a bug in this '
        'test', () {
      final parsed = _load('TN-05_partial_unused_pins.xlsx');

      expect(parsed.pairs.length, 26);
      final fixture = parsed.fixture!;
      expect(fixture.length, 4);

      for (final side in ['src', 'dst']) {
        // Only pins 1..6 of the real 9-pin DB9 are wired, but DB37-1 starts
        // at pin 10, so the boundary inference extends DB9-1 to 1..9.
        expect(_at(fixture, side, 'DB9-1').pins, 9);
        // DB37-1 is the LAST connector on its end: nothing after it bounds
        // the guess, so only the 20 pins actually wired are counted.
        expect(_at(fixture, side, 'DB37-1').pins, 20);
      }
    });

    test('TN-06: a Conn ID reused for two different connectors is flagged '
        'by its part number\'s pin count', () {
      final parsed = _load('TN-06_conflicting_connector_id.xlsx');

      expect(parsed.pairs.length, 46);
      final fixture = parsed.fixture!;

      // Source end: DB9-1 (1..9) then DB37-1 (10..46) — clean.
      expect(_at(fixture, 'src', 'DB9-1').pins, 9);
      expect(_at(fixture, 'src', 'DB37-1').pins, 37);
      expect(_at(fixture, 'src', 'DB37-1').exceedsPart, isFalse);

      // Destination end: DB37-1 is both the far end of DB9-1's wires
      // (pins 1..9) and its own mated block (10..46) — 46 pins wired on a
      // part that has 37. That is the collision, now surfaced as a warning
      // instead of silently drawing wires wrong.
      final dst = _at(fixture, 'dst', 'DB37-1');
      expect(dst.pins, 46);
      expect(dst.partPins, 37);
      expect(dst.exceedsPart, isTrue);
    });
  });

  group('connector shape guess', () {
    GuessedConnector shapeOf(String part) {
      // route a one-row sheet through the real parser is overkill; the
      // generated HW-* files cover that end to end (harness_scenarios_test).
      // Here only the keyword table matters.
      return _guess(part);
    }

    test('the five connector families', () {
      const cases = {
        'DB9-M-9P': 'dsub',
        'DB37-F-37S': 'dsub',
        'DE-9S': 'dsub',
        'HD-44': 'dsub',
        'MS3116F14-19S': 'circ',
        'D38999/26WB35SN': 'circ',
        'M12-A-8P-FEMALE': 'circ',
        'M8-3P-FEMALE': 'circ',
        'TE-CPC-46S': 'rect',
        'MOLEX-MINIFIT-12': 'rect',
        'DEUTSCH-DT06-12S': 'rect',
        'AMPHENOL-RECT-24': 'rect',
        'PHOENIX-MSTB-2.5/12-TERMINAL': 'term',
        'WAGO-TERMINAL-8': 'term',
        'RJ45-8P8C-JACK': 'mod',
        'RJ11-6P4C-JACK': 'mod',
        'USB-A-4P': 'mod',
        'SOMETHING-UNKNOWN': 'rect',
      };
      cases.forEach((part, shape) {
        expect(shapeOf(part).shapeGuess, shape, reason: part);
      });
    });
  });
}

/// A connector guess for one part number, through the real parser.
GuessedConnector _guess(String part) {
  final parsed = parseNetlistWorkbook(_oneRowWorkbook(part), fileName: 'one.xlsx');
  return parsed.fixture!.first;
}

/// Minimal .xlsx with a header and one row carrying [part] as the Source part
/// number — written with the same `excel` package the parser reads with, so
/// no binary fixture is needed.
Uint8List _oneRowWorkbook(String part) {
  final book = Excel.createExcel();
  final sheet = book.getDefaultSheet()!;
  book.appendRow(sheet, [
    TextCellValue('Net'),
    TextCellValue('Conn ID'),
    TextCellValue('Part Number'),
    TextCellValue('Src Pin #'),
    TextCellValue('Dst Pin #'),
  ]);
  book.appendRow(sheet, [
    TextCellValue('N1'),
    TextCellValue('J1'),
    TextCellValue(part),
    IntCellValue(1),
    IntCellValue(1),
  ]);
  return Uint8List.fromList(book.encode()!);
}
