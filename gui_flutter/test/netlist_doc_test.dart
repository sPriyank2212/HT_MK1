// The editable netlist model (lib/client/netlist_doc.dart): what it writes is
// what `parseNetlistWorkbook` reads back, and its validation enforces the same
// limits the loader and the firmware do.
import 'package:flutter_test/flutter_test.dart';
import 'package:ht_mk1_gui/client/netlist_doc.dart';
import 'package:ht_mk1_gui/htproto/netlist_file.dart';

NetlistDoc mtx() {
  final d = NetlistDoc.blank(NetlistKind.mtx)..harnessId = 'HRN-1';
  d.addRow();
  d.addRow();
  d.rows[0]
    ..[NCol.net] = 'PWR'
    ..[NCol.labelA] = 'PWR_24V'
    ..[NCol.labelB] = 'ENG_VCC'
    ..[NCol.colour] = 'RED'
    ..[NCol.awg] = '22'
    ..[NCol.length] = '1.5'
    ..[NCol.harnessNo] = 'H-1'
    ..[NCol.partA] = 'DB15-M'
    ..[NCol.partB] = 'DB15-F';
  return d;
}

void main() {
  group('continuity / resistance netlist', () {
    test('saves and loads back unchanged', () {
      final d = mtx();
      final p = parseNetlistWorkbook(d.toXlsx(), fileName: 'x.xlsx');
      expect(p.pairs.length, 2);
      expect(p.harnessId, 'HRN-1');
      final a = p.pairs[0];
      expect([a.hi, a.lo, a.name, a.srcLabel, a.dstLabel], [1, 1, 'PWR', 'PWR_24V', 'ENG_VCC']);
      final w = a.meta!;
      expect([w.source, w.destination, w.srcConnId, w.dstConnId],
          ['Side A', 'Side B', 'X1', 'X2']);
      expect([w.colour, w.awg, w.length, w.harnessNo, w.srcPart, w.dstPart],
          ['RED', '22', '1.5', 'H-1', 'DB15-M', 'DB15-F']);
    });

    test('"Add wire" continues the pin numbering and copies the connectors', () {
      final d = NetlistDoc.blank(NetlistKind.mtx)
        ..addRow()
        ..addRow()
        ..addRow();
      expect(d.rows.map((r) => r.hi), [1, 2, 3]);
      expect(d.rows.map((r) => r.lo), [1, 2, 3]);
      expect(d.rows[2][NCol.connA], 'X1');
      expect(d.rows[2][NCol.connB], 'X2');
    });

    test('straight-through fill and duplicate', () {
      final d = NetlistDoc.blank(NetlistKind.mtx)..fillStraightThrough(4, 10);
      expect(d.rows.map((r) => r.hi), [10, 11, 12, 13]);
      final copy = d.duplicate(d.rows[1]);
      expect(d.rows.length, 5);
      expect(d.rows.indexOf(copy), 2, reason: 'inserted right after the original');
      expect(copy.hi, 14, reason: 'a new pin, so the copy is a different wire');
      expect(d.isValid(), isTrue);
    });

    test('validation: empty, bad pins, duplicates, missing net name', () {
      expect(NetlistDoc.blank(NetlistKind.mtx).validate().single.message,
          contains('no wires'));

      final d = NetlistDoc.blank(NetlistKind.mtx)..fillStraightThrough(3, 1);
      d.rows[0][NCol.srcPin] = 'abc';
      d.rows[1][NCol.dstPin] = '300';
      d.rows[2][NCol.net] = '  ';
      final msgs = d.validate().map((i) => i.toString()).toList();
      expect(msgs, contains('Row 1: Src / Dst pins must be whole numbers.'));
      expect(msgs, contains('Row 2: Src / Dst pins must be 1..256.'));
      expect(msgs, contains('Row 3: Net name is empty.'));
      expect(d.isValid(), isFalse);

      final dup = NetlistDoc.blank(NetlistKind.mtx)..fillStraightThrough(2, 5);
      dup.rows[1][NCol.srcPin] = '5';
      dup.rows[1][NCol.dstPin] = '5';
      expect(dup.validate().map((i) => i.message), contains('Pin pair 5-5 repeats row 1.'));
    });

    test('a blank Conn ID is a warning, not an error', () {
      final d = NetlistDoc.blank(NetlistKind.mtx)..fillStraightThrough(1, 1);
      d.rows[0][NCol.connA] = '';
      final issues = d.validate();
      expect(issues.single.error, isFalse);
      expect(d.isValid(), isTrue);
    });

    test('an edited loaded netlist round-trips its rows', () {
      final p = parseNetlistWorkbook(mtx().toXlsx(), fileName: 'x.xlsx');
      final d = NetlistDoc.fromParsed(NetlistKind.mtx, p.pairs,
          name: 'x.xlsx', harnessId: p.harnessId);
      expect(d.rows[0][NCol.net], 'PWR');
      expect(d.rows[0][NCol.colour], 'RED');
      expect(d.harnessId, 'HRN-1');
      final again = parseNetlistWorkbook(d.toXlsx(), fileName: 'y.xlsx');
      expect([for (final r in again.pairs) (r.hi, r.lo)], [(1, 1), (2, 2)]);
    });
  });

  group('HV netlist', () {
    NetlistDoc hv() {
      final d = NetlistDoc.blank(NetlistKind.hv);
      d.fillStraightThrough(2, 1, netPrefix: 'HV_');
      d.fillStraightThrough(1, 70, netPrefix: 'HV_');
      return d;
    }

    test('card and relay come from the HS pin (64 per card)', () {
      expect(NetlistDoc.hvLocation(1), (1, 1));
      expect(NetlistDoc.hvLocation(64), (1, 64));
      expect(NetlistDoc.hvLocation(65), (2, 1));
      expect(NetlistDoc.hvLocation(70), (2, 6));
      expect(NetlistDoc.hvLocation(192), (3, 64));
    });

    test('loads back with HS = HI, LS = LO and the stack size from Card', () {
      final p = parseNetlistWorkbook(hv().toXlsx(), fileName: 'hv.xlsx');
      expect([for (final r in p.pairs) (r.hi, r.lo)], [(1, 1), (2, 2), (70, 70)]);
      expect(p.pairs.map((r) => r.name), ['HV_1', 'HV_2', 'HV_3']);
      expect(p.cards, 2, reason: 'pin 70 is on card 2, so the netlist needs 2 cards');
    });

    test('an HS pin beyond the fitted cards is an error (firmware fault F05)', () {
      final d = hv();
      expect(d.isValid(stack: 2), isTrue);
      final bad = d.validate(stack: 1).where((i) => i.error).toList();
      expect(bad.single.row, 3);
      expect(bad.single.message, contains('beyond the fitted HV cards'));
      expect(d.isValid(stack: 1), isFalse);
    });
  });
}
