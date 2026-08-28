import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scopo/scopo.dart';
import 'package:scopo/src/environment/scope_config.dart' show notifyObserver;

import 'utils/observer.dart';
import 'utils/settle.dart';

void main() {
  late RecordingObserver observer;

  setUp(() {
    observer = RecordingObserver();
    ScopeConfig.observer = observer;
  });

  tearDown(() {
    ScopeConfig.observer = null;
  });

  group('ScopeCompositeObserver', () {
    // `ScopeConfig.observer` holds one, and wanting two is ordinary. A
    // delegate written by hand is the one subclass that gets nothing from
    // `ScopeObserver` being a `base class` with empty hooks: a hook added
    // later arrives with the base implementation and every observer behind the
    // delegate goes quiet without a word. This one is the package's, so it
    // grows with the class it forwards.
    test('hands every event to each observer, in order', () {
      final first = RecordingObserver(trace: true);
      final second = RecordingObserver(trace: true);
      final order = <String>[];

      ScopeConfig.observer = ScopeCompositeObserver([
        _MarkingObserver(order, 'first', first),
        _MarkingObserver(order, 'second', second),
      ]);

      final target = _Target();
      notifyObserver((observer) => observer.onInit(target));
      notifyObserver((observer) => observer.onTrace(target, 'a step'));

      expect(first.events, ['init target', 'trace target a step']);
      expect(second.events, first.events, reason: 'both heard the same');
      expect(
        order,
        ['first', 'second', 'first', 'second'],
        reason: 'and in the order they were given, one event at a time',
      );
    });

    // The trade `ScopeConfig.observer` makes for itself, applied one level
    // down: one bad listener is not the whole recording.
    test('an observer that throws does not stop the ones behind it', () {
      final reported = <Object>[];
      final previousOnError = FlutterError.onError;
      FlutterError.onError = (details) => reported.add(details.exception);
      addTearDown(() => FlutterError.onError = previousOnError);

      final behind = RecordingObserver();

      ScopeConfig.observer = ScopeCompositeObserver([
        const _ThrowingOnReadyObserver(),
        behind,
      ]);

      final target = _Target();
      notifyObserver((observer) => observer.onReady(target));

      FlutterError.onError = previousOnError;

      expect(behind.events, ['ready target']);
      expect(reported.single, isA<StateError>());
    });
  });

  testWidgets(
      'a scope built on the asynchronous element reports its own phase, not '
      'the bare pair', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: _CounterScope(child: SizedBox()),
      ),
    );

    // `LiteScope` -- `_CounterScope`'s family -- is built on
    // `AsyncScopeElementBase`: its `initScope()` defaults to an immediate
    // `AsyncScopeReady()`, same as a bare `AsyncScope`. `reportsOwnLifecycle`
    // is therefore `true`, so the single `onInit` below is the asynchronous
    // phase's own -- the structural pair `ScopeWidgetElementBase` fires for
    // every other family is suppressed here, not doubled with it.
    expect(observer.events, ['init _CounterScope', 'ready _CounterScope']);

    await tester.pumpWidget(const SizedBox());

    // The asynchronous teardown -- `dispose`/`disposed` below -- runs on the
    // real event loop rather than the fake clock `pump` advances, so it is
    // not necessarily done the instant the widget leaves the tree. `settle()`
    // gives it the chance `pump`/`pumpAndSettle` cannot.
    await settle(
      tester,
      until: () => observer.events.contains('disposed _CounterScope'),
    );

    expect(observer.events, [
      'init _CounterScope',
      'ready _CounterScope',
      'dispose _CounterScope',
      'disposed _CounterScope',
    ]);
  });

  testWidgets(
      'a scope with no phase of its own reports exactly the structural pair',
      (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: _PlainScope(child: SizedBox()),
      ),
    );

    // `ScopeWidgetBase` -- `_PlainScope`'s family -- goes no further than
    // `ScopeWidgetElementBase` itself: it runs no initialization of its own,
    // so `reportsOwnLifecycle` keeps its default `false` and this is the bare
    // reporting `ScopeWidgetElementBase` gives every such family: `onInit`,
    // then `onDispose` and `onDisposed` as a pair around the teardown.
    expect(observer.events, ['init _PlainScope']);

    await tester.pumpWidget(const SizedBox());

    expect(observer.events, [
      'init _PlainScope',
      'dispose _PlainScope',
      'disposed _PlainScope',
    ]);
  });

  testWidgets(
      'a scope whose init() throws reports neither half of the structural '
      'pair', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: _FailingInitScope(),
      ),
    );

    expect(tester.takeException(), isA<StateError>());

    // `init()` threw before `_initPhase` ever reached `done`, so `build()`
    // never sent `onInit` -- and the teardown pair belongs to a scope that
    // announced one: `unmountScope()`/`dispose()` still run internally (the
    // "symmetry, not success" comment on `unmount()`), but nothing is
    // reported for a teardown nobody was told had opened. The failure itself
    // is reported, and it is the whole of what this scope has to say.
    expect(observer.events, [
      'error _FailingInitScope initialization Bad state: init failed',
    ]);

    await tester.pumpWidget(const SizedBox());

    expect(
      observer.events,
      ['error _FailingInitScope initialization Bad state: init failed'],
      reason: 'no onInit was ever sent, so the teardown reports no '
          'onDispose/onDisposed either',
    );
  });

  testWidgets(
      'a scope with a phase of its own whose init() throws reports the '
      'failure through the same point', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: _FailingInitAsyncScope(),
      ),
    );

    expect(tester.takeException(), isA<StateError>());

    // `reportsOwnLifecycle` is `true` here, and that is why this event has to
    // come from `build()` rather than from the asynchronous half: the phase
    // that reports its own failures is started from `performRebuild` only
    // when `_didInit` holds, so an `init()` that threw leaves it never
    // started and with nothing to say. The synchronous hook is the one place
    // both kinds of family pass through.
    expect(observer.events, [
      'error _FailingInitAsyncScope initialization Bad state: init failed',
    ]);

    await tester.pumpWidget(const SizedBox());
    await settle(
      tester,
      until: () => observer.events.contains('disposed _FailingInitAsyncScope'),
    );

    // The teardown pair follows all the same, and that is the difference
    // between the two kinds of family: a phase-reporting one closes
    // `onDispose`/`onDisposed` whichever way the scope went, while the
    // structural one above reports neither half without an `onInit` of its
    // own. What is absent here is `onCancelled`: there was no initialization
    // to cancel.
    expect(observer.events, [
      'error _FailingInitAsyncScope initialization Bad state: init failed',
      'dispose _FailingInitAsyncScope',
      'disposed _FailingInitAsyncScope',
    ]);
  });

  testWidgets(
      'a controller that cannot be released after a failed initialization '
      'reports the disposal failure', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: _FailingControllerScope(),
      ),
    );
    await tester.pumpAndSettle();

    // The secondary failure still leaves through `FlutterError.reportError`,
    // which the test harness turns into an exception of its own; taken here so
    // it does not fail the test on its way out.
    expect(tester.takeException(), isA<StateError>());

    // `_releaseController` is the only path that gives a controller back when
    // the initialization never handed it over, and its failure used to reach
    // `FlutterError.reportError` alone. The expiry of the very same wait
    // reaches the observer (`onTimeout` with `its controller to be released`),
    // so an observer heard about a release that ran too long and nothing at
    // all about one that failed.
    expect(
      observer.events,
      contains(
        'error _FailingControllerScope disposal Bad state: dispose failed',
      ),
    );

    await tester.pumpWidget(const SizedBox());
    await settle(
      tester,
      until: () => observer.events.contains('disposed _FailingControllerScope'),
    );
  });

  testWidgets(
      "a ScopeModel whose dispose callback throws reports the scope's "
      'disposal failure', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ScopeModel<_Model>(
          create: (context) => _Model(),
          dispose: (model) => throw StateError('dispose failed'),
          builder: (context) => const SizedBox.shrink(),
        ),
      ),
    );

    expect(observer.events, ['init ScopeModel<_Model>']);

    // Only the scope is taken away, and the `Directionality` above it stays:
    // the failure escapes `Element.unmount()`, and the framework's walk over
    // the rest of the tree ends with it. Swapping the whole tree here left an
    // element of the view scope undisposed, and the leak tracker counted it —
    // a property of a throwing teardown, not of this scope.
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(),
      ),
    );

    // `dispose` here is the callback of a public parameter, and it runs from
    // the `finally` of `unmount()` -- outside the guard that reports
    // `unmountScope()` beside it. Its failure used to leave for the framework
    // and no further, so the recording closed the pair as if the teardown had
    // gone through.
    expect(tester.takeException(), isA<StateError>());
    expect(observer.events, [
      'init ScopeModel<_Model>',
      'dispose ScopeModel<_Model>',
      'error ScopeModel<_Model> disposal Bad state: dispose failed',
      'disposed ScopeModel<_Model>',
    ]);
  });

  testWidgets('an expired wait for a scopeKey reports onTimeout',
      (tester) async {
    final hang = Completer<void>();
    addTearDown(() {
      if (!hang.isCompleted) {
        hang.complete();
      }
    });

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: AsyncScopeCoordinator(
          child: Column(
            children: [
              _keyed(tag: 'first', gate: hang),
              _keyed(tag: 'second', scopeKeyTimeout: _short),
            ],
          ),
        ),
      ),
    );

    await settle(
      tester,
      until: () => observer.events.any((event) => event.startsWith('timeout ')),
    );
    expect(tester.takeException(), isA<TimeoutException>());

    // The other four bounded waits have reported through the observer since
    // the observer existed; this one and the wait for children reported only
    // through `FlutterError` and the scope's own callback.
    expect(
      observer.events,
      contains('timeout AsyncScope(second) access to its scopeKey'),
    );

    // Both scopes are still standing, and the first is still parked in its
    // initialization. Letting it go and taking the tree away is what keeps
    // the leak tracker looking at the package rather than at the gate this
    // test holds: the model is disposed of by the last step of the teardown,
    // and the teardown is a chain of real futures.
    hang.complete();
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(
      tester,
      until: () =>
          observer.events.where((e) => e.startsWith('disposed ')).length >= 3,
    );
  });

  testWidgets('an expired wait for the children reports onTimeout',
      (tester) async {
    final childGate = Completer<void>();
    addTearDown(() {
      if (!childGate.isCompleted) {
        childGate.complete();
      }
    });

    // No coordinator: a child registers with the nearest `AsyncScopeParent`,
    // which here is the parent scope itself. The `Directionality` stays put
    // and only the scope is swapped out -- the shape the neighbouring test of
    // this same wait uses, and the one that leaves the leak tracker looking
    // at the package rather than at a tree pulled out from under a teardown.
    Widget build({required bool present}) => Directionality(
          textDirection: TextDirection.ltr,
          child: present
              ? _parent(
                  waitForChildrenTimeout: _short,
                  child: _held(childGate),
                )
              : const SizedBox.shrink(),
        );

    await tester.pumpWidget(build(present: true));
    await tester.pumpAndSettle();

    await tester.pumpWidget(build(present: false));
    await settle(
      tester,
      until: () => observer.events.contains('disposed AsyncScope(parent)'),
    );

    // The other four bounded waits have reported through the observer since
    // the observer existed; this one and the wait for a `scopeKey` reported
    // only through `FlutterError` and the scope's own callback.
    expect(
      observer.events,
      contains('timeout AsyncScope(parent) its child scopes'),
    );
    expect(tester.takeException(), isA<TimeoutException>());

    childGate.complete();
    await settle(tester, until: () => false);
  });

  testWidgets('a throwing observer does not reach the scope', (tester) async {
    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = previous);

    ScopeConfig.observer = _ThrowingObserver();

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: _CounterScope(child: Text('built')),
      ),
    );

    expect(
      find.text('built'),
      findsOneWidget,
      reason: 'the scope builds its subtree even though the observer threw',
    );
    expect(errors, hasLength(1));
    expect(errors.single.library, 'scopo');

    // See the first test: lets the scope's own asynchronous teardown finish
    // before the leak tracker looks for what it releases.
    await tester.pumpWidget(const SizedBox());
    await settle(tester, until: () => false);
  });

  test(
      'an observer that produces a scope event of its own is stopped after '
      'the first', () {
    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = previous);

    ScopeConfig.observer = _NestingObserver();

    notifyObserver((observer) => observer.onInit(const _FakeObservable()));

    expect(
      errors,
      hasLength(1),
      reason: 'the nested notification is refused rather than attempted, so '
          'exactly one failure is reported and the call returns normally',
    );
  });

  test('reset() leaves the observer alone', () {
    final observer = RecordingObserver();
    ScopeConfig.observer = observer;

    ScopeConfig.reset();

    expect(ScopeConfig.observer, same(observer));
  });

  testWidgets(
    'an asynchronous scope reports initialization, progress and disposal',
    (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: _AsyncScope(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox());
      await settle(
        tester,
        until: () => observer.events.contains('disposed _AsyncScope'),
      );

      expect(observer.events, [
        'init _AsyncScope',
        'progress _AsyncScope 1/2',
        'progress _AsyncScope 2/2',
        'ready _AsyncScope',
        'dispose _AsyncScope',
        'disposed _AsyncScope',
      ]);
    },
  );

  testWidgets(
    'an initialization that throws reports onError for the initialization '
    'phase',
    (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: AsyncScope(
            initScope: (context) async* {
              yield AsyncScopeProgress('step');
              throw StateError('init failed');
            },
            disposeScope: () {},
            progressBuilder: (context, progress) => const Text('init'),
            errorBuilder: (context, error, stackTrace, progress) =>
                Text('$error'),
            builder: (context) => const Text('ready'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(observer.events, [
        'init AsyncScope',
        'progress AsyncScope step',
        'error AsyncScope initialization Bad state: init failed',
      ]);
    },
  );

  testWidgets(
    'a teardown that throws reports onError for the disposal phase',
    (tester) async {
      // `_performAsyncDispose()` runs from a future `dispose()` discards, so
      // the failure it re-throws at the end has nobody to be handed to. It
      // used to leave as an unhandled error of the zone, which is why this
      // test was written around `runZonedGuarded`; it is reported through
      // `FlutterError.reportError` now, like every other failure of a teardown
      // with no caller, and the harness turns that into an exception of the
      // test.
      Widget build({required bool present}) => Directionality(
            textDirection: TextDirection.ltr,
            child: present
                ? AsyncScope(
                    initScope: (context) => Stream.value(AsyncScopeReady()),
                    disposeScope: () => throw StateError('dispose failed'),
                    progressBuilder: (context, progress) => const Text('init'),
                    errorBuilder: (context, error, stackTrace, progress) =>
                        Text('$error'),
                    builder: (context) => const Text('ready'),
                  )
                : const SizedBox.shrink(),
          );

      await tester.pumpWidget(build(present: true));
      await tester.pumpAndSettle();

      await tester.pumpWidget(build(present: false));
      await settle(
        tester,
        until: () => observer.events.contains('disposed AsyncScope'),
      );

      expect(observer.events, [
        'init AsyncScope',
        'ready AsyncScope',
        'dispose AsyncScope',
        'error AsyncScope disposal Bad state: dispose failed',
        // After the failure and because of it, not instead of it: the scope
        // is gone either way, and an observer that pairs `dispose` with
        // `disposed` would otherwise count this teardown as still running.
        'disposed AsyncScope',
      ]);
      expect(
        tester.takeException(),
        isA<StateError>(),
        reason: 'the failure still leaves the package, and by the channel an '
            'application actually watches',
      );
    },
  );

  // `close()` is the only path on which the first stage of a teardown can
  // fail at all: a scope taken off the tree has already been unmounted by the
  // framework -- `ScopeWidgetElementBase.unmount()` runs `unmountScope()`
  // before it starts the asynchronous half -- so by the time the teardown
  // reaches that stage it is a no-op there.
  testWidgets(
    'a failing onUnmount reports onError for the unmount phase',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(child: _ClosingScope(failUnmount: true)),
        ),
      );
      await tester.pumpAndSettle();

      Object? failure;
      var done = false;
      unawaited(
        tester
            .element<_ClosingScopeElement>(
              find.byType(_ClosingScope, skipOffstage: false),
            )
            .close()
            .then(
          (_) => done = true,
          onError: (Object error) {
            failure = error;
            done = true;
          },
        ),
      );
      await settle(tester, until: () => done);

      final eventsAfterClose = List.of(observer.events);
      expect(eventsAfterClose, [
        'init _ClosingScope',
        'ready _ClosingScope',
        'dispose _ClosingScope',
        'error _ClosingScope unmount Bad state: onUnmount failed',
        'disposed _ClosingScope',
      ]);
      expect(
        failure,
        isA<StateError>(),
        reason: 'the caller of close() still hears the first failure',
      );

      // A closed scope stays mounted, and taking it off the tree afterwards
      // does *not* run a second teardown over it:
      // `LiteScopeElementBase._performAsyncDispose()` returns the
      // `_closeCompleter.future` that `close()` above already completed,
      // rather than running its body again, so the framework's own
      // `unmount()` reports nothing new. Now that the pair is a counting
      // contract, that is asserted rather than left to the comment above.
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester, until: () => false);

      expect(
        observer.events,
        eventsAfterClose,
        reason: 'no second onDispose/onDisposed for a teardown that already '
            'ran',
      );
    },
  );

  // The second stage of the teardown, and the one place in it that reaches
  // user code without a guard of its own: the expiry callback of the wait for
  // the child scopes. The child below is held open, so the wait can only run
  // out.
  testWidgets(
    'a failing onWaitForChildrenTimeout reports onError for the preparation '
    'phase',
    (tester) async {
      final childGate = Completer<void>();
      addTearDown(() {
        if (!childGate.isCompleted) {
          childGate.complete();
        }
      });

      Widget build({required bool present}) => Directionality(
            textDirection: TextDirection.ltr,
            child: present
                ? AsyncScope(
                    tag: 'parent',
                    waitForChildrenTimeout: const Duration(milliseconds: 50),
                    onWaitForChildrenTimeout: () =>
                        throw StateError('onWaitForChildrenTimeout failed'),
                    initScope: (context) => Stream.value(AsyncScopeReady()),
                    disposeScope: () {},
                    progressBuilder: (context, progress) => const Text('init'),
                    errorBuilder: (context, error, stackTrace, progress) =>
                        Text('$error'),
                    builder: (context) => AsyncScope(
                      tag: 'child',
                      initScope: (context) => Stream.value(AsyncScopeReady()),
                      disposeScope: () => childGate.future,
                      progressBuilder: (context, progress) =>
                          const Text('init'),
                      errorBuilder: (context, error, stackTrace, progress) =>
                          Text('$error'),
                      builder: (context) => const Text('ready'),
                    ),
                  )
                : const SizedBox.shrink(),
          );

      // Two failures arrive here, one after the other -- the expiry of the
      // wait, and then the hook that made a failure of it -- and
      // `takeException` collapses several of them into one summary string.
      // Captured directly, so both can be seen. The second used to leave as
      // an uncaught error of the zone instead, which is what this test was
      // written around.
      final reported = <FlutterErrorDetails>[];
      final previousOnError = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = previousOnError);

      await tester.pumpWidget(build(present: true));
      await tester.pumpAndSettle();

      await tester.pumpWidget(build(present: false));
      await settle(
        tester,
        until: () => observer.events.contains('disposed AsyncScope(parent)'),
      );

      // Put back before the assertions: a failing `expect` reported through it
      // would be collected instead of ending the test.
      FlutterError.onError = previousOnError;

      const preparationFailed =
          'error AsyncScope(parent) preparationForDisposal Bad state: '
          'onWaitForChildrenTimeout failed';

      expect(observer.events, [
        'init AsyncScope(parent)',
        'ready AsyncScope(parent)',
        'init AsyncScope(child)',
        'ready AsyncScope(child)',
        'dispose AsyncScope(child)',
        // The expiry itself, then the failure of the hook it called. Both
        // belong to the parent: the wait for the children now reports through
        // the observer like the other five bounded waits.
        'dispose AsyncScope(parent)',
        'timeout AsyncScope(parent) its child scopes',
        preparationFailed,
        'disposed AsyncScope(parent)',
      ]);
      expect(
        reported.map((details) => details.exception),
        [
          isA<TimeoutException>(),
          isA<StateError>(),
        ],
        reason: 'the expiry of the wait, and then the hook that failed on it '
            '-- both through the channel an application watches',
      );

      childGate.complete();
      await settle(
        tester,
        until: () => observer.events.contains('disposed AsyncScope(child)'),
      );
    },
  );

  // The cancellation of an initialization is user code twice over -- the
  // `finally` of the generator being cancelled, and the callback that says
  // the wait for it ran out -- and both land in the same phase.
  testWidgets(
    'a failing onInitCancellationTimeout reports onError for the '
    'cancellation phase',
    (tester) async {
      // Never completed, so the generator can never be resumed and the
      // cancellation can only expire.
      final hang = Completer<void>();

      // Two failures are reported here, one after the other -- the expiry of
      // the wait, and then the callback that made a failure of it -- and
      // `takeException` collapses several of them into one summary string.
      // Captured directly, so both can be seen.
      final reported = <FlutterErrorDetails>[];
      final previousOnError = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = previousOnError);

      Widget build({required bool present}) => Directionality(
            textDirection: TextDirection.ltr,
            child: present
                ? AsyncScope(
                    initCancellationTimeout: const Duration(milliseconds: 50),
                    onInitCancellationTimeout: () =>
                        throw StateError('onInitCancellationTimeout failed'),
                    initScope: (context) async* {
                      await hang.future;
                      yield AsyncScopeReady();
                    },
                    disposeScope: () {},
                    progressBuilder: (context, progress) => const Text('init'),
                    errorBuilder: (context, error, stackTrace, progress) =>
                        Text('$error'),
                    builder: (context) => const Text('ready'),
                  )
                : const SizedBox.shrink(),
          );

      await tester.pumpWidget(build(present: true));
      await tester.pump();

      await tester.pumpWidget(build(present: false));
      await settle(
        tester,
        until: () => observer.events.contains('disposed AsyncScope'),
      );

      // Put back before the assertions below, and not only by the tear-down:
      // while it is in place, a failing `expect` is reported through it and
      // collected instead of ending the test.
      FlutterError.onError = previousOnError;

      const cancellationFailed =
          'error AsyncScope initializationCancellation Bad state: '
          'onInitCancellationTimeout failed';

      expect(observer.events, [
        'init AsyncScope',
        // The pair opens before the four stages, so everything the teardown
        // finds is inside it -- the expiry of the cancellation and the hook
        // that failed on it among the rest.
        'dispose AsyncScope',
        'timeout AsyncScope its initialization to be cancelled',
        cancellationFailed,
        'cancelled AsyncScope',
        // The scope never became ready, so there is nothing for
        // `disposeScope` to release -- and the pair is reported all the same.
        'disposed AsyncScope',
      ]);
      expect(
        reported.map((details) => details.exception),
        [
          isA<TimeoutException>(),
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'onInitCancellationTimeout failed',
          ),
        ],
        reason: 'both go on being reported the way they always were, and the '
            'observer hears them beside the report rather than instead of it',
      );
    },
  );

  // The one path on which a scope is cancelled without ever having reported
  // an `onInit`: it never got as far as subscribing to its own
  // initialization, because it was still queued behind another scope on the
  // same `scopeKey` when it was taken off the tree.
  testWidgets(
    'a scope cancelled while queued for its scopeKey reports no onInit at all',
    (tester) async {
      final holderGate = Completer<void>();
      addTearDown(() {
        if (!holderGate.isCompleted) {
          holderGate.complete();
        }
      });

      Widget build({required bool successor}) => Directionality(
            textDirection: TextDirection.ltr,
            child: AsyncScopeCoordinator(
              child: Column(
                children: [
                  AsyncScope(
                    key: const ValueKey('holder'),
                    tag: 'holder',
                    scopeKey: 'shared',
                    initScope: (context) => Stream.value(AsyncScopeReady()),
                    disposeScope: () => holderGate.future,
                    progressBuilder: (context, progress) => const Text('init'),
                    errorBuilder: (context, error, stackTrace, progress) =>
                        Text('$error'),
                    builder: (context) => const Text('ready'),
                  ),
                  if (successor)
                    AsyncScope(
                      key: const ValueKey('successor'),
                      tag: 'successor',
                      scopeKey: 'shared',
                      scopeKeyTimeout: const Duration(days: 1),
                      initScope: (context) => Stream.value(AsyncScopeReady()),
                      disposeScope: () {},
                      progressBuilder: (context, progress) =>
                          const Text('init'),
                      errorBuilder: (context, error, stackTrace, progress) =>
                          Text('$error'),
                      builder: (context) => const Text('ready'),
                    ),
                ],
              ),
            ),
          );

      await tester.pumpWidget(build(successor: true));
      await tester.pumpAndSettle();

      observer.events.clear();

      // The successor leaves while its wait for the key is still pending.
      await tester.pumpWidget(build(successor: false));
      await settle(
        tester,
        until: () => observer.events.contains('disposed AsyncScope(successor)'),
      );

      expect(observer.events, [
        'dispose AsyncScope(successor)',
        'cancelled AsyncScope(successor)',
        'disposed AsyncScope(successor)',
      ]);

      holderGate.complete();
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester, until: () => false);
    },
  );

  testWidgets(
    'a hanging teardown reports onTimeout after disposeScopeTimeout',
    (tester) async {
      final hang = Completer<void>();

      Widget build({required bool present}) => Directionality(
            textDirection: TextDirection.ltr,
            child: present
                ? AsyncScope(
                    disposeScopeTimeout: const Duration(milliseconds: 50),
                    initScope: (context) => Stream.value(AsyncScopeReady()),
                    disposeScope: () => hang.future,
                    progressBuilder: (context, progress) => const Text(
                      'init',
                    ),
                    errorBuilder: (context, error, stackTrace, progress) =>
                        Text('$error'),
                    builder: (context) => const Text('ready'),
                  )
                : const SizedBox.shrink(),
          );

      await tester.pumpWidget(build(present: true));
      await tester.pumpAndSettle();

      await tester.pumpWidget(build(present: false));
      // The abandoned `disposeScope()` is left running in the background --
      // giving up on waiting for it does not stop the teardown, which goes
      // on to report `disposed` right after the expiry, in the same
      // continuation. Settling for `timeout` alone would race that.
      await settle(
        tester,
        until: () => observer.events.contains('disposed AsyncScope'),
      );

      expect(observer.events, [
        'init AsyncScope',
        'ready AsyncScope',
        'dispose AsyncScope',
        'timeout AsyncScope its own teardown',
        'disposed AsyncScope',
      ]);
      expect(tester.takeException(), isA<TimeoutException>());
    },
  );

  test('a dependency container reports its lifecycle through the observer',
      () async {
    final dependencies = _TestDependencies();

    await dependencies.init(null).drain<void>();
    await dependencies.dispose();

    expect(observer.events, [
      'init _TestDependencies',
      'step _TestDependencies dep1',
      'progress _TestDependencies dep1 (1/2)',
      'step _TestDependencies dep2',
      'progress _TestDependencies dep2 (2/2)',
      'ready _TestDependencies',
      'dispose _TestDependencies',
      'disposed _TestDependencies',
    ]);
    // Neither dependency registered a disposer, so the walk finds nothing to
    // release and says nothing about either -- an entry with no release
    // behind it is what a hung teardown looks like, and these two are not
    // that. The pairs of the disposal are in `scope_step_entry_test.dart`.
  });

  test('the print observer writes one line per event', () {
    final lines = <String>[];
    const scope = _FakeObservable('CounterScope(#4e0b7)');

    ScopePrintObserver(output: lines.add)
      ..onInit(scope)
      ..onReady(scope)
      ..onTrace(scope, 'wait for access to [key]');

    expect(
      lines,
      [
        'scopo | CounterScope(#4e0b7) | initialize…',
        'scopo | CounterScope(#4e0b7) | initialized',
      ],
      reason: 'a trace is silent unless trace: true',
    );
  });

  test('the print observer prints a trace when trace is true', () {
    final lines = <String>[];
    const scope = _FakeObservable('CounterScope(#4e0b7)');

    ScopePrintObserver(output: lines.add, trace: true)
        .onTrace(scope, 'wait for access to [key]');

    expect(lines, ['scopo | CounterScope(#4e0b7) | wait for access to [key]']);
  });

  test('the print observer covers the rest of the lifecycle', () {
    final lines = <String>[];
    const scope = _FakeObservable('CounterScope(#4e0b7)');

    ScopePrintObserver(output: lines.add)
      ..onProgress(scope, 'dep1 (1/2)')
      ..onCancelled(scope)
      ..onDispose(scope)
      ..onDisposed(scope)
      ..onTimeout(scope, 'the disposal');

    expect(lines, [
      'scopo | CounterScope(#4e0b7) | progress: dep1 (1/2)',
      'scopo | CounterScope(#4e0b7) | initialization cancelled',
      'scopo | CounterScope(#4e0b7) | dispose…',
      'scopo | CounterScope(#4e0b7) | disposed',
      'scopo | CounterScope(#4e0b7) | gave up waiting for the disposal',
    ]);
  });

  test('the print observer adds the stack trace on its own line', () {
    final lines = <String>[];
    const scope = _FakeObservable('CounterScope(#4e0b7)');
    final stackTrace = StackTrace.fromString('#0 main');

    ScopePrintObserver(output: lines.add).onError(
      scope,
      ScopePhase.initialization,
      StateError('no network'),
      stackTrace,
    );

    final expected = 'scopo | CounterScope(#4e0b7) | initialization failed: '
        'Bad state: no network\n$stackTrace';
    expect(lines, [expected]);
  });

  test('the print observer leaves out a missing stack trace', () {
    final lines = <String>[];
    const scope = _FakeObservable('CounterScope(#4e0b7)');

    ScopePrintObserver(output: lines.add).onError(
      scope,
      ScopePhase.disposal,
      StateError('dispose failed'),
      null,
    );

    const expected = 'scopo | CounterScope(#4e0b7) | disposal failed: Bad '
        'state: dispose failed';
    expect(lines, [expected]);
  });

  test('the print observer spells out every failed phase in English', () {
    final lines = <String>[];
    const scope = _FakeObservable('CounterScope(#4e0b7)');
    final error = StateError('boom');

    ScopePrintObserver(output: lines.add)
      ..onError(scope, ScopePhase.initialization, error, null)
      ..onError(scope, ScopePhase.initializationCancellation, error, null)
      ..onError(scope, ScopePhase.preparationForDisposal, error, null)
      ..onError(scope, ScopePhase.unmount, error, null)
      ..onError(scope, ScopePhase.disposal, error, null)
      ..onError(scope, ScopePhase.abandonedWait, error, null);

    const cancellationFailed =
        'scopo | CounterScope(#4e0b7) | initialization cancellation failed: '
        'Bad state: boom';
    const preparationFailed =
        'scopo | CounterScope(#4e0b7) | preparation for disposal failed: '
        'Bad state: boom';
    const abandonedWaitFailed =
        'scopo | CounterScope(#4e0b7) | an abandoned wait ended in a '
        'failure: Bad state: boom';

    expect(lines, [
      'scopo | CounterScope(#4e0b7) | initialization failed: Bad state: boom',
      cancellationFailed,
      preparationFailed,
      'scopo | CounterScope(#4e0b7) | unmount failed: Bad state: boom',
      'scopo | CounterScope(#4e0b7) | disposal failed: Bad state: boom',
      abandonedWaitFailed,
    ]);
  });

  test('an anonymous dependency group is not printed with a doubled space', () {
    final lines = <String>[];
    final group = ScopeDependency.sequential('', const []) as ScopeObservable;

    ScopePrintObserver(output: lines.add).onInit(group);

    expect(lines, ['scopo | [group] | initialize…']);
  });

  // The last family of user code the observer could not hear. A failing build
  // is turned into an `ErrorWidget` by Flutter's build error boundary -- which
  // is what the subtree shows, not what the observer hears, the same
  // distinction that put a report on the `init()` hook. The report is added to
  // the throw rather than put in its place: unlike a teardown with no caller,
  // a build has one, and it is the boundary that draws the red rectangle.
  testWidgets(
    'a build that throws reports onError for the build phase',
    (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: AsyncScope(
            initScope: (context) => Stream.value(AsyncScopeReady()),
            disposeScope: () {},
            progressBuilder: (context, progress) => const Text('init'),
            errorBuilder: (context, error, stackTrace, progress) =>
                Text('$error'),
            builder: (context) => throw StateError('build failed'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isStateError);
      expect(observer.events, [
        'init AsyncScope',
        'ready AsyncScope',
        'error AsyncScope build Bad state: build failed',
      ]);

      // The scope is Ready and still mounted -- only its subtree was replaced
      // -- so the teardown is the ordinary asynchronous one, and a test that
      // ended here would leave it half-done for the leak tracker to find.
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(
        tester,
        until: () => observer.events.contains('disposed AsyncScope'),
      );
    },
  );

  // The same phase from a family that has no `buildOn*` at all, and the reason
  // the guard stands where it does: one in `buildOnState` covers the four
  // asynchronous families, passes the test above and fails this one.
  testWidgets(
    'a scope widget whose own build throws reports the same phase',
    (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: _BuildFailingScope(),
        ),
      );

      expect(tester.takeException(), isStateError);
      expect(observer.events, [
        'init _BuildFailingScope',
        'error _BuildFailingScope build Bad state: build failed',
      ]);
    },
  );
}

