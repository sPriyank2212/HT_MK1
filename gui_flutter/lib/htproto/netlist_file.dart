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

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
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

  /// The connector layout guessed from `Conn ID`/`Part Number` columns, if
  /// the sheet has them — null when it doesn't (e.g. the minimal `NET,
  /// HI, LO` shape), same as [cards]. Ordered by inferred pin position
  /// (lowest first). A guess, not a measurement: `AppState` presents it for
  /// operator confirmation before it becomes the active fixture.
  final List<GuessedConnector>? fixture;

  const ParsedNetlist(this.pairs, this.cards, [this.fixture]);
}

/// One connector as guessed from a netlist file's `Conn ID`/`Part Number`
/// columns. Deliberately independent of `design/model.dart`'s `ConnType` —
/// this file stays outside the UI/design layer, same as the rest of
/// `htproto/`; `AppState` (which already imports both) maps [shapeGuess] to
/// a real `ConnType` when the operator confirms.
class GuessedConnector {
  final String id;
  final int pins;

  /// 'dsub' | 'circ' | 'rect' — see [_guessShape].
  final String shapeGuess;
  final String partNumber;

  const GuessedConnector({
    required this.id,
    required this.pins,
    required this.shapeGuess,
    required this.partNumber,
  });
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

// Connector-layout columns — all optional. `required_format`'s real sample
// (example_netlist27072026.xlsx) has exactly these header names.
const List<String> _connAHeaders = ['conn id', 'connector', 'conn'];
const List<String> _partAHeaders = ['part number', 'part #', 'part no'];
const List<String> _connBHeaders = ['conn id b', 'connector b', 'conn b'];
const List<String> _partBHeaders = ['part number b', 'part # b', 'part no b'];

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

/// Rewrites `Target="/xl/...'` relationship references to the relative form
/// (`Target="..."`) the `excel` package's parser assumes.
///
/// Both forms are legal OOXML (ECMA-376 package-relationship resolution
/// allows a target relative to either the part's own folder or the package
/// root), but `excel` 4.0.6 only handles the relative form — it resolves a
/// worksheet's target by blindly prepending `xl/`, so an already-absolute
/// `/xl/worksheets/sheet1.xml` target becomes the non-existent path
/// `xl//xl/worksheets/sheet1.xml` and the lookup fails with a bare "Null
/// check operator used on a null value" instead of a catchable exception.
/// **openpyxl's default writer always emits the absolute form** (confirmed
/// by generating a fresh file with a stock `openpyxl.Workbook()` and
/// inspecting `xl/_rels/workbook.xml.rels`) — openpyxl is a very common way
/// for a design tool to produce a netlist spreadsheet, so this is a real
/// compatibility gap for operator-supplied files, not a one-off malformed
/// example. Patched here rather than in the dependency.
Uint8List _normalizeRelationshipTargets(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  var changed = false;
  for (final file in List<ArchiveFile>.from(archive.files)) {
    if (!file.isFile || !file.name.endsWith('.rels')) continue;
    final text = utf8.decode(file.content as List<int>);
    if (!text.contains('Target="/xl/')) continue;
    final fixed = text.replaceAll('Target="/xl/', 'Target="');
    final fixedBytes = utf8.encode(fixed);
    archive.addFile(ArchiveFile(file.name, fixedBytes.length, fixedBytes));
    changed = true;
  }
  if (!changed) return bytes;
  final encoded = ZipEncoder().encode(archive);
  return encoded == null ? bytes : Uint8List.fromList(encoded);
}

/// Parses the first sheet of an `.xlsx` workbook into pin pairs. Throws
/// [NetlistFileFormatException] with a message an operator can act on — this
/// runs from a file-picker button, not a debugger, so "row 14: ..." beats a
/// stack trace.
ParsedNetlist parseNetlistWorkbook(Uint8List bytes, {required String fileName}) {
  try {
    return _parse(_normalizeRelationshipTargets(bytes), fileName);
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
  int? connACol, partACol, connBCol, partBCol;
  final header = rows.first;
  for (var c = 0; c < header.length; c++) {
    final h = _cellText(header[c]);
    if (h == null) continue;
    final n = _norm(h);
    hiCol ??= _hiHeaders.contains(n) ? c : null;
    loCol ??= _loHeaders.contains(n) ? c : null;
    nameCol ??= _nameHeaders.contains(n) ? c : null;
    cardCol ??= _cardHeaders.contains(n) ? c : null;
    // Checked before _connAHeaders: "conn id b" must not also match "conn"
    // (a substring of the A-side alias list's normalised forms would not
    // collide here since matching is exact, not substring, but B is still
    // resolved first for clarity).
    connBCol ??= _connBHeaders.contains(n) ? c : null;
    partBCol ??= _partBHeaders.contains(n) ? c : null;
    connACol ??= _connAHeaders.contains(n) ? c : null;
    partACol ??= _partAHeaders.contains(n) ? c : null;
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
  final connObs = <String, _ConnObs>{};
  void observe(int? col, int? partCol, List<Data?> row, int pin) {
    if (col == null) return;
    final id = _cellText(at(row, col));
    if (id == null) return;
    final partNumber = partCol == null ? null : _cellText(at(row, partCol));
    final o = connObs[id];
    if (o == null) {
      connObs[id] = _ConnObs(pin, pin, partNumber);
    } else {
      if (pin < o.minPin) o.minPin = pin;
      if (pin > o.maxPin) o.maxPin = pin;
      o.partNumber ??= partNumber;
    }
  }

  for (var r = 1; r < rows.length; r++) {
    final row = rows[r];
    if (row.every((cell) => cell?.value == null)) continue; // blank row

    // HI and LO are separate physical mux banks (matrix_card.h: hi_en[]/
    // hi_sns[] vs lo_en[]/lo_sns[], different chips entirely), each with its
    // own independent 1..256 addressing - not a shared flat space. "HI pin 5
    // -> LO pin 5" is an ordinary straight-through wire (same label on both
    // connector halves), not a self-connection, so HI == LO is not rejected
    // here. (Previously it was - see PROJECT_LOG.md GUI-08/CL-41.)
    final hi = pinAt(row, hiCol, 'HI', r + 1);
    final lo = pinAt(row, loCol, 'LO', r + 1);
    final name = nameCol == null ? null : _cellText(at(row, nameCol));
    if (cardCol != null) {
      final n = _cellInt(at(row, cardCol));
      if (n != null) cards = cards == null ? n : math.max(cards, n);
    }
    observe(connACol, partACol, row, hi);
    observe(connBCol, partBCol, row, lo);
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

  return ParsedNetlist(pairs, cards, _guessFixture(connObs));
}

/// Running (min pin, max pin, first-seen part number) for one `Conn ID`
/// seen while scanning rows — [_guessFixture] turns this into a
/// [GuessedConnector] once every row has been visited.
class _ConnObs {
  int minPin;
  int maxPin;
  String? partNumber;
  _ConnObs(this.minPin, this.maxPin, this.partNumber);
}

/// Turns per-connector pin observations into an ordered connector list.
/// Block boundaries are inferred, not measured: connectors are sorted by
/// the lowest pin number seen on each, and each one's pin count runs from
/// its own lowest observed pin to just before the next connector's lowest
/// (the last connector runs to its own highest observed pin). This is
/// exactly right when the file's numbering is already sequential by
/// connector, confirmed true of the real `required_format` sample
/// (2026-08-14, GUI-08/CL-41) — but it is a guess from what happens to be
/// wired in this file, not a real connector pin count, whenever a
/// connector's trailing pins are entirely unused. The operator confirms/
/// edits before this becomes the active fixture (`AppState`).
List<GuessedConnector>? _guessFixture(Map<String, _ConnObs> connObs) {
  if (connObs.isEmpty) return null;
  final ids = connObs.keys.toList()
    ..sort((a, b) => connObs[a]!.minPin.compareTo(connObs[b]!.minPin));
  final out = <GuessedConnector>[];
  for (var i = 0; i < ids.length; i++) {
    final o = connObs[ids[i]]!;
    final blockEnd =
        i + 1 < ids.length ? connObs[ids[i + 1]]!.minPin - 1 : o.maxPin;
    final pins = math.max(o.maxPin, blockEnd) - o.minPin + 1;
    out.add(GuessedConnector(
      id: ids[i],
      pins: pins,
      shapeGuess: _guessShape(o.partNumber),
      partNumber: o.partNumber ?? '',
    ));
  }
  return out;
}

/// 'dsub' | 'circ' | 'rect' from a mating-connector part-number string —
/// a keyword guess, not a lookup against a real parts database.
String _guessShape(String? partNumber) {
  final p = (partNumber ?? '').toUpperCase();
  if (p.contains('DSUB') || p.contains('D-SUB') || p.contains('DB')) {
    return 'dsub';
  }
  if (p.contains('CIRC') ||
      p.contains('MS3') ||
      p.contains('38999') ||
      p.contains('AMPHENOL')) {
    return 'circ';
  }
  return 'rect';
}
