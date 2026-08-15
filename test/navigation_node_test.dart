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

    testWidgets('system back pops a pushed route inside the node', (
      tester,
    ) async {
      await tester.pumpWidget(const _Host(useNode: true));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('pushed: secret'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('pushed: secret'), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('system back closes a dialog inside the node', (tester) async {
      await tester.pumpWidget(const _Host(useNode: true));

      await tester.tap(find.text('open dialog'));
      await tester.pumpAndSettle();
      expect(find.text('dialog'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('dialog'), findsNothing);
      expect(find.text('open dialog'), findsOneWidget);
    });

    testWidgets('system back respects a guarded route inside the node', (
      tester,
    ) async {
      await tester.pumpWidget(const _Host(useNode: true));

      await tester.tap(find.text('open guarded'));
      await tester.pumpAndSettle();
      expect(find.text('guarded route'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('guarded route'), findsOneWidget);
    });

    testWidgets('system back stays in a root node while it has an inner route',
        (
      tester,
    ) async {
      await tester.pumpWidget(const _Host(useNode: true, isRoot: true));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('pushed: secret'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('pushed: secret'), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets(
        'system back asks onPop once when the node has nothing to '
        'close', (tester) async {
      var calls = 0;

      await tester.pumpWidget(
        _OnPopHost(
          onPop: (context, result) {
            calls++;
            // A circuit breaker, not part of the contract: a node that keeps
            // asking would otherwise hang the test instead of failing it.
            return calls > 3;
          },
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text('node content'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(
        calls,
        1,
        reason: 'one system back is one question to onPop',
      );
    });

    testWidgets('an onPop that refuses keeps the outer route', (tester) async {
      var calls = 0;

      await tester.pumpWidget(
        _OnPopHost(
          onPop: (context, result) {
            calls++;
            return calls > 3;
          },
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(
        find.text('node content'),
        findsOneWidget,
        reason: 'onPop returned false, so the route it guards must stay',
      );
    });

    testWidgets('an onPop that allows the pop lets the outer route go', (
      tester,
    ) async {
      var calls = 0;

      await tester.pumpWidget(
        _OnPopHost(
          onPop: (context, result) {
            calls++;
            return true;
          },
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(calls, 1);
      expect(
        find.text('go'),
        findsOneWidget,
        reason: 'the screen that pushed the node is back on top',
      );
    });

    testWidgets(
        'system back still reaches onPop after an inner route came '
        'and went', (tester) async {
      var calls = 0;

      await tester.pumpWidget(
        _OnPopHost(
          onPop: (context, result) {
            calls++;
            return calls > 3;
          },
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      // Moving the inner stack makes the nested navigator report itself anew,
      // and the forwarding marker must not colour that report.
      await tester.tap(find.text('open inside'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('close inside'));
      await tester.pumpAndSettle();
      expect(find.text('node content'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(
        calls,
        1,
        reason: 'the node has nothing of its own left to close, so the back '
            'belongs to onPop',
      );
      expect(find.text('node content'), findsOneWidget);
    });

    testWidgets('system back inside nested nodes keeps the enclosing route', (
      tester,
    ) async {
      await tester.pumpWidget(const _NestedHost());

      await tester.tap(find.text('open inner'));
      await tester.pumpAndSettle();
      expect(find.text('inner pushed'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('inner pushed'), findsNothing);
      expect(
        find.text('open inner'),
        findsOneWidget,
        reason: 'the innermost node handled the back; nothing above it moved',
      );
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
  final bool isRoot;

  const _Host({
    required this.useNode,
    this.navigatorKey,
    this.isRoot = false,
  });

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: ScopeModel<_Config>(
          create: (context) => const _Config('secret'),
          dispose: (model) {},
          builder: (context) => useNode
              ? NavigationNode(
                  navigatorKey: navigatorKey,
                  isRoot: isRoot,
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                // The future a push returns completes when the route is popped,
                // and nothing here waits for that.
                onPressed: () => unawaited(
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => const _Pushed(),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
              TextButton(
                onPressed: () => unawaited(
                  showDialog<void>(
                    context: context,
                    useRootNavigator: false,
                    builder: (context) => const AlertDialog(
                      content: Text('dialog'),
                    ),
                  ),
                ),
                child: const Text('open dialog'),
              ),
              TextButton(
                onPressed: () => unawaited(
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => const _GuardedPushed(),
                    ),
                  ),
                ),
                child: const Text('open guarded'),
              ),
            ],
          ),
        ),
      );
}

/// Puts a node with an [NavigationNode.onPop] on a route of its own, so a pop
/// that leaves the node has somewhere to land.
final class _OnPopHost extends StatelessWidget {
  final FutureOr<bool> Function(BuildContext context, Object? result) onPop;

  const _OnPopHost({required this.onPop});

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => unawaited(
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => NavigationNode(
                        onPop: onPop,
                        child: const _OnPopNodeContent(),
                      ),
                    ),
                  ),
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
}

final class _OnPopNodeContent extends StatelessWidget {
  const _OnPopNodeContent();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('node content'),
              TextButton(
                onPressed: () => unawaited(
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => Scaffold(
                        body: Center(
                          child: TextButton(
                            onPressed: Navigator.of(context).pop,
                            child: const Text('close inside'),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                child: const Text('open inside'),
              ),
            ],
          ),
        ),
      );
}

/// A node inside another node: the inner one is the only one with a route of
/// its own to close.
final class _NestedHost extends StatelessWidget {
  const _NestedHost();

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: NavigationNode(
          isRoot: true,
          child: NavigationNode(
            child: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => unawaited(
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (context) => const Scaffold(
                            body: Center(child: Text('inner pushed')),
                          ),
                        ),
                      ),
                    ),
                    child: const Text('open inner'),
                  ),
                ),
              ),
            ),
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

final class _GuardedPushed extends StatelessWidget {
  const _GuardedPushed();

  @override
  Widget build(BuildContext context) => const PopScope(
        canPop: false,
        child: Scaffold(
          body: Center(child: Text('guarded route')),
        ),
      );
}
