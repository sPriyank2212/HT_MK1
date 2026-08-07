/// Where the GUI writes things.
///
/// Direct port of `htproto/paths.py`.
///
/// A packaged executable is launched from wherever the operator happens to be —
/// Explorer, a Start-menu shortcut, C:\Windows — and the current directory is
/// almost never writable. Defaulting the session log to a relative `sessions/`
/// worked from a checkout and failed with `PermissionError: [WinError 5]` on
/// the first real double-click, taking the whole connection down with it,
/// because the log is opened as part of connecting (brief §3.5 rule 5).
///
/// So: pick a per-user location that is always writable, and fall back to the
/// system temp directory rather than failing to connect. Session logs are how
/// field failures get diagnosed; losing the link because we could not open one
/// is the wrong trade.
library;

import 'dart:io';

const String app = 'HT_MK1';

String _join(String a, String b) =>
    a.endsWith(Platform.pathSeparator) ? '$a$b' : '$a${Platform.pathSeparator}$b';

/// A writable directory for session logs, created if needed.
Directory defaultLogDir() {
  final candidates = <String>[];

  final local = Platform.environment['LOCALAPPDATA'];
  if (local != null && local.isNotEmpty) {
    candidates.add(_join(_join(local, app), 'sessions')); // Windows
  }
  final xdg = Platform.environment['XDG_DATA_HOME'];
  if (xdg != null && xdg.isNotEmpty) {
    candidates.add(_join(_join(xdg, app), 'sessions'));
  }
  final home = Platform.environment['USERPROFILE'] ??
      Platform.environment['HOME'] ??
      Directory.current.path;
  candidates.add(_join(_join(_join(_join(home, '.local'), 'share'), app), 'sessions'));
  candidates.add(_join(_join(Directory.systemTemp.path, app), 'sessions'));

  for (final path in candidates) {
    try {
      final dir = Directory(path);
      dir.createSync(recursive: true);
      final probe = File(_join(path, '.writable'));
      probe.writeAsStringSync('');
      probe.deleteSync();
      return dir;
    } on FileSystemException {
      continue;
    }
  }

  // Nothing worked; hand back temp and let the caller surface the failure.
  return Directory.systemTemp;
}
