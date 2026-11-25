/// Keeps a copy of what a session produced — the **log**, the **results**
/// (each run's CSV and PDF report) and the **netlists** — in three separate
/// folders next to where the GUI is run:
///
/// ```
/// <GUI folder>/Logs      harness_tester_log_<start>.txt, session-….log
/// <GUI folder>/Results   report_….csv / .pdf written by this session's runs
/// <GUI folder>/Netlists  the MTX and HV netlists that were loaded (.xlsx)
/// ```
///
/// It runs when the window is closed ([ClientOutput.save] from the app's exit
/// request) and again after every finished run, so a crash or a forced close
/// still leaves the last run's files behind.
///
/// "<GUI folder>" is the folder the program is running from. The single-file
/// `Harness_Tester.exe` unpacks itself to a temporary folder that is deleted
/// on exit, so for it the folder the .exe was started from is used (found
/// through the launcher process, see [sfxLauncherDir]). If the GUI folder is not writable (e.g.
/// under Program Files) the folders are made under `Documents\Harness_Tester`
/// instead.
library;

import 'dart:io';

import 'client_controller.dart';
import 'client_tabs.dart' show buildLogFileText;
import 'netlist_doc.dart';

/// The folder the single-file `Harness_Tester.exe` was started from, found
/// through the launcher process that unpacked this program (it is this
/// process's parent). Null when this is not such a launch.
Future<Directory?> sfxLauncherDir() async {
  if (!Platform.isWindows) return null;
  try {
    final r = await Process.run('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      r'$pp=(Get-CimInstance Win32_Process -Filter "ProcessId=' '$pid' r'").ParentProcessId;'
          r'(Get-CimInstance Win32_Process -Filter "ProcessId=$pp").ExecutablePath',
    ]).timeout(const Duration(seconds: 8));
    final path = '${r.stdout}'.trim();
    if (path.isEmpty) return null;
    final name = path.split(RegExp(r'[\/]')).last.toLowerCase();
    if (!name.contains('harness') && !name.contains('7z')) return null;
    final dir = File(path).parent;
    return dir.existsSync() ? dir : null;
  } on Object {
    return null;
  }
}

/// The folder the three output folders are made in (see the library note).
/// [launcherDir] is [sfxLauncherDir]'s answer for a single-file launch.
Directory clientOutputRoot({Directory? launcherDir}) {
  final candidates = <Directory>[];
  if (launcherDir != null) candidates.add(launcherDir);
  final exeDir = File(Platform.resolvedExecutable).parent;
  final temp = Directory.systemTemp.resolveSymbolicLinksSync().toLowerCase();
  final exeIsTemp = exeDir.path.toLowerCase().startsWith(temp);
  if (!exeIsTemp) candidates.add(exeDir);
  final home = Platform.environment['USERPROFILE'] ??
      Platform.environment['HOME'] ??
      Directory.current.path;
  candidates.add(Directory(
      '$home${Platform.pathSeparator}Documents${Platform.pathSeparator}Harness_Tester'));
  candidates.add(Directory(
      '${Directory.current.path}${Platform.pathSeparator}Harness_Tester'));
  for (final d in candidates) {
    try {
      d.createSync(recursive: true);
      final probe = File('${d.path}${Platform.pathSeparator}.writable');
      probe.writeAsStringSync('');
      probe.deleteSync();
      return d;
    } on Object {
      continue;
    }
  }
  return Directory.systemTemp;
}

class ClientOutput {
  final ClientController ctl;
  final DateTime started = DateTime.now();
  final Directory Function() _rootOf;
  Directory? _root;

  Directory? _launcherDir;

  /// [rootOf] is injectable for tests; the app uses [clientOutputRoot].
  ClientOutput(this.ctl, {Directory Function()? rootOf})
      : _rootOf = rootOf ?? (() => clientOutputRoot());

  /// Finds the folder a single-file launch started from, once, at start-up, so
  /// closing the window does not have to wait for it.
  Future<void> prepare() async {
    _launcherDir = await sfxLauncherDir();
    _root = null;
  }

  Directory get root => _root ??= _launcherDir != null
      ? clientOutputRoot(launcherDir: _launcherDir)
      : _rootOf();

  static String _two(int n) => n.toString().padLeft(2, '0');

  String get _stamp =>
      '${started.year}${_two(started.month)}${_two(started.day)}_'
      '${_two(started.hour)}${_two(started.minute)}${_two(started.second)}';

  Directory _folder(String leaf) {
    final d = Directory('${root.path}${Platform.pathSeparator}$leaf');
    d.createSync(recursive: true);
    return d;
  }

  /// Writes the log, copies this session's reports and writes the loaded
  /// netlists. Never throws: a failure is logged and the rest still runs.
  /// Returns the number of files written.
  int save() {
    final s = ctl.s;
    var n = 0;

    // ---- Logs --------------------------------------------------------------
    try {
      final logs = _folder('Logs');
      File('${logs.path}${Platform.pathSeparator}harness_tester_log_$_stamp.txt')
          .writeAsStringSync(buildLogFileText(s));
      n++;
      final raw = s.cm.logger.path;
      if (raw != null && raw.existsSync()) {
        raw.copySync(
            '${logs.path}${Platform.pathSeparator}${raw.uri.pathSegments.last}');
        n++;
      }
    } on Object catch (e) {
      s.log('warn', 'out', 'could not save the log: $e');
    }

    // ---- Results -----------------------------------------------------------
    try {
      final from = s.reportsDir;
      if (from != null && from.existsSync()) {
        final results = _folder('Results');
        for (final f in from.listSync().whereType<File>()) {
          final name = f.uri.pathSegments.last;
          final lower = name.toLowerCase();
          if (!(lower.endsWith('.csv') || lower.endsWith('.pdf'))) continue;
          // only what this session's runs wrote
          if (f.lastModifiedSync().isBefore(started)) continue;
          final dest = File('${results.path}${Platform.pathSeparator}$name');
          if (dest.existsSync() && dest.lengthSync() == f.lengthSync()) continue;
          f.copySync(dest.path);
          n++;
        }
      }
    } on Object catch (e) {
      s.log('warn', 'out', 'could not save the results: $e');
    }

    // ---- Netlists ----------------------------------------------------------
    try {
      for (final kind in NetlistKind.values) {
        final doc = ctl.loadedNetlistDoc(kind);
        if (doc == null) continue;
        final netlists = _folder('Netlists');
        final stem = doc.name.replaceAll(RegExp(r'\.[^.]*$'), '');
        final tag = kind == NetlistKind.hv ? '_HV' : '';
        File('${netlists.path}${Platform.pathSeparator}$stem$tag.xlsx')
            .writeAsBytesSync(doc.toBytes('xlsx'));
        n++;
      }
    } on Object catch (e) {
      s.log('warn', 'out', 'could not save the netlists: $e');
    }
    return n;
  }
}
