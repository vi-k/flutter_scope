import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scopo/scopo.dart';

import 'utils/leaks.dart';

void main() {
  setUp(_TestScopeElement.reset);

  // The switches are global and several tests below move them. `reset()` puts
  // the lot back, so a test that changes one cannot reach the next.
  tearDown(ScopeConfig.reset);

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

    await _tearDownTree(tester, scopes: 2);
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

    await _tearDownTree(tester, scopes: 2);
  });

  testWidgets('a scopeKey without a coordinator is an error', (tester) async {
    // `_performAsyncInit()` is started from the first `performRebuild()` and
    // its future is discarded, so the `FlutterError` thrown by
    // `AsyncScopeCoordinator.enter` never reaches the framework's own error
    // handling: it surfaces as an uncaught error of the zone the mount ran in
    // (the first build happens inside `mount`). `tester.takeException()`
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

    await _tearDownTree(tester, scopes: 1);
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

    await _tearDownTree(tester, scopes: 1);
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

  // The other half of the same public API, and the half that had no default
  // at all: `null` reached `ChildRegistry` unchanged, and there `null` means
  // "no limit", so the most natural call of the method -- without arguments --
  // was the one that could wait for ever. The static helper on the
  // coordinator has always substituted the `ScopeConfig` default.
  testWidgets('the mixin waitForChildren applies the default timeout',
      (tester) async {
    final previous = ScopeConfig.defaultWaitForChildrenTimeout;
    ScopeConfig.defaultWaitForChildrenTimeout =
        const Duration(milliseconds: 50);
    addTearDown(() => ScopeConfig.defaultWaitForChildrenTimeout = previous);

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

    final parent =
        tester.element<_TestScopeElement>(find.byType(_TestScope).first);
    expect(parent.childrenCount, 1);

    var waited = false;
    unawaited(
      // No `timeout`, which is the point: the child never unregisters, so
      // anything but a default of its own leaves this future unsettled.
      parent.waitForChildren().then((_) => waited = true),
    );
    await _settle(tester, until: () => waited);

    expect(
      waited,
      isTrue,
      reason: 'the wait gave up on the configured default, the way the '
          'coordinator has always done',
    );
    expect(
      tester.takeException(),
      isA<TimeoutException>(),
      reason: 'and the expiry is reported',
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
  testWidgets(
    'the next scope on a key is let in only once the previous one has '
    'finished disposing',
    (tester) async {
      // The one thing the key promises: the successor does not start while
      // the holder is still releasing what it holds. `exit()` runs in the
      // `finally` of `_performAsyncDispose`, *after* `disposeAsync()`, and
      // this gate is what makes the difference observable — the holder sits
      // inside its disposal for as long as the test likes.
      final gate = Completer<void>();

      Widget build({required bool holder, required bool successor}) =>
          Directionality(
            textDirection: TextDirection.ltr,
            child: AsyncScopeCoordinator(
              child: Column(
                children: [
                  if (holder)
                    _TestScope(
                      key: const ValueKey('holder'),
                      testKey: 'k',
                      disposeLabel: 'holder',
                      disposeGate: gate,
                    ),
                  if (successor)
                    const _TestScope(
                      key: ValueKey('successor'),
                      testKey: 'k',
                      disposeLabel: 'successor',
                    ),
                ],
              ),
            ),
          );

      await tester.pumpWidget(build(holder: true, successor: false));
      await tester.pumpAndSettle();

      expect(_TestScopeElement.initialized, 1);

      // The holder leaves and the successor arrives in the same frame, so the
      // successor asks for the key while the holder is still inside
      // `disposeAsync`.
      await tester.pumpWidget(build(holder: false, successor: true));
      await _settle(tester, until: () => _TestScopeElement.initialized > 1);

      final successor = tester.element<_TestScopeElement>(
        find.byKey(const ValueKey('successor')),
      );

      expect(
        _TestScopeElement.initialized,
        1,
        reason: 'the successor is queued behind a key that is still held',
      );
      expect(
        successor.state,
        isA<AsyncScopeWaiting>(),
        reason: 'and it has not started initializing',
      );
      expect(_TestScopeElement.disposalOrder, isEmpty);

      gate.complete();
      await _settle(tester, until: () => _TestScopeElement.initialized > 1);

      expect(
        _TestScopeElement.disposalOrder,
        ['holder'],
        reason: 'the holder finished disposing first',
      );
      expect(
        _TestScopeElement.initialized,
        2,
        reason: 'and only then was the successor let in',
      );
      expect(
        successor.keyTimedOut,
        isFalse,
        reason: 'it was handed the key, not let in on an expired wait',
      );
      expect(tester.takeException(), isNull);
    },
  );

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

    await _tearDownTree(tester, scopes: 2);
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

    await _tearDownTree(tester, scopes: 1);
  });

  // A generator parked on a future that never completes cannot be cancelled:
  // `StreamSubscription.cancel()` waits for the body to end, and the body is
  // suspended at an `await` it will never come back from. The disposal waited
  // for that cancellation with no limit of its own, so it never reached the
  // release below it: the scope stayed registered with its parent, and its
  // `scopeKey` was never given back -- every later scope on that key queued
  // behind an entry nobody would ever complete.
  //
  // What proves the release is a later scope on the same key getting in and
  // initializing, with its own limit set far beyond anything this test can
  // advance: an expiry cannot be what let it in.
  testWidgets('a scopeKey is given back by a scope stuck in initAsync',
      (tester) async {
    // Short enough to expire inside `_settle`'s budget of real time.
    ScopeConfig.defaultInitCancellationTimeout =
        const Duration(milliseconds: 50);

    // Never completed: this is the hang under test.
    final hang = Completer<void>();

    Widget build({required bool hung, required bool successor}) =>
        Directionality(
          textDirection: TextDirection.ltr,
          child: AsyncScopeCoordinator(
            child: Column(
              children: [
                if (hung) _TestScope(testKey: 'shared', initGate: hang),
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

    await tester.pumpWidget(build(hung: true, successor: false));
    await tester.pumpAndSettle();

    expect(
      _TestScopeElement.initialized,
      1,
      reason: 'it got the key and is parked inside `initAsync()`',
    );

    // It leaves the tree while still parked. Nothing observable marks the
    // moment the disposal gives up -- `disposeAsync()` is skipped on a scope
    // that never initialized -- so the settle runs its whole budget.
    await tester.pumpWidget(build(hung: false, successor: false));
    await _settle(tester, until: () => false);

    expect(
      tester.takeException(),
      isA<TimeoutException>().having(
        (error) => error.message,
        'message',
        contains("couldn't wait for its initialization to be cancelled"),
      ),
      reason: 'giving up on a cancellation is reported, never silent',
    );

    await tester.pumpWidget(build(hung: false, successor: true));
    await _settle(
      tester,
      until: () => _TestScopeElement.initialized == 2,
    );
    await tester.pumpAndSettle();

    final successor =
        tester.element<_TestScopeElement>(find.byType(_TestScope));

    expect(
      successor.state,
      isA<AsyncScopeReady>(),
      reason: 'the stuck scope gave the key back on its way out',
    );
    expect(
      successor.keyTimedOut,
      isFalse,
      reason: 'it got the key, it was not let in on an expired wait',
    );

    // Only the successor: the scope this test hangs on purpose never finishes
    // its own teardown, which is the whole point of it.
    await _tearDownTree(tester, scopes: 1);
  });

  // The same hole one step further down the teardown. `disposeAsync()` is the
  // scope's own release, and it is user code: one that never completes held
  // the block that gives the key back exactly as an uncancellable
  // initialization did.
  //
  // Proved the same way: the successor's own limit is a day, so it can only be
  // in because the key came back.
  testWidgets('a scopeKey is given back by a scope stuck in disposeAsync',
      (tester) async {
    // Short enough to expire inside `_settle`'s budget of real time.
    ScopeConfig.defaultDisposeAsyncTimeout = const Duration(milliseconds: 50);

    // Never completed: this is the hang under test.
    final hang = Completer<void>();

    Widget build({required bool hung, required bool successor}) =>
        Directionality(
          textDirection: TextDirection.ltr,
          child: AsyncScopeCoordinator(
            child: Column(
              children: [
                if (hung) _TestScope(testKey: 'shared', disposeGate: hang),
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

    await tester.pumpWidget(build(hung: true, successor: false));
    await tester.pumpAndSettle();

    expect(_TestScopeElement.initialized, 1, reason: 'it holds the key');

    // It leaves the tree and parks inside its own teardown.
    await tester.pumpWidget(build(hung: false, successor: false));
    await _settle(tester, until: () => false);

    expect(
      tester.takeException(),
      isA<TimeoutException>().having(
        (error) => error.message,
        'message',
        contains("couldn't wait for its own teardown"),
      ),
      reason: 'giving up on a teardown is reported, never silent',
    );

    await tester.pumpWidget(build(hung: false, successor: true));
    await _settle(tester, until: () => _TestScopeElement.initialized == 2);
    await tester.pumpAndSettle();

    final successor =
        tester.element<_TestScopeElement>(find.byType(_TestScope));

    expect(
      successor.state,
      isA<AsyncScopeReady>(),
      reason: 'the stuck scope gave the key back on its way out',
    );
    expect(
      successor.keyTimedOut,
      isFalse,
      reason: 'it got the key, it was not let in on an expired wait',
    );

    // Only the successor: the scope this test hangs on purpose never finishes
    // its own teardown, which is the whole point of it.
    await _tearDownTree(tester, scopes: 1);
  });

  // A place in a queue is taken once and cannot be moved, so the pair
  // (`scopeKey`, owning coordinator) is fixed for the lifetime of the element.
  // Both ways of breaking that -- a `scopeKey` that starts returning something
  // else, and a `GlobalKey` move under a different coordinator -- used to leave
  // the entry parked on the old queue in silence, and the mutual exclusion the
  // key exists for simply stopped working. The violation is now loud in debug
  // builds.
  group('the scopeKey of a live scope', () {
    testWidgets(
      'cannot change',
      (tester) async {
        Widget build(Object key) => Directionality(
              textDirection: TextDirection.ltr,
              child: AsyncScopeCoordinator(child: _TestScope(testKey: key)),
            );

        await tester.pumpWidget(build('first'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(build('second'));

        final exception = tester.takeException();
        expect(exception, isA<FlutterError>());
        expect(
          exception.toString(),
          contains('`scopeKey`'),
          reason: 'the report says what happened',
        );
        expect(
          exception.toString(),
          contains('different `key`'),
          reason: 'and what to do instead',
        );
      },
      // The violation is raised while the element is being updated, and the
      // subtree it breaks stays unmounted -- see [unmountableTree].
      experimentalLeakTesting: unmountableTree,
    );

    // `null` is a value this getter may legitimately return, and a scope that
    // reads it as `null` decides just as irrevocably that it needs no key:
    // nothing takes an entry afterwards. `AsyncScope(scopeKey: userId)` with a
    // `userId` that is null until an async load finishes is ordinary usage, so
    // a key that turns up late is not exotic -- and it used to be completely
    // silent, because the check only ran once an entry existed.
    testWidgets(
      'cannot appear after the scope has mounted',
      (tester) async {
        Widget build(Object? lateKey) => Directionality(
              textDirection: TextDirection.ltr,
              child: AsyncScopeCoordinator(
                child: Column(
                  children: [
                    const _TestScope(testKey: 'shared'),
                    _TestScope(testKey: lateKey),
                  ],
                ),
              ),
            );

        await tester.pumpWidget(build(null));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          _TestScopeElement.initialized,
          2,
          reason: 'the second scope read no key, so it never queued for one',
        );

        await tester.pumpWidget(build('shared'));

        final exception = tester.takeException();
        expect(exception, isA<FlutterError>());
        expect(
          exception.toString(),
          contains('appeared'),
          reason:
              'the report says the key was never taken at all, which is not '
              'the same as an entry left on the wrong queue',
        );
        expect(
          exception.toString(),
          contains('different `key`'),
          reason: 'and says what to do instead',
        );
      },
      // The violation is raised while the element is being updated, and the
      // subtree it breaks stays unmounted -- see [unmountableTree].
      experimentalLeakTesting: unmountableTree,
    );

    testWidgets(
      'cannot be given up while the scope is holding it',
      (tester) async {
        Widget build(Object? key) => Directionality(
              textDirection: TextDirection.ltr,
              child: AsyncScopeCoordinator(child: _TestScope(testKey: key)),
            );

        await tester.pumpWidget(build('shared'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(build(null));

        final exception = tester.takeException();
        expect(exception, isA<FlutterError>());
        expect(
          exception.toString(),
          contains('given up'),
          reason: 'a key let go is not a key that changed: the entry is still '
              'held, by a scope that no longer claims to need it',
        );
        expect(
          exception.toString(),
          contains('different `key`'),
          reason: 'and says what to do instead',
        );
      },
      // The violation is raised while the element is being updated, and the
      // subtree it breaks stays unmounted -- see [unmountableTree].
      experimentalLeakTesting: unmountableTree,
    );

    testWidgets(
      'cannot move under another coordinator',
      (tester) async {
        // The very same widget instance on both sides of the move, so the
        // framework takes the `child.widget == newWidget` shortcut in
        // `updateChild` and never rebuilds the element it just reactivated:
        // `activate()` is then the only place left to notice the new
        // coordinator.
        final scope = _TestScope(key: GlobalKey(), testKey: 'shared');
        // `Expanded`, so the `ErrorWidget` the framework substitutes for the
        // failed build has bounded constraints: an unbounded one overflows the
        // `Column` and buries the report under a second, unrelated exception.
        Widget build({required bool moved}) => Directionality(
              textDirection: TextDirection.ltr,
              child: Column(
                children: [
                  Expanded(
                    child: AsyncScopeCoordinator(
                      child: moved ? const SizedBox.shrink() : scope,
                    ),
                  ),
                  Expanded(
                    child: AsyncScopeCoordinator(
                      child: moved ? scope : const SizedBox.shrink(),
                    ),
                  ),
                ],
              ),
            );

        await tester.pumpWidget(build(moved: false));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final [oldParent, newParent] = tester
            .elementList(find.byType(AsyncScopeCoordinator))
            .cast<AsyncScopeParent>()
            .toList();
        expect(oldParent.childrenCount, 1);

        await tester.pumpWidget(build(moved: true));

        final exception = tester.takeException();
        expect(exception, isA<FlutterError>());
        expect(
          exception.toString(),
          contains('$AsyncScopeCoordinator'),
          reason: 'the report names the coordinator the entry is parked on',
        );
        expect(
          exception.toString(),
          contains('different `key`'),
          reason: 'and says what to do instead',
        );

        // Reporting the violation must not cost the parent handoff the move
        // itself needs. The scope has left the first coordinator's subtree, and
        // it is alive and well under the second one: a diagnostic that unwound
        // `activate()` before `_registerWithParent()` would leave the first
        // coordinator waiting for it forever.
        expect(
          oldParent.childrenCount,
          0,
          reason: 'the coordinator the scope left must not keep waiting for it',
        );
        expect(
          newParent.childrenCount,
          1,
          reason: 'the coordinator it moved under is what waits for it now',
        );

        var waited = false;
        unawaited(
          oldParent
              .waitForChildren(timeout: const Duration(days: 1))
              .then((_) => waited = true),
        );
        await _settle(tester, until: () => waited);

        expect(
          waited,
          isTrue,
          reason: 'the limit is far beyond what this test can advance, so only '
              'an empty registry can have released the wait',
        );
      },
      // The violation is raised while the element is being updated, and the
      // subtree it breaks stays unmounted -- see [unmountableTree].
      experimentalLeakTesting: unmountableTree,
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

/// Removes the tree and lets the [scopes] still standing tear themselves down.
///
/// A test that ends while a scope is still in the middle of its asynchronous
/// teardown leaves the model of that scope undisposed, and the leak tracker
/// says so: `_model.dispose()` is the last thing the teardown does, and
/// `pumpAndSettle` never reaches it -- it moves the fake clock only, while the
/// teardown is a chain of real futures.
Future<void> _tearDownTree(WidgetTester tester, {required int scopes}) async {
  final before = _TestScopeElement.disposed;

  await tester.pumpWidget(const SizedBox.shrink());
  await _settle(
    tester,
    until: () => _TestScopeElement.disposed >= before + scopes,
  );
}

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

  /// Parks [_TestScopeElement.initAsync] on this until it is completed.
  ///
  /// A gate that is never completed is a generator that cannot be cancelled:
  /// the body is suspended at an `await`, so it never reaches the point where
  /// a cancellation could end it.
  final Completer<void>? initGate;

  const _TestScope({
    super.key,
    this.testKey,
    this.disposeLabel,
    this.disposeDelay = Duration.zero,
    this.keyTimeout,
    this.throwOnKeyTimeout = false,
    this.disposeGate,
    this.initGate,
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

  /// How many scopes have finished their `disposeAsync()`.
  ///
  /// The teardown is asynchronous and its last act is disposing of the model,
  /// so a test that ends before this counter moves ends on a scope that is
  /// still tearing down -- which the leak tracker reports.
  static int disposed = 0;
  static final disposalOrder = <String>[];

  static void reset() {
    initialized = 0;
    disposed = 0;
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
    if (widget.initGate case final gate?) {
      await gate.future;
    }
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
    disposed++;
  }

  @override
  Widget buildOnState(AsyncScopeState state) => widget.child;
}
