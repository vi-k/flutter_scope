import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scopo/scopo.dart';

import 'utils/observer.dart';
import 'utils/settle.dart';

/// `ScopeTimeout.none` is the one way to say "wait as long as it takes" for a
/// single scope.
///
/// Before it there were three values and all three were taken: absent or
/// `null` meant "take the default", `Duration.zero` meant "expire at once",
/// and any other `Duration` was the limit itself. Removing the limit was
/// possible only for every scope at once, through `ScopeConfig`.
///
/// Every test here is about an expiry that must *not* happen: the assertion is
/// that no `onTimeout` reaches the observer while the wait is held far past
/// the limit that would otherwise apply.
void main() {
  late RecordingObserver observer;

  setUp(() {
    observer = RecordingObserver();
    ScopeConfig.observer = observer;
    // A limit small enough that a bounded wait would certainly expire within
    // the rounds `settle` gives it.
    ScopeConfig.defaultScopeKeyTimeout = const Duration(milliseconds: 20);
    ScopeConfig.defaultDisposeScopeTimeout = const Duration(milliseconds: 20);
    ScopeConfig.defaultWaitForChildrenTimeout =
        const Duration(milliseconds: 20);
  });

  tearDown(() {
    ScopeConfig.observer = null;
    ScopeConfig.reset();
  });

  bool expired() => observer.events.any((e) => e.startsWith('timeout '));

  testWidgets('ScopeTimeout.none removes the limit on the wait for a scopeKey',
      (tester) async {
    final hold = Completer<void>();
    addTearDown(() {
      if (!hold.isCompleted) {
        hold.complete();
      }
    });

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: AsyncScopeCoordinator(
          child: Column(
            children: [
              _scope(tag: 'holder', scopeKey: 'shared', initGate: hold),
              _scope(
                tag: 'waiter',
                scopeKey: 'shared',
                scopeKeyTimeout: ScopeTimeout.none,
              ),
            ],
          ),
        ),
      ),
    );
    await settle(tester, until: () => false);

    expect(
      expired(),
      isFalse,
      reason: 'the default limit is 20ms and the wait was held far longer; '
          'without ScopeTimeout.none it would have given up',
    );
    expect(
      observer.events,
      isNot(contains('ready AsyncScope(waiter)')),
      reason: 'and it is still waiting rather than let in early',
    );

    hold.complete();
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester, until: () => false);
  });

  testWidgets("ScopeTimeout.none removes the limit on a scope's own teardown",
      (tester) async {
    final hold = Completer<void>();
    addTearDown(() {
      if (!hold.isCompleted) {
        hold.complete();
      }
    });

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: _scope(
          tag: 'slow',
          disposeGate: hold,
          disposeScopeTimeout: ScopeTimeout.none,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester, until: () => false);

    expect(expired(), isFalse, reason: 'the teardown is still allowed to run');
    expect(observer.events, isNot(contains('disposed AsyncScope(slow)')));

    hold.complete();
    await settle(tester, until: () => false);
  });

  testWidgets('ScopeTimeout.none removes the limit on the wait for children',
      (tester) async {
    final hold = Completer<void>();
    addTearDown(() {
      if (!hold.isCompleted) {
        hold.complete();
      }
    });

    Widget build({required bool present}) => Directionality(
          textDirection: TextDirection.ltr,
          child: present
              ? _parent(
                  waitForChildrenTimeout: ScopeTimeout.none,
                  child: _scope(
                    tag: 'child',
                    disposeGate: hold,
                    // Unbounded too: with the default 20 ms the child's own
                    // teardown would be given up on first, the parent would
                    // have nothing left to wait for, and the wait under test
                    // would never run out to begin with.
                    disposeScopeTimeout: ScopeTimeout.none,
                  ),
                )
              : const SizedBox.shrink(),
        );

    await tester.pumpWidget(build(present: true));
    await tester.pumpAndSettle();

    await tester.pumpWidget(build(present: false));
    await settle(tester, until: () => false);

    expect(
      observer.events,
      isNot(contains('timeout AsyncScope(parent) its child scopes')),
      reason: 'the parent waits for the child',
    );
    expect(observer.events, isNot(contains('disposed AsyncScope(parent)')));

    hold.complete();
    await settle(tester, until: () => false);
  });

  testWidgets(
      'ScopeTimeout.none as the default removes the limit on the wait for a '
      'cancelled initialization', (tester) async {
    // The one timeout a single scope may not remove for itself. Every piece of
    // documentation that says so sends the reader here to remove it for the
    // whole application instead, so this is the value a reader who followed
    // that advice writes.
    ScopeConfig.defaultInitCancellationTimeout = ScopeTimeout.none;

    final hold = Completer<void>();
    addTearDown(() {
      if (!hold.isCompleted) {
        hold.complete();
      }
    });

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: _scope(tag: 'cancelled', initGate: hold),
      ),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester, until: () => false);

    expect(
      expired(),
      isFalse,
      reason: 'the marker means "no limit at all" wherever it is written, and '
          'a global default that expires at once is the opposite of what was '
          'asked for',
    );
    expect(
      observer.events,
      isNot(contains('disposed AsyncScope(cancelled)')),
      reason: 'and the teardown is still waiting for the cancellation',
    );

    hold.complete();
    await settle(
      tester,
      until: () => observer.events.contains('disposed AsyncScope(cancelled)'),
    );
    expect(
      observer.events,
      contains('disposed AsyncScope(cancelled)'),
      reason: 'the wait was unbounded, not stuck: letting the generator run '
          'out finishes it',
    );
  });

  testWidgets('ScopeTimeout.none is refused by pauseAfterInitialization',
      (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: _scope(
          tag: 'paused',
          pauseAfterInitialization: ScopeTimeout.none,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      observer.events.where((event) => event.contains('initialization')),
      contains(contains('not accepted by pauseAfterInitialization')),
      reason: 'a pause is a length of time, not a limit on a wait: "wait as '
          'long as it takes" says nothing here, and used to mean "do not '
          'pause at all" -- the opposite of the one thing the parameter does',
    );
  });

  testWidgets('a Duration that lost the marker is refused, not run at once',
      (tester) async {
    late BuildContext context;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: AsyncScopeCoordinator(
          child: Builder(
            builder: (innerContext) {
              context = innerContext;

              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(
      () => AsyncScopeCoordinator.waitForChildren(
        context,
        // What arithmetic leaves of the marker: `ScopeTimeout.none` is
        // recognised by its type, and `+` gives back a plain [Duration]. All
        // that survives is the negative length behind it, which a timer reads
        // as "expire at once" -- the opposite of what was written.
        // ignore: prefer_const_constructors
        timeout: ScopeTimeout.none + Duration.zero,
      ),
      throwsAssertionError,
    );
  });

  testWidgets('ScopeTimeout.none is refused by initCancellationTimeout',
      (tester) async {
    final hold = Completer<void>();
    addTearDown(() {
      if (!hold.isCompleted) {
        hold.complete();
      }
    });

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: _scope(
          tag: 'cancelled',
          initGate: hold,
          initCancellationTimeout: ScopeTimeout.none,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The teardown is what reads the value, so the refusal lands there. The
    // cancellation stage guards itself -- a failure there must not replace
    // the teardown it was entered for -- so the assertion arrives as an
    // `onError` of that phase rather than as an uncaught error, and the
    // teardown goes on to the end.
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(
      tester,
      until: () => observer.events.contains('disposed AsyncScope(cancelled)'),
    );

    // The same assertion also goes to `FlutterError.reportError`, which the
    // harness turns into an exception of its own; taken here so it does not
    // end the test on its way out.
    expect(tester.takeException(), isA<AssertionError>());

    expect(
      observer.events.where(
        (event) => event.contains('initializationCancellation'),
      ),
      contains(contains('not accepted by initCancellationTimeout')),
      reason: 'a cancellation that waits with no limit is the hang the limit '
          'was put there to prevent',
    );
    expect(
      observer.events,
      contains('disposed AsyncScope(cancelled)'),
      reason: 'and the teardown still finishes rather than hanging on it',
    );

    hold.complete();
    await settle(tester, until: () => false);
  });
}

Widget _scope({
  required String tag,
  Object? scopeKey,
  Completer<void>? initGate,
  Completer<void>? disposeGate,
  Duration? scopeKeyTimeout,
  Duration? disposeScopeTimeout,
  Duration? initCancellationTimeout,
  Duration? pauseAfterInitialization,
}) =>
    AsyncScope(
      tag: tag,
      scopeKey: scopeKey,
      scopeKeyTimeout: scopeKeyTimeout,
      disposeScopeTimeout: disposeScopeTimeout,
      initCancellationTimeout: initCancellationTimeout,
      pauseAfterInitialization: pauseAfterInitialization,
      initScope: (context) async* {
        if (initGate != null) {
          await initGate.future;
        }
        yield AsyncScopeReady();
      },
      disposeScope: () async {
        if (disposeGate != null) {
          await disposeGate.future;
        }
      },
      progressBuilder: (context, progress) => const SizedBox.shrink(),
      builder: (context) => const SizedBox.shrink(),
      errorBuilder: (context, error, stackTrace, progress) =>
          const SizedBox.shrink(),
    );

Widget _parent({
  required Widget child,
  Duration? waitForChildrenTimeout,
}) =>
    AsyncScope(
      tag: 'parent',
      waitForChildrenTimeout: waitForChildrenTimeout,
      initScope: (context) => Stream.value(AsyncScopeReady()),
      disposeScope: () {},
      progressBuilder: (context, progress) => const SizedBox.shrink(),
      builder: (context) => child,
      errorBuilder: (context, error, stackTrace, progress) =>
          const SizedBox.shrink(),
    );
