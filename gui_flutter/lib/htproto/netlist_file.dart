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

/// One (hi, lo) pin pair, with the row's descriptive metadata carried through
/// for display only — the wire protocol's `NETLIST ADD` takes pins, never
/// names.
///
/// Rows that share a [name] are ONE net: a source pin with several rows is a
/// Y branch, several sources into one destination is the mirror image, and so
/// on — `AppState.rebuildNets` groups by it. [detail] is the free-text
/// `Connector Detail` column (`straight`, `crossed pin 5 -> 8`, `Y branch 1
/// of 3`, `inline splice`, ...); [kindFromDetail] reads the joint it declares.
class ParsedNetPair {
  final int hi;
  final int lo;
  final String? name;
  final String? srcLabel;
  final String? dstLabel;
  final String? detail;
  const ParsedNetPair(this.hi, this.lo,
      [this.name, this.srcLabel, this.dstLabel, this.detail]);
}

/// The joint a `Connector Detail` cell declares, or null when it says nothing
/// about one (`straight`, `crossed ...`, blank). Structure beats this: a net
/// with several rows is a Y/multi-drop whatever its detail says; the only
/// joint that CANNOT be seen from structure is an inline splice, which is
/// still one source to one destination, so that is what this exists for.
String? kindFromDetail(String? detail) {
  final d = (detail ?? '').toLowerCase();
  if (d.isEmpty) return null;
  if (d.contains('splice') || d.contains('inline') || d.contains('butt')) {
    return 'I';
  }
  if (d.contains('y branch') || d.contains('y-branch') || d.contains('y joint')) {
    return 'Y';
  }
  return null;
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

  /// 'dsub' | 'circ' | 'rect' | 'term' | 'mod' — see [_guessShape].
  final String shapeGuess;
  final String partNumber;

  /// 'src' | 'dst' — which END of the harness this connector sits on: `Conn
  /// ID` (Side-A, the HI pins) or `Conn ID B` (Side-B, the LO pins).
  ///
  /// Every connector is guessed per end, so a designator used on both ends —
  /// `example_netlist27072026.xlsx`'s `DB15-1` is the male plug at one end and
  /// the female socket at the other — yields TWO connectors, one per end, not
  /// one connector with its pin range merged. (It used to be merged, which
  /// drew every wire of a mated pair as a zero-length line on a single
  /// connector.) HI and LO are separate 1..256 address spaces on the matrix
  /// card, so each end's pins are numbered on their own.
  final String side;

  /// The pin count the part number itself states (`DB37-F-37S` -> 37,
  /// `MS3116F14-19S` -> 19), or null when it states none. Used only as a
  /// sanity check on [pins].
  final int? partPins;

  /// True when more pins were observed on this connector than its part number
  /// has — a Conn ID reused for two different connectors, or a connector
  /// whose first pins are unwired so the block boundaries came out shifted.
  /// The layout is still built, but the operator is warned.
  bool get exceedsPart => partPins != null && pins > partPins!;

  const GuessedConnector({
    required this.id,
    required this.pins,
    required this.shapeGuess,
    required this.partNumber,
    required this.side,
    this.partPins,
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

// Per-pin signal labels and the free-text wire detail (`Y branch 1 of 3`,
// `crossed pin 5 -> 8`, `inline splice`) - display only.
const List<String> _srcLabelHeaders = [
  'src pin label', 'source pin label', 'src label', 'pin label',
];
const List<String> _dstLabelHeaders = [
  'dst pin label', 'destination pin label', 'dst label',
];
const List<String> _detailHeaders = [
  'connector detail', 'wire detail', 'detail', 'joint',
];

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
  int? srcLabelCol, dstLabelCol, detailCol;
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
    srcLabelCol ??= _srcLabelHeaders.contains(n) ? c : null;
    dstLabelCol ??= _dstLabelHeaders.contains(n) ? c : null;
    detailCol ??= _detailHeaders.contains(n) ? c : null;
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
  // Each harness END is observed on its own: `Conn ID` with the Src (HI) pins,
  // `Conn ID B` with the Dst (LO) pins. A designator that appears at both ends
  // is two connectors (see GuessedConnector.side).
  final srcObs = <String, _ConnObs>{};
  final dstObs = <String, _ConnObs>{};
  void observe(Map<String, _ConnObs> into, int? col, int? partCol,
      List<Data?> row, int pin) {
    if (col == null) return;
    final id = _cellText(at(row, col));
    if (id == null) return;
    final o = into.putIfAbsent(id, _ConnObs.new);
    o.partNumber ??= partCol == null ? null : _cellText(at(row, partCol));
    o.min = o.min == null ? pin : math.min(o.min!, pin);
    o.max = o.max == null ? pin : math.max(o.max!, pin);
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
    observe(srcObs, connACol, partACol, row, hi);
    observe(dstObs, connBCol, partBCol, row, lo);
    pairs.add(ParsedNetPair(
      hi,
      lo,
      name,
      srcLabelCol == null ? null : _cellText(at(row, srcLabelCol)),
      dstLabelCol == null ? null : _cellText(at(row, dstLabelCol)),
      detailCol == null ? null : _cellText(at(row, detailCol)),
    ));
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

  return ParsedNetlist(pairs, cards, _guessFixture(srcObs, dstObs));
}

/// Pin range seen for one `Conn ID` on one harness end while scanning rows.
class _ConnObs {
  int? min, max;
  String? partNumber;
}

/// Turns per-connector pin observations into an ordered connector list: every
/// Side-A (`src`) connector, then every Side-B (`dst`) connector.
///
/// Block boundaries are inferred, not measured. On each end, connectors are
/// sorted by the lowest pin seen on them; a connector's block starts right
/// after the previous one's ends (the first starts at pin 1) and runs to just
/// before the next connector's lowest pin (the last runs to its own highest
/// observed pin). That is exactly right when the file numbers pins
/// sequentially by connector — true of the real `required_format` sample —
/// but it is a guess from what happens to be wired in this file, not a real
/// connector pin count, whenever a connector's trailing pins are entirely
/// unused. The operator confirms or edits it before it becomes the active
/// fixture (`AppState`).
List<GuessedConnector>? _guessFixture(
    Map<String, _ConnObs> srcObs, Map<String, _ConnObs> dstObs) {
  if (srcObs.isEmpty && dstObs.isEmpty) return null;

  List<GuessedConnector> end(Map<String, _ConnObs> obs, String side) {
    final ids = obs.keys.toList()
      ..sort((a, b) => obs[a]!.min!.compareTo(obs[b]!.min!));
    final out = <GuessedConnector>[];
    var start = 1; // first pin of this connector's block
    for (var i = 0; i < ids.length; i++) {
      final o = obs[ids[i]]!;
      final last = i + 1 == ids.length;
      final blockEnd = last ? o.max! : obs[ids[i + 1]]!.min! - 1;
      final pins = math.max(o.max!, blockEnd) - start + 1;
      out.add(GuessedConnector(
        id: ids[i],
        pins: pins,
        shapeGuess: _guessShape(o.partNumber),
        partNumber: o.partNumber ?? '',
        side: side,
        partPins: _pinsFromPart(o.partNumber),
      ));
      start += pins;
    }
    return out;
  }

  return [...end(srcObs, 'src'), ...end(dstObs, 'dst')];
}

/// The pin count a part number states: a D-sub's `DB<n>` or a trailing
/// `<n>P` / `<n>S` (plug / socket) — `DB9-M-9P` -> 9, `MS3116F14-19S` -> 19.
/// Null when it states none (most terminal blocks, CPC, Molex...).
int? _pinsFromPart(String? partNumber) {
  final p = (partNumber ?? '').toUpperCase();
  final tail = RegExp(r'(\d{1,3})[PS]$').firstMatch(p);
  if (tail != null) return int.parse(tail.group(1)!);
  final db = RegExp(r'DB(\d{1,2})').firstMatch(p);
  if (db != null) return int.parse(db.group(1)!);
  return null;
}

/// 'dsub' | 'circ' | 'rect' | 'term' | 'mod' from a mating-connector
/// part-number string — a keyword guess, not a lookup against a real parts
/// database. The operator confirms it (and can change it) before it is used.
///
///  * `dsub` — D-subminiature, including high-density (`DB15`, `DE-9`,
///    `DA-15`, `HD-44`, `D-SUB`)
///  * `circ` — circular: MIL-DTL-38999 / MS3xxx, M8/M12/M16 sensor plugs,
///    Amphenol round
///  * `term` — terminal blocks / screw terminals / Phoenix / WAGO
///  * `mod`  — modular and network jacks: RJ45, RJ11, USB, Ethernet
///  * `rect` — everything else (TE CPC, Molex, Deutsch, JST, Amphenol
///    rectangular...) - the default
String _guessShape(String? partNumber) {
  final p = (partNumber ?? '').toUpperCase();
  if (p.contains('TERMINAL') ||
      p.contains('SCREW') ||
      p.contains('PHOENIX') ||
      p.contains('WAGO') ||
      p.contains('MSTB') ||
      p.contains('DINKLE') ||
      p.contains('TBLOCK') ||
      p.startsWith('TB-') ||
      p.startsWith('TB_')) {
    return 'term';
  }
  if (p.contains('RJ45') ||
      p.contains('RJ-45') ||
      p.contains('RJ11') ||
      p.contains('RJ-11') ||
      p.contains('RJ12') ||
      p.contains('MODULAR') ||
      p.contains('ETHERNET') ||
      p.contains('USB') ||
      p.contains('8P8C')) {
    return 'mod';
  }
  if (p.contains('DSUB') ||
      p.contains('D-SUB') ||
      p.contains('DB') ||
      RegExp(r'(^|[^A-Z])(D[A-E]|HD)-?\d').hasMatch(p)) {
    return 'dsub';
  }
  if (p.contains('RECT') ||
      p.contains('CPC') ||
      p.contains('MOLEX') ||
      p.contains('DEUTSCH') ||
      p.contains('JST')) {
    return 'rect';
  }
  if (p.contains('CIRC') ||
      p.contains('MS3') ||
      p.contains('MS27') ||
      p.contains('38999') ||
      p.contains('MIL-DTL') ||
      RegExp(r'(^|[^A-Z0-9])M(8|12|16|23|27)([^0-9]|$)').hasMatch(p) ||
      p.contains('AMPHENOL')) {
    return 'circ';
  }
  return 'rect';
}
