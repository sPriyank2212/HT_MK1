/// Port-selector behaviour tests.
///
/// `layout_test.dart` renders the selector but never drives it, so a selector
/// that painted correctly and did nothing on click passed every test in the
/// suite. These tests click it.
///
/// Three faults are pinned here:
///
///   * the dropdown threw "No Overlay widget found" on every click, because
///     `WidgetsApp` built with only `builder:` has no Navigator and so no
///     Overlay (see `overlay_check_test.dart`);
///   * Connect opened the COM port at the *TCP* default of 46000 baud on the
///     plain double-click launch, so the handshake always timed out;
///   * picking a port dialled it immediately, leaving no way to retry a failed
///     connect without reopening the menu.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ht_mk1_gui/app/app_state.dart';
import 'package:ht_mk1_gui/htproto/connection.dart';
import 'package:ht_mk1_gui/htproto/serial_transport.dart' show defaultBaud;
import 'package:ht_mk1_gui/main.dart';

const List<PortEntry> kTwoPorts = [
  PortEntry('COM7', 'ST-LINK VCP'),
  PortEntry('COM4', 'USB Serial'),
];

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

/// An AppState whose selector lists [ports] and whose link goes to a fake.
({AppState state, _FakeTransport transport}) stateWithPorts({
  List<PortEntry> Function()? ports,
  int port = defaultBaud,
}) {
  final t = _FakeTransport();
  late final AppState s;
  final cm = ConnectionManager(
    onLinkState: (st, d) => s.onLinkState(st, d),
    transportFactory: () => t,
    logDir: Directory.systemTemp,
  );
  s = AppState(
    cm: cm,
    host: '127.0.0.1',
    port: port,
    listPorts: ports ?? () => kTwoPorts,
  );
  s.refreshPorts();
  return (state: s, transport: t);
}

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Let a fire-and-forget connect or disconnect run to completion. Neither is
/// awaitable from the button that starts it, and `pumpAndSettle` is out: the
/// hazard banner animates forever.
///
/// The `runAsync` slice is not optional. `ConnectionManager.disconnect` awaits
/// `StreamSubscription.cancel()`, whose future is owned by the root zone —
/// `tester.pump()`'s fake clock never completes it, so the whole teardown
/// stalls at that first await until real async gets a turn. The pumps around
/// it deliver the stream events and rebuild the tree.
Future<void> drain(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester
      .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Drop the link inside the test body. `addTearDown` runs after flutter_test
/// has already asserted that no timers are pending, and a live link leaves the
/// connection manager's 500 ms link watchdog ticking. Not awaited: the
/// watchdog is cancelled synchronously, before the await that would stall.
Future<void> dropLink(WidgetTester tester, AppState s) async {
  unawaited(s.disconnect());
  await drain(tester);
}

Future<void> pumpApp(WidgetTester tester, AppState s) async {
  tester.view.physicalSize = const Size(1480, 940);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  // The real app tree, not a hand-built harness: the Overlay bug was a
  // property of what HtApp puts above HtHome.
  await tester.pumpWidget(HtApp(state: s, storedTheme: 'light'));
  await settle(tester);
}

void main() {
  group('dropdown', () {
    testWidgets('opens and lists every port', (tester) async {
      final s = stateWithPorts().state;
      await pumpApp(tester, s);

      await tester.tap(find.text('COM7'));
      await settle(tester);
      expect(tester.takeException(), isNull);

      expect(find.text('COM7 — ST-LINK VCP'), findsOneWidget);
      expect(find.text('COM4 — USB Serial'), findsOneWidget);
    });

    testWidgets('picking a port selects it without connecting', (tester) async {
      final r = stateWithPorts();
      await pumpApp(tester, r.state);

      await tester.tap(find.text('COM7'));
      await settle(tester);
      await tester.tap(find.text('COM4 — USB Serial'));
      await settle(tester);

      expect(r.state.selPort, 'COM4');
      expect(r.state.link, isFalse);
      expect(r.transport.openedHost, isNull, reason: 'picking must not dial');
      // The menu is gone and the trigger now names the choice.
      expect(find.text('COM4 — USB Serial'), findsNothing);
      expect(find.text('COM4'), findsOneWidget);
    });

    testWidgets('a second tap closes it', (tester) async {
      final s = stateWithPorts().state;
      await pumpApp(tester, s);

      await tester.tap(find.text('COM7'));
      await settle(tester);
      expect(find.text('COM4 — USB Serial'), findsOneWidget);

      await tester.tap(find.text('COM7'));
      await settle(tester);
      expect(find.text('COM4 — USB Serial'), findsNothing);
    });

    testWidgets('refresh behind an open menu updates the rows', (tester) async {
      var listed = kTwoPorts;
      final s = stateWithPorts(ports: () => listed).state;
      await pumpApp(tester, s);

      await tester.tap(find.text('COM7'));
      await settle(tester);
      expect(find.text('COM4 — USB Serial'), findsOneWidget);

      listed = const [PortEntry('COM9', 'ST-LINK VCP')];
      s.refreshPorts();
      await settle(tester);

      expect(find.text('COM4 — USB Serial'), findsNothing);
      expect(find.text('COM9 — ST-LINK VCP'), findsOneWidget);
    });

    testWidgets('the menu folds away when the link comes up', (tester) async {
      final s = stateWithPorts().state;
      await pumpApp(tester, s);

      await tester.tap(find.text('COM7'));
      await settle(tester);
      expect(find.text('COM4 — USB Serial'), findsOneWidget);

      s.link = true;
      s.host = 'COM7';
      s.paintLink();
      await settle(tester);

      expect(find.text('COM4 — USB Serial'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('connect / disconnect', () {
    testWidgets('Connect opens the selected port at the link baud rate',
        (tester) async {
      final r = stateWithPorts();
      await pumpApp(tester, r.state);

      await tester.tap(find.text('COM7'));
      await settle(tester);
      await tester.tap(find.text('COM4 — USB Serial'));
      await settle(tester);

      await tester.tap(find.text('CONNECT'));
      await drain(tester);

      expect(r.transport.openedHost, 'COM4');
      expect(r.transport.openedPort, defaultBaud,
          reason: 'a serial link must open at the baud rate, not a TCP port');
      expect(r.state.link, isTrue);
      expect(find.text('DISCONNECT'), findsOneWidget);

      await dropLink(tester, r.state);
    });

    testWidgets('Disconnect drops the link and offers Connect again',
        (tester) async {
      final r = stateWithPorts();
      await pumpApp(tester, r.state);

      await tester.tap(find.text('CONNECT'));
      await drain(tester);
      expect(r.state.link, isTrue);

      await tester.tap(find.text('DISCONNECT'));
      await drain(tester);

      expect(r.state.link, isFalse);
      expect(r.state.handling, 'unknown');
      expect(find.text('CONNECT'), findsOneWidget);
      expect(find.text('NO LINK'), findsOneWidget);
    });

    test('a second connect while one is in flight is ignored', () async {
      final r = stateWithPorts();
      final s = r.state;
      addTearDown(s.cm.disconnect);

      s.connectTo('COM7');
      expect(s.connecting, isTrue);
      // The impatient double-click: this used to re-enter cm.connect and tear
      // the first attempt's half-open link down.
      s.connectTo('COM4');

      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(s.connecting, isFalse);
      expect(s.link, isTrue);
      expect(r.transport.openedHost, 'COM7');
    });
  });

  group('refresh', () {
    test('reports what it found', () {
      var listed = kTwoPorts;
      final s = stateWithPorts(ports: () => listed).state;

      s.refreshPorts();
      expect(s.logs.last.message, contains('COM7, COM4'));

      listed = const [];
      s.refreshPorts();
      expect(s.logs.last.message, contains('no serial ports'));
      expect(s.selPort, isNull);
    });

    test('warns when the selected port disappears', () {
      var listed = kTwoPorts;
      final s = stateWithPorts(ports: () => listed).state;
      s.choosePort('COM4');

      listed = const [PortEntry('COM9', 'ST-LINK VCP')];
      s.refreshPorts();

      expect(s.selPort, 'COM9');
      expect(s.logs.last.message, contains('COM4 is gone'));
    });
  });

  group('link target', () {
    test('a plain launch is a serial link at the default baud rate', () {
      // The regression: this used to be options.port (46000), the TCP default,
      // handed to SerialTransport as a baud rate.
      expect(linkPortFor(parseArgs(const [])), defaultBaud);
    });

    test('--baud is honoured with and without --serial', () {
      expect(linkPortFor(parseArgs(const ['--baud', '9600'])), 9600);
      expect(
        linkPortFor(parseArgs(const ['--serial', 'COM7', '--baud', '9600'])),
        9600,
      );
    });

    test('an explicit TCP target keeps its TCP port', () {
      expect(linkPortFor(parseArgs(const ['--port', '46000'])), 46000);
      expect(linkPortFor(parseArgs(const ['--host', '10.0.0.4'])), 46000);
    });
  });

  group('non-serial links', () {
    testWidgets('the port picker hides when the transport is a socket',
        (tester) async {
      final t = _FakeTransport();
      late final AppState s;
      final cm = ConnectionManager(
        onLinkState: (st, d) => s.onLinkState(st, d),
        transportFactory: () => t,
        logDir: Directory.systemTemp,
      );
      s = AppState(
        cm: cm,
        host: '127.0.0.1',
        port: 46000,
        serialLink: false,
        listPorts: () => kTwoPorts,
      );
      s.refreshPorts(quiet: true);
      await pumpApp(tester, s);

      // No COM-port trigger to aim a socket with; the link controls remain.
      expect(find.text('COM7'), findsNothing);
      expect(find.text('CONNECT'), findsOneWidget);
    });
  });
}
