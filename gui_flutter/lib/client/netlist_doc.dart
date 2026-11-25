/// An editable netlist for the client app's netlist editor.
///
/// Two kinds, because the instrument has two:
///
/// * [NetlistKind.mtx] — the **continuity / resistance** netlist, on the
///   Matrix connector (J-MTX). One row per wire: Side-A pin → Side-B pin, with
///   the client's descriptive columns (Source, Conn ID, Part Number, pin
///   labels, Destination, Colour, AWG, Length, Harness No).
/// * [NetlistKind.hv] — the **HV insulation** netlist, on the HV connector
///   (J-HV). One row per wire: the **HS pin** (the HV card relay that injects)
///   and the **LS pin** (its return). HS pin 1..64 is card 1, 65..128 card 2,
///   and so on, so the card and relay are shown for every row.
///
/// [toXlsx] writes exactly the column names `htproto/netlist_file.dart` reads,
/// so a saved file loads back unchanged — and "Apply" loads these same bytes.
library;

import 'dart:typed_data';

import '../htproto/netlist_file.dart';
import '../htproto/netlist_formats.dart';

enum NetlistKind { mtx, hv }

/// Relays per HV card (`HV_PINS_PER_SIDE` in the firmware).
const int kHvPinsPerCard = 64;

/// The editable columns, in the order they are shown and saved.
enum NCol {
  net('Net', 150),
  source('Source', 90),
  connA('Conn ID', 80),
  partA('Part Number', 110),
  labelA('Src Pin Label', 120),
  srcPin('Src Pin #', 80),
  dstPin('Dst Pin #', 80),
  labelB('Dst Pin Label', 120),
  connB('Conn ID B', 80),
  partB('Part Number B', 110),
  destination('Destination', 100),
  colour('Colour', 80),
  awg('AWG', 60),
  length('Length', 70),
  harnessNo('Harness No', 90),
  detail('Connector Detail', 140),
  // HV only
  hsPin('HS Pin', 80),
  lsPin('LS Pin', 80);

  final String title;
  final double width;
  const NCol(this.title, this.width);
}

List<NCol> columnsOf(NetlistKind k) => k == NetlistKind.mtx
    ? const [
        NCol.net, NCol.source, NCol.connA, NCol.partA, NCol.labelA,
        NCol.srcPin, NCol.dstPin, NCol.labelB, NCol.connB, NCol.partB,
        NCol.destination, NCol.colour, NCol.awg, NCol.length, NCol.harnessNo,
        NCol.detail, //
      ]
    : const [NCol.net, NCol.hsPin, NCol.lsPin, NCol.detail];

class NetRowDraft {
  static int _next = 0;
  final int id = _next++;
  final Map<NCol, String> v;

  NetRowDraft([Map<NCol, String>? init]) : v = {...?init};

  String operator [](NCol c) => v[c] ?? '';
  void operator []=(NCol c, String s) => v[c] = s;

  /// The row's pins, for either kind (HS/LS share the Src/Dst slots).
  int? get hi => int.tryParse((this[NCol.srcPin].isNotEmpty
          ? this[NCol.srcPin]
          : this[NCol.hsPin])
      .trim());
  int? get lo => int.tryParse((this[NCol.dstPin].isNotEmpty
          ? this[NCol.dstPin]
          : this[NCol.lsPin])
      .trim());
}

class NetlistIssue {
  /// 1-based row, or null for a whole-file issue.
  final int? row;
  final String message;
  final bool error;
  const NetlistIssue(this.row, this.message, {this.error = true});

  @override
  String toString() => row == null ? message : 'Row $row: $message';
}

class NetlistDoc {
  final NetlistKind kind;
  String name;
  String harnessId;
  final List<NetRowDraft> rows;

  NetlistDoc(this.kind,
      {this.name = '', this.harnessId = '', List<NetRowDraft>? rows})
      : rows = rows ?? [];

  /// A blank document of [kind].
  factory NetlistDoc.blank(NetlistKind kind) => NetlistDoc(kind,
      name: kind == NetlistKind.mtx ? 'new_netlist.xlsx' : 'new_hv_netlist.xlsx');

