import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scopo/scopo.dart';

final _defaultScopeKeysTimeout = ScopeConfig.defaultScopeKeysTimeout;
final _defaultWaitForChildrenTimeout =
    ScopeConfig.defaultWaitForChildrenTimeout;

void main() {
  setUp(_TestScopeElement.reset);

  tearDown(() {
    ScopeConfig.defaultScopeKeysTimeout = _defaultScopeKeysTimeout;
    ScopeConfig.defaultWaitForChildrenTimeout = _defaultWaitForChildrenTimeout;
  });

  testWidgets('two coordinators do not share a key', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: [
            AsyncScopeCoordinator(child: _TestScope(testKey: 'shared')),
            AsyncScopeCoordinator(child: _TestScope(testKey: 'shared')),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(_TestScopeElement.initialized, 2);
    expect(
      tester.takeException(),
      isNull,
      reason: 'neither scope waited for the one in the other coordinator',
    );
  });

  testWidgets('the nearest coordinator serves the key', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: AsyncScopeCoordinator(
          child: Column(
            children: [
              _TestScope(testKey: 'shared'),
              AsyncScopeCoordinator(child: _TestScope(testKey: 'shared')),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(_TestScopeElement.initialized, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a scopeKey without a coordinator is an error', (tester) async {
    // `_performAsyncInit()` is started from `mount()` and its future is
    // discarded, so the `FlutterError` thrown by `AsyncScopeCoordinator.enter`
    // never reaches the framework's own error handling: it surfaces as an
    // uncaught error of the zone the mount ran in. `tester.takeException()`
    // cannot see it (`flutter_test`'s `handleUncaughtError` ends the test on
    // the spot instead of parking the details), so the mount runs inside a
    // guarded child zone that catches it first.
    final errors = <Object>[];
    await runZonedGuarded(
      () async {
        await tester.pumpWidget(
          const Directionality(
            textDirection: TextDirection.ltr,
            child: _TestScope(testKey: 'shared'),
          ),
        );
        await tester.pump();
      },
      (error, stackTrace) => errors.add(error),
    );

    expect(errors, hasLength(1));
    expect(errors.single, isA<FlutterError>());
    expect(
      errors.single.toString(),
      contains('No `AsyncScopeCoordinator`'),
    );
    expect(
      errors.single.toString(),
      contains('`scopeKey`'),
      reason: 'the message says what the missing coordinator was needed for',
    );
  });

  testWidgets('a scope with no parent scope registers with the coordinator',
      (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: AsyncScopeCoordinator(child: _TestScope()),
      ),
    );
    await tester.pumpAndSettle();

    expect(_coordinatorOf(tester).childrenCount, 1);
  });

  testWidgets(
      'a scope under nested coordinators registers with the nearest one',
      (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: AsyncScopeCoordinator(
          child: AsyncScopeCoordinator(child: _TestScope()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final [outer, inner] = tester
        .elementList(find.byType(AsyncScopeCoordinator))
        .cast<AsyncScopeParent>()
        .toList();

    expect(
      inner.childrenCount,
      1,
      reason: 'the scope registered with the nearest coordinator',
    );
    expect(
      outer.childrenCount,
      0,
      reason: 'the outer coordinator never sees a child of the inner one',
    );
  });

  testWidgets(
      'a coordinator between two scopes does not take the place of the parent',
      (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: _TestScope(
          disposeLabel: 'parent',
          child: AsyncScopeCoordinator(
            child: _TestScope(
              disposeLabel: 'child',
              disposeDelay: Duration(milliseconds: 50),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      _coordinatorOf(tester).childrenCount,
      0,
      reason: 'the child registered with the parent scope, not the coordinator',
    );

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox.shrink(),
      ),
    );
    await _settle(
      tester,
      until: () => _TestScopeElement.disposalOrder.length == 2,
    );

    expect(_TestScopeElement.disposalOrder, ['child', 'parent']);
  });

  testWidgets('a parent scope waits for the scope below it', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: _TestScope(
          disposeLabel: 'parent',
          child: _TestScope(
            disposeLabel: 'child',
            disposeDelay: Duration(milliseconds: 50),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox.shrink(),
      ),
    );
    await _settle(
      tester,
      until: () => _TestScopeElement.disposalOrder.length == 2,
    );

    expect(_TestScopeElement.disposalOrder, ['child', 'parent']);
  });

  testWidgets('a coordinator above a parent scope leaves the pair alone',
      (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: AsyncScopeCoordinator(
          child: _TestScope(
            disposeLabel: 'parent',
            child: _TestScope(
              disposeLabel: 'child',
              disposeDelay: Duration(milliseconds: 50),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox.shrink(),
      ),
    );
    await _settle(
      tester,
      until: () => _TestScopeElement.disposalOrder.length == 2,
    );

    expect(_TestScopeElement.disposalOrder, ['child', 'parent']);
  });

  testWidgets('a scope with no parent and no coordinator disposes cleanly',
      (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: _TestScope(disposeLabel: 'lonely'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox.shrink(),
      ),
    );
    await _settle(
      tester,
      until: () => _TestScopeElement.disposalOrder.isNotEmpty,
    );

    expect(_TestScopeElement.disposalOrder, ['lonely']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('waitForChildren completes only after disposeAsync has finished',
      (tester) async {
    final gate = Completer<void>();
    late BuildContext context;

    Widget build({required bool withScope}) => Directionality(
          textDirection: TextDirection.ltr,
          child: AsyncScopeCoordinator(
            child: Column(
              children: [
                if (withScope)
                  _TestScope(disposeLabel: 'top', disposeGate: gate),
                Builder(
                  builder: (builderContext) {
                    // Stays in the tree after the scope is removed, so the
                    // context passed to `waitForChildren` is still valid then.
                    context = builderContext;

                    return const SizedBox.shrink();
                  },
                ),
              ],
            ),
          ),
        );

    await tester.pumpWidget(build(withScope: true));
    await tester.pumpAndSettle();

    expect(_coordinatorOf(tester).childrenCount, 1);

    await tester.pumpWidget(build(withScope: false));

    var waited = false;
    unawaited(
      AsyncScopeCoordinator.waitForChildren(context).then((_) => waited = true),
    );
    await _settle(tester, until: () => waited);

    expect(waited, isFalse, reason: 'disposeAsync has not finished yet');
    expect(_TestScopeElement.disposalOrder, isEmpty);

    gate.complete();
    await _settle(tester, until: () => waited);

    expect(_TestScopeElement.disposalOrder, ['top']);
    expect(waited, isTrue);
    expect(_coordinatorOf(tester).childrenCount, 0);
  });

  testWidgets('waitForChildren without a coordinator is an error',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (builderContext) {
            context = builderContext;

            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(
      () => AsyncScopeCoordinator.waitForChildren(context),
      throwsA(
        isA<FlutterError>().having(
          (error) => error.toString(),
          'toString()',
          contains('No `AsyncScopeCoordinator`'),
        ),
      ),
    );
  });

  // The two tests below pin the reporting of an expired wait. The core is
  // silent by design -- it only calls the `onTimeout` it is given -- so
  // `FlutterError.reportError` survives solely because both call sites in
  // `async_scope_core.dart` pass a callback that does it.
  testWidgets('an expired wait for a scopeKey is reported', (tester) async {
    ScopeConfig.defaultScopeKeysTimeout = const Duration(milliseconds: 50);

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: AsyncScopeCoordinator(
          child: Column(
            children: [
              _TestScope(testKey: 'shared'),
              _TestScope(testKey: 'shared'),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    final exception = tester.takeException();
    expect(exception, isA<TimeoutException>());
    expect(
      (exception as TimeoutException).message,
      contains("couldn't wait to get access to [shared]"),
    );
    expect(
      _TestScopeElement.initialized,
      2,
      reason: 'the scope that timed out was let in anyway',
    );
  });

  testWidgets('an expired wait for children is reported', (tester) async {
    ScopeConfig.defaultWaitForChildrenTimeout =
        const Duration(milliseconds: 50);
    final gate = Completer<void>();

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: _TestScope(
          disposeLabel: 'parent',
          child: _TestScope(disposeLabel: 'child', disposeGate: gate),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox.shrink(),
      ),
    );
    await _settle(
      tester,
      until: () => _TestScopeElement.disposalOrder.contains('parent'),
    );

    expect(
      _TestScopeElement.disposalOrder,
      ['parent'],
      reason: 'the parent gave up on the child and disposed of itself',
    );

    final exception = tester.takeException();
    expect(exception, isA<TimeoutException>());
    expect(
      (exception as TimeoutException).message,
      contains("couldn't wait for the children to complete"),
    );

    gate.complete();
    await _settle(
      tester,
      until: () => _TestScopeElement.disposalOrder.length == 2,
    );
  });
}

/// The coordinator's element, seen through the public half of its wait-root
/// role.
AsyncScopeParent _coordinatorOf(WidgetTester tester) =>
    tester.element(find.byType(AsyncScopeCoordinator)) as AsyncScopeParent;

/// Pumps frames interleaved with slices of *real* time, until [until] holds or
/// the budget runs out.
///
/// The `StreamSubscription.cancel()` chain of
/// `AsyncScopeElementBase._performAsyncDispose` only makes progress outside the
/// test's fake-async zone, so `pumpAndSettle()` alone never reaches
/// `disposeAsync()`. The same workaround is documented in
/// `async_scope_test.dart` and `lite_scope_test.dart`.
Future<void> _settle(
  WidgetTester tester, {
  required bool Function() until,
}) async {
  for (var i = 0; i < 20 && !until(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 10));
  }
}

final class _TestScope extends AsyncScopeCore<_TestScope, _TestScopeElement> {
  final Object? testKey;
  final String? disposeLabel;
  final Duration disposeDelay;

  /// Holds [_TestScopeElement.disposeAsync] until it is completed.
  ///
  /// A gate keeps a disposal pending without leaving a timer behind, which a
  /// long [disposeDelay] would (the binding fails the test for a timer that
  /// outlives the widget tree).
  final Completer<void>? disposeGate;

  const _TestScope({
    this.testKey,
    this.disposeLabel,
    this.disposeDelay = Duration.zero,
    this.disposeGate,
    // `child` is inherited from `ProxyWidget`; declaring it again here would
    // shadow it (`overridden_fields`).
    super.child = const SizedBox.shrink(),
  });

  @override
  _TestScopeElement createScopeElement() => _TestScopeElement(this);
}

final class _TestScopeElement
    extends AsyncScopeElementBase<_TestScope, _TestScopeElement> {
  _TestScopeElement(super.widget);

  static int initialized = 0;
  static final disposalOrder = <String>[];

  static void reset() {
    initialized = 0;
    disposalOrder.clear();
  }

  @override
  Object? get scopeKey => widget.testKey;

  @override
  Stream<AsyncScopeInitState> initAsync() async* {
    initialized++;
    yield AsyncScopeReady();
  }

  @override
  FutureOr<void> disposeAsync() async {
    if (widget.disposeGate case final gate?) {
      await gate.future;
    }
    if (widget.disposeDelay > Duration.zero) {
      await Future<void>.delayed(widget.disposeDelay);
    }
    if (widget.disposeLabel case final label?) {
      disposalOrder.add(label);
    }
  }

  @override
  Widget buildOnState(AsyncScopeState state) => widget.child;
}
