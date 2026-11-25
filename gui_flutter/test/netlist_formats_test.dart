// CSV / XLS / XLSX netlists: every format a netlist is exported in loads back
// to the same pairs, and a binary .xls is refused with a message.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ht_mk1_gui/client/netlist_doc.dart';
import 'package:ht_mk1_gui/htproto/netlist_file.dart';
import 'package:ht_mk1_gui/htproto/netlist_formats.dart';

ParsedNetlist _load(String file) => parseNetlistWorkbook(
    File('../test_netlists/$file').readAsBytesSync(),
    fileName: file);

List<(int, int)> _pairs(ParsedNetlist p) =>
    [for (final x in p.pairs) (x.hi, x.lo)];

void main() {
  for (final (file, kind) in [
    ('HT_MK1_continuity_12net.xlsx', NetlistKind.mtx),
    ('HT_MK1_HV_insulation_12net.xlsx', NetlistKind.hv),
  ]) {
    for (final ext in kNetlistExtensions) {
      test('$file exported as .$ext loads back unchanged', () {
        final src = _load(file);
        final doc = NetlistDoc.fromParsed(kind, src.pairs, name: file);
        final bytes = doc.toBytes(ext);
        final back = parseNetlistWorkbook(bytes, fileName: 'x.$ext');
        expect(_pairs(back), _pairs(src));
        expect(back.pairs.map((p) => p.name), src.pairs.map((p) => p.name));
      });
    }
  }

  test('csv with a BOM, quotes, CRLF and a semicolon delimiter loads', () {
    const text = '\uFEFFNet;HS Pin;LS Pin\r\n"A;1";1;2\r\nB;3;4\r\n';
    final p = parseNetlistWorkbook(Uint8List.fromList(utf8.encode(text)),
        fileName: 'hv.csv');
    expect(_pairs(p), [(1, 2), (3, 4)]);
    expect(p.pairs.first.name, 'A;1');
  });

  test('an .xlsx renamed .xls is read by its content', () {
    final bytes = File('../test_netlists/HT_MK1_continuity_12net.xlsx')
        .readAsBytesSync();
    expect(_pairs(parseNetlistWorkbook(bytes, fileName: 'renamed.xls')).length,
        12);
  });

  test('a binary Excel 97-2003 .xls is refused with an explanation', () {
    final biff = Uint8List.fromList(
        [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, 0, 0, 0, 0]);
    expect(
        () => parseNetlistWorkbook(biff, fileName: 'old.xls'),
        throwsA(isA<NetlistFileFormatException>()
            .having((e) => e.message, 'message', contains('save it as .xlsx'))));
  });

  test('extension helpers', () {
    expect(extensionOf(r'C:\a b\Net.LIST.CSV'), 'csv');
    expect(withNetlistExtension('x'), 'x.xlsx');
    expect(withNetlistExtension('x.xls'), 'x.xls');
    expect(withNetlistExtension('x.txt'), 'x.txt.xlsx');
  });
}
