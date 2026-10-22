/// The `test_netlists/HW-*.xlsx` harness scenarios
/// (`test_netlists/generate_harness_scenarios.py`), loaded through the real
/// parser and the real `AppState` pipeline.
///
/// What this pins, per scenario: every connector type the diagram supports is
/// guessed, each harness END has its own connectors (a designator at both ends
/// is two connectors), every pin resolves onto a connector, no wire collapses
/// to a zero-length line, and rows that share a net name become the right
/// joint — Y branch, merge, multi-drop node, inline splice.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ht_mk1_gui/app/app_state.dart';
import 'package:ht_mk1_gui/design/model.dart';
import 'package:ht_mk1_gui/design/painters.dart';
import 'package:ht_mk1_gui/design/tokens.dart';
import 'package:ht_mk1_gui/htproto/codec.dart' as proto;
import 'package:ht_mk1_gui/htproto/connection.dart';
import 'package:ht_mk1_gui/htproto/messages.dart' as msg;
import 'package:ht_mk1_gui/htproto/netlist_file.dart';
import 'package:ht_mk1_gui/main.dart';

class _FakeTransport implements Transport {
  final StreamController<Uint8List> _ctl =
      StreamController<Uint8List>.broadcast();

  @override
  Future<void> open(String host, int port) async {}

  @override
  void send(List<int> data) {
    final body = ascii.decode(data).substring(1).trim();
    String? reply;
    if (body == 'STATUS') {
      reply = '<STATUS state=idle fixture=none hv_mv=0\n';
    } else if (body == 'NETLIST GET') {
      reply = '<NETLIST 0\n';
    } else if (body == 'CAL GET') {
      reply =
          '<CAL current_ua=2000 method=ratiometric rref_mohm=100000 rref_tol_mohm=10 gain_max=128\n';
    } else if (body == 'LIMITS GET') {
      reply = '<LIMITS r_max_mohm=5000 ins_min_mohm=10000000\n';
    } else if (body.startsWith('NETLIST BEGIN') ||
        body.startsWith('NETLIST ADD') ||
        body == 'NETLIST END') {
      reply = '<OK\n';
    } else {
      reply = '<ERR ENOTSUP not supported by the fake\n';
    }
    if (!_ctl.isClosed) _ctl.add(Uint8List.fromList(ascii.encode(reply)));
  }

  @override
  Stream<Uint8List> get incoming => _ctl.stream;

  @override
  Future<void> close() async {
    if (!_ctl.isClosed) _ctl.close();
  }
}

String _path(String file) =>
    '${Directory.current.path}/../test_netlists/$file';

Uint8List _bytes(String file) => File(_path(file)).readAsBytesSync();

GuessedConnector _at(List<GuessedConnector> f, String side, String id) =>
    f.firstWhere((c) => c.side == side && c.id == id,
        orElse: () => throw StateError('no $side "$id"'));

