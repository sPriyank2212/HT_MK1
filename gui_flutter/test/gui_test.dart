/// GUI-layer tests, mirroring `gui/tests/test_model.py` and
/// `test_gui_smoke.py`: the seeded harness must be deterministic, and the
/// safety rules must hold without a display.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ht_mk1_gui/app/app_state.dart';
import 'package:ht_mk1_gui/design/model.dart';
import 'package:ht_mk1_gui/htproto/codec.dart' as proto;
import 'package:ht_mk1_gui/htproto/connection.dart';
import 'package:ht_mk1_gui/htproto/messages.dart' as msg;

AppState newState() {
  final cm = ConnectionManager(logDir: Directory.systemTemp);
  return AppState(cm: cm, host: '127.0.0.1', port: 46000);
}

void main() {
  // kFix (design/model.dart) is process-global mutable state now
  // (setActiveFixture, GUI-11) — reset it after every test so one test's
  // fixture never leaks into the next.
  tearDown(() => setActiveFixture(buildDefaultFixture()));

  // =========================================================================
  group('mulberry32 matches the page bit for bit', () {
    test('the first values of seed 880 are stable', () {
      final r = Mulberry32(880);
      final got = List<double>.generate(4, (_) => r.next());
      for (final v in got) {
        expect(v, greaterThanOrEqualTo(0.0));
        expect(v, lessThan(1.0));
        // The result is an unsigned 32-bit integer over 2^32, so scaling it
        // back up must land exactly on a whole number.
        final scaled = v * 4294967296;
        expect(scaled, closeTo(scaled.roundToDouble(), 1e-6));
      }
      // Re-seeding reproduces the sequence exactly.
      final again = Mulberry32(880);
      expect(List<double>.generate(4, (_) => again.next()), got);
    });

    test('different seeds diverge', () {
      expect(Mulberry32(880).next(), isNot(Mulberry32(881).next()));
    });
  });

  // =========================================================================
  group('the seeded harness is deterministic', () {
    test('two builds are identical', () {
      final a = buildNets();
      final b = buildNets();
      expect(a.length, b.length);
      for (var i = 0; i < a.length; i++) {
        expect(a[i].name, b[i].name);
        expect(a[i].src, b[i].src);
        expect(a[i].dsts, b[i].dsts);
        expect(a[i].r, b[i].r);
        expect(a[i].wire, b[i].wire);
      }
    });

    test('the design\'s fixed facts hold', () {
      final nets = buildNets();
      expect(nets.length, 118);
      expect(nets[0].name, 'PWR_28V_A');
      expect(nets[11].name, 'SPLICE_28V');
      // seeded faults
      expect(nets[4].open, isTrue);
      expect(nets[5].r, 4.812);
      expect(nets[2].ins, 3.2);
      // six Y joints, four I joints
      expect(nets.where((n) => n.joint == 'Y').length, 6);
      expect(nets.where((n) => n.joint == 'I').length, 4);
      // HV relay assignment is a direct function of the source pin's own
      // flat board position (GUI-11), not this list's order.
      for (final n in nets) {
        expect(n.card, n.hs ~/ 64);
        expect(n.relay, n.hs % 64);
      }
    });

    test('every net lands on a real connector pin', () {
      final nets = buildNets();
      for (final n in nets) {
        expect(kConn[n.src.c]!.side, 'L');
        expect(n.src.p, inInclusiveRange(1, kConn[n.src.c]!.pins));
        for (final d in n.dsts) {
          expect(kConn[d.c]!.side, 'R');
          expect(d.p, inInclusiveRange(1, kConn[d.c]!.pins));
        }
      }
    });
  });

  // =========================================================================
  group('connector geometry', () {
    test('layoutFixture gives every pin a coordinate', () {
      layoutFixture();
      for (final c in kFix.connectors) {
        expect(c.pts.length, greaterThanOrEqualTo(c.pins),
            reason: '${c.id} (${c.type})');
        for (final p in c.pts.take(c.pins)) {
          expect(p.x, greaterThan(0));
          expect(p.y, greaterThan(0));
          expect(p.x, lessThan(kCanvasW));
          expect(p.y, lessThan(kCanvasH));
        }
      }
      // Left connectors sit left of right connectors.
      expect(kConnsL.first.x, lessThan(kConnsR.first.x));
    });
  });

  // =========================================================================
  group('gating rules — can()', () {
    test('nothing runs while a run is in flight', () {
      final s = newState();
      s.running = 'cont';
      expect(s.can('cont').$1, isFalse);
      expect(s.can('res').$1, isFalse);
      expect(s.can('hv').$1, isFalse);
      expect(s.can('cont').$2, 'A test is already running');
    });

    test('stage 1 is blocked once the harness is on J-HV', () {
      final s = newState();
      s.onHv = true;
      expect(s.can('cont').$1, isFalse);
      expect(s.can('res').$1, isFalse);
      expect(s.can('cont').$2, contains('reset to return it to J-MTX'));
    });

    test('netlist continuity needs the MTX netlist, cross does not', () {
      final s = newState();
      s.nlMtx.loaded = false;
      s.setMode('net');
      expect(s.can('cont').$1, isFalse);
      s.setMode('cross');
      expect(s.can('cont').$1, isTrue);
    });

    test('resistance always needs the MTX netlist', () {
      final s = newState();
      s.nlMtx.loaded = false;
      s.setMode('cross');
      expect(s.can('res').$1, isFalse);
      expect(s.can('res').$2, contains('needs the MTX netlist'));
    });

    test('HV is locked until the instrument says the fixture moved', () {
      final s = newState();
      expect(s.can('hv').$1, isFalse);
      expect(s.can('hv').$2, contains('must pass before HV unlocks'));

      // Passing stage 1 is not enough on its own.
      s.R['cont'] = 'pass';
      s.R['res'] = 'pass';
      expect(s.can('hv').$1, isFalse);
      expect(s.can('hv').$2, contains('moved to J-HV'));

      // Only the fixture the instrument reports opens it.
      s.onEvent(const msg.FixtureEvent(fixture: proto.Fixture.hv));
      expect(s.onHv, isTrue);
      expect(s.can('hv').$1, isTrue);
    });
  });

  // =========================================================================
  group('safety rules', () {
    test('"safe to handle" comes from !SAFE and nothing else', () {
      final s = newState();
      expect(s.handling, 'unknown');

      // A run finishing does not make it safe.
      s.onEvent(const msg.Done(
          kind: proto.TestKind.cont, passed: 3, failed: 0));
      expect(s.handling, 'unknown');

      // Nor does going idle.
      s.onEvent(const msg.StateEvent(state: proto.State.idle));
      expect(s.handling, 'unknown');

      // Only !SAFE does.
      s.onEvent(const msg.SafeEvent());
      expect(s.handling, 'safe');
    });

    test('link loss forces unknown and drops the arm', () {
      final s = newState();
      s.link = true;
      s.armed = true;
      s.handling = 'safe';
      s.running = 'insul';

      s.linkDown('port closed by instrument');

      expect(s.link, isFalse);
      expect(s.armed, isFalse);
      expect(s.handling, 'unknown'); // never degrades to "safe"
      expect(s.running, isNull);
      expect(s.hvPill.text, 'Link lost');
      expect(s.statePill.text, 'State unknown');
    });

    test('any fixture change disarms', () {
      final s = newState();
      s.onEvent(const msg.FixtureEvent(fixture: proto.Fixture.hv));
      s.armed = true;
      // The case this exists to stop: arm on HV, claim a move back to the
      // matrix, then energise.
      s.onEvent(const msg.FixtureEvent(fixture: proto.Fixture.mtx));
      expect(s.armed, isFalse);
      expect(s.onHv, isFalse);
      expect(s.can('hv').$1, isFalse);
    });

    test('!SAFE drops the arm and zeroes the rail', () {
      final s = newState();
      s.link = true;
      s.armed = true;
      s.hvMv = 500000;
      s.onEvent(const msg.SafeEvent());
      expect(s.armed, isFalse);
      expect(s.hvMv, 0);
      expect(s.hvLive, isFalse);
    });

    test('!STATE idle drops the arm; fault forces unknown', () {
      final s = newState();
      s.armed = true;
      s.onEvent(const msg.StateEvent(state: proto.State.idle));
      expect(s.armed, isFalse);

      s.handling = 'safe';
      s.armed = true;
      s.onEvent(const msg.StateEvent(state: proto.State.fault));
      expect(s.armed, isFalse);
      expect(s.handling, 'unknown');
    });

    test('the hazard banner tracks the rail, not the arm', () {
      final s = newState();
      s.link = true;
      s.onEvent(const msg.HvEvent(millivolts: kHvLiveMv - 1));
      expect(s.hvLive, isFalse);
      s.onEvent(const msg.HvEvent(millivolts: kHvLiveMv));
      expect(s.hvLive, isTrue);
      expect(s.hvPill.text, startsWith('HV LIVE'));
    });
  });

  // =========================================================================
  group('run results drive the design', () {
    test('a passing continuity run unlocks the handover, not HV', () {
      final s = newState();
      s.link = true;
      s.onEvent(
          const msg.Done(kind: proto.TestKind.cont, passed: 12, failed: 0));
      expect(s.R['cont'], 'pass');
      s.onEvent(
          const msg.Done(kind: proto.TestKind.res, passed: 12, failed: 0));
      expect(s.R['res'], 'pass');

      expect(s.phase, 'hold');
      expect(s.vTitle, 'MOVE DUT');
      expect(s.can('hv').$1, isFalse); // still needs the fixture move
    });

    test('a failing run holds the gate shut', () {
      final s = newState();
      s.link = true;
      s.onEvent(
          const msg.Done(kind: proto.TestKind.cont, passed: 11, failed: 1));
      expect(s.R['cont'], 'fail');
      expect(s.vTitle, 'FAIL');
      expect(s.phase, 'fail');
      expect(s.can('hv').$1, isFalse);
    });

    test('progress paints the right bar', () {
      final s = newState();
      s.runKind = 'cont';
      s.onEvent(const msg.Progress(done: 3, total: 12));
      expect(s.dcBar, closeTo(0.25, 1e-9));
      expect(s.vElapsed, '3 / 12');

      s.runKind = 'res';
      s.onEvent(const msg.Progress(done: 6, total: 12));
      expect(s.drBar, closeTo(0.5, 1e-9));
    });

    test('a continuity failure raises F06 and shows in the fault list', () {
      final s = newState();
      // The F06 fault row names nets[4], so the model needs at least five.
      s.rebuildNets(const [
        msg.NetEntry(hi: 1, lo: 2),
        msg.NetEntry(hi: 3, lo: 4),
        msg.NetEntry(hi: 5, lo: 6),
        msg.NetEntry(hi: 7, lo: 8),
        msg.NetEntry(hi: 9, lo: 10),
      ]);
      s.onEvent(const msg.ContResult(
          hi: 1, lo: 2, status: proto.ContStatus.open));
      expect(s.nets[0].open, isTrue);
      expect(s.faultsOn['f06'], isTrue);
      expect(s.faultList.map((f) => f.code), contains('F06'));
      expect(s.faultCountPill.text, '1 open');
    });
  });

  // =========================================================================
  group('rebuildNets', () {
    test('maps instrument pins onto fixture connectors', () {
      final s = newState();
      s.rebuildNets(const [
        msg.NetEntry(hi: 1, lo: 2),
        msg.NetEntry(hi: 5, lo: 9),
      ]);
      expect(s.nets.length, 2);
      expect(s.netc, 2);
      expect(s.nlMtx.loaded, isTrue);
      expect(s.nlMtx.nets, 2);
      expect(s.nets[0].pinHi, 1);
      expect(s.nets[0].pinLo, 2);
      // GUI-11: pins 1 and 2 both land on the same physical connector (J1,
      // base 0, 37 pins in the default demo fixture) - real per-connector
      // lookup, not the old "hi always L-side pool, lo always R-side pool"
      // fabrication. `side` no longer implies which role a pin plays.
      expect(s.nets[0].src.c, 'J1');
      expect(s.nets[0].src.p, 1);
      expect(s.nets[0].dsts[0].c, 'J1');
      expect(s.nets[0].dsts[0].p, 2);
      expect(s.nets[1].name, 'NET_002');
    });

    test('an empty netlist marks the MTX file unloaded', () {
      final s = newState();
      s.rebuildNets(const []);
      expect(s.nlMtx.loaded, isFalse);
      expect(s.can('res').$1, isFalse);
    });
  });

  // =========================================================================
  group('netlist and stack bookkeeping', () {
    test('a stack mismatch is reported, not silently accepted', () {
      final s = newState();
      s.setStack(3);
      s.loadHv('AV-880_HV_4card.hnl', 4, 160);
      expect(s.stackMatch(), isFalse);
      expect(s.logs.last.message, contains('64 nets unreachable'));

      s.loadHv('AV-880_HV_3card.hnl', 3, 118);
      expect(s.stackMatch(), isTrue);
    });

    test('hvConnName follows the fitted stack', () {
      final s = newState();
      s.setStack(1);
      expect(s.hvConnName(), 'J-HV1');
      s.setStack(3);
      expect(s.hvConnName(), 'J-HV1–3');
    });

    test('the HV run flow asks for a netlist before it asks to energise', () {
      final s = newState();
      s.requestHv();
      expect(s.mdNlOpen, isTrue);
      expect(s.mdVerifyOpen, isFalse);

      s.pickHvFile(hvFilesFor(s.netc).first);
      expect(s.mdNlOpen, isFalse);
      expect(s.mdVerifyOpen, isTrue);
      // The acknowledgement starts unchecked every time.
      expect(s.ackChecked, isFalse);
    });

    test('the verification list reflects what actually passed', () {
      final s = newState();
      s.loadHv('AV-880_HV_3card.hnl', 3, 118);
      s.requestHv();
      final checks = s.verifyChecks;
      expect(checks[0].state, 'bad'); // continuity has not passed
      expect(checks[0].value, 'not passed');

      s.R['cont'] = 'pass';
      s.R['res'] = 'pass';
      expect(s.verifyChecks[0].state, 'ok');
      expect(s.verifyChecks[1].state, 'ok');
      expect(s.verifyChecks[3].state, 'ok'); // stack matches
    });
  });

  // =========================================================================
  group('reset', () {
    test('resetAll returns every latch to its idle value', () {
      final s = newState();
      s.R['cont'] = 'pass';
      s.R['res'] = 'pass';
      s.R['hv'] = 'fail';
      s.onHv = true;
      s.faultsOn['f04'] = true;
      s.hvLive = true;
      s.running = 'insul';

      s.resetAll();

      expect(s.R.values, everyElement(isNull));
      expect(s.onHv, isFalse);
      expect(s.faultsOn.values, everyElement(isFalse));
      expect(s.hvLive, isFalse);
      expect(s.running, isNull);
      expect(s.vTitle, 'READY');
      expect(s.phase, '');
      expect(s.stage2, 'lock');
    });
  });

  // =========================================================================
  group('port selector', () {
    test('refreshPorts populates the list and keeps a surviving choice', () {
      var listed = const [
        PortEntry('COM7', 'ST-LINK VCP'),
        PortEntry('COM4', 'USB Serial'),
      ];
      final cm = ConnectionManager(logDir: Directory.systemTemp);
      final s = AppState(
          cm: cm, host: '127.0.0.1', port: 46000, listPorts: () => listed);

      s.refreshPorts();
      expect(s.ports, listed);
      expect(s.selPort, 'COM7'); // the first port is preselected

      // The pending choice survives while its port is still there.
      s.selPort = 'COM4';
      s.refreshPorts();
      expect(s.selPort, 'COM4');

      // ... and is reseeded when its port disappears.
      listed = const [PortEntry('COM9', 'ST-LINK VCP')];
      s.refreshPorts();
      expect(s.selPort, 'COM9');

      listed = const [];
      s.refreshPorts();
      expect(s.selPort, isNull);
    });

    test('connectTo connects with the chosen host; disconnect drops the link',
        () async {
      final t = _FakeTransport();
      late final AppState s;
      final cm = ConnectionManager(
        onLinkState: (st, d) => s.onLinkState(st, d),
        transportFactory: () => t,
        logDir: Directory.systemTemp,
      );
      s = AppState(cm: cm, host: '127.0.0.1', port: 115200);
      addTearDown(cm.disconnect);

      s.connectTo('COM7');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(s.host, 'COM7');
      expect(s.selPort, 'COM7');
      expect(t.openedHost, 'COM7');
      expect(t.openedPort, 115200);
      expect(s.link, isTrue);

      s.armed = true;
      await s.disconnect();
      expect(s.link, isFalse);
      expect(s.armed, isFalse);
      expect(s.handling, 'unknown');
      expect(s.linkDetail, 'disconnected');
      expect(s.hvPill.text, 'Link lost');
      expect(s.statePill.text, 'State unknown');
    });
  });

  // =========================================================================
  group('the action button follows the design', () {
    test('label and style track the phase', () {
      final s = newState();
      expect(s.actButton.label, 'Run S1');

      s.R['cont'] = 'pass';
      expect(s.actButton.label, 'Reset');

      s.R['res'] = 'pass';
      expect(s.actButton.label, 'Move DUT');
      expect(s.actButton.disabled, isTrue);

      s.onEvent(const msg.FixtureEvent(fixture: proto.Fixture.hv));
      expect(s.actButton.label, 'Run HV');
      expect(s.actButton.style, 'hv');

      s.running = 'insul';
      expect(s.actButton.label, 'Stop');
      expect(s.actButton.style, 'stop');
    });
  });
}

// ---------------------------------------------------------------------------
// a transport the test drives by hand — same pattern as protocol_test.dart,
// plus a record of where open() was aimed
// ---------------------------------------------------------------------------

class _FakeTransport implements Transport {
  final StreamController<Uint8List> _ctl =
      StreamController<Uint8List>.broadcast();
  String? openedHost;
  int? openedPort;

  @override
  Future<void> open(String host, int port) async {
    openedHost = host;
    openedPort = port;
  }

  @override
  void send(List<int> data) {
    final body = ascii.decode(data).substring(1).trim();
    if (body == 'STATUS') {
      push('<STATUS state=idle fixture=mtx hv_mv=0\n');
    } else if (body == 'NETLIST GET') {
      push('<NETLIST 0\n');
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
