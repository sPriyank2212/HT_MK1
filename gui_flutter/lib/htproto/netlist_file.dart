/// Reads a netlist straight out of an Excel (`.xlsx`) file.
///
/// Real harnesses usually have a netlist spreadsheet from the design side
/// long before there is a harness on the fixture to run cross-continuity
/// discovery against — this is the other way to give the instrument a
/// netlist (`AppState.browseMtxNetlist` / `browseHvNetlist`), reading real
/// file bytes instead of only ever picking from canned demo entries or
/// building one from a scan.
///
/// Pure Dart, no platform channel — the `excel` package decodes the zip/XML
/// itself, so this file (unlike `netlist_picker_io.dart`) is safe to import
/// from tests and from `AppState` directly.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:excel/excel.dart';

/// The instrument only ever talks pins 1..256 (`AppState.rebuildNets`).
const int kMaxNetlistPin = 256;

class NetlistFileFormatException implements Exception {
  final String message;
  const NetlistFileFormatException(this.message);
  @override
  String toString() => message;
}

/// One (hi, lo) pin pair, with the net name carried through for display only
/// — the wire protocol's `NETLIST ADD` takes pins, never names.
class ParsedNetPair {
  final int hi;
  final int lo;
  final String? name;
  const ParsedNetPair(this.hi, this.lo, [this.name]);
}

class ParsedNetlist {
  final List<ParsedNetPair> pairs;

  /// The declared HV card count, if the sheet has a CARD/CARDS column —
  /// null when the file only lists pin pairs and leaves the stack size to
  /// whatever the instrument currently reports.
  final int? cards;

  const ParsedNetlist(this.pairs, this.cards);
}

// Column headers this recognises, case-insensitive with surrounding
// whitespace trimmed. Real spreadsheets will not agree on names, so each
// field accepts several common spellings rather than one exact string.
const List<String> _hiHeaders = [
  'hi', 'hi pin', 'hs', 'hs pin', 'high', 'from', 'from pin', //
  'pin a', 'pin1', 'pin 1', 'src pin #', 'src pin', 'source pin',
];
const List<String> _loHeaders = [
  'lo', 'lo pin', 'ls', 'ls pin', 'low', 'to', 'to pin', //
  'pin b', 'pin2', 'pin 2', 'dst pin #', 'dst pin', 'destination pin',
];
const List<String> _nameHeaders = ['net', 'net name', 'name', 'signal'];
const List<String> _cardHeaders = ['card', 'cards', 'hv card', 'stack'];

String _norm(String s) => s.trim().toLowerCase();

/// `Data?.value` on every cell type prints the way an operator typed or read
/// it (`IntCellValue`/`DoubleCellValue`/`TextCellValue` all override
/// `toString()`), so this is the one place that needs to know the cell
/// carries a `CellValue` at all.
String? _cellText(Data? cell) {
  final v = cell?.value;
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

int? _cellInt(Data? cell) {
  final v = cell?.value;
  if (v == null) return null;
  if (v is IntCellValue) return v.value;
  if (v is DoubleCellValue) return v.value.round();
  return int.tryParse(v.toString().trim());
}

/// Parses the first sheet of an `.xlsx` workbook into pin pairs. Throws
/// [NetlistFileFormatException] with a message an operator can act on — this
/// runs from a file-picker button, not a debugger, so "row 14: ..." beats a
/// stack trace.
ParsedNetlist parseNetlistWorkbook(Uint8List bytes, {required String fileName}) {
  try {
    return _parse(bytes, fileName);
  } on NetlistFileFormatException {
    rethrow;
  } on Object {
    // The excel package raises plain ArgumentError/FormatException for a
    // corrupted or non-.xlsx file (zip-open failure, missing workbook.xml,
    // ...) — none of that is a Dart-level bug for the operator to see.
    throw NetlistFileFormatException('$fileName is not a readable .xlsx file');
  }
}

ParsedNetlist _parse(Uint8List bytes, String fileName) {
  final book = Excel.decodeBytes(bytes);
  if (book.tables.isEmpty) {
    throw NetlistFileFormatException('$fileName has no sheets');
  }
  final sheet = book.tables[book.tables.keys.first]!;
  final rows = sheet.rows;
  if (rows.isEmpty) {
    throw NetlistFileFormatException("$fileName's first sheet is empty");
  }

  int? hiCol, loCol, nameCol, cardCol;
  final header = rows.first;
  for (var c = 0; c < header.length; c++) {
    final h = _cellText(header[c]);
    if (h == null) continue;
    final n = _norm(h);
    hiCol ??= _hiHeaders.contains(n) ? c : null;
    loCol ??= _loHeaders.contains(n) ? c : null;
    nameCol ??= _nameHeaders.contains(n) ? c : null;
    cardCol ??= _cardHeaders.contains(n) ? c : null;
  }
  if (hiCol == null || loCol == null) {
    final seen = header.map(_cellText).whereType<String>().join(', ');
    throw NetlistFileFormatException(
        "$fileName's header row needs a HI/HS pin column and a LO/LS pin "
        'column — found: ${seen.isEmpty ? "(no header text at all)" : seen}');
  }

  Data? at(List<Data?> row, int col) => col < row.length ? row[col] : null;

  int pinAt(List<Data?> row, int col, String label, int rowNum) {
    final n = _cellInt(at(row, col));
    if (n == null) {
      throw NetlistFileFormatException(
          'row $rowNum: the $label column is not a whole number');
    }
    if (n < 1 || n > kMaxNetlistPin) {
      throw NetlistFileFormatException(
          'row $rowNum: $label pin $n is outside 1..$kMaxNetlistPin');
    }
    return n;
  }

  final pairs = <ParsedNetPair>[];
  int? cards;
  for (var r = 1; r < rows.length; r++) {
    final row = rows[r];
    if (row.every((cell) => cell?.value == null)) continue; // blank row

    final hi = pinAt(row, hiCol, 'HI', r + 1);
    final lo = pinAt(row, loCol, 'LO', r + 1);
    if (hi == lo) {
      throw NetlistFileFormatException(
          'row ${r + 1}: HI and LO are both pin $hi');
    }
    final name = nameCol == null ? null : _cellText(at(row, nameCol));
    if (cardCol != null) {
      final n = _cellInt(at(row, cardCol));
      if (n != null) cards = cards == null ? n : math.max(cards, n);
    }
    pairs.add(ParsedNetPair(hi, lo, name));
  }

  if (pairs.isEmpty) {
    throw NetlistFileFormatException(
        '$fileName has a header row but no net rows under it');
  }

  final seenPairs = <String>{};
  for (final p in pairs) {
    if (!seenPairs.add('${p.hi}:${p.lo}')) {
      throw NetlistFileFormatException(
          'duplicate pin pair ${p.hi}-${p.lo} in $fileName');
    }
  }

  return ParsedNetlist(pairs, cards);
}