  /// A document holding the rows of an already-loaded netlist.
  factory NetlistDoc.fromParsed(NetlistKind kind, List<ParsedNetPair> pairs,
      {String name = '', String? harnessId}) {
    final d = NetlistDoc(kind, name: name, harnessId: harnessId ?? '');
    for (final p in pairs) {
      final w = p.meta;
      final r = NetRowDraft();
      r[NCol.net] = p.name ?? '';
      r[NCol.detail] = p.detail ?? '';
      if (kind == NetlistKind.mtx) {
        r[NCol.source] = w?.source ?? '';
        r[NCol.connA] = w?.srcConnId ?? '';
        r[NCol.partA] = w?.srcPart ?? '';
        r[NCol.labelA] = p.srcLabel ?? '';
        r[NCol.srcPin] = '${p.hi}';
        r[NCol.dstPin] = '${p.lo}';
        r[NCol.labelB] = p.dstLabel ?? '';
        r[NCol.connB] = w?.dstConnId ?? '';
        r[NCol.partB] = w?.dstPart ?? '';
        r[NCol.destination] = w?.destination ?? '';
        r[NCol.colour] = w?.colour ?? '';
        r[NCol.awg] = w?.awg ?? '';
        r[NCol.length] = w?.length ?? '';
        r[NCol.harnessNo] = w?.harnessNo ?? '';
      } else {
        r[NCol.hsPin] = '${p.hi}';
        r[NCol.lsPin] = '${p.lo}';
      }
      d.rows.add(r);
    }
    return d;
  }

  List<NCol> get columns => columnsOf(kind);

  /// The HV card (1-based) and relay (1..64) an HS pin lands on.
  static (int card, int relay) hvLocation(int hs) =>
      ((hs - 1) ~/ kHvPinsPerCard + 1, (hs - 1) % kHvPinsPerCard + 1);

  // ---- editing -----------------------------------------------------------

  /// Appends one row. For continuity the pins default to the next free number
  /// after the last row, so "Add wire" repeatedly makes a straight-through
  /// harness without typing.
  NetRowDraft addRow({
    String connA = 'X1',
    String connB = 'X2',
    String source = 'Side A',
    String destination = 'Side B',
  }) {
    final n = rows.length + 1;
    final last = rows.isEmpty ? null : rows.last.hi;
    final nextPin = '${(last ?? 0) + 1}';
    final r = NetRowDraft();
    r[NCol.net] = 'NET_$n';
    if (kind == NetlistKind.mtx) {
      r[NCol.source] = rows.isEmpty ? source : rows.last[NCol.source];
      r[NCol.connA] = rows.isEmpty ? connA : rows.last[NCol.connA];
      r[NCol.connB] = rows.isEmpty ? connB : rows.last[NCol.connB];
      r[NCol.destination] =
          rows.isEmpty ? destination : rows.last[NCol.destination];
      r[NCol.partA] = rows.isEmpty ? '' : rows.last[NCol.partA];
      r[NCol.partB] = rows.isEmpty ? '' : rows.last[NCol.partB];
      r[NCol.srcPin] = nextPin;
      r[NCol.dstPin] = nextPin;
    } else {
      r[NCol.hsPin] = nextPin;
      r[NCol.lsPin] = nextPin;
    }
    rows.add(r);
    return r;
  }

  /// Appends [count] straight-through wires (pin N to pin N) starting at
  /// [startPin].
  void fillStraightThrough(int count, int startPin,
      {String netPrefix = 'NET_',
      String connA = 'X1',
      String connB = 'X2',
      String source = 'Side A',
      String destination = 'Side B'}) {
    for (var i = 0; i < count; i++) {
      final pin = '${startPin + i}';
      final r = NetRowDraft();
      r[NCol.net] = '$netPrefix${rows.length + 1}';
      if (kind == NetlistKind.mtx) {
        r[NCol.source] = source;
        r[NCol.destination] = destination;
        r[NCol.connA] = connA;
        r[NCol.connB] = connB;
        r[NCol.srcPin] = pin;
        r[NCol.dstPin] = pin;
      } else {
        r[NCol.hsPin] = pin;
        r[NCol.lsPin] = pin;
      }
      rows.add(r);
    }
  }

  NetRowDraft duplicate(NetRowDraft src) {
    final r = NetRowDraft({...src.v});
    // the next free pin on both ends, so the copy is a different wire
    final hi = rows.map((x) => x.hi ?? 0).fold<int>(0, (m, p) => p > m ? p : m);
    if (kind == NetlistKind.mtx) {
      r[NCol.srcPin] = '${hi + 1}';
      r[NCol.dstPin] = '${hi + 1}';
    } else {
      r[NCol.hsPin] = '${hi + 1}';
      r[NCol.lsPin] = '${hi + 1}';
    }
    rows.insert(rows.indexOf(src) + 1, r);
    return r;
  }

  // ---- validation --------------------------------------------------------

