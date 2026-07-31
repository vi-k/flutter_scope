import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scopo/scopo.dart';

void main() {
  setUp(_TestScopeElement.reset);

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

  const _TestScope({
    this.testKey,
    this.disposeLabel,
    this.disposeDelay = Duration.zero,
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