void main() {
  tearDown(() => setActiveFixture(buildDefaultFixture()));

  // -------------------------------------------------------------------------
  // straight off the parser: connector ends, types and pin counts
  // -------------------------------------------------------------------------
  group('parser', () {
    test('HW-01 D-sub family: five connectors PER END, all dsub, mated '
        'designators repeated at both ends', () {
      final p = parseNetlistWorkbook(
          _bytes('HW-01_dsub_family_mated_pairs.xlsx'),
          fileName: 'HW-01');
      expect(p.pairs.length, 136);
      final f = p.fixture!;
      expect(f.length, 10);
      const sizes = {'DB9-1': 9, 'DB15-1': 15, 'DB25-1': 25, 'DB37-1': 37, 'DB50-1': 50};
      for (final side in ['src', 'dst']) {
        sizes.forEach((id, pins) {
          final c = _at(f, side, id);
          expect(c.pins, pins, reason: '$side $id');
          expect(c.shapeGuess, 'dsub', reason: '$side $id');
          expect(c.exceedsPart, isFalse, reason: '$side $id');
        });
      }
    });

    test('HW-02 circular: MS3116, MIL-38999, M12 and M8 all guess circ', () {
      final p = parseNetlistWorkbook(_bytes('HW-02_circular_connectors.xlsx'),
          fileName: 'HW-02');
      final f = p.fixture!;
      for (final c in f) {
        expect(c.shapeGuess, 'circ', reason: '${c.side} ${c.id} ${c.partNumber}');
      }
      expect(_at(f, 'src', 'J1').pins, 19);
      expect(_at(f, 'src', 'J3').pins, 8);
      expect(_at(f, 'src', 'J4').pins, 3);
    });

    test('HW-03 rectangular: CPC, Mini-Fit, Deutsch, JST, Amphenol all '
        'guess rect, and five connectors gather into three', () {
      final p = parseNetlistWorkbook(_bytes('HW-03_rectangular_connectors.xlsx'),
          fileName: 'HW-03');
      final f = p.fixture!;
      expect(f.where((c) => c.side == 'src').length, 5);
      expect(f.where((c) => c.side == 'dst').length, 3);
      for (final c in f) {
        expect(c.shapeGuess, 'rect', reason: '${c.side} ${c.id} ${c.partNumber}');
      }
    });

    test('HW-04: terminal blocks, RJ45/RJ11 and USB each get their own '
        'family', () {
      final p = parseNetlistWorkbook(
          _bytes('HW-04_terminal_blocks_and_modular_jacks.xlsx'),
          fileName: 'HW-04');
      final f = p.fixture!;
      for (final id in ['TB1', 'TB2']) {
        expect(_at(f, 'src', id).shapeGuess, 'term', reason: id);
      }
      for (final id in ['ETH1', 'ETH2', 'TEL1', 'USB1']) {
        expect(_at(f, 'src', id).shapeGuess, 'mod', reason: id);
      }
    });

    test('HW-08 mixed: every family appears in one harness', () {
      final p = parseNetlistWorkbook(_bytes('HW-08_mixed_avionics_harness.xlsx'),
          fileName: 'HW-08');
      final shapes = p.fixture!.map((c) => c.shapeGuess).toSet();
      expect(shapes, {'circ', 'dsub', 'rect', 'term', 'mod'});
    });

    test('the joint a Connector Detail declares', () {
      expect(kindFromDetail('inline butt splice'), 'I');
      expect(kindFromDetail('Y branch 2 of 3'), 'Y');
      expect(kindFromDetail('straight'), isNull);
      expect(kindFromDetail('crossed pin 5 -> 8'), isNull);
      expect(kindFromDetail(null), isNull);
    });
  });

  // -------------------------------------------------------------------------
  // through AppState: nets, joints, geometry
  // -------------------------------------------------------------------------
  group('loaded into the app', () {
    late AppState s;
    late ConnectionManager cm;

    Future<void> load(String file) async {
      final t = _FakeTransport();
      cm = ConnectionManager(
        onEvent: (m) => s.onEvent(m),
        onLinkState: (st, d) => s.onLinkState(st, d),
        transportFactory: () => t,
        logDir: Directory.systemTemp,
      );
      s = AppState(
        cm: cm,
        host: '127.0.0.1',
        port: 46000,
        pickNetlistFile: () async => (file, _bytes(file)),
      );
      await s.connect();
      await s.browseMtxNetlist();
      // the operator accepts the guess as-is
      s.confirmFixtureGuess(List<ConnectorDef>.of(kFix.connectors));
    }

    tearDown(() => cm.disconnect());

    const files = [
      'HW-01_dsub_family_mated_pairs.xlsx',
      'HW-02_circular_connectors.xlsx',
      'HW-03_rectangular_connectors.xlsx',
      'HW-04_terminal_blocks_and_modular_jacks.xlsx',
      'HW-05_y_joints_branch_and_merge.xlsx',
      'HW-06_inline_splices_crossed_and_spares.xlsx',
      'HW-07_multidrop_buses.xlsx',
      'HW-08_mixed_avionics_harness.xlsx',
      'HW-09_density_stress_5_types.xlsx',
    ];

    for (final file in files) {
      test('$file: every pin resolves and no wire collapses', () async {
        await load(file);
        expect(s.nets, isNotEmpty);

        // every pin of every net sits on a real connector of the right END
        for (final n in s.nets) {
          for (final p in n.srcs) {
            expect(p.c, isNot('?'), reason: '${n.name} src $p');
            expect(kConn[p.c]!.side, 'L', reason: '${n.name} source is Side A');
          }
          for (final d in n.dsts) {
            expect(d.c, isNot('?'), reason: '${n.name} dst $d');
            expect(kConn[d.c]!.side, 'R', reason: '${n.name} destination is Side B');
          }
        }

        // every wire has real length, left to right
        for (final n in s.nets) {
          final parts = netSegments(n);
          expect(parts.segs, isNotEmpty);
          for (final line in parts.segs) {
            var length = 0.0;
            for (var i = 1; i < line.length; i++) {
              length += (line[i].x - line[i - 1].x).abs() +
                  (line[i].y - line[i - 1].y).abs();
              // routed like a schematic: every leg is horizontal or vertical
              expect(
                  line[i].x == line[i - 1].x || line[i].y == line[i - 1].y,
                  isTrue,
                  reason: '${n.name}: a diagonal leg');
            }
            expect(length, greaterThan(10),
                reason: '${n.name}: a zero-length wire');
          }
        }

        // the connectors do not overlap inside their column
        for (final column in [kConnsL, kConnsR]) {
          final sorted = List<ConnectorDef>.of(column)
            ..sort((a, b) => a.y.compareTo(b.y));
          for (var i = 1; i < sorted.length; i++) {
            expect(sorted[i].y, greaterThanOrEqualTo(sorted[i - 1].y + sorted[i - 1].h),
                reason: '${sorted[i].name} overlaps ${sorted[i - 1].name}');
          }
        }
        // ...and the pair count matches what was uploaded
        expect(s.netc, parseNetlistWorkbook(_bytes(file), fileName: file).pairs.length);
      });
    }

    test('HW-05: 1->N branches and N->1 merges are Y joints; the rest plain',
        () async {
      await load('HW-05_y_joints_branch_and_merge.xlsx');
      final byName = {for (final n in s.nets) n.name: n};

      final pwr = byName['PWR_28V']!;
      expect(pwr.joint, 'Y');
      expect(pwr.srcs.length, 1);
      expect(pwr.dsts.length, 4);
      expect(pwr.pairs.length, 4);

      expect(byName['GND_BUS']!.dsts.length, 6);
      expect(byName['SENSE_5V']!.dsts.length, 3);
      expect(byName['SHIELD']!.dsts.length, 2);

      final merge = byName['RTN_VALVES']!;
      expect(merge.joint, 'Y');
      expect(merge.srcs.length, 5);
      expect(merge.dsts.length, 1);

      expect(s.nets.where((n) => n.joint == 'Y').length, 6);
      // pin labels from the file landed on the connectors
      expect(kConn['TB-IN']!.pinLabels[1], '28V_IN');
    });

    test('HW-07: buses are multi-drop nodes, a 1x3 is a Y', () async {
      await load('HW-07_multidrop_buses.xlsx');
      final byName = {for (final n in s.nets) n.name: n};
      for (final bus in ['CAN_H', 'CAN_L', 'GND_BUS', 'PWR_24V']) {
        expect(byName[bus]!.joint, 'M', reason: bus);
        expect(byName[bus]!.srcs.length, greaterThan(1), reason: bus);
        expect(byName[bus]!.dsts.length, greaterThan(1), reason: bus);
      }
      expect(byName['CAN_H']!.srcs.length, 2);
      expect(byName['CAN_H']!.dsts.length, 3);
      expect(byName['RS485_A']!.joint, 'Y');
      expect(byName['RS485_A']!.dsts.length, 3);
    });

    test('HW-06: inline splices are I joints, crossed wires stay plain',
        () async {
      await load('HW-06_inline_splices_crossed_and_spares.xlsx');
      final splices = s.nets.where((n) => n.joint == 'I').toList();
      expect(splices.length, 9);
      for (final n in splices) {
        expect(n.srcs.length, 1);
        expect(n.dsts.length, 1);
      }
      final swap = s.nets.firstWhere((n) => n.name == 'SWAP_5_6');
      expect(swap.joint, isNull);
      expect(swap.detail, startsWith('crossed'));
    });

    test('a mated pair draws as two connectors, one per end, and its wires '
        'run across the canvas', () async {
      await load('HW-01_dsub_family_mated_pairs.xlsx');
      expect(kConnsL.map((c) => c.name),
          ['DB9-1', 'DB15-1', 'DB25-1', 'DB37-1', 'DB50-1']);
      expect(kConnsR.map((c) => c.name),
          ['DB9-1', 'DB15-1', 'DB25-1', 'DB37-1', 'DB50-1']);
      // internal keys stay unique even though the designators repeat
      expect(kConn.length, 10);
      final n = s.nets.first;
      expect(pinXY(n.src).x, lessThan(kCanvasW / 2));
      expect(pinXY(n.dsts.first).x, greaterThan(kCanvasW / 2));
    });

    test('only the failed branch of a Y is marked open', () async {
      await load('HW-05_y_joints_branch_and_merge.xlsx');
      final pwr = s.nets.firstWhere((n) => n.name == 'PWR_28V');
      final bad = pwr.pairs[2]; // the third branch

      // the run reports each branch in turn: three connect, the third is open
      for (final p in pwr.pairs) {
        s.onEvent(msg.ContResult(
            hi: p.hi,
            lo: p.lo,
            status: identical(p, bad)
                ? proto.ContStatus.open
                : proto.ContStatus.pass));
      }
      expect(pwr.open, isTrue);
      expect(pwr.openPairs, {bad.key});
      expect(pwr.pinOpen(bad.dst), isTrue);
      expect(pwr.pinOpen(pwr.pairs[0].dst), isFalse);
      expect(pwr.pinOpen(pwr.pairs[1].dst), isFalse);

      // the diagram colours that branch alone
      s.tested = true;
      s.faultsOn['f06'] = true;
      final st = DiagState(
        nets: s.nets,
        netAt: s.netAt,
        tested: true,
        faultF06: true,
      );
      expect(st.netState(pwr), 'fail');
      expect(st.branchState(pwr, bad.dst), 'fail');
      expect(st.branchState(pwr, pwr.pairs[0].dst), 'pass');

      // before any result, a wire is simply not tested
      final fresh = s.nets.firstWhere((n) => n.name == 'GND_BUS');
      expect(st.netState(fresh), 'idle');
      expect(st.branchState(fresh, fresh.pairs[0].dst), 'idle');

      // a later pass on that pair clears it
      s.onEvent(msg.ContResult(
          hi: bad.hi, lo: bad.lo, status: proto.ContStatus.pass));
      expect(pwr.open, isFalse);
      expect(pwr.openPairs, isEmpty);
    });

    test('report rows name the right connector at each end of a Y branch',
        () async {
      await load('HW-05_y_joints_branch_and_merge.xlsx');
      final pwr = s.nets.firstWhere((n) => n.name == 'PWR_28V');
      final branch = pwr.pairs[3]; // lands on TB-OUT

      s.cmode = 'net';
      s.runKind = 'cont';
      s.onEvent(msg.ContResult(
          hi: branch.hi, lo: branch.lo, status: proto.ContStatus.pass));
      final row = s.contRowsLive.last;
      expect(row.srcConnId, 'TB-IN');
      expect(row.dstConnId, 'TB-OUT');
      expect(row.dstPinLabel, '28V_TB');
    });
  });
  // -------------------------------------------------------------------------
  // painted for real: the wiring diagram on screen, at several window sizes
  // -------------------------------------------------------------------------
  group('wiring diagram renders', () {
    Widget harness(AppState s, {required bool dark}) => HtTheme(
          isDark: dark,
          child: Builder(
            builder: (context) => Directionality(
              textDirection: TextDirection.ltr,
              child: MediaQuery(
                data: MediaQueryData.fromView(View.of(context)),
                child: DefaultTextStyle(
                  style: context.type.body,
                  child: HtHome(state: s, onToggleTheme: () {}),
                ),
              ),
            ),
          ),
        );

    for (final file in [
      'HW-01_dsub_family_mated_pairs.xlsx',
      'HW-05_y_joints_branch_and_merge.xlsx',
      'HW-07_multidrop_buses.xlsx',
      'HW-08_mixed_avionics_harness.xlsx',
      'HW-09_density_stress_5_types.xlsx',
    ]) {
      for (final size in const [Size(1480, 940), Size(1000, 900), Size(800, 900)]) {
        for (final dark in [true, false]) {
          testWidgets('$file at ${size.width.toInt()}x${size.height.toInt()} '
              '${dark ? "dark" : "light"}', (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.reset);

            late AppState s;
            await tester.runAsync(() async {
              final t = _FakeTransport();
              final cm = ConnectionManager(
                onEvent: (m) => s.onEvent(m),
                onLinkState: (st, d) => s.onLinkState(st, d),
                transportFactory: () => t,
                logDir: Directory.systemTemp,
              );
              s = AppState(
                cm: cm,
                host: '127.0.0.1',
                port: 46000,
                pickNetlistFile: () async => (file, _bytes(file)),
              );
              addTearDown(cm.disconnect);
              await s.connect();
              await s.browseMtxNetlist();
              s.confirmFixtureGuess(List<ConnectorDef>.of(kFix.connectors));
            });
            // some results, a hover and a selection, so every paint path runs
            for (final n in s.nets.take(6)) {
              for (final p in n.pairs) {
                s.onEvent(msg.ContResult(
                    hi: p.hi,
                    lo: p.lo,
                    status: n.name.hashCode.isEven
                        ? proto.ContStatus.pass
                        : proto.ContStatus.open));
              }
            }
            s.hoverNet = s.nets.first;
            s.selNet = s.nets[s.nets.length ~/ 2];
            s.go('cont');

            await tester.pumpWidget(harness(s, dark: dark));
            await tester.pump(const Duration(milliseconds: 300));
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  });
}
