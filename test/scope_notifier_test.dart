import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scopo/scopo.dart';

void main() {
  testWidgets(
    'ScopeNotifier.value re-subscribes to the new listenable on swap',
    (tester) async {
      final first = ValueNotifier<int>(0);
      final second = ValueNotifier<int>(100);
      addTearDown(first.dispose);
      addTearDown(second.dispose);

      Widget app(ValueNotifier<int> value) => MaterialApp(
            home: ScopeNotifier<ValueNotifier<int>>.value(
              value: value,
              builder: (context) => const _ValueView(),
            ),
          );

      await tester.pumpWidget(app(first));
      expect(find.text('0'), findsOneWidget);

      // Sanity check: before the swap, mutating the original listenable
      // still triggers a rebuild.
      first.value = 1;
      await tester.pump();
      expect(find.text('1'), findsOneWidget);

      // Swap the listenable at the same widget position (same type, no
      // key), so the element is updated in place instead of recreated.
      await tester.pumpWidget(app(second));
      expect(find.text('100'), findsOneWidget);

      // The old listenable must no longer trigger rebuilds: its listener
      // was removed on swap.
      first.value = 2;
      await tester.pump();
      expect(find.text('100'), findsOneWidget);
      expect(find.text('2'), findsNothing);

      // The new listenable must trigger rebuilds: this is the regression
      // under test. `update` must call `addListener` on the new value, not
      // `removeListener`.
      second.value = 101;
      await tester.pump();
      expect(find.text('101'), findsOneWidget);
    },
  );
}

class _ValueView extends StatelessWidget {
  const _ValueView();

  @override
  Widget build(BuildContext context) {
    final value = ScopeNotifier.select<ValueNotifier<int>, int>(
      context,
      (model) => model.value,
    );

    return Text('$value');
  }
}