/// A minimal [LiteScope]: nothing to initialize asynchronously, and [child]
/// is shown right away rather than after a ready state is reached.
final class _CounterScope extends LiteScope<_CounterScope, _CounterScopeState> {
  const _CounterScope({super.child});

  @override
  Widget? buildOnWaiting(BuildContext context) => child;

  @override
  _CounterScopeState createState() => _CounterScopeState();
}

final class _CounterScopeState
    extends LiteScopeState<_CounterScope, _CounterScopeState> {
  @override
  Widget build(BuildContext context) => params.child;
}

/// A scope with no `buildOn*` of its own, whose [build] throws.
///
/// The failure has to come from the widget's own build rather than from a
/// state branch: that is the half of the surface a guard around `buildOnState`
/// would not reach.
final class _BuildFailingScope extends ScopeWidgetBase<_BuildFailingScope> {
  const _BuildFailingScope();

  @override
  Widget build(BuildContext context) => throw StateError('build failed');
}

/// A scope with no phase of its own: [ScopeWidgetBase] goes no further than
/// [ScopeWidgetElementBase] itself, so it never overrides
/// [ScopeWidgetElementBase.reportsOwnLifecycle].
final class _PlainScope extends ScopeWidgetBase<_PlainScope> {
  const _PlainScope({super.child});

