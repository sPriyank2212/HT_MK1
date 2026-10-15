/// Reads the `test_netlists/TN-*.xlsx` connector-variety samples
/// (`test_netlists/generate_connector_test_netlists.py`) off disk through
/// the real parser, and checks `_guessFixture`/`_guessShape`'s output
/// (`netlist_file.dart`) lands where each file was built to land. Same
/// "read the real bundled file end to end" discipline as
/// `netlist_file_test.dart`'s `required_format/` cases — these are
/// generated fixtures, but the parser doesn't know that, and neither should
/// this test pretend to.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ht_mk1_gui/htproto/netlist_file.dart';

GuessedConnector _byId(List<GuessedConnector> fixture, String id) =>
    fixture.firstWhere((c) => c.id == id,
        orElse: () => throw StateError('no connector "$id" in $fixture'));

void main() {
  group('connector-layout guess, against test_netlists/TN-*.xlsx', () {
    test('TN-01: a symmetric mating pair (same Conn ID both ends) guesses '
        'two dsub connectors with no src/dst distinction', () {
      final bytes =
          File('${Directory.current.path}/../test_netlists/'
                  'TN-01_symmetric_dsub_pair.xlsx')
              .readAsBytesSync();
      final parsed = parseNetlistWorkbook(bytes, fileName: 'TN-01.xlsx');

      expect(parsed.pairs.length, 46);
      final fixture = parsed.fixture!;
      expect(fixture.length, 2);
      final db9 = _byId(fixture, 'DB9-1');
      expect(db9.pins, 9);
      expect(db9.shapeGuess, 'dsub');
      expect(db9.side, isNull,
          reason: 'same Conn ID on both Source and Destination — a mating '
              'pair, not two different connectors');
      final db37 = _byId(fixture, 'DB37-1');
      expect(db37.pins, 37);
      expect(db37.shapeGuess, 'dsub');
    });

    test('TN-02: distinct Source/Destination connectors resolve all three '
        'shape guesses and a real src/dst side each', () {
      final bytes =
          File('${Directory.current.path}/../test_netlists/'
                  'TN-02_distinct_src_dst_connectors.xlsx')
              .readAsBytesSync();
      final parsed = parseNetlistWorkbook(bytes, fileName: 'TN-02.xlsx');

      expect(parsed.pairs.length, 46);
      final fixture = parsed.fixture!;
      expect(fixture.length, 3);

      final dsub = _byId(fixture, 'J1-DB9');
      expect(dsub.pins, 9);
      expect(dsub.shapeGuess, 'dsub');
      expect(dsub.side, 'src');

      final circ = _byId(fixture, 'J2-CIRC');
      expect(circ.pins, 37);
      expect(circ.shapeGuess, 'circ');
      expect(circ.side, 'src');

      final rect = _byId(fixture, 'J3-RECT');
      expect(rect.pins, 46);
      expect(rect.shapeGuess, 'rect',
          reason: 'TE-CPC-46S has none of the DSUB/CIRC/MS3/38999/AMPHENOL '
              'keywords _guessShape looks for, so it falls through to rect');
      expect(rect.side, 'dst');
    });

    test('TN-03: six small mating pairs each guess their own 9-pin dsub '
        'block, not one merged connector', () {
      final bytes =
          File('${Directory.current.path}/../test_netlists/'
                  'TN-03_many_small_connectors.xlsx')
              .readAsBytesSync();
      final parsed = parseNetlistWorkbook(bytes, fileName: 'TN-03.xlsx');

      expect(parsed.pairs.length, 54);
      final fixture = parsed.fixture!;
      expect(fixture.length, 6);
      for (var i = 1; i <= 6; i++) {
        final c = _byId(fixture, 'DB9-$i');
        expect(c.pins, 9, reason: 'DB9-$i');
        expect(c.shapeGuess, 'dsub', reason: 'DB9-$i');
      }
    });

    test('TN-04: a single 100-pin connector is one block, no boundary '
        'inference needed', () {
      final bytes =
          File('${Directory.current.path}/../test_netlists/'
                  'TN-04_single_large_connector.xlsx')
              .readAsBytesSync();
      final parsed = parseNetlistWorkbook(bytes, fileName: 'TN-04.xlsx');

      expect(parsed.pairs.length, 100);
      final fixture = parsed.fixture!;
      expect(fixture.length, 1);
      final big = _byId(fixture, 'J1-BIG');
      expect(big.pins, 100);
      expect(big.shapeGuess, 'rect');
    });

    test('TN-05: an earlier connector with unused trailing pins is '
        'extended to the next connector\'s start, but the last connector '
        'in the list is not — a real limit of the guess, not a bug in this '
        'test', () {
      final bytes =
          File('${Directory.current.path}/../test_netlists/'
                  'TN-05_partial_unused_pins.xlsx')
              .readAsBytesSync();
      final parsed = parseNetlistWorkbook(bytes, fileName: 'TN-05.xlsx');

      expect(parsed.pairs.length, 26);
      final fixture = parsed.fixture!;
      expect(fixture.length, 2);

      // Only pins 1..6 of the real 9-pin DB9 are wired, but since DB37-1
      // starts at pin 10, the boundary-inference in _guessFixture correctly
      // extends DB9-1 to cover pins 1..9 anyway.
      final db9 = _byId(fixture, 'DB9-1');
      expect(db9.pins, 9);

      // DB37-1 is the LAST connector in the file, so there is no next
      // block's start pin to infer a boundary from — only the 20 pins
      // actually wired (10..29) are counted, not the real connector's 37.
      final db37 = _byId(fixture, 'DB37-1');
      expect(db37.pins, 20);
    });

    test('TN-06: a Conn ID reused as both a native mated pair and a '
        'foreign far end is flagged conflicting, without corrupting its '
        'own native pin range', () {
      final bytes =
          File('${Directory.current.path}/../test_netlists/'
                  'TN-06_conflicting_connector_id.xlsx')
              .readAsBytesSync();
      final parsed = parseNetlistWorkbook(bytes, fileName: 'TN-06.xlsx');

      expect(parsed.pairs.length, 46);
      final fixture = parsed.fixture!;
      expect(fixture.length, 2);

      final db9 = _byId(fixture, 'DB9-1');
      expect(db9.pins, 9);
      expect(db9.side, 'src');
      expect(db9.conflicting, isFalse);

      // DB37-1 is also the Destination for DB9-1's 9 pins (a genuine
      // box-to-box wire) - before the fix this widened DB37-1's guessed
      // range to 1..46 (46 pins, wrong) and shifted its base so pins 1..9
      // could never resolve back to it. It must now report its own real
      // 37-pin native block (10..46) and flag the conflict instead.
      final db37 = _byId(fixture, 'DB37-1');
      expect(db37.pins, 37);
      expect(db37.side, isNull);
      expect(db37.conflicting, isTrue);
    });
  });
}
