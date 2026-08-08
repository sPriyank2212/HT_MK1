/// Regression tests for the buttons wired up this session: `FAULT CLEAR`,
/// `MANUAL PATH` ("Close path"), `MANUAL OFF` ("Discharge"), and the
/// `!DONE` correctness fix for a run refused by a latched fault (FW-10).
///
/// Before this session none of `commands.faultClear()`, `commands.manualPath()`
/// or `commands.manualOff()` were ever called from `AppState` — the codec
/// encoders existed, nothing sent them. See `Doc/GUI_protocol_command_coverage.md`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ht_mk1_gui/app/app_state.dart';
import 'package:ht_mk1_gui/htproto/codec.dart' as proto;
import 'package:ht_mk1_gui/htproto/connection.dart';

/// Answers a scripted reply per command body, and can push extra lines (e.g.
/// `!STATE fault`) before that reply — so a test can reproduce exactly what
/// the brief (FW-10) says the firmware sends when a run is refused by a
/// latched fault: `!STATE fault` then `!DONE <kind> 0 0`.
class _ScriptedTransport implements Transport {
  final StreamController<Uint8List> _ctl =
      StreamController<Uint8List>.broadcast();
  final List<String> sent = [];

  /// exact command body (no leading '>', no trailing '\n') -> reply line to
  /// send instead of the default success
  final Map<String, String> replyOverride = {};

  /// exact command body -> extra lines pushed AFTER its reply. Matches the
  /// brief: `<OK started` comes back the moment a run is accepted onto the
  /// sequencer queue; `!STATE fault` / `!DONE <kind> 0 0` follow only once
  /// the sequencer actually tries to run it and finds the fault latched.
  /// Reversing this order (events before the reply) is not just unrealistic
  /// — it lets `_beginRun`'s post-reply `running = kind` clobber the cleanup
  /// `_onDone`'s fault path already did, which is exactly the bug this file
  /// exists to catch.
  final Map<String, List<String>> postEvents = {};

  @override
  Future<void> open(String host, int port) async {}

  @override
  void send(List<int> data) {
    final body = ascii.decode(data).substring(1).trim();
    sent.add(body);
    final override = replyOverride[body];
    if (override != null) {
      push('$override\n');
    } else if (body == 'STATUS') {
      push('<STATUS state=idle fixture=none hv_mv=0\n');
    } else if (body == 'NETLIST GET') {
      push('<NETLIST 0\n');
    } else if (body == 'CAL GET') {
      push('<CAL current_ua=3000 gain=32 rref_mohm=100000\n');
    } else if (body == 'LIMITS GET') {
      push('<LIMITS r_max_mohm=5000 ins_min_mohm=10000000\n');
    } else if (body == 'FAULT CLEAR' ||
        body.startsWith('MANUAL PATH') ||
        body == 'MANUAL OFF' ||
        body == 'CONT RUN verify' ||
        body == 'RES RUN') {
      push('<OK started\n');
    } else {
      push('<ERR ENOTSUP not supported by the fake\n');
    }
    for (final line in postEvents[body] ?? const <String>[]) {
      push('$line\n');
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

({AppState state, _ScriptedTransport transport}) connectedState() {
  final t = _ScriptedTransport();
  late final AppState s;
  final cm = ConnectionManager(
    onEvent: (m) => s.onEvent(m),
    onLinkState: (st, d) => s.onLinkState(st, d),
    transportFactory: () => t,
    logDir: Directory.systemTemp,
  );
  s = AppState(cm: cm, host: '127.0.0.1', port: 46000);
  return (state: s, transport: t);
}

void main() {
  group('FAULT CLEAR', () {
    test('clearFault() sends FAULT CLEAR and logs success', () async {
      final r = connectedState();
      await r.state.connect();
      addTearDown(r.state.cm.disconnect);

      await r.state.clearFault();

      expect(r.transport.sent, contains('FAULT CLEAR'));
      expect(r.state.logs.last.lvl, 'ok');
    });

    test('a refusal is logged, not swallowed', () async {
      final r = connectedState();
      r.transport.replyOverride['FAULT CLEAR'] =
          '<ERR EHW nothing to clear right now';
      await r.state.connect();
      addTearDown(r.state.cm.disconnect);

      await r.state.clearFault();

      expect(r.state.logs.last.lvl, 'fail');
      expect(r.state.logs.last.message, contains('EHW'));
    });

    test('inFault and the state pill go red, not neutral grey', () async {
      final r = connectedState();
      await r.state.connect();
      addTearDown(r.state.cm.disconnect);
      expect(r.state.inFault, isFalse);

      r.state.instState = proto.State.fault;
      r.state.paintLink();

      expect(r.state.inFault, isTrue);
      expect(r.state.statePill.variant.toString(), contains('bad'));
    });
  });

  group('a run refused by a latched fault', () {
    test('!STATE fault then !DONE 0 0 must not read as a pass', () async {
      final r = connectedState();
      r.transport.postEvents['CONT RUN verify'] = [
        '!STATE fault',
        '!DONE cont 0 0',
      ];
      await r.state.connect();
      addTearDown(r.state.cm.disconnect);

      await r.state.runCont();
      // The pre-events (including !DONE) are pushed synchronously inside
      // send(), off the same broadcast stream; give the event loop a turn to
      // deliver them through the framer before asserting.
      await Future<void>.delayed(Duration.zero);

      expect(r.state.inFault, isTrue,
          reason: 'the !STATE fault event must be reflected');
      expect(r.state.R['cont'], isNull,
          reason: '0 failed out of 0 run must never read as a pass');
      expect(r.state.running, isNull);
    });
  });

  group('MANUAL PATH — Diagnostics "Close path"', () {
    test('manualClosePath sends 1-based wire pins', () async {
      final r = connectedState();
      await r.state.connect();
      addTearDown(r.state.cm.disconnect);

      await r.state.manualClosePath(15, 72);

      expect(r.transport.sent, contains('MANUAL PATH 15 72'));
    });
  });

  group('MANUAL OFF — Diagnostics "Discharge"', () {
    test('manualOff sends MANUAL OFF', () async {
      final r = connectedState();
      await r.state.connect();
      addTearDown(r.state.cm.disconnect);

      await r.state.manualOff();

      expect(r.transport.sent, contains('MANUAL OFF'));
    });
  });

  group('MTX netbar routing', () {
    test('Select…/Change… opens an explainer before navigating anywhere',
        () async {
      final s = connectedState().state;
      s.go('run');
      s.setMode('net', quiet: true);

      s.openMtxNlExplainer();

      expect(s.mdMtxOpen, isTrue);
      expect(s.view, 'run',
          reason: 'opening the explainer must not itself navigate');
    });

    test('confirming the explainer switches to cross mode and Continuity',
        () async {
      final s = connectedState().state;
      s.go('run');
      s.setMode('net', quiet: true);
      s.openMtxNlExplainer();

      s.confirmGoToBuildMtxNetlist();

      expect(s.mdMtxOpen, isFalse);
      expect(s.view, 'cont');
      expect(s.cmode, 'cross');
    });

    test('Cancel closes the explainer without navigating', () async {
      final s = connectedState().state;
      s.go('run');
      s.openMtxNlExplainer();

      s.closeMtxNlExplainer();

      expect(s.mdMtxOpen, isFalse);
      expect(s.view, 'run');
    });
  });
}
