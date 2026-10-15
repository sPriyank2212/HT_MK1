/// The customer/developer build split (`lib/app/build_tag.dart`) — a
/// customer build must have no Diag rail button, not just one hidden behind
/// a runtime check that could be re-enabled without recompiling.
library;

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ht_mk1_gui/app/app_state.dart';
import 'package:ht_mk1_gui/app/build_tag.dart';
import 'package:ht_mk1_gui/app/shell.dart';
import 'package:ht_mk1_gui/design/tokens.dart';
import 'package:ht_mk1_gui/htproto/connection.dart';

AppState newState() {
  final cm = ConnectionManager(logDir: Directory.systemTemp);
  return AppState(cm: cm, host: '127.0.0.1', port: 46000);
}

/// `Rail`'s vertical layout has an `Expanded` spacer pinning Diag to the
/// bottom, which needs a bounded height ancestor - the real app gives it one
/// via `Expanded(child: Row(children: [Rail(s: s), ...]))` (main.dart); a
/// bare `pumpWidget` doesn't establish any height on its own, so this
/// harness supplies one explicitly.
Widget harness(Widget child) => HtTheme(
      isDark: false,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (context) => MediaQuery(
            data: MediaQueryData.fromView(View.of(context)),
            child: DefaultTextStyle(
              style: context.type.body,
              child: SizedBox(height: 700, child: child),
            ),
          ),
        ),
      ),
    );

void main() {
  test('kCustomerBuild defaults to false (developer/full build) - the '
      'normal `flutter test` run carries no --dart-define', () {
    expect(kCustomerBuild, isFalse);
  });

  group('Rail', () {
    testWidgets('the developer build shows the Diag button', (tester) async {
      final s = newState();
      await tester.pumpWidget(harness(Rail(s: s, customerBuild: false)));
      // _RailButton renders its label uppercased (widget.label.toUpperCase()
      // in shell.dart) - the finder has to match what's actually on screen.
      expect(find.text('DIAG'), findsOneWidget);
    });

    testWidgets('the customer build has no Diag button at all',
        (tester) async {
      final s = newState();
      await tester.pumpWidget(harness(Rail(s: s, customerBuild: true)));
      expect(find.text('DIAG'), findsNothing);
      // Every other section stays - only Diag is customer-gated.
      expect(find.text('RUN'), findsOneWidget);
      expect(find.text('RESULTS'), findsOneWidget);
    });
  });
}
