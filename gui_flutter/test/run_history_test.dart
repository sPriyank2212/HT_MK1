/// `RunHistoryStore`/`RunHistoryEntry` regression tests (GUI-05: run history
/// is stored on the GUI host, not the instrument). Covers the in-memory
/// default (what every other AppState test relies on to avoid touching
/// disk), real persistence across a fresh store pointed at the same
/// directory, append order, and tolerance of a corrupt line.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ht_mk1_gui/app/run_history.dart';

void main() {
  group('RunHistoryStore (in-memory)', () {
    test('starts empty and accumulates appended entries', () {
      final store = RunHistoryStore();
      expect(store.load(), isEmpty);

      store.append(RunHistoryEntry(
        timestamp: DateTime(2026, 8, 12, 10, 0),
        kind: 'cont',
        mtxNetlist: 'AV-880_RevC',
        hvNetlist: null,
        passed: 5,
        failed: 0,
      ));
      final loaded = store.load();
      expect(loaded, hasLength(1));
      expect(loaded.single.kind, 'cont');
      expect(loaded.single.pass, isTrue);
    });

    test('never touches disk', () {
      // No Directory given -> _file is null -> append/load must not throw
      // even where no writable location exists at all.
      final store = RunHistoryStore();
      store.append(RunHistoryEntry(
        timestamp: DateTime.now(),
        kind: 'res',
        mtxNetlist: null,
        hvNetlist: null,
        passed: 0,
        failed: 1,
      ));
      expect(store.load().single.pass, isFalse);
    });
  });

  group('RunHistoryStore (on disk)', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('ht_mk1_history_test_');
    });

    tearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('persists across a fresh store pointed at the same directory', () {
      final writer = RunHistoryStore(dir);
      writer.append(RunHistoryEntry(
        timestamp: DateTime(2026, 8, 12, 9, 30),
        kind: 'insul',
        mtxNetlist: 'AV-880_RevC',
        hvNetlist: 'AV-880_HV_3card',
        passed: 63,
        failed: 1,
      ));
      writer.append(RunHistoryEntry(
        timestamp: DateTime(2026, 8, 12, 9, 45),
        kind: 'cont',
        mtxNetlist: 'AV-880_RevC',
        hvNetlist: null,
        passed: 8,
        failed: 0,
      ));

      // A second store instance, same directory, nothing shared but the
      // file on disk - this is what "reopen the app" looks like.
      final reader = RunHistoryStore(dir);
      final loaded = reader.load();
      expect(loaded, hasLength(2));
      expect(loaded[0].kind, 'insul');
      expect(loaded[0].passed, 63);
      expect(loaded[0].failed, 1);
      expect(loaded[0].pass, isFalse);
      expect(loaded[1].kind, 'cont');
      expect(loaded[1].pass, isTrue);
      expect(loaded[1].mtxNetlist, 'AV-880_RevC');
      expect(loaded[1].hvNetlist, isNull);
    });

    test('one corrupt line does not hide the rest', () {
      final f = File('${dir.path}${Platform.pathSeparator}run_history.jsonl');
      f.createSync(recursive: true);
      f.writeAsStringSync(
        '${RunHistoryEntry(timestamp: DateTime(2026, 8, 12), kind: 'cont', mtxNetlist: null, hvNetlist: null, passed: 1, failed: 0).toJsonLine()}\n'
        'not valid json - a crash mid-write, for example\n'
        '${RunHistoryEntry(timestamp: DateTime(2026, 8, 12, 1), kind: 'res', mtxNetlist: null, hvNetlist: null, passed: 2, failed: 0).toJsonLine()}\n',
      );

      final loaded = RunHistoryStore(dir).load();
      expect(loaded, hasLength(2));
      expect(loaded[0].kind, 'cont');
      expect(loaded[1].kind, 'res');
    });

    test('reading a directory with no history file yet returns empty', () {
      expect(RunHistoryStore(dir).load(), isEmpty);
    });
  });
}