  @override
  Widget build(BuildContext context) => child;
}

/// A scope whose `init()` throws before it can announce `onInit`.
final class _FailingInitScope
    extends ScopeWidgetCore<_FailingInitScope, _FailingInitScopeElement> {
  const _FailingInitScope();

  @override
  _FailingInitScopeElement createScopeElement() =>
      _FailingInitScopeElement(this);
}

final class _FailingInitScopeElement extends ScopeWidgetElementBase<
    _FailingInitScope, _FailingInitScopeElement> {
  _FailingInitScopeElement(super.widget);

  @override
  void init() {
    super.init();
    throw StateError('init failed');
  }

  @override
  Widget buildChild() => const SizedBox.shrink();
}

/// A scope on the asynchronous element whose synchronous `init()` throws.
///
/// That hook is where `AsyncScopeBase.init` runs `onMount`, and it is the
/// only part of an asynchronous family that runs before the phase which
/// reports itself.
final class _FailingInitAsyncScope extends AsyncScopeCore<
    _FailingInitAsyncScope, _FailingInitAsyncScopeElement> {
  const _FailingInitAsyncScope();

  @override
  _FailingInitAsyncScopeElement createScopeElement() =>
      _FailingInitAsyncScopeElement(this);
}

final class _FailingInitAsyncScopeElement extends AsyncScopeElementBase<
    _FailingInitAsyncScope, _FailingInitAsyncScopeElement> {
  _FailingInitAsyncScopeElement(super.widget);

  @override
  void init() {
    super.init();
    throw StateError('init failed');
  }

  @override
  Stream<AsyncScopeInitState> initScope() async* {
    yield AsyncScopeReady();
  }

  @override
  Widget buildOnState(AsyncScopeState state) => const SizedBox.shrink();
}