  /// Everything wrong with the document, errors first. [stack] is the number
  /// of HV cards fitted (HV netlists only).
  List<NetlistIssue> validate({int stack = 3}) {
    final out = <NetlistIssue>[];
    if (rows.isEmpty) {
      out.add(const NetlistIssue(null, 'The netlist has no wires.'));
      return out;
    }
    final seen = <String, int>{};
    final pinLabel = kind == NetlistKind.mtx ? 'Src / Dst' : 'HS / LS';
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final n = i + 1;
      if (r[NCol.net].trim().isEmpty) {
        out.add(NetlistIssue(n, 'Net name is empty.'));
      }
      final hi = r.hi, lo = r.lo;
      if (hi == null || lo == null) {
        out.add(NetlistIssue(n, '$pinLabel pins must be whole numbers.'));
        continue;
      }
      if (hi < 1 || hi > kMaxNetlistPin || lo < 1 || lo > kMaxNetlistPin) {
        out.add(NetlistIssue(n, '$pinLabel pins must be 1..$kMaxNetlistPin.'));
        continue;
      }
      final key = '$hi:$lo';
      final dup = seen[key];
      if (dup != null) {
        out.add(NetlistIssue(n, 'Pin pair $hi-$lo repeats row $dup.'));
      } else {
        seen[key] = n;
      }
      if (kind == NetlistKind.hv && hi > stack * kHvPinsPerCard) {
        out.add(NetlistIssue(
            n,
            'HS pin $hi is beyond the fitted HV cards '
            '($stack card${stack == 1 ? '' : 's'} = ${stack * kHvPinsPerCard} pins).'));
      }
      if (kind == NetlistKind.mtx) {
        if (r[NCol.connA].trim().isEmpty || r[NCol.connB].trim().isEmpty) {
          out.add(NetlistIssue(
              n,
              'Conn ID is empty — the Connector View and reports will not '
              'name this wire\'s connectors.',
              error: false));
        }
      }
    }
    out.sort((a, b) => (b.error ? 1 : 0) - (a.error ? 1 : 0));
    return out;
  }

  bool isValid({int stack = 3}) => !validate(stack: stack).any((i) => i.error);

  // ---- save --------------------------------------------------------------

  /// The header row and one row per wire, as the values a spreadsheet holds:
  /// numbers for pins/AWG/length, text for the rest. What every export format
  /// (`.xlsx`, `.xls`, `.csv`) is written from, and what the loader reads back.
  List<List<Object?>> toRows() {
    Object? num(String s) {
      final t = s.trim();
      return int.tryParse(t) ?? double.tryParse(t) ?? s;
    }

    final out = <List<Object?>>[];
    if (kind == NetlistKind.mtx) {
      out.add(const [
        'Net', 'Source', 'Conn ID', 'Part Number', 'Src Pin Label',
        'Src Pin #', 'Dst Pin #', 'Dst Pin Label', 'Conn ID B',
        'Part Number B', 'Destination', 'Colour', 'AWG', 'Length',
        'Harness No', 'Connector Detail', 'Harness ID', //
      ]);
      for (final r in rows) {
        out.add([
          r[NCol.net],
          r[NCol.source],
          r[NCol.connA],
          r[NCol.partA],
          r[NCol.labelA],
          num(r[NCol.srcPin]),
          num(r[NCol.dstPin]),
          r[NCol.labelB],
          r[NCol.connB],
          r[NCol.partB],
          r[NCol.destination],
          r[NCol.colour],
          num(r[NCol.awg]),
          num(r[NCol.length]),
          r[NCol.harnessNo],
          r[NCol.detail],
          harnessId,
        ]);
      }
    } else {
      out.add(const [
        'Net', 'HS Pin', 'LS Pin', 'Card', 'Connector Detail', 'Harness ID', //
      ]);
      for (final r in rows) {
        final hs = r.hi;
        out.add([
          r[NCol.net],
          num(r[NCol.hsPin]),
          num(r[NCol.lsPin]),
          // the card the HS pin lands on; the loader takes the largest as the
          // stack size the netlist was made for
          hs == null ? '' : hvLocation(hs).$1,
          r[NCol.detail],
          harnessId,
        ]);
      }
    }
    return out;
  }

  /// The workbook `parseNetlistWorkbook` reads back.
  Uint8List toXlsx() => encodeSheet(toRows(), 'xlsx');

  /// The same rows in the format [ext] (`xlsx`, `xls` or `csv`).
  Uint8List toBytes(String ext) => encodeSheet(toRows(), ext);
}
