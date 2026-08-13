import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scopo/scopo.dart';

void main() {
  group('NavigationNode', () {
    testWidgets('a screen pushed inside the node still sees the scope above it',
        (tester) async {
      await tester.pumpWidget(const _Host(useNode: true));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(
        find.text('pushed: secret'),
        findsOneWidget,
        reason: 'the nested navigator lives below the scope, so the route it '
            'pushes does too',
      );
    });

    testWidgets(
      'control: the same screen pushed on the root navigator does not',
      (tester) async {
        await tester.pumpWidget(const _Host(useNode: false));

        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        expect(
          find.text('pushed: none'),
          findsOneWidget,
          reason: 'the root navigator sits above the scope, and this is the '
              'whole reason NavigationNode exists',
        );
      },
    );

    testWidgets('popping inside the node returns to the node content', (
      tester,
    ) async {
      await tester.pumpWidget(const _Host(useNode: true));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('open'), findsNothing);

      await tester.tap(find.text('back'));
      await tester.pumpAndSettle();

      expect(find.text('open'), findsOneWidget);
      expect(find.text('pushed: secret'), findsNothing);
    });

    testWidgets('the navigatorKey hands the nested navigator to its owner', (
      tester,
    ) async {
      final key = GlobalKey<NodeNavigatorState>();

      await tester.pumpWidget(_Host(useNode: true, navigatorKey: key));

      expect(key.currentState, isNotNull);

      // Not awaited: the future a push returns completes when the route is
      // *popped*, so awaiting it here would wait for a screen nobody closes.
      unawaited(
        key.currentState!.push<void>(
          MaterialPageRoute<void>(builder: (context) => const _Pushed()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('pushed: secret'),
        findsOneWidget,
        reason: 'a route pushed through the key lands in the same node',
      );
    });

    testWidgets('a node route is not on the root navigator', (tester) async {
      await tester.pumpWidget(const _Host(useNode: true));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final rootNavigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );

      expect(
        rootNavigator.canPop(),
        isFalse,
        reason: 'the root navigator still holds a single route',
      );
    });
  });
}

final class _Config {
  final String value;

  const _Config(this.value);
}

final class _Host extends StatelessWidget {
  final bool useNode;
  final GlobalKey<NodeNavigatorState>? navigatorKey;

  const _Host({required this.useNode, this.navigatorKey});

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: ScopeModel<_Config>(
          create: (context) => const _Config('secret'),
          dispose: (model) {},
          builder: (context) => useNode
              ? NavigationNode(
                  navigatorKey: navigatorKey,
                  child: const _NodeContent(),
                )
              : const _NodeContent(),
        ),
      );
}

final class _NodeContent extends StatelessWidget {
  const _NodeContent();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: TextButton(
            // The future a push returns completes when the route is popped,
            // and nothing here waits for that.
            onPressed: () => unawaited(
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (context) => const _Pushed()),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      );
}

final class _Pushed extends StatelessWidget {
  const _Pushed();

  @override
  Widget build(BuildContext context) {
    final config = ScopeModel.maybeOf<_Config>(context, listen: false);

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('pushed: ${config?.value ?? 'none'}'),
            TextButton(
              onPressed: Navigator.of(context).pop,
              child: const Text('back'),
            ),
          ],
        ),
      ),
    );
  }
}