/// A controller scope whose initialization fails and whose controller then
/// fails to be released.
final class _FailingControllerScope extends AsyncControllerScopeBase<
    _FailingControllerScope, _FailingController> {
  const _FailingControllerScope();

  @override
  _FailingController createController(BuildContext context) =>
      _FailingController();

  @override
  Widget buildOnProgress(BuildContext context) => const SizedBox.shrink();

  @override
  Widget buildOnError(
    BuildContext context,
    Object error,
    StackTrace stackTrace,
  ) =>
      const SizedBox.shrink();

  @override
  Widget buildOnReady(BuildContext context, _FailingController controller) =>
      const SizedBox.shrink();
}

final class _FailingController extends ScopeController {
  @override
  Future<void> init() async => throw StateError('init failed');

  @override
  Future<void> dispose() async => throw StateError('dispose failed');
}

/// A model with nothing in it: what matters is its disposer.
final class _Model {}

const _short = Duration(milliseconds: 50);

/// A scope on the shared `scopeKey`, optionally held in its initialization or
/// in its teardown.
Widget _keyed({
  required String tag,
  Completer<void>? gate,
  Completer<void>? disposeGate,
  Duration? scopeKeyTimeout,
}) =>
    AsyncScope(
      tag: tag,
      scopeKey: 'shared',
      scopeKeyTimeout: scopeKeyTimeout,
      initScope: (context) async* {
        if (gate != null) {
          await gate.future;
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

/// A child scope whose teardown is held until [gate] is completed.
Widget _held(Completer<void> gate) => AsyncScope(
      tag: 'child',
      initScope: (context) => Stream.value(AsyncScopeReady()),
      disposeScope: () => gate.future,
      progressBuilder: (context, progress) => const SizedBox.shrink(),
      builder: (context) => const SizedBox.shrink(),
      errorBuilder: (context, error, stackTrace, progress) =>
          const SizedBox.shrink(),
    );

/// A scope that waits for the scope below it before disposing of itself.
Widget _parent({
  required Widget child,
  Duration? waitForChildrenTimeout,
}) =>
    AsyncScope(
      tag: 'parent',
      waitForChildrenTimeout: waitForChildrenTimeout,
      initScope: (context) async* {
        yield AsyncScopeReady();
      },
      disposeScope: () {},
      progressBuilder: (context, progress) => const SizedBox.shrink(),
      builder: (context) => child,
      errorBuilder: (context, error, stackTrace, progress) =>
          const SizedBox.shrink(),
    );

/// Fails every hook it is asked for.
final class _ThrowingObserver extends ScopeObserver {
  @override
  void onInit(ScopeObservable target) => throw StateError('observer failed');
}

/// Produces a second scope event from [onInit] -- the shape [notifyObserver]
/// itself refuses to recurse into, rather than one that reaches it through a
/// second build. A build reentrant enough to test that path would have to
/// fight the framework's own build-scope lock first, and that lock -- not
/// [notifyObserver]'s -- is what a widget-tree version of this test would
/// actually be exercising.
final class _NestingObserver extends ScopeObserver {
  @override
  void onInit(ScopeObservable target) =>
      notifyObserver((observer) => observer.onDisposed(target));
}

/// A [ScopeObservable] with no scope behind it, for a test that calls
/// [notifyObserver] directly rather than through a widget tree, or that
/// exercises a [ScopeObserver] such as [ScopePrintObserver] without building
/// one.
final class _FakeObservable implements ScopeObservable {
  const _FakeObservable([this.debugLabel = '_FakeObservable']);

  @override
  final String debugLabel;
}

/// A minimal [AsyncScopeCore] with two progress steps before it is ready.
final class _AsyncScope
    extends AsyncScopeCore<_AsyncScope, _AsyncScopeElement> {
  const _AsyncScope();

  @override
  _AsyncScopeElement createScopeElement() => _AsyncScopeElement(this);
}

final class _AsyncScopeElement
    extends AsyncScopeElementBase<_AsyncScope, _AsyncScopeElement> {
  _AsyncScopeElement(super.widget);

  @override
  Stream<AsyncScopeInitState> initScope() async* {
    yield AsyncScopeProgress('1/2');
    yield AsyncScopeProgress('2/2');
    yield AsyncScopeReady();
  }

  @override
  Widget buildOnState(AsyncScopeState state) => const SizedBox.shrink();
}

/// A container with two dependencies, driven directly: its `C` is `void`, so
/// nothing above it -- a widget included -- is needed to call
/// [ScopeAutoDependencies.init].
final class _TestDependencies
    extends ScopeAutoDependencies<_TestDependencies, void> {
  @override
  ScopeDependency buildDependencies(void context) => sequential('', [
        dep('dep1', (handle) {}),
        dep('dep2', (handle) {}),
      ]);
}

/// A scope that can be taken down with `close()` while it stays on screen.
///
/// The `LiteScope` family is used for the sake of that one method: it is the
/// only way into a teardown whose *first* stage -- `onUnmount` -- has not
/// already been run by the framework.
final class _ClosingScope extends LiteScopeCore<_ClosingScope,
    _ClosingScopeElement, _ClosingScopeState> {
  /// Makes [_ClosingScopeState.onUnmount] fail.
  final bool failUnmount;

  const _ClosingScope({this.failUnmount = false});

  @override
  _ClosingScopeElement createScopeElement() => _ClosingScopeElement(this);
}

final class _ClosingScopeElement extends LiteScopeElementBase<_ClosingScope,
    _ClosingScopeElement, _ClosingScopeState> {
  _ClosingScopeElement(super.widget);

  @override
  Widget? buildOnWaiting() => const Text('waiting');

  @override
  Widget buildOnProgress(Object? progress) => const Text('initializing');

  @override
  Widget buildOnError(Object error, StackTrace stackTrace, Object? progress) =>
      const Text('error');

  @override
  _ClosingScopeState createState() => _ClosingScopeState();
}

final class _ClosingScopeState extends LiteScopeCoreState<_ClosingScope,
    _ClosingScopeElement, _ClosingScopeState> {
  @override
  void onUnmount() {
    super.onUnmount();
    if (params.failUnmount) {
      throw StateError('onUnmount failed');
    }
  }

  @override
  Widget build(BuildContext context) => const Text('ready');
}

/// Something to report about, with a label a test can read.
final class _Target implements ScopeObservable {
  @override
  String get debugLabel => 'target';
}

/// Records the order the composite reaches its observers in, then forwards.
final class _MarkingObserver extends ScopeObserver {
  final List<String> order;
  final String name;
  final ScopeObserver inner;

  const _MarkingObserver(this.order, this.name, this.inner);

  @override
  void onInit(ScopeObservable target) {
    order.add(name);
    inner.onInit(target);
  }

  @override
  void onTrace(ScopeObservable target, String message) {
    order.add(name);
    inner.onTrace(target, message);
  }
}

/// An observer of the kind the composite has to survive.
final class _ThrowingOnReadyObserver extends ScopeObserver {
  const _ThrowingOnReadyObserver();

  @override
  void onReady(ScopeObservable target) => throw StateError('observer failed');
}
