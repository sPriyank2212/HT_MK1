// The client app's "Save Log (.txt)" file: one text file with a header (app,
// firmware, port), the application log with real timestamps, and the serial
// traffic. Firmware E[ / W[ lines must show as ERROR / WARN, not INFO.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ht_mk1_gui/app/app_state.dart';
import 'package:ht_mk1_gui/client/client_tabs.dart';
import 'package:ht_mk1_gui/htproto/connection.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppState s;
  setUp(() {
    late AppState ref;
    final cm = ConnectionManager(
      onEvent: (m) => ref.onEvent(m),
      onLinkState: (st, d) => ref.onLinkState(st, d),
      logDir: Directory.systemTemp,
    );
    s = ref = AppState(
      cm: cm,
      host: '127.0.0.1',
      port: 1,
      serialLink: true,
      pickNetlistFile: () async => null,
      pickSavePath: ({required dialogTitle, required fileName, required allowedExtensions}) async => null,
    );
  });

  test('firmware severity comes from the E[ / W[ prefix', () {
    expect(logLevelOf(const LogEntry(0, 'info', 'fw', 'E[1203] DIAG: x')), 'ERROR');
    expect(logLevelOf(const LogEntry(0, 'info', 'fw', '#W[12] BOARD: y')), 'WARN');
    expect(logLevelOf(const LogEntry(0, 'info', 'fw', 'I[3] boot')), 'INFO');
    // Only firmware lines are re-read; an app line that merely starts "E[".
    expect(logLevelOf(const LogEntry(0, 'info', 'app', 'E[1] note')), 'INFO');
    expect(logLevelOf(const LogEntry(0, 'fail', 'link', 'lost')), 'ERROR');
  });

  test('log lines carry the real wall-clock time', () {
    final e = LogEntry(5.0, 'info', 'app', 'hello', DateTime(2026, 11, 17, 9, 8, 7, 6));
    expect(logLine(e), '[09:08:07.006] [INFO] hello');
  });

  test('one file: header, application log, serial traffic', () {
    s.log('info', 'link', 'connected');
    s.logs.add(LogEntry(0, 'info', 'fw',
        'E[4000] DIAG: mcp23017.c:39 i2c3 wr 0x20 r0x00 hal=1 e=0x10(NAK)',
        DateTime(2026, 11, 17, 10, 0, 0, 5)));
    s.onWire('tx', '>ID?');
    s.onWire('rx', '<OK');

    final txt = buildLogFileText(s, now: DateTime(2026, 11, 17, 10, 5, 0));

    expect(txt, startsWith('HARNESS TESTER - LOG FILE\r\n'));
    expect(txt, contains('Generated  : 2026-11-17 10:05:00.000'));
    expect(txt, contains('App build  :'));
    expect(txt, contains('Link       : not connected'));
    // the app's own boot line + the two added above
    expect(txt, contains('===== APPLICATION LOG (3 lines) ====='));
    expect(txt, contains(
        '[2026-11-17 10:00:00.005] [ERROR] fw    E[4000] DIAG: mcp23017.c:39 i2c3 wr 0x20'));
    expect(txt, contains('===== SERIAL TRAFFIC TX/RX (2 lines'));
    expect(txt, contains('[TX] >ID?'));
    expect(txt, contains('[RX] <OK'));
    // Windows line endings throughout, no bare LF.
    expect(RegExp(r'(?<!\r)\n').hasMatch(txt), isFalse);
  });
}
