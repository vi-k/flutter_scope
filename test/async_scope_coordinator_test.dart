import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scopo/scopo.dart';

void main() {
  // Captured eagerly, before any test can change them: a lazy top-level
  // `final` initializes on its first read -- inside the first `tearDown` --
  // so it would capture whatever the test that ran first left behind.
  late final Duration? defaultScopeKeysTimeout;
  late final Duration? defaultWaitForChildrenTimeout;

  setUpAll(() {
    defaultScopeKeysTimeout = ScopeConfig.defaultScopeKeysTimeout;
    defaultWaitForChildrenTimeout = ScopeConfig.defaultWaitForChildrenTimeout;
  });

  setUp(_TestScopeElement.reset);

  tearDown(() {
    ScopeConfig.defaultScopeKeysTimeout = defaultScopeKeysTimeout;
    ScopeConfig.defaultWaitForChildrenTimeout = defaultWaitForChildrenTimeout;
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
    Widget build({required bool withScope}) => _coordinatorTree(
          withScope: withScope,
          gate: gate,
          onContext: (builderContext) => context = builderContext,
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

  // The two tests below pin the defaults of the public `waitForChildren`:
  // without them the wait is unbounded again, or silent again, and the suite
  // stays green.
  testWidgets('waitForChildren gives up on time and reports the expiry',
      (tester) async {
    ScopeConfig.defaultWaitForChildrenTimeout =
        const Duration(milliseconds: 50);
    final gate = Completer<void>();
    late BuildContext context;
    Widget build({required bool withScope}) => _coordinatorTree(
          withScope: withScope,
          gate: gate,
          onContext: (builderContext) => context = builderContext,
        );

    await tester.pumpWidget(build(withScope: true));
    await tester.pumpAndSettle();
    // The scope leaves the tree and hangs in `disposeAsync`; the coordinator
    // stays mounted and keeps waiting for it.
    await tester.pumpWidget(build(withScope: false));

    Object? error;
    var waited = false;
    unawaited(
      // No `timeout` and no `onTimeout`: both defaults are what is under test.
      AsyncScopeCoordinator.waitForChildren(context).then(
        (_) => waited = true,
        onError: (Object failure) => error = failure,
      ),
    );
    await _settle(tester, until: () => waited || error != null);

    expect(error, isNull, reason: 'an expiry completes the future normally');
    expect(
      waited,
      isTrue,
      reason:
          'the wait is bounded by ScopeConfig.defaultWaitForChildrenTimeout',
    );
    expect(
      _TestScopeElement.disposalOrder,
      isEmpty,
      reason: 'the scope never finished; the wait gave up on it',
    );

    final exception = tester.takeException();
    expect(
      exception,
      isA<TimeoutException>(),
      reason: 'an expiry is reported even without an onTimeout callback',
    );
    expect(
      (exception as TimeoutException).message,
      startsWith('$AsyncScopeCoordinator'),
      reason: 'the coordinator puts its own name in front of the message',
    );

    gate.complete();
    await _settle(
      tester,
      until: () => _TestScopeElement.disposalOrder.isNotEmpty,
    );
  });

  testWidgets('waitForChildren reports an expiry that outlives the coordinator',
      (tester) async {
    ScopeConfig.defaultWaitForChildrenTimeout =
        const Duration(milliseconds: 50);
    final gate = Completer<void>();
    late BuildContext context;

    await tester.pumpWidget(
      _coordinatorTree(
        withScope: true,
        gate: gate,
        onContext: (builderContext) => context = builderContext,
      ),
    );
    await tester.pumpAndSettle();

    Object? error;
    var waited = false;
    unawaited(
      AsyncScopeCoordinator.waitForChildren(context).then(
        (_) => waited = true,
        onError: (Object failure) => error = failure,
      ),
    );

    // The whole tree goes away while the wait is running -- "before tearing
    // down a test" is the documented use case -- so the coordinator's element
    // is unmounted by the time the timeout fires and its widget is gone.
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox.shrink(),
      ),
    );
    await _settle(tester, until: () => waited || error != null);

    expect(error, isNull, reason: 'an expiry completes the future normally');
    expect(waited, isTrue);

    final exception = tester.takeException();
    expect(exception, isA<TimeoutException>());
    expect(
      (exception as TimeoutException).message,
      startsWith('$AsyncScopeCoordinator'),
    );

    gate.complete();
    await _settle(
      tester,
      until: () => _TestScopeElement.disposalOrder.isNotEmpty,
    );
  });

  // `AsyncScopeParent.waitForChildren` is public API in its own right, not
  // just the plumbing behind the static helper: `AsyncScopeCore.of` hands out
  // the element, and every custom `AsyncScopeElementBase` exposes the method.
  // Called without an `onTimeout` it must report the expiry itself, or a
  // dropped child is total silence.
  testWidgets('the mixin waitForChildren reports an expiry by default',
      (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: _TestScope(
          disposeLabel: 'parent',
          child: _TestScope(disposeLabel: 'child'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The very object `AsyncScopeCore.of<_TestScope, _TestScopeElement>(
    // context, listen: false)` returns for the outer scope.
    final parent =
        tester.element<_TestScopeElement>(find.byType(_TestScope).first);
    expect(parent.childrenCount, 1);

    Object? error;
    var waited = false;
    unawaited(
      // No `onTimeout`: its default is what is under test. The child scope is
      // still mounted and never unregisters, so the wait can only expire.
      parent.waitForChildren(timeout: const Duration(milliseconds: 50)).then(
            (_) => waited = true,
            onError: (Object failure) => error = failure,
          ),
    );
    await _settle(tester, until: () => waited || error != null);

    expect(error, isNull, reason: 'an expiry completes the future normally');
    expect(waited, isTrue);

    final exception = tester.takeException();
    expect(
      exception,
      isA<TimeoutException>(),
      reason: 'an expiry is reported even without an onTimeout callback',
    );
    expect(
      (exception as TimeoutException).message,
      startsWith('$_TestScope'),
      reason: 'the element puts its own short description in front of the '
          'message the registry builds',
    );
    expect(
      find.byType(_TestScope),
      findsNWidgets(2),
      reason: 'the child that was dropped is still mounted -- nothing was '
          'really waited for, so the silence would have been the whole story',
    );
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

  // An expired `scopeKey` wait lets the scope in anyway and reports the
  // expiry, so `onScopeKeyTimeout()` -- ordinary user code -- runs with the
  // entry already in the queue. A failure there used to drop the entry from
  // the element, and the disposal's `exit()` then never released the key: the
  // queue kept an entry nobody would ever complete, and every later scope on
  // that key waited for it with no way out.
  //
  // The assertion is about effects, never about timings: what proves it is
  // that a later scope on the same key gets in and initializes, without
  // having had to give up on the wait (`keyTimedOut`), and its own limit is
  // set far beyond what the test can advance, so an expiry cannot be what let
  // it in.
  testWidgets('a failing onScopeKeyTimeout does not leak the scopeKey',
      (tester) async {
    Widget build({
      required bool holder,
      required bool waiter,
      required bool successor,
    }) =>
        Directionality(
          textDirection: TextDirection.ltr,
          child: AsyncScopeCoordinator(
            child: Column(
              children: [
                if (holder)
                  const _TestScope(testKey: 'shared', disposeLabel: 'holder'),
                if (waiter)
                  const _TestScope(
                    testKey: 'shared',
                    keyTimeout: Duration(milliseconds: 50),
                    throwOnKeyTimeout: true,
                  ),
                if (successor)
                  const _TestScope(
                    testKey: 'shared',
                    disposeLabel: 'successor',
                    keyTimeout: Duration(days: 1),
                  ),
              ],
            ),
          ),
        );

    // The hook's failure surfaces as an uncaught error of the zone the mount
    // ran in -- `_performAsyncInit()`'s future is discarded -- so a guarded
    // child zone catches it before `flutter_test` ends the test on it.
    // Nothing inside that zone may throw, so every `expect` is made once it
    // is gone.
    final errors = <Object>[];
    await runZonedGuarded(
      () async {
        await tester.pumpWidget(
          build(holder: true, waiter: false, successor: false),
        );
        await tester.pumpAndSettle();

        // The waiter queues up behind the holder and its limit expires: it is
        // let in anyway, the expiry is reported, and `onScopeKeyTimeout()`
        // throws.
        await tester
            .pumpWidget(build(holder: true, waiter: true, successor: false));
        await tester.pump(const Duration(milliseconds: 100));
      },
      (error, stackTrace) => errors.add(error),
    );

    expect(errors, hasLength(1));
    expect(errors.single, isA<StateError>());
    expect(
      tester.takeException(),
      isA<TimeoutException>(),
      reason: 'the expiry itself is still reported',
    );

    // Both scopes leave; the holder releases the key on the way out, and so
    // must the waiter whose hook threw.
    await tester
        .pumpWidget(build(holder: false, waiter: false, successor: false));
    await _settle(
      tester,
      until: () => _TestScopeElement.disposalOrder.contains('holder'),
    );
    expect(_TestScopeElement.disposalOrder, ['holder']);

    await tester
        .pumpWidget(build(holder: false, waiter: false, successor: true));
    await tester.pumpAndSettle();

    final successor =
        tester.element<_TestScopeElement>(find.byType(_TestScope));

    expect(
      successor.state,
      isA<AsyncScopeReady>(),
      reason: 'the key was released, so the next scope got in at once',
    );
    expect(
      successor.keyTimedOut,
      isFalse,
      reason: 'it got the key, it was not let in on an expired wait',
    );
    expect(tester.takeException(), isNull);
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

/// A coordinator over an optional gated scope, plus a [Builder] whose context
/// stays valid after that scope has left the tree.
Widget _coordinatorTree({
  required bool withScope,
  required Completer<void> gate,
  required ValueSetter<BuildContext> onContext,
}) =>
    Directionality(
      textDirection: TextDirection.ltr,
      child: AsyncScopeCoordinator(
        child: Column(
          children: [
            if (withScope) _TestScope(disposeLabel: 'top', disposeGate: gate),
            Builder(
              builder: (context) {
                onContext(context);

                return const SizedBox.shrink();
              },
            ),
          ],
        ),
      ),
    );

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

  /// Overrides [AsyncScopeElementBase.scopeKeyTimeout] for this scope only,
  /// so one scope in a tree can expire while another one cannot.
  final Duration? keyTimeout;

  /// Makes [AsyncScopeElementBase.onScopeKeyTimeout] fail, the way a plain
  /// user error in an overridden hook does.
  final bool throwOnKeyTimeout;

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
    this.keyTimeout,
    this.throwOnKeyTimeout = false,
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
  /// Whether this scope had to be let into its key without ever getting it.
  bool keyTimedOut = false;

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
  Duration? get scopeKeyTimeout => widget.keyTimeout ?? super.scopeKeyTimeout;

  @override
  void onScopeKeyTimeout() {
    keyTimedOut = true;
    if (widget.throwOnKeyTimeout) {
      throw StateError('onScopeKeyTimeout failed');
    }
  }

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
