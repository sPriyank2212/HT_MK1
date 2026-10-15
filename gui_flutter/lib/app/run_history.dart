/// GUI-05: run history, stored on the GUI host (decided 2026-08-12 — not the
/// instrument). One line of JSON per completed run, appended immediately and
/// flushed, the same reliability reasoning `SessionLogger` uses for session
/// logs (`htproto/connection.dart`) — a crash between two runs must not lose
/// the ones already finished.
///
/// `RunHistoryStore()` with no directory is in-memory only: the ~180
/// existing GUI tests that construct `AppState` without a history directory
/// keep working unmodified, and never touch disk. The real app
/// (`main.dart`) passes `defaultHistoryDir()`.
library;

import 'dart:convert';
import 'dart:io';

/// One completed run: `CONT RUN`, `RES RUN` or `INSUL RUN`, whichever kind
/// just finished. There is no "build" concept in the protocol — no serial
/// number, no single event tying continuity+resistance+HV together — so this
/// is one row per finished test, not per harness. `mtxNetlist`/`hvNetlist`
/// are whatever was loaded at the moment the run finished, or null if none.
class RunHistoryEntry {
  final DateTime timestamp;
  final String kind; // 'cont' | 'res' | 'insul'
  final String? mtxNetlist;
  final String? hvNetlist;
  final int passed;
  final int failed;

  const RunHistoryEntry({
    required this.timestamp,
    required this.kind,
    required this.mtxNetlist,
    required this.hvNetlist,
    required this.passed,
    required this.failed,
  });

  bool get pass => failed == 0;

  String toJsonLine() => jsonEncode({
        't': timestamp.toIso8601String(),
        'kind': kind,
        'mtx': mtxNetlist,
        'hv': hvNetlist,
        'passed': passed,
        'failed': failed,
      });

  factory RunHistoryEntry.fromJsonLine(String line) {
    final j = jsonDecode(line) as Map<String, dynamic>;
    return RunHistoryEntry(
      timestamp: DateTime.parse(j['t'] as String),
      kind: j['kind'] as String,
      mtxNetlist: j['mtx'] as String?,
      hvNetlist: j['hv'] as String?,
      passed: j['passed'] as int,
      failed: j['failed'] as int,
    );
  }
}

class RunHistoryStore {
  final Directory? dir;
  List<RunHistoryEntry>? _cache;

  RunHistoryStore([this.dir]);

  File? get _file =>
      dir == null ? null : File('${dir!.path}${Platform.pathSeparator}run_history.jsonl');

  /// Oldest first (append order). Callers wanting newest-first reverse it —
  /// kept as the natural order of the underlying log rather than baked in
  /// here, same as a session log reads top-to-bottom.
  List<RunHistoryEntry> load() {
    final cached = _cache;
    if (cached != null) return List.unmodifiable(cached);

    final f = _file;
    if (f == null || !f.existsSync()) {
      _cache = [];
      return const [];
    }
    final entries = <RunHistoryEntry>[];
    for (final line in f.readAsLinesSync()) {
      if (line.trim().isEmpty) continue;
      try {
        entries.add(RunHistoryEntry.fromJsonLine(line));
      } on FormatException {
        // One corrupt line (e.g. a partial write from a crash) must not
        // hide every other run's history - skip it, keep the rest.
        continue;
      }
    }
    _cache = entries;
    return List.unmodifiable(entries);
  }

  void append(RunHistoryEntry e) {
    load(); // ensure the cache is populated before adding to it
    _cache!.add(e);

    final f = _file;
    if (f == null) return; // in-memory mode
    dir!.createSync(recursive: true);
    f.writeAsStringSync('${e.toJsonLine()}\n', mode: FileMode.append, flush: true);
  }
}
