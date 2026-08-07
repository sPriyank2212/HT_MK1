/// Layout regression tests.
///
/// `flutter analyze` cannot see a RenderFlex overflow and neither can the
/// headless model tests — those faults only exist once real constraints flow
/// through the tree. This builds every view at the sizes the design's
/// breakpoints care about, in both themes, and fails on any exception the
/// rendering library raises.
///
/// The first run of this file caught the `Verdict` overflow (IntrinsicHeight
/// resolving to the 122px act button and clipping the headline by 15px).
library;

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ht_mk1_gui/app/app_state.dart';
import 'package:ht_mk1_gui/design/tokens.dart';
import 'package:ht_mk1_gui/htproto/connection.dart';
import 'package:ht_mk1_gui/htproto/codec.dart' as proto;
import 'package:ht_mk1_gui/htproto/messages.dart' as msg;
import 'package:ht_mk1_gui/main.dart';

AppState newState() {
  final cm = ConnectionManager(logDir: Directory.systemTemp);
  return AppState(cm: cm, host: '127.0.0.1', port: 46000);
}

/// Mirrors what `HtApp` builds around `HtHome`.
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

/// Pump without `pumpAndSettle`: the hazard banner runs a repeating animation
/// that never settles, so a settle would hang the moment HV goes live.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

const List<String> kViews = [
  'run',
  'cont',
  'res',
  'hv',
  'program',
  'results',
  'diag',
];

/// The window size setup.cmd asks the runner for, plus the two breakpoints.
const Map<String, Size> kSizes = {
  'default 1480x940': Size(1480, 940),
  'wide 1920x1080': Size(1920, 1080),
  'medium 1000x900': Size(1000, 900), // below the 1080 breakpoint
  'narrow 800x900': Size(800, 900), // below the 860 breakpoint
};

void main() {
  for (final sizeEntry in kSizes.entries) {
    for (final dark in [false, true]) {
      final theme = dark ? 'dark' : 'light';
      group('${sizeEntry.key} · $theme', () {
        for (final view in kViews) {
          testWidgets('$view lays out cleanly', (tester) async {
            tester.view.physicalSize = sizeEntry.value;
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.reset);

            final s = newState();
            s.go(view);
            await tester.pumpWidget(harness(s, dark: dark));
            await settle(tester);

            expect(tester.takeException(), isNull);
          });
        }
      });
    }
  }

  group('status bar port selector', () {
    Future<void> check(
      WidgetTester tester,
      AppState s,
    ) async {
      tester.view.physicalSize = const Size(1480, 940);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(harness(s, dark: false));
      await settle(tester);
      expect(tester.takeException(), isNull);
    }

    AppState stateWithPorts() {
      final cm = ConnectionManager(logDir: Directory.systemTemp);
      final s = AppState(
        cm: cm,
        host: '127.0.0.1',
        port: 115200,
        listPorts: () => const [
          PortEntry('COM7', 'ST-LINK VCP'),
          PortEntry('COM4', 'USB Serial'),
        ],
      );
      s.refreshPorts();
      return s;
    }

    testWidgets('disconnected: preselected port, Connect, no-link pill',
        (tester) async {
      final s = stateWithPorts();
      await check(tester, s);

      expect(find.text('COM7'), findsOneWidget);
      expect(find.text('CONNECT'), findsOneWidget);
      expect(find.text('NO LINK'), findsOneWidget);
    });

    testWidgets('linked: the pill names the port and the button flips',
        (tester) async {
      final s = stateWithPorts();
      s.host = 'COM7';
      s.link = true;
      s.paintLink();
      await check(tester, s);

      expect(find.text('LINK COM7'), findsOneWidget);
      expect(find.text('DISCONNECT'), findsOneWidget);
    });
  });

  group('states that change layout', () {
    Future<void> check(
      WidgetTester tester,
      void Function(AppState) mutate, {
      String view = 'run',
      Size size = const Size(1480, 940),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final s = newState();
      s.go(view);
      mutate(s);
      await tester.pumpWidget(harness(s, dark: false));
      await settle(tester);
      expect(tester.takeException(), isNull);
    }

    testWidgets('handover banner (phase=hold)', (tester) async {
      await check(tester, (s) {
        s.link = true;
        s.R['cont'] = 'pass';
        s.R['res'] = 'pass';
        s.finishStage1();
      });
    });

    testWidgets('fault list populated', (tester) async {
      await check(tester, (s) {
        s.faultsOn['f06'] = true;
        s.faultsOn['f08'] = true;
        s.faultsOn['f04'] = true;
      });
    });

    testWidgets('hazard banner while HV is live', (tester) async {
      await check(tester, (s) {
        s.link = true;
        s.onEvent(const msg.HvEvent(millivolts: 500000));
      });
    });

    testWidgets('HV view unlocked on the HV fixture', (tester) async {
      await check(tester, (s) {
        s.link = true;
        s.onEvent(const msg.FixtureEvent(fixture: proto.Fixture.hv));
      }, view: 'hv');
    });

    testWidgets('link lost', (tester) async {
      await check(tester, (s) {
        s.link = true;
        s.linkDown('port closed by instrument');
      });
    });

    testWidgets('cross continuity mode', (tester) async {
      await check(tester, (s) => s.setMode('cross'), view: 'cont');
    });

    testWidgets('HV netlist loaded, 4-card mismatch', (tester) async {
      await check(tester, (s) {
        s.setStack(3);
        s.loadHv('AV-880_HV_4card.hnl', 4, 160);
      }, view: 'program');
    });

    testWidgets('MTX netlist unloaded (empty netbar)', (tester) async {
      await check(tester, (s) => s.unloadNetlist('mtx'), view: 'cont');
    });

    testWidgets('log bar expanded', (tester) async {
      await check(tester, (s) => s.toggleLog());
    });

    testWidgets('HV netlist picker modal', (tester) async {
      await check(tester, (s) => s.openNlPicker());
    });

    testWidgets('pre-HV verification modal', (tester) async {
      await check(tester, (s) {
        s.loadHv('AV-880_HV_3card.hnl', 3, 118);
        s.R['cont'] = 'pass';
        s.R['res'] = 'pass';
        s.openVerify();
      });
    });

    testWidgets('single HV card', (tester) async {
      await check(tester, (s) => s.setStack(1), view: 'hv');
    });

    testWidgets('four HV cards', (tester) async {
      await check(tester, (s) => s.setStack(4), view: 'hv');
    });
  });
}
