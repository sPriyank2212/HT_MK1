/// Protocol-layer tests, mirroring `gui/tests/test_codec.py`,
/// `test_connection.py` and `test_simulator.py`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ht_mk1_gui/htproto/codec.dart';
import 'package:ht_mk1_gui/htproto/connection.dart';
import 'package:ht_mk1_gui/htproto/messages.dart';
import 'package:ht_mk1_gui/htproto/simulator.dart';

String wire(Uint8List b) => ascii.decode(b);

void main() {
  // =========================================================================
  group('command encoders are byte-exact', () {
    test('simple commands', () {
      expect(wire(commands.ping()), '>PING\n');
      expect(wire(commands.identify()), '>ID\n');
      expect(wire(commands.status()), '>STATUS\n');
      expect(wire(commands.safe()), '>SAFE\n');
      expect(wire(commands.abort()), '>ABORT\n');
      expect(wire(commands.faultClear()), '>FAULT CLEAR\n');
      expect(wire(commands.netlistEnd()), '>NETLIST END\n');
      expect(wire(commands.netlistGet()), '>NETLIST GET\n');
      expect(wire(commands.resRun()), '>RES RUN\n');
      expect(wire(commands.insulArm()), '>INSUL ARM\n');
      expect(wire(commands.insulRun()), '>INSUL RUN\n');
      expect(wire(commands.manualOff()), '>MANUAL OFF\n');
      expect(wire(commands.calGet()), '>CAL GET\n');
      expect(wire(commands.calRun(3, 4)), '>CAL RUN 3 4\n');
      expect(wire(commands.limitsGet()), '>LIMITS GET\n');
      expect(wire(commands.tempRead()), '>TEMP READ\n');
      expect(wire(commands.busScan()), '>BUS SCAN\n');
    });

    test('parameterised commands', () {
      expect(wire(commands.netlistBegin(12)), '>NETLIST BEGIN 12\n');
      expect(wire(commands.netlistAdd(1, 256)), '>NETLIST ADD 1 256\n');
      expect(wire(commands.contRun(ContMode.verify)), '>CONT RUN verify\n');
      expect(wire(commands.contRun(ContMode.discover)), '>CONT RUN discover\n');
      expect(wire(commands.hvSet(500000)), '>HV SET 500000\n');
      expect(wire(commands.fixture(Fixture.hv)), '>FIXTURE hv\n');
      expect(wire(commands.manualPath(3, 4)), '>MANUAL PATH 3 4\n');
      expect(wire(commands.manualSweep(14)), '>MANUAL SWEEP 14\n');
      expect(wire(commands.manualRelay(0, 5, true)), '>MANUAL RELAY 0 5 1\n');
      expect(wire(commands.manualRelay(0, 5, false)), '>MANUAL RELAY 0 5 0\n');
      expect(wire(commands.limitsSet(1000, 100)),
          '>LIMITS SET r_max_mohm=1000 ins_min_mohm=100\n');
    });

    test('pins outside 1..256 are refused before they reach the wire', () {
      // brief 8.1 answer 1
      expect(() => commands.netlistAdd(0, 4), throwsA(isA<ProtocolError>()));
      expect(() => commands.netlistAdd(1, 257), throwsA(isA<ProtocolError>()));
      expect(() => commands.manualPath(-1, 4), throwsA(isA<ProtocolError>()));
      expect(() => commands.hvSet(-1), throwsA(isA<ProtocolError>()));
    });
  });

  // =========================================================================
  group('parseLine accepts the contract', () {
    test('replies', () {
      expect(parseLine('<PONG'), const Pong());
      expect(parseLine('<ID HT_MK1 fw=1.0.0 proto=1'),
          const IdReply(fw: '1.0.0', proto: 1));
      expect(
        parseLine('<STATUS state=idle fixture=mtx hv_mv=0'),
        const StatusReply(
            state: State.idle, fixture: Fixture.mtx, hvMv: 0),
      );
      expect(parseLine('<OK'), const Ok(detail: ''));
      expect(parseLine('<OK started'), const Ok(detail: 'started'));
      expect(parseLine('<ERR EBUSY a run is already in progress'),
          const ErrReply(code: 'EBUSY', text: 'a run is already in progress'));
      expect(parseLine('<NETLIST 3'), const NetlistReply(count: 3));
      expect(parseLine('<NET 1 2'), const NetEntry(hi: 1, lo: 2));
      expect(
        parseLine('<CAL current_ua=2000 method=ratiometric rref_mohm=100000 '
            'rref_tol_mohm=10 gain_max=128'),
        const CalReply(
          currentUa: 2000,
          method: 'ratiometric',
          rrefMohm: 100000,
          rrefTolMohm: 10,
          gainMax: 128,
        ),
      );
      expect(
        parseLine('<LIMITS r_max_mohm=1000 ins_min_mohm=100'),
        const LimitsReply(rMaxMohm: 1000, insMinMohm: 100),
      );
    });

    test('events', () {
      expect(parseLine('!PROGRESS 3 12'), const Progress(done: 3, total: 12));
      expect(parseLine('!CONT 1 2 pass'),
          const ContResult(hi: 1, lo: 2, status: ContStatus.pass));
      expect(
        parseLine('!RES 1 2 -5 fail_low'),
        const ResResult(
            hi: 1, lo: 2, milliohms: -5, status: ResStatus.failLow),
      );
      expect(parseLine('!INSUL 1 5 fail'),
          const InsulResult(net: 1, leakMohm: 5, status: InsulStatus.fail));
      expect(parseLine('!FAULT F04 insulation low on net 1'),
          const Fault(code: 'F04', text: 'insulation low on net 1'));
      expect(parseLine('!DONE cont 11 1'),
          const Done(kind: TestKind.cont, passed: 11, failed: 1));
      expect(parseLine('!STATE hv_armed'),
          const StateEvent(state: State.hvArmed));
      expect(parseLine('!FIXTURE none'),
          const FixtureEvent(fixture: Fixture.none));
      expect(parseLine('!HV 500000'), const HvEvent(millivolts: 500000));
      expect(parseLine('!TEMP 235'), const TempEvent(deciCelsius: 235));
      expect(parseLine('!MANUAL adc_mv=1500 adc_code=1862'),
          const ManualEvent(adcMv: 1500, adcCode: 1862));
      expect(parseLine('!BUSLINE U101 ok'),
          const BusLineEvent(name: 'U101', ok: true));
      expect(parseLine('!BUSLINE U69 fault'),
          const BusLineEvent(name: 'U69', ok: false));
      expect(parseLine('!DONE sweep 3 0'),
          const Done(kind: TestKind.sweep, passed: 3, failed: 0));
      expect(parseLine('!DONE bus 10 1'),
          const Done(kind: TestKind.bus, passed: 10, failed: 1));
      expect(
        parseLine('!CAL_RESULT r_mohm=45 ratiometric=1 pass'),
        const CalResultEvent(rMohm: 45, ratiometric: true, pass: true),
      );
      expect(
        parseLine('!CAL_RESULT r_mohm=12000 ratiometric=0 fail'),
        const CalResultEvent(rMohm: 12000, ratiometric: false, pass: false),
      );
      expect(parseLine('!SAFE'), const SafeEvent());
      expect(parseLine('# free text'), const LogLine(' free text'));
    });

    test('negative measurement values are legal (brief 8.4 finding 2)', () {
      final r = parseLine('!RES 1 2 -12 pass') as ResResult;
      expect(r.milliohms, -12);
      final i = parseLine('!INSUL 1 -3 pass') as InsulResult;
      expect(i.leakMohm, -3);
      final s = parseLine('<STATUS state=idle fixture=none hv_mv=-1')
          as StatusReply;
      expect(s.hvMv, -1);
    });
  });

  // =========================================================================
  group('parseLine rejects everything else', () {
    void bad(String line) {
      expect(() => parseLine(line), throwsA(isA<ProtocolError>()),
          reason: line);
    }

    test('structural errors', () {
      bad('');
      bad('PONG'); // no prefix
      bad('>PING'); // command prefix, not an instrument line
      bad('<PONG extra'); // wrong field count
      bad('<ID NOT_HT_MK1 fw=1.0.0 proto=1');
      bad('<ID HT_MK1 fw=1.0 proto=1'); // bad semver
      bad('<STATUS state=idle fixture=mtx'); // missing field
      bad('<STATUS fixture=mtx state=idle hv_mv=0'); // wrong field order
      bad('<STATUS state=nope fixture=mtx hv_mv=0'); // unknown enum
      bad('!PROGRESS 3'); // wrong field count
      bad('!PROGRESS x 12'); // non-integer
      bad('!PROGRESS -1 12'); // counts are unsigned
      bad('!CONT 1 2 maybe'); // unknown enum
      bad('!DONE cont 1'); // wrong field count
      bad('!SAFE now'); // SAFE takes no arguments
      bad('<WHAT'); // unrecognised reply
      bad('!WHAT'); // unrecognised event
    });
  });

  // =========================================================================
  group('LineFramer', () {
    test('splits on newlines and keeps partial lines pending', () {
      final f = LineFramer();
      expect(f.feed(ascii.encode('<PO')), isEmpty);
      expect(f.feed(ascii.encode('NG\n!SAFE\n')), ['<PONG', '!SAFE']);
      expect(f.pending, isEmpty);
    });

    test('strips a defensive trailing CR', () {
      final f = LineFramer();
      expect(f.feed(ascii.encode('<PONG\r\n')), ['<PONG']);
    });

    test('rejects non-ascii bytes', () {
      final f = LineFramer();
      expect(() => f.feed([0xff, 0x0a]), throwsA(isA<FormatException>()));
    });
  });

  // =========================================================================
  group('ConnectionManager', () {
    test('connect handshakes with >STATUS and reports what it says', () async {
      final t = FakeTransport();
      final cm = ConnectionManager(
          transportFactory: () => t, logDir: Directory.systemTemp);
      addTearDown(cm.disconnect);

      final status = await cm.connect(port: 1);
      expect(t.sent, ['>STATUS\n']);
      expect(status.state, State.idle);
      expect(cm.state, LinkState.connected);
    });

    test('a command times out and takes the link with it (3.5.1)', () async {
      final t = FakeTransport(autoStatus: true, autoElse: false);
      final states = <LinkState>[];
      final cm = ConnectionManager(
        transportFactory: () => t,
        commandTimeout: const Duration(milliseconds: 60),
        onLinkState: (s, _) => states.add(s),
        logDir: Directory.systemTemp,
      );
      addTearDown(cm.disconnect);
      await cm.connect(port: 1);

      await expectLater(
          cm.execute(commands.ping()), throwsA(isA<CommandTimeoutError>()));
      expect(cm.state, LinkState.linkLost);
      expect(states, contains(LinkState.linkLost));

      // Every later command raises until connect() is called again.
      await expectLater(
          cm.execute(commands.ping()), throwsA(isA<LinkLostError>()));
    });

    test('a closed port is link loss, never "idle" (3.5.3)', () async {
      final t = FakeTransport();
      final cm = ConnectionManager(
          transportFactory: () => t, logDir: Directory.systemTemp);
      addTearDown(cm.disconnect);
      await cm.connect(port: 1);

      t.closeIncoming();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(cm.state, LinkState.linkLost);
    });

    test('silence past the link timeout is link loss', () async {
      final t = FakeTransport();
      final cm = ConnectionManager(
        transportFactory: () => t,
        linkTimeout: const Duration(milliseconds: 80),
        logDir: Directory.systemTemp,
      );
      addTearDown(cm.disconnect);
      await cm.connect(port: 1);
      expect(cm.state, LinkState.connected);

      await Future<void>.delayed(const Duration(milliseconds: 220));
      expect(cm.state, LinkState.linkLost);
    });

    test('commands before connect raise NotConnectedError', () async {
      final cm = ConnectionManager(
          transportFactory: FakeTransport.new, logDir: Directory.systemTemp);
      await expectLater(
          cm.execute(commands.ping()), throwsA(isA<NotConnectedError>()));
    });

    test('netlistGet consumes the header and all <NET lines', () async {
      final t = FakeTransport();
      t.netlist = const [[1, 2], [3, 4], [5, 6]];
      final cm = ConnectionManager(
          transportFactory: () => t, logDir: Directory.systemTemp);
      addTearDown(cm.disconnect);
      await cm.connect(port: 1);

      final entries = await cm.netlistGet();
      expect(entries, const [
        NetEntry(hi: 1, lo: 2),
        NetEntry(hi: 3, lo: 4),
        NetEntry(hi: 5, lo: 6),
      ]);

      // A following command still matches its own reply.
      expect(await cm.execute(commands.ping()), const Pong());
    });

    test('events reach onEvent and never the reply queue', () async {
      final t = FakeTransport();
      final events = <Message>[];
      final cm = ConnectionManager(
        transportFactory: () => t,
        onEvent: events.add,
        logDir: Directory.systemTemp,
      );
      addTearDown(cm.disconnect);
      await cm.connect(port: 1);

      t.push('!PROGRESS 1 2\n# hello\n!SAFE\n');
      await Future<void>.delayed(Duration.zero);
      expect(events, const [
        Progress(done: 1, total: 2),
        LogLine(' hello'),
        SafeEvent(),
      ]);
    });

    test('a malformed line is surfaced and the link survives', () async {
      final t = FakeTransport();
      final errors = <String>[];
      final cm = ConnectionManager(
        transportFactory: () => t,
        onProtocolError: (raw, _) => errors.add(raw),
        logDir: Directory.systemTemp,
      );
      addTearDown(cm.disconnect);
      await cm.connect(port: 1);

      t.push('!NONSENSE 1 2 3\n');
      await Future<void>.delayed(Duration.zero);
      expect(errors, ['!NONSENSE 1 2 3']);
      expect(cm.state, LinkState.connected);
    });
  });

  // =========================================================================
  group('simulator', () {
    late SimulatorServer sim;
    late ConnectionManager cm;

    Future<void> boot(String scenario, {int nets = 12}) async {
      sim = await SimulatorServer.start(
        makeScenario(scenario, nets: nets),
        port: 0,
        interval: const Duration(milliseconds: 1),
      );
      cm = ConnectionManager(logDir: Directory.systemTemp);
    }

    tearDown(() async {
      await cm.disconnect();
      await sim.stop();
    });

    test('answers PING and ID', () async {
      await boot('pass');
      await cm.connect(port: sim.port);
      expect(await cm.execute(commands.ping()), const Pong());
      final id = await cm.execute(commands.identify()) as IdReply;
      expect(id.fw, fwVersion);
      expect(id.proto, protoVersion);
    });

    test('CONT RUN verify without a netlist is refused (8.1 answer 4)',
        () async {
      await boot('pass');
      await cm.connect(port: sim.port);
      final reply =
          await cm.execute(commands.contRun(ContMode.verify)) as ErrReply;
      expect(reply.code, 'ERANGE');
    });

    test('a netlist round-trips', () async {
      await boot('pass', nets: 4);
      await cm.connect(port: sim.port);
      await cm.execute(commands.netlistBegin(2));
      await cm.execute(commands.netlistAdd(1, 2));
      await cm.execute(commands.netlistAdd(3, 4));
      final end = await cm.execute(commands.netlistEnd()) as Ok;
      expect(end.detail, 'loaded=2');
      expect(await cm.netlistGet(),
          const [NetEntry(hi: 1, lo: 2), NetEntry(hi: 3, lo: 4)]);
    });

    test('arming is refused off the HV fixture (EFIXTURE)', () async {
      await boot('pass');
      await cm.connect(port: sim.port);
      final reply = await cm.execute(commands.insulArm()) as ErrReply;
      expect(reply.code, 'EFIXTURE');
    });

    test('HV SET is refused while not armed (8.1 answer 2)', () async {
      await boot('pass');
      await cm.connect(port: sim.port);
      final reply = await cm.execute(commands.hvSet(100000)) as ErrReply;
      expect(reply.code, 'ENOTARMED');
      // HV SET 0 is always accepted.
      expect(await cm.execute(commands.hvSet(0)), isA<Ok>());
    });

    test('MANUAL RELAY is refused by design (EHW)', () async {
      await boot('pass');
      await cm.connect(port: sim.port);
      final reply =
          await cm.execute(commands.manualRelay(0, 1, true)) as ErrReply;
      expect(reply.code, 'EHW');
    });

    test('a continuity run streams results and ends with !DONE last',
        () async {
      final events = <Message>[];
      sim = await SimulatorServer.start(
        makeScenario('opens_shorts', nets: 6),
        port: 0,
        interval: const Duration(milliseconds: 1),
      );
      cm = ConnectionManager(
          onEvent: events.add, logDir: Directory.systemTemp);
      await cm.connect(port: sim.port);

      await cm.execute(commands.netlistBegin(6));
      for (var i = 0; i < 6; i++) {
        await cm.execute(commands.netlistAdd(2 * i + 1, 2 * i + 2));
      }
      await cm.execute(commands.netlistEnd());
      await cm.execute(commands.contRun(ContMode.verify));

      final done = await _waitForDone(events);
      expect(done.kind, TestKind.cont);
      expect(done.failed, 3); // two opens and one short
      expect(done.passed, 3);
      // 8.1 answer 7: !DONE is the last event of every run.
      expect(events.last, isA<Done>());
      expect(events.whereType<ContResult>().length, 6);
    });

    test('MANUAL PATH reports its own reading via !MANUAL (GUI-06)', () async {
      final events = <Message>[];
      sim = await SimulatorServer.start(
        makeScenario('pass', nets: 4),
        port: 0,
        interval: const Duration(milliseconds: 1),
      );
      cm = ConnectionManager(onEvent: events.add, logDir: Directory.systemTemp);
      await cm.connect(port: sim.port);

      expect(await cm.execute(commands.manualPath(3, 4)), isA<Ok>());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final manual = events.whereType<ManualEvent>().single;
      expect(manual.adcMv, greaterThan(0));
      expect(manual.adcCode, greaterThan(0));
    });

    test('MANUAL SWEEP streams matches for one HS pin, ends with !DONE sweep',
        () async {
      final events = <Message>[];
      sim = await SimulatorServer.start(
        makeScenario('pass', nets: 6),
        port: 0,
        interval: const Duration(milliseconds: 1),
      );
      cm = ConnectionManager(onEvent: events.add, logDir: Directory.systemTemp);
      await cm.connect(port: sim.port);

      // The 'pass' scenario's fixed fake harness pairs hi=1 with lo=2.
      await cm.execute(commands.manualSweep(1));
      final done = await _waitForDone(events);
      expect(done.kind, TestKind.sweep);
      expect(done.passed, 1);
      final matches = events.whereType<ContResult>().toList();
      expect(matches, hasLength(1));
      expect(matches.single.hi, 1);
      expect(matches.single.lo, 2);
      // A sweep must never look like a real Continuity run finishing.
      expect(events.whereType<Done>().where((d) => d.kind == TestKind.cont),
          isEmpty);
    });

    test('BUS SCAN reports one line per probed device, ends with !DONE bus',
        () async {
      final events = <Message>[];
      sim = await SimulatorServer.start(
        makeScenario('pass', nets: 4),
        port: 0,
        interval: const Duration(milliseconds: 1),
      );
      cm = ConnectionManager(onEvent: events.add, logDir: Directory.systemTemp);
      await cm.connect(port: sim.port);

      await cm.execute(commands.busScan());
      final done = await _waitForDone(events);
      expect(done.kind, TestKind.bus);
      expect(done.failed, 0);
      final lines = events.whereType<BusLineEvent>().toList();
      expect(lines.length, done.passed);
      expect(lines.every((l) => l.ok), isTrue);
      expect(lines.map((l) => l.name), contains('U68'));
    });

    test('CAL RUN reports a standalone ratiometric result, no !DONE',
        () async {
      final events = <Message>[];
      sim = await SimulatorServer.start(
        makeScenario('pass', nets: 4),
        port: 0,
        interval: const Duration(milliseconds: 1),
      );
      cm = ConnectionManager(onEvent: events.add, logDir: Directory.systemTemp);
      await cm.connect(port: sim.port);

      expect(await cm.execute(commands.calRun(3, 4)), isA<Ok>());
      await Future<void>.delayed(const Duration(milliseconds: 60));

      final result = events.whereType<CalResultEvent>().single;
      expect(result.ratiometric, isTrue);
      expect(result.pass, isTrue);
      // One measurement, not a run - no !DONE.
      expect(events.whereType<Done>(), isEmpty);
    });

    test('insulation reports a fault and discharges before !DONE', () async {
      final events = <Message>[];
      sim = await SimulatorServer.start(
        makeScenario('insul_fail', nets: 4),
        port: 0,
        interval: const Duration(milliseconds: 1),
      );
      cm = ConnectionManager(
          onEvent: events.add, logDir: Directory.systemTemp);
      await cm.connect(port: sim.port);

      await cm.execute(commands.fixture(Fixture.hv));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(await cm.execute(commands.insulArm()), isA<Ok>());
      await cm.execute(commands.insulRun());

      final done = await _waitForDone(events, timeout: const Duration(seconds: 8));
      expect(done.kind, TestKind.insul);
      expect(done.failed, 1);
      expect(events.whereType<Fault>().map((f) => f.code), contains('F04'));
      // The rail is back down and !SAFE went out before !DONE.
      final safeIndex = events.lastIndexWhere((e) => e is SafeEvent);
      final doneIndex = events.lastIndexWhere((e) => e is Done);
      expect(safeIndex, lessThan(doneIndex));
      expect((events.whereType<HvEvent>().last).millivolts, 0);
    });

    test('the disconnect scenario drops the link with no !DONE', () async {
      final events = <Message>[];
      final states = <LinkState>[];
      sim = await SimulatorServer.start(
        makeScenario('disconnect', nets: 8),
        port: 0,
        interval: const Duration(milliseconds: 1),
      );
      cm = ConnectionManager(
        onEvent: events.add,
        onLinkState: (s, _) => states.add(s),
        logDir: Directory.systemTemp,
      );
      await cm.connect(port: sim.port);
      await cm.execute(commands.resRun());

      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (cm.state == LinkState.connected &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(cm.state, LinkState.linkLost);
      expect(events.whereType<Done>(), isEmpty);
    });
  });
}

Future<Done> _waitForDone(
  List<Message> events, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final done = events.whereType<Done>();
    if (done.isNotEmpty) return done.first;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  throw StateError('no !DONE within $timeout; saw $events');
}

// ---------------------------------------------------------------------------
// a transport the test drives by hand
// ---------------------------------------------------------------------------

class FakeTransport implements Transport {
  final StreamController<Uint8List> _ctl =
      StreamController<Uint8List>.broadcast();
  final List<String> sent = <String>[];

  /// Reply to `>STATUS` automatically, so `connect()` completes.
  final bool autoStatus;

  /// Reply to everything else automatically too.
  final bool autoElse;

  List<List<int>> netlist = const [];

  FakeTransport({this.autoStatus = true, this.autoElse = true});

  @override
  Future<void> open(String host, int port) async {}

  @override
  void send(List<int> data) {
    final line = ascii.decode(data);
    sent.add(line);
    final body = line.substring(1).trim();
    if (body == 'STATUS') {
      if (autoStatus) push('<STATUS state=idle fixture=mtx hv_mv=0\n');
      return;
    }
    if (!autoElse) return;
    if (body == 'NETLIST GET') {
      push('<NETLIST ${netlist.length}\n');
      for (final p in netlist) {
        push('<NET ${p[0]} ${p[1]}\n');
      }
      return;
    }
    push('<PONG\n');
  }

  void push(String text) {
    if (!_ctl.isClosed) _ctl.add(Uint8List.fromList(ascii.encode(text)));
  }

  void closeIncoming() {
    if (!_ctl.isClosed) _ctl.close();
  }

  @override
  Stream<Uint8List> get incoming => _ctl.stream;

  @override
  Future<void> close() async => closeIncoming();
}
