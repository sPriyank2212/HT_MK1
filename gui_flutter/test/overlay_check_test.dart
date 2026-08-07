import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('WidgetsApp with only builder has no Overlay', (tester) async {
    late BuildContext captured;
    await tester.pumpWidget(WidgetsApp(
      color: const Color(0xffffffff),
      builder: (context, _) => Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(builder: (context) {
          captured = context;
          return const SizedBox();
        }),
      ),
    ));
    expect(Overlay.maybeOf(captured), isNull);
  });
}
