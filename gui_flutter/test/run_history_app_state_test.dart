/// GUI-05 integration: `AppState._onDone` must record a real history entry
/// for every completed run, and `exportHistoryCsv()` must write real rows —
/// not the five hardcoded ones the Results view used to show. Complements
/// `run_history_test.dart`, which covers `RunHistoryStore` in isolation.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ht_mk1_gui/app/app_state.dart';
import 'package:ht_mk1_gui/app/run_history.dart';
import 'package:ht_mk1_gui/htproto/codec.dart' as proto;
import 'package:ht_mk1_gui/htproto/connection.dart';
import 'package:ht_mk1_gui/htproto/messages.dart' as msg;

AppState _state({RunHistoryStore? history, Future<String?> Function({
  required String dialogTitle,
  required String fileName,
  required List<String> allowedExtensions,
})? pickSavePath}) {
  final cm = ConnectionManager(logDir: Directory.systemTemp);
  return AppState(
    cm: cm,
    host: '127.0.0.1',
    port: 46000,
    history: history,
    pickSavePath: pickSavePath,
  );
}

void main() {
  group('AppState records run history on !DONE', () {
    test('a passing continuity run is recorded with the loaded netlists', () {
      final s = _state();
      s.onEvent(const msg.Done(kind: proto.TestKind.cont, passed: 8, failed: 0));

      final entries = s.history.load();
      expect(entries, hasLength(1));
      expect(entries.single.kind, 'cont');
      expect(entries.single.passed, 8);
      expect(entries.single.failed, 0);
      expect(entries.single.pass, isTrue);
      // No netlist is loaded at construction (GUI Reality Check, cause A) —
      // whatever AppState actually has loaded should show up here, not a
      // hardcoded value invented by the test.
      expect(entries.single.mtxNetlist, s.nlMtx.loaded ? s.nlMtx.name : null);
    });

    test('a failing run is recorded as a fail, not silently dropped', () {
      final s = _state();
      s.onEvent(const msg.Done(kind: proto.TestKind.res, passed: 10, failed: 2));

      final entries = s.history.load();
      expect(entries.single.kind, 'res');
      expect(entries.single.pass, isFalse);
    });

    test('a fault-refused run (FW-10) is not recorded at all', () {
      // inFault reads off instState - drive it through the real event that
      // sets it (STATE fault) rather than poking a private field.
      final s = _state();
      s.onEvent(const msg.StateEvent(state: proto.State.fault));
      s.onEvent(const msg.Done(kind: proto.TestKind.insul, passed: 0, failed: 0));

      // A refused run is not a real result - !DONE 0 0 here means "never
      // ran", and recording it would show a false "0 failed" pass in the
      // history table.
      expect(s.history.load(), isEmpty);
    });

    test('multiple runs accumulate in order', () {
      final s = _state();
      s.onEvent(const msg.Done(kind: proto.TestKind.cont, passed: 5, failed: 0));
      s.onEvent(const msg.Done(kind: proto.TestKind.res, passed: 5, failed: 0));
      s.onEvent(const msg.Done(kind: proto.TestKind.insul, passed: 63, failed: 1));

      final entries = s.history.load();
      expect(entries.map((e) => e.kind).toList(), ['cont', 'res', 'insul']);
    });
  });

  group('AppState.exportHistoryCsv', () {
    test('returns false and does not prompt when nothing is recorded', () async {
      var promptCount = 0;
      final s = _state(pickSavePath: ({
        required dialogTitle,
        required fileName,
        required allowedExtensions,
      }) async {
        promptCount++;
        return null;
      });

      final ok = await s.exportHistoryCsv();
      expect(ok, isFalse);
      expect(promptCount, 0);
    });

    test('returns false when the operator cancels the save dialog', () async {
      final s = _state();
      s.onEvent(const msg.Done(kind: proto.TestKind.cont, passed: 1, failed: 0));

      final ok = await s.exportHistoryCsv(); // default injected picker returns null
      expect(ok, isFalse);
    });

    test('writes a real CSV with a header and one row per run', () async {
      final dir = Directory.systemTemp.createTempSync('ht_mk1_csv_test_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final csvPath = '${dir.path}${Platform.pathSeparator}out.csv';

      final s = _state(pickSavePath: ({
        required dialogTitle,
        required fileName,
        required allowedExtensions,
      }) async =>
          csvPath);
      s.onEvent(const msg.Done(kind: proto.TestKind.cont, passed: 8, failed: 0));
      s.onEvent(const msg.Done(kind: proto.TestKind.res, passed: 6, failed: 1));

      final ok = await s.exportHistoryCsv();
      expect(ok, isTrue);

      final lines = File(csvPath).readAsLinesSync();
      // header + 2 runs, newest first (res, then cont)
      expect(lines, hasLength(3));
      expect(lines[0], startsWith('Timestamp,Kind,MTX netlist,HV netlist,'));
      expect(lines[1], contains('res'));
      expect(lines[1], contains('Fail'));
      expect(lines[2], contains('cont'));
      expect(lines[2], contains('Pass'));
    });
  });
}
