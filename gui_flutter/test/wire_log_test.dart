/// Coverage for the TX/RX wire console: `ConnectionManager.onWire` surfacing
/// raw protocol lines, `AppState.onWire`/`wireLog` capping, and the status
/// bar's Log/Console tab actually showing them on screen.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ht_mk1_gui/app/app_state.dart';
import 'package:ht_mk1_gui/htproto/connection.dart';
import 'package:ht_mk1_gui/main.dart';

class _FakeTransport implements Transport {
  final StreamController<Uint8List> _ctl =
      StreamController<Uint8List>.broadcast();

  @override
  Future<void> open(String host, int port) async {}

  @override
  void send(List<int> data) {
    final body = ascii.decode(data).substring(1).trim();
    if (body == 'STATUS') {
      push('<STATUS state=idle fixture=none hv_mv=0\n');
    } else if (body == 'NETLIST GET') {
      push('<NETLIST 0\n');
    } else if (body == 'CAL GET') {
      push('<CAL current_ua=3000 gain=32 rref_mohm=100000\n');
    } else if (body == 'LIMITS GET') {
      push('<LIMITS r_max_mohm=5000 ins_min_mohm=10000000\n');
    } else {
      push('<ERR ENOTSUP not supported by the fake\n');
    }
  }

  void push(String text) {
    if (!_ctl.isClosed) _ctl.add(Uint8List.fromList(ascii.encode(text)));
  }

  @override
  Stream<Uint8List> get incoming => _ctl.stream;

  @override
  Future<void> close() async {
    if (!_ctl.isClosed) _ctl.close();
  }
}

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> dropLink(WidgetTester tester, ConnectionManager cm) async {
  unawaited(cm.disconnect());
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester
      .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  group('ConnectionManager.onWire', () {
    test('fires for both directions with the exact wire text', () async {
      final tx = <String>[];
      final rx = <String>[];
      final cm = ConnectionManager(
        transportFactory: _FakeTransport.new,
        logDir: Directory.systemTemp,
        onWire: (dir, text) {
          if (dir == 'tx') {
            tx.add(text);
          } else if (dir == 'rx') {
            rx.add(text);
          } else {
            fail('unexpected direction: $dir');
          }
        },
      );
      addTearDown(cm.disconnect);

      await cm.connect();

      expect(tx, contains('>STATUS'));
      expect(rx, contains('<STATUS state=idle fixture=none hv_mv=0'));
      // No leading '>' stripped, no trailing newline left in — exactly what
      // SessionLogger.tx()/rx() would have written to the session file.
      expect(tx.every((l) => !l.endsWith('\n')), isTrue);
    });
  });

  group('AppState.onWire', () {
    test('appends entries and caps at wireLogCap', () {
      final cm = ConnectionManager(logDir: Directory.systemTemp);
      final s = AppState(cm: cm, host: '127.0.0.1', port: 46000);

      for (var i = 0; i < AppState.wireLogCap + 50; i++) {
        s.onWire('tx', 'line $i');
      }

      expect(s.wireLog.length, AppState.wireLogCap);
      // Oldest dropped, not newest — the console is scrollback, not a ring
      // that overwrites what an operator is currently reading.
      expect(s.wireLog.first.text, 'line 50');
      expect(s.wireLog.last.text, 'line ${AppState.wireLogCap + 49}');
    });

    test('setLogView toggles independently of logOpen', () {
      final cm = ConnectionManager(logDir: Directory.systemTemp);
      final s = AppState(cm: cm, host: '127.0.0.1', port: 46000);

      expect(s.logView, 'ops');
      s.setLogView('wire');
      expect(s.logView, 'wire');
      expect(s.logOpen, isFalse,
          reason: 'switching tabs must not itself expand the panel');
    });
  });

  group('the Console tab, through real taps', () {
    testWidgets('shows the exact tx/rx lines that crossed the wire',
        (tester) async {
      // onWire is wired the same way main.dart wires it — through AppState,
      // not directly, so this exercises the same path main.dart uses rather
      // than a shortcut a test-only wiring could hide a mistake in.
      late final AppState s;
      final cm = ConnectionManager(
        transportFactory: _FakeTransport.new,
        logDir: Directory.systemTemp,
        onEvent: (m) => s.onEvent(m),
        onLinkState: (st, d) => s.onLinkState(st, d),
        onWire: (dir, text) => s.onWire(dir, text),
      );
      s = AppState(cm: cm, host: '127.0.0.1', port: 46000);

      tester.view.physicalSize = const Size(1480, 940);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(HtApp(state: s, storedTheme: 'light'));
      await settle(tester);

      await s.connect();
      await settle(tester);

      // EXPAND opens the panel on the operator-log tab (the default);
      // console traffic already exists by now but isn't shown until the
      // operator switches tabs.
      await tester.tap(find.text('EXPAND'));
      await settle(tester);
      expect(s.logOpen, isTrue);
      expect(find.textContaining('>STATUS'), findsNothing);

      await tester.tap(find.text('Console'));
      await settle(tester);

      expect(find.textContaining('>STATUS'), findsOneWidget);
      expect(find.textContaining('<STATUS state=idle'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await dropLink(tester, cm);
    });
  });
}
