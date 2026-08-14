/// `AppState.browseMtxNetlist` / `browseHvNetlist` regression tests — the
/// AppState half of "Browse the file system…" now reads a real file instead
/// of doing nothing (`lib/app/modals.dart`'s button used to have
/// `onTap: () {}`). `netlist_file_test.dart` already proves the parser;
/// `netlist_select_flow_test.dart` proves the MTX modal's buttons actually
/// reach AppState. This file proves what AppState does once a file is
/// picked: MTX pairs go out over the wire exactly like a saved
/// cross-continuity scan does, HV metadata never touches the wire at all
/// (there is no HV-netlist wire command — see
/// `Doc/GUI_protocol_command_coverage.md`), and a malformed file fails
/// loudly instead of silently.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ht_mk1_gui/app/app_state.dart';
import 'package:ht_mk1_gui/design/model.dart';
import 'package:ht_mk1_gui/htproto/connection.dart';

Uint8List _workbook(List<List<CellValue?>> rows) {
  final book = Excel.createExcel();
  final sheet = book.getDefaultSheet()!;
  for (final row in rows) {
    book.appendRow(sheet, row);
  }
  return Uint8List.fromList(book.encode()!);
}

/// Answers `STATUS`/`NETLIST GET`/`CAL GET`/`LIMITS GET` so `connect()`
/// succeeds, plus `NETLIST BEGIN/ADD/END`, recording every command sent.
class _FakeTransport implements Transport {
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
    } else if (body.startsWith('NETLIST BEGIN')) {
      push('<OK\n');
    } else if (body.startsWith('NETLIST ADD')) {
      push('<OK\n');
    } else if (body == 'NETLIST END') {
      push('<OK loaded=${sent.where((s) => s.startsWith('NETLIST ADD')).length}\n');
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

void main() {
  // kFix (design/model.dart) is process-global mutable state now
  // (setActiveFixture, GUI-11) — reset it after every test so one test's
  // fixture guess never leaks into the next.
  tearDown(() => setActiveFixture(buildDefaultFixture()));

  group('browseMtxNetlist', () {
    late _FakeTransport t;
    late AppState s;
    late ConnectionManager cm;

    Future<void> boot({
      required Future<(String, Uint8List)?> Function() pickNetlistFile,
    }) async {
      t = _FakeTransport();
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
        pickNetlistFile: pickNetlistFile,
      );
      await s.connect();
    }

    tearDown(() => cm.disconnect());

    test('uploads real (hi, lo) pairs via NETLIST BEGIN/ADD/END, same as a '
        'saved cross-continuity scan', () async {
      final bytes = _workbook([
        [TextCellValue('NET'), TextCellValue('HI'), TextCellValue('LO')],
        [TextCellValue('PWR_28V_A'), IntCellValue(1), IntCellValue(2)],
        [TextCellValue('GND_RET'), IntCellValue(3), IntCellValue(4)],
      ]);
      await boot(pickNetlistFile: () async => ('harness.xlsx', bytes));

      await s.browseMtxNetlist();

      expect(
        t.sent,
        containsAllInOrder([
          'NETLIST BEGIN 2',
          'NETLIST ADD 1 2',
          'NETLIST ADD 3 4',
          'NETLIST END',
        ]),
      );
      expect(s.nlMtx.loaded, isTrue);
      expect(s.nlMtx.name, 'harness.xlsx');
      expect(s.nlMtx.origin, 'file');
      expect(s.nets.length, 2);
      expect(s.mdMtxOpen, isFalse);
    });

    test('GUI-11: a file with Conn ID/Part Number columns applies a guessed '
        'connector layout and opens the confirmation panel', () async {
      final bytes = _workbook([
        [
          TextCellValue('NET'), TextCellValue('Conn ID'),
          TextCellValue('Part Number'), TextCellValue('HI'),
          TextCellValue('LO'), TextCellValue('Conn ID B'),
          TextCellValue('Part Number B'),
        ],
        [
          TextCellValue('A'), TextCellValue('J1'), TextCellValue('DB9-M'),
          IntCellValue(1), IntCellValue(1), TextCellValue('J1'),
          TextCellValue('DB9-M'),
        ],
        [
          TextCellValue('B'), TextCellValue('J1'), TextCellValue('DB9-M'),
          IntCellValue(2), IntCellValue(10), TextCellValue('J2'),
          TextCellValue('MS3116-Circular'),
        ],
      ]);
      await boot(pickNetlistFile: () async => ('guessed.xlsx', bytes));
      final before = kFix;

      await s.browseMtxNetlist();

      expect(s.mdFixtureOpen, isTrue);
      expect(s.fixtureBeforeGuess, same(before));
      expect(kFix.connectors.map((c) => c.id), ['J1', 'J2']);
      expect(kFix.connectors[0].type, ConnType.dsub);
      expect(kFix.connectors[1].type, ConnType.circ);
      // Applied optimistically - real per-pin lookup already resolves
      // against it, not the old modulo fabrication.
      expect(s.nets[0].src.c, 'J1');

      // Cancel reverts to the fixture that was active before the guess.
      s.cancelFixtureGuess();
      expect(kFix, same(before));
      expect(s.mdFixtureOpen, isFalse);
      expect(s.fixtureBeforeGuess, isNull);
    });

    test('GUI-11: confirming the guess with edits applies the edited '
        'connectors, not the raw guess', () async {
      final bytes = _workbook([
        [
          TextCellValue('Conn ID'), TextCellValue('Part Number'),
          TextCellValue('HI'), TextCellValue('LO'), TextCellValue('Conn ID B'),
          TextCellValue('Part Number B'),
        ],
        [
          TextCellValue('P1'), TextCellValue('AMP-9'), IntCellValue(1),
          IntCellValue(2), TextCellValue('P1'), TextCellValue('AMP-9'),
        ],
      ]);
      await boot(pickNetlistFile: () async => ('guessed2.xlsx', bytes));
      await s.browseMtxNetlist();
      expect(kFix.connectors.single.type, ConnType.rect); // raw guess

      final edited = kFix.connectors
          .map((c) => ConnectorDef(
                id: c.id,
                label: 'Operator label',
                type: ConnType.dsub, // operator corrected the shape
                pins: c.pins,
                side: c.side,
                base: c.base,
              ))
          .toList();
      s.confirmFixtureGuess(edited);

      expect(s.mdFixtureOpen, isFalse);
      expect(s.fixtureBeforeGuess, isNull);
      expect(kFix.connectors.single.type, ConnType.dsub);
      expect(kFix.connectors.single.label, 'Operator label');
    });

    test('operator cancelling the file dialog sends nothing and changes '
        'nothing', () async {
      await boot(pickNetlistFile: () async => null);
      s.openMtxNlExplainer();
      final sentAtConnect = List<String>.from(t.sent);

      await s.browseMtxNetlist();

      expect(t.sent, sentAtConnect,
          reason: 'nothing beyond the connect handshake should be sent');
      expect(s.nlMtx.loaded, isFalse,
          reason: 'connect() already cleared the pre-connection placeholder');
      expect(s.mdMtxOpen, isTrue,
          reason: 'a cancelled pick must leave the modal exactly as it was');
    });

    test('a malformed file fails loudly instead of silently and uploads '
        'nothing', () async {
      final bytes = _workbook([
        [TextCellValue('FOO'), TextCellValue('BAR')],
        [IntCellValue(1), IntCellValue(2)],
      ]);
      await boot(pickNetlistFile: () async => ('bad.xlsx', bytes));
      final sentAtConnect = List<String>.from(t.sent);

      await s.browseMtxNetlist();

      expect(t.sent, sentAtConnect,
          reason: 'a file that fails to parse must never reach the wire');
      expect(s.nlMtx.loaded, isFalse);
      expect(s.logs.last.lvl, 'fail');
      expect(s.logs.last.message, contains('bad.xlsx'));
    });
  });

  group('browseHvNetlist', () {
    test('loads name/cards/nets from the file and moves straight to the '
        'pre-HV verification modal', () async {
      final t = _FakeTransport();
      late final AppState s;
      final cm = ConnectionManager(
        onEvent: (m) => s.onEvent(m),
        onLinkState: (st, d) => s.onLinkState(st, d),
        transportFactory: () => t,
        logDir: Directory.systemTemp,
      );
      final bytes = _workbook([
        [TextCellValue('HI'), TextCellValue('LO'), TextCellValue('CARDS')],
        [IntCellValue(1), IntCellValue(2), IntCellValue(4)],
        [IntCellValue(3), IntCellValue(4), IntCellValue(4)],
      ]);
      s = AppState(
        cm: cm,
        host: '127.0.0.1',
        port: 46000,
        pickNetlistFile: () async => ('hv_stack.xlsx', bytes),
      );
      addTearDown(cm.disconnect);
      s.openNlPicker();

      await s.browseHvNetlist();

      expect(s.nlHv.loaded, isTrue);
      expect(s.nlHv.name, 'hv_stack.xlsx');
      expect(s.nlHv.cards, 4);
      expect(s.nlHv.nets, 2);
      expect(s.mdNlOpen, isFalse);
      expect(s.mdVerifyOpen, isTrue);
      expect(t.sent, isEmpty,
          reason: 'the HV netlist is GUI-side metadata only — nothing to '
              'upload, per Doc/GUI_protocol_command_coverage.md');
    });

    test('a file with no CARDS column defaults to the fitted stack', () async {
      final t = _FakeTransport();
      late final AppState s;
      final cm = ConnectionManager(
        onEvent: (m) => s.onEvent(m),
        onLinkState: (st, d) => s.onLinkState(st, d),
        transportFactory: () => t,
        logDir: Directory.systemTemp,
      );
      final bytes = _workbook([
        [TextCellValue('HI'), TextCellValue('LO')],
        [IntCellValue(1), IntCellValue(2)],
      ]);
      s = AppState(
        cm: cm,
        host: '127.0.0.1',
        port: 46000,
        pickNetlistFile: () async => ('no_cards.xlsx', bytes),
      );
      addTearDown(cm.disconnect);
      expect(s.stack, 3, reason: 'AppState defaults to a 3-card stack');

      await s.browseHvNetlist();

      expect(s.nlHv.cards, 3);
    });

    test('a malformed file fails loudly, leaves the netlist unloaded and '
        'keeps the picker modal open', () async {
      final t = _FakeTransport();
      late final AppState s;
      final cm = ConnectionManager(
        onEvent: (m) => s.onEvent(m),
        onLinkState: (st, d) => s.onLinkState(st, d),
        transportFactory: () => t,
        logDir: Directory.systemTemp,
      );
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      s = AppState(
        cm: cm,
        host: '127.0.0.1',
        port: 46000,
        pickNetlistFile: () async => ('not_excel.txt', bytes),
      );
      addTearDown(cm.disconnect);
      s.openNlPicker();

      await s.browseHvNetlist();

      expect(s.nlHv.loaded, isFalse);
      expect(s.mdNlOpen, isTrue);
      expect(s.logs.last.lvl, 'fail');
    });
  });
}
