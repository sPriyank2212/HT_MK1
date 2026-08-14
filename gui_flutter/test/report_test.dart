/// `required_format`-shaped test report regression tests (`app/report.dart`).
///
/// Two layers: the CSV column/row shape against literal expected text (no
/// simulator needed — this is pure formatting), and one real-simulator,
/// real-`AppState` run proving the per-row detail that formatting depends on
/// actually gets captured while a run streams results in, not just that the
/// formatter is correct in isolation.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ht_mk1_gui/app/app_state.dart';
import 'package:ht_mk1_gui/app/report.dart';
import 'package:ht_mk1_gui/htproto/connection.dart';
import 'package:ht_mk1_gui/htproto/simulator.dart';

Future<void> waitUntil(bool Function() cond,
    {Duration timeout = const Duration(seconds: 5)}) async {
  final deadline = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('waitUntil timed out');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  group('ContReport.toCsv', () {
    test('matches the required_format column shape', () {
      final meta = ReportMeta(
        dutId: 'HT-0008',
        operatorName: '',
        netlistName: null,
        pass: false,
        when: DateTime(2026, 7, 27, 14, 11, 8),
      );
      final r = ContReport(meta, const [
        // No srcConnId/dstConnId given - GUI-11's '—' default (no netlist
        // loaded / connector unknown), same as before that field existed.
        ContReportRow(testNum: 1, srcPin: 1, dstPin: 1, status: 'NOT CONNECTED'),
        ContReportRow(
          testNum: 2,
          srcPin: 2,
          dstPin: 2,
          status: 'CONNECTED',
          srcConnId: 'J1',
          dstConnId: 'J2',
        ),
      ]);

      final lines = r.toCsv().split('\n');
      expect(lines[0], '# Harness Tester Results');
      expect(lines[1], '# DUT ID,HT-0008');
      expect(lines[2], '# Operator,');
      expect(lines[3], '# Netlist,');
      expect(lines[4], '# Verdict,FAIL');
      expect(lines[5], '# Date/Time,2026-07-27 14:11:08');
      expect(lines[6], '');
      expect(
        lines[7],
        'Test #,Source,Part Number,Conn ID,Src Pin Label,Src Pin #,Status,'
        'Dst Pin #,Dst Pin Label,Conn ID,Part Number,Destination',
      );
      expect(lines[8], '1,,,—,Pin 1,1,NOT CONNECTED,1,Pin 1,—,,');
      expect(lines[9], '2,,,J1,Pin 2,2,CONNECTED,2,Pin 2,J2,,');
    });

    test('connected counts only CONNECTED rows', () {
      final meta = ReportMeta(
        dutId: '',
        operatorName: '',
        netlistName: null,
        pass: true,
        when: DateTime(2026),
      );
      final r = ContReport(meta, const [
        ContReportRow(testNum: 1, srcPin: 1, dstPin: 1, status: 'CONNECTED'),
        ContReportRow(testNum: 2, srcPin: 2, dstPin: 2, status: 'NOT CONNECTED'),
        ContReportRow(testNum: 3, srcPin: 3, dstPin: 3, status: 'CONNECTED'),
      ]);
      expect(r.connected, 2);
    });
  });

  group('ResReport.toCsv', () {
    test('matches the required_format column shape, three-state status', () {
      final meta = ReportMeta(
        dutId: 'HT-0004',
        operatorName: '',
        netlistName: null,
        pass: false,
        when: DateTime(2026, 8, 10, 15),
      );
      final r = ResReport(meta, '2.000', '500', const [
        ResReportRow(
          testNum: 1,
          srcPin: 1,
          dstPin: 14,
          resistanceMohm: 42.3,
          status: 'PASS',
          srcConnId: 'J1',
          dstConnId: 'J2',
        ),
        // No srcConnId/dstConnId given - GUI-11's '—' default.
        ResReportRow(
            testNum: 2,
            srcPin: 3,
            dstPin: 10,
            resistanceMohm: 655.2,
            status: 'FAIL_HIGH'),
      ]);

      final lines = r.toCsv().split('\n');
      expect(lines[0], '# Harness Tester Results — Resistance');
      expect(lines[4], '# Excitation Current (mA),2.000');
      expect(lines[5], '# Resistance Limit (mOhm),500');
      expect(lines[6], '# Verdict,FAIL');
      expect(lines[8], '');
      expect(
        lines[9],
        'Test #,Source,Part Number,Conn ID,Src Pin Label,Src Pin #,'
        'Resistance (mOhm),Limit (mOhm),Status,Dst Pin #,Dst Pin Label,'
        'Conn ID,Part Number,Destination',
      );
      expect(lines[10], '1,,,J1,Pin 1,1,42.3,500,PASS,14,Pin 14,J2,,');
      expect(lines[11], '2,,,—,Pin 3,3,655.2,500,FAIL_HIGH,10,Pin 10,—,,');
    });
  });

  group('InsulReport.toCsv', () {
    test('matches the required_format column shape, per-net rows', () {
      final meta = ReportMeta(
        dutId: 'HT-0004',
        operatorName: '',
        netlistName: null,
        pass: false,
        when: DateTime(2026, 8, 10, 15, 4, 30),
      );
      final r = InsulReport(meta, '500', '10', const [
        InsulReportRow(
          testNum: 1,
          net: 'GND_RET',
          hvCard: 'H1',
          hsPin: 'HS-03',
          leakV: 0.052,
          insulationMohm: 3.2,
          status: 'FAIL',
        ),
      ]);

      final lines = r.toCsv().split('\n');
      expect(lines[0], '# Harness Tester Results — HV Insulation');
      expect(lines[4], '# HV Applied (V),500');
      expect(lines[5], '# Insulation Limit (MOhm),10');
      expect(lines[6], '# Verdict,FAIL');
      expect(lines[8], '');
      expect(
        lines[9],
        'Test #,Net,HV Card,HS Pin,Leak V,Insulation (MOhm),Limit (MOhm),'
        'Status',
      );
      expect(lines[10], '1,GND_RET,H1,HS-03,0.052,3.2,10,FAIL');
    });
  });

  // ===========================================================================
  // Real simulator, real AppState — proves the per-row capture that feeds
  // the report actually happens while a run streams results in, the same
  // pattern netlist_upload_test.dart uses for the netlist-upload fix.
  // ===========================================================================
  group('AppState builds a real report from a real run', () {
    late SimulatorServer sim;
    late ConnectionManager cm;
    late AppState s;

    Future<void> boot(String scenario, {int nets = 4}) async {
      sim = await SimulatorServer.start(
        makeScenario(scenario, nets: nets),
        port: 0,
        interval: const Duration(milliseconds: 1),
      );
      cm = ConnectionManager(
        onEvent: (m) => s.onEvent(m),
        onLinkState: (st, d) => s.onLinkState(st, d),
        logDir: Directory.systemTemp,
      );
      s = AppState(cm: cm, host: '127.0.0.1', port: sim.port);
    }

    tearDown(() async {
      await cm.disconnect();
      await sim.stop();
    });

    test('continuity: lastContReport has one row per real !CONT result',
        () async {
      await boot('pass', nets: 4);
      await s.connect();
      s.setDutId('HT-TEST');

      // Discover the simulator's real nets, upload them, then verify against
      // that real netlist - same sequence netlist_upload_test.dart proves.
      s.setMode('cross');
      await s.runCont();
      await waitUntil(() => s.running == null);
      await s.saveDiscoveredNetlist();

      expect(s.lastContReport, isNull,
          reason: 'discovery mode does not build a verify-mode report');

      s.setMode('net');
      await s.runCont();
      await waitUntil(() => s.running == null);

      final r = s.lastContReport;
      expect(r, isNotNull);
      expect(r!.rows.length, 4);
      expect(r.meta.dutId, 'HT-TEST');
      expect(r.meta.pass, s.R['cont'] == 'pass');
      // Real pins from the real netlist, not placeholders.
      expect(r.rows.every((row) => row.srcPin >= 1 && row.srcPin <= 256), isTrue);
      expect(r.rows.map((row) => row.testNum), [1, 2, 3, 4]);
      // GUI-11: every row resolves to a real connector under the default
      // fixture (which spans the full 1..256 range) - not the '—' fallback.
      expect(r.rows.every((row) => row.srcConnId != '—'), isTrue);
      expect(r.rows.every((row) => row.dstConnId != '—'), isTrue);
    });

    test('resistance: lastResReport carries real milliohm readings',
        () async {
      await boot('pass', nets: 4);
      await s.connect();

      s.setMode('cross');
      await s.runCont();
      await waitUntil(() => s.running == null);
      await s.saveDiscoveredNetlist();

      await s.runRes();
      await waitUntil(() => s.running == null);

      final r = s.lastResReport;
      expect(r, isNotNull);
      expect(r!.rows.length, 4);
      // The 'pass' scenario reports real, non-zero resistance readings.
      expect(r.rows.every((row) => row.resistanceMohm >= 0), isTrue);
      expect(r.limitMohm, isNot('—'), reason: 'LIMITS GET ran on connect');
    });
  });
}
