/// Drives the actual "no MTX netlist -> Select... -> cross discovery -> Save
/// -> verify-mode continuity" flow through real widget taps, not direct
/// AppState method calls.
///
/// `netlist_upload_test.dart` already proves the AppState-level pipeline
/// works against the real simulator; this file exists because a method being
/// correct doesn't prove the button that's supposed to call it actually does
/// — that's exactly the kind of gap a user clicking through the built exe
/// finds and a unit test doesn't. Uses a scripted fake transport (no real
/// sockets) so the discovery run's 256-pin sweep doesn't need real wall-clock
/// time to complete.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ht_mk1_gui/app/app_state.dart';
import 'package:ht_mk1_gui/design/widgets.dart';
import 'package:ht_mk1_gui/htproto/connection.dart';
import 'package:ht_mk1_gui/main.dart';

/// Answers a scripted reply per command body. `CONT RUN discover` and
/// `CONT RUN verify` each play back a fixed event script instead of actually
/// simulating a 256-pin sweep, so the test completes in milliseconds.
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
      push('<CAL current_ua=3000 gain=32 rref_mohm=100000\n');
    } else if (body == 'LIMITS GET') {
      push('<LIMITS r_max_mohm=5000 ins_min_mohm=10000000\n');
    } else if (body == 'CONT RUN discover') {
      push('<OK started\n');
      push('!STATE running\n');
      push('!CONT 1 2 pass\n');
      push('!CONT 3 4 pass\n');
      push('!PROGRESS 256 256\n');
      push('!STATE idle\n');
      push('!DONE cont 2 0\n');
    } else if (body == 'NETLIST BEGIN 2') {
      push('<OK\n');
    } else if (body == 'NETLIST ADD 1 2' || body == 'NETLIST ADD 3 4') {
      push('<OK\n');
    } else if (body == 'NETLIST END') {
      push('<OK loaded=2\n');
    } else if (body == 'CONT RUN verify') {
      push('<OK started\n');
      push('!STATE running\n');
      push('!CONT 1 2 pass\n');
      push('!CONT 3 4 pass\n');
      push('!PROGRESS 2 2\n');
      push('!STATE idle\n');
      push('!DONE cont 2 0\n');
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

Future<void> pumpApp(WidgetTester tester, AppState s) async {
  tester.view.physicalSize = const Size(1480, 940);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(HtApp(state: s, storedTheme: 'light'));
  await settle(tester);
}

/// `ConnectionManager.disconnect()` awaits `StreamSubscription.cancel()`,
/// whose future is owned by the root zone — `tester.pump()`'s fake clock
/// never completes it, regardless of whether the transport underneath is a
/// real socket or (as here) a plain StreamController. Leaving the link
/// watchdog's periodic timer pending past the end of the test trips
/// flutter_test's "!timersPending" invariant; addTearDown runs too late to
/// avoid that, so this has to happen in the test body itself.
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
  testWidgets(
      'Netbar Select... -> cross discovery -> Save -> verify-mode '
      'continuity actually runs, end to end, through real taps',
      (tester) async {
    final t = _ScriptedTransport();
    late final AppState s;
    final cm = ConnectionManager(
      onEvent: (m) => s.onEvent(m),
      onLinkState: (st, d) => s.onLinkState(st, d),
      transportFactory: () => t,
      logDir: Directory.systemTemp,
    );
    s = AppState(cm: cm, host: '127.0.0.1', port: 46000);

    await pumpApp(tester, s);
    await s.connect();
    await settle(tester);

    // Fresh instrument boot: no netlist. Confirmed in the actual rendered
    // netbar, not just in AppState fields. The default view (Run) has one
    // MTX netbar and no HV netbar, so this SELECT… is unambiguous.
    expect(find.text('No MTX netlist loaded'), findsOneWidget);
    expect(find.text('SELECT…'), findsOneWidget);

    await tester.tap(find.text('SELECT…'));
    await settle(tester);

    // Select… used to silently jump to the Continuity view instead, with
    // only a collapsed-by-default log line explaining why. That read as "I
    // clicked Select… and nothing happened," which is what this modal
    // exists to fix — it explains both ways to load an MTX netlist (browse a
    // file, or build one from cross continuity) before navigating anywhere.
    expect(find.text('Select the MTX netlist'), findsOneWidget,
        reason: 'Select… must explain itself before navigating away, not '
            'jump silently');
    expect(s.view, 'run', reason: 'the modal must not navigate on its own');

    await tester.tap(find.text('TAKE ME THERE'));
    await settle(tester);

    expect(s.mdMtxOpen, isFalse);
    expect(s.view, 'cont', reason: 'confirming the modal lands on Continuity');
    expect(find.text('RUN CONTINUITY'), findsOneWidget);

    // The view is a scrolling page; RUN CONTINUITY sits in the top bar so
    // this is normally a no-op, but ensureVisible is cheap insurance against
    // exactly the class of bug this file exists to catch — a control that
    // exists in the tree but a tap can't actually reach.
    await tester.ensureVisible(find.text('RUN CONTINUITY'));
    await tester.tap(find.text('RUN CONTINUITY'));
    await settle(tester);
    expect(tester.takeException(), isNull);

    expect(s.running, isNull, reason: 'the scripted discovery run completed');
    expect(find.text('SAVE AS MTX NETLIST'), findsOneWidget);

    final saveBtn = tester.widget<Btn>(find.ancestor(
      of: find.text('SAVE AS MTX NETLIST'),
      matching: find.byType(Btn),
    ));
    expect(saveBtn.onTap, isNotNull,
        reason: 'Save must be enabled once discovery found nets — this is '
            'exactly the button that used to be permanently disabled');

    // The "Discovered netlist" panel is well down the Continuity page — a
    // real operator would have scrolled to it, so the test must too, or a
    // tap that looks like it landed can silently miss (as it did on the
    // first version of this test: the tap hit-tested outside the viewport
    // and none of the NETLIST commands below were ever sent).
    await tester.ensureVisible(find.text('SAVE AS MTX NETLIST'));
    await tester.tap(find.text('SAVE AS MTX NETLIST'));
    await settle(tester);

    expect(t.sent, containsAllInOrder(
        ['NETLIST BEGIN 2', 'NETLIST ADD 1 2', 'NETLIST ADD 3 4', 'NETLIST END']));
    expect(s.nlMtx.loaded, isTrue);
    expect(find.text('No MTX netlist loaded'), findsNothing);

    // Switch to netlist mode and confirm Run continuity is now enabled and
    // actually completes with a pass, not a refusal.
    s.setMode('net');
    await settle(tester);
    expect(find.text('RUN CONTINUITY'), findsOneWidget);

    final runBtn = tester.widget<Btn>(find.ancestor(
      of: find.text('RUN CONTINUITY'),
      matching: find.byType(Btn),
    ));
    expect(runBtn.onTap, isNotNull,
        reason: 'verify-mode continuity must be reachable once a netlist is '
            'loaded — this is the exact button the original bug refused');

    await tester.ensureVisible(find.text('RUN CONTINUITY'));
    await tester.tap(find.text('RUN CONTINUITY'));
    await settle(tester);

    expect(s.R['cont'], 'pass');
    expect(tester.takeException(), isNull);

    await dropLink(tester, cm);
  });
}
