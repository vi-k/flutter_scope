import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scopo/scopo.dart';

import 'utils/settle.dart';

void main() {
  group('ScopeController', () {
    test('runs the hooks in order, each exactly once', () async {
      final controller = _TestController();

      expect(controller.mounted, isFalse);

      await controller.performInit();
      expect(controller.mounted, isTrue);
      expect(controller.calls, ['init']);

      await controller.performDispose();
      expect(controller.mounted, isFalse);
      expect(
        controller.calls,
        ['init', 'onUnmount', 'dispose'],
        reason: 'the wrapper unmounts before it disposes',
      );
    });

    test('the wrappers are idempotent', () async {
      final controller = _TestController();

      await controller.performInit();
      controller
        ..performUnmount()
        ..performUnmount();
      await controller.performDispose();
      await controller.performDispose();

      expect(controller.calls, ['init', 'onUnmount', 'dispose']);
    });

    test('a controller that never initialized has nothing to unmount',
        () async {
      final controller = _TestController();

      await controller.performDispose();

      expect(
        controller.calls,
        ['dispose'],
        reason: '`onUnmount` belongs to a controller that was mounted',
      );
    });
  });

  group('AsyncControllerScope', () {
    testWidgets('builds the ready branch and tears the controller down once',
        (tester) async {
      final controller = _TestController();

      await tester.pumpWidget(_Host(controller: controller));
      await tester.pumpAndSettle();

      expect(find.text('ready'), findsOneWidget);
      expect(controller.calls, ['init']);

      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester, until: () => controller.calls.contains('dispose'));

      expect(
        controller.calls,
        ['init', 'onUnmount', 'dispose'],
        reason: 'the scope unmounts the controller before it disposes of it',
      );
    });

    // The hole this family exists to close: a controller whose `init` threw is
    // holding whatever it took before the failure, and the scope never saw it.
    testWidgets('disposes of a controller whose init failed', (tester) async {
      final controller = _TestController(failOnInit: true);

      await tester.pumpWidget(_Host(controller: controller));
      await settle(tester, until: () => controller.calls.contains('dispose'));
      // The teardown may already be over when the settle is entered, and then
      // it draws no frame at all; the error branch needs one.
      await tester.pump();

      expect(find.text('error'), findsOneWidget);
      expect(controller.calls, ['init', 'onUnmount', 'dispose']);
      expect(tester.takeException(), isNull);
    });

    // `performDispose` calls `onUnmount` too, but only when the asynchronous
    // half of the teardown gets there -- which can be much later, or never.
    // What the scope owes the controller is the synchronous half: let go of
    // the outside world now, at the moment the scope leaves the tree.
    testWidgets('unmounts the controller before the asynchronous teardown',
        (tester) async {
      final gate = Completer<void>();
      final controller = _TestController(initGate: gate);

      await tester.pumpWidget(_Host(controller: controller));
      await tester.pump();

      expect(controller.calls, ['init']);

      await tester.pumpWidget(const SizedBox.shrink());

      expect(
        controller.calls,
        ['init', 'onUnmount'],
        reason: 'the initialization is still parked on its future, and the '
            'controller has already been told to let go',
      );
      expect(controller.mounted, isFalse);

      // Let the parked initialization finish, so the teardown can run out and
      // the test does not end on a scope that is still disposing.
      gate.complete();
      await settle(tester, until: () => controller.calls.contains('dispose'));
    });

    // The same hole, reached the other way: nothing threw, the scope simply
    // left before the initialization had finished.
    testWidgets('disposes of a controller left behind by a scope that went',
        (tester) async {
      final gate = Completer<void>();
      final controller = _TestController(initGate: gate);

      await tester.pumpWidget(_Host(controller: controller));
      await tester.pump();

      expect(find.text('initializing'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      gate.complete();
      await settle(tester, until: () => controller.calls.contains('dispose'));

      expect(controller.calls, ['init', 'onUnmount', 'dispose']);
    });

    testWidgets(
        'the constructor form creates the controller once and hands it to the '
        'subtree', (tester) async {
      var created = 0;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: AsyncControllerScope<_TestController>(
            create: (context) {
              created++;

              return _TestController();
            },
            initBuilder: (context) => const Text('initializing'),
            errorBuilder: (context, error, stackTrace) => const Text('error'),
            builder: (context, controller) => const _Reader(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(created, 1);
      expect(find.text('reader: init'), findsOneWidget);
    });
  });
}

/// Reads the controller from the context, the way a descendant does.
final class _Reader extends StatelessWidget {
  const _Reader();

  @override
  Widget build(BuildContext context) {
    final calls = AsyncControllerScope.select<_TestController, String>(
      context,
      (scope) => scope.data.calls.join(','),
    );

    return Text('reader: $calls');
  }
}

final class _Host extends StatelessWidget {
  final _TestController controller;

  const _Host({required this.controller});

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: _TestScope(controller: controller),
      );
}

/// Hands out a controller made outside, so the test can inspect it.
final class _TestScope
    extends AsyncControllerScopeBase<_TestScope, _TestController> {
  final _TestController controller;

  const _TestScope({required this.controller});

  @override
  _TestController createController(BuildContext context) => controller;

  @override
  Widget buildOnInitializing(BuildContext context) =>
      const Text('initializing');

  @override
  Widget buildOnError(
    BuildContext context,
    Object error,
    StackTrace stackTrace,
  ) =>
      const Text('error');

  @override
  Widget buildOnReady(BuildContext context, _TestController controller) =>
      const Text('ready');
}

/// Records what the scope called, in order.
final class _TestController extends ScopeController {
  final calls = <String>[];

  /// Holds [init] until it is completed.
  final Completer<void>? initGate;

  /// Makes [init] fail, the way user code does.
  final bool failOnInit;

  _TestController({this.initGate, this.failOnInit = false});

  @override
  Future<void> init() async {
    calls.add('init');
    if (initGate case final gate?) {
      await gate.future;
    }
    if (failOnInit) {
      throw StateError('init failed');
    }
  }

  @override
  void onUnmount() => calls.add('onUnmount');

  @override
  Future<void> dispose() async => calls.add('dispose');
}
