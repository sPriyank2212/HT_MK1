/// Temporary verification: the generated .xlsx files must parse with the
/// same parser AppState.browseMtxNetlist uses.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ht_mk1_gui/htproto/netlist_file.dart';

void main() {
  final root = Directory.current.parent;
  final dir = Directory('${root.path}/test_netlists');

  test('generated .xlsx files exist', () {
    expect(dir.existsSync(), isTrue,
        reason: 'expected ${dir.path} to exist from gui_flutter/');
  });

  for (final f in dir.listSync().whereType<File>().where((f) => f.path.endsWith('.xlsx'))) {
    test('parses ${f.path.split(Platform.pathSeparator).last}', () {
      final bytes = f.readAsBytesSync();
      final parsed = parseNetlistWorkbook(bytes, fileName: f.path.split(Platform.pathSeparator).last);
      expect(parsed.pairs, isNotEmpty);
    });
  }
}
