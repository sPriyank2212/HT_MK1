/// Build date/time stamps: the firmware reports when it was compiled in the
/// `>ID` reply (`build=YYYY-MM-DDTHH:MM:SS`, the build PC's clock), the GUI
/// carries its own, and both reach the operator.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ht_mk1_gui/app/app_state.dart';
import 'package:ht_mk1_gui/app/build_tag.dart';
import 'package:ht_mk1_gui/htproto/codec.dart';
import 'package:ht_mk1_gui/htproto/connection.dart';
import 'package:ht_mk1_gui/htproto/messages.dart';
import 'package:ht_mk1_gui/htproto/simulator.dart';

void main() {
  group('ID reply build stamp', () {
    test('is parsed when the firmware sends it', () {
      expect(
        parseLine('<ID HT_MK1 fw=0.1.0 proto=1 build=2026-10-22T18:30:12'),
        const IdReply(fw: '0.1.0', proto: 1, build: '2026-10-22T18:30:12'),
      );
    });

    test('older firmware without the field still parses', () {
      final m = parseLine('<ID HT_MK1 fw=0.1.0 proto=1') as IdReply;
      expect(m.build, isNull);
    });

    test('a malformed stamp is a protocol error, not silently shown', () {
      for (final bad in [
        '<ID HT_MK1 fw=0.1.0 proto=1 build=Oct 22 2026',
        '<ID HT_MK1 fw=0.1.0 proto=1 build=2026-10-22 18:30:12',
        '<ID HT_MK1 fw=0.1.0 proto=1 build=',
        '<ID HT_MK1 fw=0.1.0 proto=1 when=2026-10-22T18:30:12',
        '<ID HT_MK1 fw=0.1.0 proto=1 build=2026-10-22T18:30:12 extra',
      ]) {
        expect(() => parseLine(bad), throwsA(isA<ProtocolError>()), reason: bad);
      }
    });
  });

  group('display', () {
    test('a full stamp is shown without seconds', () {
      expect(prettyStamp('2026-10-22T18:30:12'), '2026-10-22 18:30');
    });

    test('anything else is passed through unchanged', () {
      expect(prettyStamp(kUnstamped), kUnstamped);
      expect(prettyStamp('whatever'), 'whatever');
    });
  });

  group('reaches the GUI (real simulator)', () {
    test('connect() records the firmware build stamp', () async {
      final sim = await SimulatorServer.start(makeScenario('pass', nets: 4),
          port: 0, interval: Duration.zero);
      late final AppState s;
      final cm = ConnectionManager(
        onEvent: (m) => s.onEvent(m),
        onLinkState: (st, d) => s.onLinkState(st, d),
        logDir: Directory.systemTemp,
      );
      s = AppState(cm: cm, host: '127.0.0.1', port: sim.port);
      addTearDown(() async {
        await cm.disconnect();
        await sim.stop();
      });

      expect(s.fwBuild, isNull);
      await s.connect();

      expect(s.fwBuild, isNotNull);
      expect(s.fwBuild, matches(RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$')));
      expect(s.logs.any((l) => l.message.contains('built')), isTrue);
    });
  });
}
