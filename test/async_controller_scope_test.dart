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

    test('performInit runs once, and never after the teardown', () async {
      final controller = _TestController();

      await controller.performInit();
      await controller.performInit();

      expect(controller.calls, ['init'], reason: 'at most once, as promised');

      await controller.performDispose();
      await controller.performInit();

      expect(
        controller.calls,
        ['init', 'onUnmount', 'dispose'],
        reason: 'a controller that has been let go of is not brought back: '
            '`init` would run against what `dispose` has already released',
      );
      expect(controller.mounted, isFalse);
    });

    test('a second performDispose waits for the first instead of racing it',
        () async {
      final gate = Completer<void>();
      final controller = _TestController(disposeGate: gate);
      var firstDone = false;
      var secondDone = false;

      await controller.performInit();
      unawaited(controller.performDispose().then((_) => firstDone = true));
      unawaited(controller.performDispose().then((_) => secondDone = true));
      await pumpEventQueue();

      expect(controller.calls, ['init', 'onUnmount', 'dispose']);
      expect(firstDone, isFalse);
      expect(
        secondDone,
        isFalse,
        reason: 'the teardown it was told was over is still running',
      );

      gate.complete();
      await pumpEventQueue();

      expect(firstDone, isTrue);
      expect(secondDone, isTrue);
    });

    test('every caller of performDispose sees the same failure', () async {
      final controller = _TestController(failOnDispose: true);

      await controller.performInit();

      // Both handlers are attached where the futures are made: an error that
      // reaches a future nobody is listening to yet is an unhandled one.
      final outcomes = await Future.wait([
        controller.performDispose().then<Object?>(
              (_) => null,
              onError: (Object error) => error,
            ),
        controller.performDispose().then<Object?>(
              (_) => null,
              onError: (Object error) => error,
            ),
      ]);

      expect(outcomes.first, isA<StateError>());
      expect(
        outcomes.last,
        isA<StateError>(),
        reason: 'a failure the first caller sees is not a success for the next',
      );
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

      expect(find.textContaining('error:'), findsOneWidget);
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
      late _TestController controller;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: AsyncControllerScope<_TestController>(
            create: (context) {
              created++;

              return controller = _TestController();
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

      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester, until: () => controller.calls.contains('dispose'));
    });
  });

  group('a controller whose dispose also fails', () {
    // `dispose()` runs on every path, including the one where `init()` failed
    // halfway -- and the documentation says so, which makes that the path it
    // is most likely to fail on. An exception raised from a `finally`
    // replaces the one the `finally` was entered for, so the failure that
    // actually broke the scope disappeared and `buildOnError` was handed the
    // secondary one instead.
    testWidgets('shows the failure of init, not the failure of dispose',
        (tester) async {
      final controller = _TestController(failOnInit: true, failOnDispose: true);

      await tester.pumpWidget(_Host(controller: controller));
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'dispose failed',
        ),
        reason: 'the secondary failure is reported rather than swallowed',
      );
      expect(
        find.textContaining('init failed'),
        findsOneWidget,
        reason: 'but what the scope shows is the reason it failed',
      );
      expect(
        controller.calls,
        containsAllInOrder(['init', 'onUnmount', 'dispose']),
        reason: 'and the controller was still released',
      );
    });

    // The same path, with the teardown hanging rather than failing. Nothing
    // bounded it: the generator never finished, so the failure of `init()`
    // never reached the model and the scope showed its loading branch for
    // ever -- while `doc/async_controller_scope.md` promises the wait for
    // `dispose()` is bounded by `disposeAsyncTimeout`.
    testWidgets('gives up on a hanging dispose and still shows the failure',
        (tester) async {
      final hang = Completer<void>();
      addTearDown(hang.complete);
      final controller = _TestController(failOnInit: true, disposeGate: hang);

      await tester.pumpWidget(
        _Host(
          controller: controller,
          disposeAsyncTimeout: const Duration(milliseconds: 50),
        ),
      );
      bool errorShown() => find.textContaining('error:').evaluate().isNotEmpty;

      await settle(tester, until: errorShown);

      expect(
        tester.takeException(),
        isA<TimeoutException>(),
        reason: 'the wait was given up on, and said so',
      );
      expect(
        find.textContaining('init failed'),
        findsOneWidget,
        reason: 'a teardown that never finishes must not keep the scope on '
            'its loading branch for ever',
      );
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
  final Duration? disposeAsyncTimeout;

  const _Host({required this.controller, this.disposeAsyncTimeout});

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: _TestScope(
          controller: controller,
          disposeAsyncTimeout: disposeAsyncTimeout,
        ),
      );
}

/// Hands out a controller made outside, so the test can inspect it.
final class _TestScope
    extends AsyncControllerScopeBase<_TestScope, _TestController> {
  final _TestController controller;

  const _TestScope({required this.controller, super.disposeAsyncTimeout});

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
      Text('error: $error');

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

  /// Makes [dispose] fail. It runs on every path, including the one where
  /// [init] failed halfway -- which is where it is most likely to.
  final bool failOnDispose;

  /// Holds [dispose] until it is completed.
  final Completer<void>? disposeGate;

  _TestController({
    this.initGate,
    this.failOnInit = false,
    this.failOnDispose = false,
    this.disposeGate,
  });

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
  Future<void> dispose() async {
    calls.add('dispose');
    if (disposeGate case final gate?) {
      await gate.future;
    }
    if (failOnDispose) {
      throw StateError('dispose failed');
    }
  }
}
