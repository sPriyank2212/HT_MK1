/// Widget-tap coverage for the Diagnostics controls wired up this session
/// (`Close path`, `Discharge`) and the status-bar `Clear Fault` control —
/// same reasoning as `netlist_select_flow_test.dart`: a correct AppState
/// method proves nothing about whether the button that's supposed to call it
/// actually reaches it through the real widget tree.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ht_mk1_gui/app/app_state.dart';
import 'package:ht_mk1_gui/htproto/codec.dart' as proto;
import 'package:ht_mk1_gui/htproto/connection.dart';
import 'package:ht_mk1_gui/main.dart';

class _ScriptedTransport implements Transport {
  final StreamController<Uint8List> _ctl =
      StreamController<Uint8List>.broadcast();
  final List<String> sent = [];

  @override
  Future<void> open(String host, int port) async {}

  @override
  void send(List<int> data) {
    final body = ascii.decode(data).substring(1).trim();
    sent.add(body);
    if (body == 'STATUS') {
      push('<STATUS state=idle fixture=none hv_mv=0\n');
    } else if (body == 'NETLIST GET') {
      push('<NETLIST 0\n');
    } else if (body == 'CAL GET') {
      push('<CAL current_ua=2000 method=ratiometric rref_mohm=100000 rref_tol_mohm=10 gain_max=128\n');
    } else if (body == 'LIMITS GET') {
      push('<LIMITS r_max_mohm=5000 ins_min_mohm=10000000\n');
    } else if (body.startsWith('MANUAL PATH') || body == 'MANUAL OFF') {
      push('<OK started\n');
    } else if (body == 'FAULT CLEAR') {
      push('<OK started\n');
      push('!STATE idle\n');
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

({AppState state, _ScriptedTransport transport, ConnectionManager cm})
    connectedState() {
  final t = _ScriptedTransport();
  late final AppState s;
  final cm = ConnectionManager(
    onEvent: (m) => s.onEvent(m),
    onLinkState: (st, d) => s.onLinkState(st, d),
    transportFactory: () => t,
    logDir: Directory.systemTemp,
  );
  s = AppState(cm: cm, host: '127.0.0.1', port: 46000);
  return (state: s, transport: t, cm: cm);
}

Future<void> pumpApp(WidgetTester tester, AppState s) async {
  tester.view.physicalSize = const Size(1480, 940);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(HtApp(state: s, storedTheme: 'light'));
  await settle(tester);
}

void main() {
  testWidgets('Diagnostics — Close path and Discharge reach the instrument',
      (tester) async {
    final r = connectedState();
    await r.state.connect();
    await pumpApp(tester, r.state);

    r.state.go('diag');
    await settle(tester);

    await tester.ensureVisible(find.text('CLOSE PATH'));
    await tester.tap(find.text('CLOSE PATH'));
    await settle(tester);

    expect(
      r.transport.sent.any((c) => c.startsWith('MANUAL PATH')),
      isTrue,
      reason: 'tapping Close path must send MANUAL PATH, not silently do '
          'nothing',
    );

    await tester.ensureVisible(find.text('DISCHARGE'));
    await tester.tap(find.text('DISCHARGE'));
    await settle(tester);

    expect(r.transport.sent, contains('MANUAL OFF'));
    expect(tester.takeException(), isNull);

    // The removed MANUAL RELAY controls must actually be gone, not just
    // relabelled or disabled — the brief says do not offer them at all.
    expect(find.text('CLOSE HS ONLY'), findsNothing);
    expect(find.text('CLOSE LS PATTERN'), findsNothing);

    await dropLink(tester, r.cm);
  });

  testWidgets('Clear Fault appears only while a fault is latched, and works',
      (tester) async {
    final r = connectedState();
    await r.state.connect();
    await pumpApp(tester, r.state);

    expect(find.text('CLEAR FAULT'), findsNothing,
        reason: 'must not be a permanent fixture of the status bar');

    r.state.instState = proto.State.fault;
    r.state.paintLink();
    await settle(tester);

    expect(find.text('CLEAR FAULT'), findsOneWidget);

    await tester.tap(find.text('CLEAR FAULT'));
    await settle(tester);

    expect(r.transport.sent, contains('FAULT CLEAR'));
    expect(tester.takeException(), isNull);

    await dropLink(tester, r.cm);
  });
}
