import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scopo/scopo.dart';

import 'utils/leaks.dart';
import 'utils/settle.dart';

void main() {
  group('LiteScope.close()', () {
    // `close()` installs a screenshot barrier and waits for it. The barrier is
    // only ever released by the `ScreenshotReplacer` that `buildOnReady()`
    // mounts, and `buildOnReady()` is the `AsyncScopeReady` branch of
    // `buildOnState()` -- so in any other state nothing can release it and
    // `close()` waits forever.
    for (final (state, init, body)
        in <(String, Future<void> Function(ScopeInitContext), String)>[
      ('waiting', _neverEmits, 'waiting'),
      ('initializing', _emitsProgressOnly, 'initializing'),
      ('error', _failsImmediately, 'error'),
    ]) {
      testWidgets(
        'completes while the scope is in the $state state',
        (tester) async {
          await tester.pumpWidget(_app(_CloseScope(init: init)));
          // A few extra frames, so the init stream event (or error) is
          // delivered and applied to the model before `close()` is called.
          for (var i = 0; i < 3; i++) {
            await tester.pump();
          }
          expect(find.text(body), findsOneWidget);

          final element =
              tester.element<_CloseScopeElement>(find.byType(_CloseScope));

          // Deliberately not awaited: before the fix this future never
          // completes, so awaiting it would hang the whole test run instead of
          // failing this test.
          var isClosed = false;
          unawaited(element.close().whenComplete(() => isClosed = true));

          await settle(tester, until: () => isClosed);

          expect(
            isClosed,
            isTrue,
            reason: 'close() must not wait for a screenshot that '
                'buildOnReady() never takes in the $state state',
          );
        },
      );
    }

    testWidgets(
      'completes in the ready state once the screenshot has been captured',
      (tester) async {
        await tester.pumpWidget(_app(const _CloseScope(init: _becomesReady)));
        await tester.pumpAndSettle();
        expect(find.text('ready'), findsOneWidget);

        final element =
            tester.element<_CloseScopeElement>(find.byType(_CloseScope));

        var isClosed = false;
        unawaited(element.close().whenComplete(() => isClosed = true));

        // The closing frame: `buildOnReady()` now wraps the child into a
        // `ScreenshotReplacer` (plus the closing overlay), and the replacer's
        // post-frame callback starts the capture.
        await tester.pump();
        expect(find.byType(ScreenshotReplacer), findsOneWidget);

        await settle(tester, until: () => isClosed);

        expect(
          isClosed,
          isTrue,
          reason: 'in the ready state the barrier must still be installed and '
              'released by the ScreenshotReplacer',
        );
      },
    );

    // The barrier is released by a `ScreenshotReplacer` that has to be mounted
    // first, and everything between the decision to close and that mounting is
    // a way of never getting there. Two of them below: the widget the package
    // builds around the replacer, and the closing screen the user builds
    // beside it.
    //
    // This is the shape the topic and `example/minimal` teach for a scope at
    // the root of the application: each branch builds its own `MaterialApp`,
    // and `wrapState` returns the app around the ready branch — so every
    // `Directionality` in the tree is *below* this scope. The `Stack` the
    // closing build wraps the ready branch in resolved its alignment through a
    // `Directionality` above itself, of which there is none, so the first
    // rebuild after `close()` threw while that `Stack` was being mounted.
    testWidgets(
      'completes for a root scope whose branches build the app themselves',
      (tester) async {
        await tester.pumpWidget(
          const _CloseScope(init: _becomesReady, wrapInApp: true),
        );
        await tester.pumpAndSettle();
        expect(find.text('ready'), findsOneWidget);

        final element = _scopeOf(tester);

        // Deliberately not awaited: before the fix this future never
        // completes, so awaiting it would hang the whole run.
        var isClosed = false;
        unawaited(element.close().whenComplete(() => isClosed = true));

        await settle(tester, until: () => isClosed);

        expect(
          isClosed,
          isTrue,
          reason: 'the documented shape of a root scope must not be the one '
              'shape close() cannot finish in',
        );
      },
    );

    // The other way of never reaching the replacer, and this one is the user's
    // own code: the closing screen is built in the same pass, and a screen
    // that reads something already gone throws there. The teardown behind it
    // is not that screen's to cancel — the whole of it, four stages, the
    // `scopeKey` and the registration with the parent included.

    testWidgets(
      'completes when the closing screen refuses to build',
      (tester) async {
        await tester.pumpWidget(
          _app(const _CloseScope(init: _becomesReady, failClosingBuild: true)),
        );
        await tester.pumpAndSettle();

        final element = _scopeOf(tester);

        var isClosed = false;
        unawaited(element.close().whenComplete(() => isClosed = true));

        await settle(tester, until: () => isClosed);

        expect(
          tester.takeException(),
          isA<StateError>(),
          reason: 'the failure is still reported',
        );
        expect(
          isClosed,
          isTrue,
          reason: 'a closing screen that cannot be built is a screen nobody '
              'sees, not a teardown nobody runs',
        );
      },
    );

    // The failure the guard around the closing build cannot see: a screen that
    // is built without complaint and throws while it is being mounted. What
    // covers it is the order of the two children -- the replacer is the first
    // of them, so it is mounted, and its barrier released, before anything the
    // closing screen does can be reached. That order is load-bearing rather
    // than incidental, which is what this test is here to say.
    testWidgets(
      'completes when the closing screen refuses to mount',
      (tester) async {
        await tester.pumpWidget(
          const _CloseScope(
            init: _becomesReady,
            wrapInApp: true,
            failClosingMount: true,
          ),
        );
        await tester.pumpAndSettle();

        final element = _scopeOf(tester);

        var isClosed = false;
        unawaited(element.close().whenComplete(() => isClosed = true));

        await settle(tester, until: () => isClosed);

        expect(
          tester.takeException(),
          isFlutterError,
          reason: 'the failure is still reported',
        );
        expect(isClosed, isTrue, reason: 'and the teardown still ran');
      },
      // The violation this test is written for is raised while the closing
      // screen is being mounted, and the `Stack` half-built around it is
      // abandoned by the framework -- see [unmountableTree].
      experimentalLeakTesting: unmountableTree,
    );

    // `notifyDependents()` marks the element dirty *and* asks the next
    // rebuild to skip the subtree (`_shouldOnlyNotify`), so `updateChild`
    // returns the old child and the widget `buildOnReady()` just built is
    // thrown away. `close()` installs the screenshot barrier on
    // `mounted && state is AsyncScopeReady`, which is necessary but not
    // sufficient: the `ScreenshotReplacer` that releases the barrier is never
    // mounted, and a scope closed in place stays mounted, so the `dispose()`
    // fallback never runs either.
    testWidgets(
      'control: a plain close() mounts the ScreenshotReplacer',
      (tester) async {
        await tester.pumpWidget(_app(const _CloseScope(init: _becomesReady)));
        await tester.pumpAndSettle();
        expect(find.text('ready'), findsOneWidget);

        final element = _scopeOf(tester);

        var isClosed = false;
        unawaited(element.close().whenComplete(() => isClosed = true));

        await tester.pump();

        expect(
          find.byType(ScreenshotReplacer),
          findsOneWidget,
          reason: 'the probe must be able to see the barrier being installed',
        );

        await settle(tester, until: () => isClosed);
        expect(isClosed, isTrue);
      },
    );

    testWidgets(
      'completes when a pending notifyDependents() would skip the subtree '
      'the closing frame has to rebuild',
      (tester) async {
        await tester.pumpWidget(_app(const _CloseScope(init: _becomesReady)));
        await tester.pumpAndSettle();
        expect(find.text('ready'), findsOneWidget);

        final element = _scopeOf(tester);

        // A notify-only rebuild is left pending, and `close()` follows before
        // any frame can drain it.
        element.createdState!.notifyDependents();

        var isClosed = false;
        unawaited(element.close().whenComplete(() => isClosed = true));

        await settle(tester, until: () => isClosed);

        expect(
          isClosed,
          isTrue,
          reason: 'close() must not wait for a ScreenshotReplacer that the '
              'notify-only rebuild kept from ever being mounted',
        );
      },
    );

    testWidgets(
      'completes when the element leaves the tree before the closing frame '
      'is built',
      (tester) async {
        await tester.pumpWidget(_app(const _CloseScope(init: _becomesReady)));
        await tester.pumpAndSettle();
        expect(find.text('ready'), findsOneWidget);

        final element =
            tester.element<_CloseScopeElement>(find.byType(_CloseScope));

        var isClosed = false;
        unawaited(element.close().whenComplete(() => isClosed = true));

        // `close()` has installed the barrier and marked the element dirty, but
        // the element is deactivated before it gets a chance to rebuild: the
        // `ScreenshotReplacer` that would release the barrier is never mounted
        // at all.
        await tester.pumpWidget(_app(const SizedBox.shrink()));

        await settle(tester, until: () => isClosed);

        expect(
          isClosed,
          isTrue,
          reason: 'a scope removed from the tree while closing must not keep '
              'close() waiting for a screenshot that can no longer be taken',
        );
      },
    );

    testWidgets(
      'completes both futures when close() is called twice',
      (tester) async {
        await tester.pumpWidget(_app(const _CloseScope(init: _becomesReady)));
        await tester.pumpAndSettle();
        expect(find.text('ready'), findsOneWidget);

        final element =
            tester.element<_CloseScopeElement>(find.byType(_CloseScope));

        var isFirstClosed = false;
        var isSecondClosed = false;
        unawaited(element.close().whenComplete(() => isFirstClosed = true));

        // Build the closing frame *without* drawing it, so the
        // `ScreenshotReplacer` that is going to release the barrier is mounted
        // while its capture is still pending: drawing the frame here would run
        // the capture to completion before the second `close()` arrives.
        tester.binding.buildOwner!.buildScope(tester.binding.rootElement!);
        expect(find.byType(ScreenshotReplacer), findsOneWidget);

        // A second `close()` must not swap the barrier out from under the
        // first one: the barrier the first `close()` is waiting for is the one
        // the replacer releases.
        unawaited(element.close().whenComplete(() => isSecondClosed = true));

        await settle(tester, until: () => isFirstClosed && isSecondClosed);

        expect(
          isFirstClosed,
          isTrue,
          reason: 'the first close() must not be orphaned by the second one',
        );
        expect(
          isSecondClosed,
          isTrue,
          reason: 'the second close() must join the first one',
        );
      },
    );

    // L16 of the sixth review. Whether a teardown has a caller waiting for it
    // was read off `_isDisposing`, and the lite layer raises that only once
    // its screenshot barrier is over -- the replacer needs a build, the
    // picture a retry or two. An element taken off the tree inside that
    // window said "nobody is waiting" while `close()` was waiting for exactly
    // it, and a failed teardown was then announced twice: to the caller, and
    // to the reporter that exists for walks with no caller at all.
    testWidgets(
      'a failure during a close is not reported behind its caller back',
      (tester) async {
        await tester.pumpWidget(
          _app(const _CloseScope(init: _becomesReady, failStateDispose: true)),
        );
        await tester.pumpAndSettle();
        expect(find.text('ready'), findsOneWidget);

        final element = _scopeOf(tester);

        final reported = <Object>[];
        final previous = FlutterError.onError;
        FlutterError.onError = (details) => reported.add(details.exception);

        Object? failure;
        var settled = false;
        unawaited(
          element.close().then(
            (_) => settled = true,
            onError: (Object error) {
              failure = error;
              settled = true;
            },
          ),
        );

        // Not pumped: the barrier is installed and nothing has released it
        // yet, which is the window this test is about.
        await tester.pumpWidget(_app(const SizedBox(width: 1, height: 1)));
        await settle(tester, until: () => settled);

        FlutterError.onError = previous;

        expect(
          failure,
          isNotNull,
          reason: 'the caller of close() hears what the teardown raised',
        );
        expect(
          reported,
          isEmpty,
          reason: 'and nobody reports it a second time on its behalf: the '
              'report is for a walk with no caller, and this one has one',
        );
      },
    );

    testWidgets(
      'hands the same disposal failure to every close() caller',
      (tester) async {
        await tester.pumpWidget(
          _app(const _CloseScope(init: _becomesReady, failStateDispose: true)),
        );
        await tester.pumpAndSettle();
        expect(find.text('ready'), findsOneWidget);

        final element =
            tester.element<_CloseScopeElement>(find.byType(_CloseScope));

        Object? firstError;
        Object? secondError;
        var isFirstSettled = false;
        var isSecondSettled = false;

        // The first caller starts the disposal; the second one, issued before
        // the first can settle, joins the very same run.
        unawaited(
          element.close().then(
            (_) => isFirstSettled = true,
            onError: (Object error) {
              firstError = error;
              isFirstSettled = true;
            },
          ),
        );
        unawaited(
          element.close().then(
            (_) => isSecondSettled = true,
            onError: (Object error) {
              secondError = error;
              isSecondSettled = true;
            },
          ),
        );

        await settle(tester, until: () => isFirstSettled && isSecondSettled);

        expect(isFirstSettled, isTrue, reason: 'both calls must settle');
        expect(isSecondSettled, isTrue, reason: 'both calls must settle');
        expect(
          firstError,
          isA<StateError>(),
          reason: 'the caller that started the disposal sees it fail',
        );
        expect(
          secondError,
          same(firstError),
          reason: 'a caller that joined the run in flight must be told the '
              'same thing, not that the disposal succeeded',
        );
      },
    );

    testWidgets(
      'completes in the ready state even when the screenshot can never '
      'be taken',
      (tester) async {
        // An offstage subtree is built and laid out but never painted, so the
        // repaint boundary can never be captured.
        await tester.pumpWidget(
          _app(const Offstage(child: _CloseScope(init: _becomesReady))),
        );
        await settle(
          tester,
          until: () => _scopeOf(tester).state is AsyncScopeReady,
        );
        expect(_scopeOf(tester).state, isA<AsyncScopeReady>());

        var isClosed = false;
        unawaited(_scopeOf(tester).close().whenComplete(() => isClosed = true));

        await settle(tester, until: () => isClosed);

        expect(
          isClosed,
          isTrue,
          reason: 'the capture must give up after a bounded number of retries '
              'instead of keeping close() waiting forever',
        );
        expect(find.byType(RawImage, skipOffstage: false), findsNothing);
      },
    );

    // Giving up on the picture is not giving up on the subtree. The barrier is
    // released either way, so the teardown goes on -- and it used to go on with
    // the ready subtree still standing: every scope under it stayed mounted and
    // stayed registered, this one waited out its whole `waitForChildrenTimeout`
    // for a child nobody had taken away, and then released what that child was
    // still reading.
    testWidgets(
      'takes the subtree away even when the screenshot can never be taken',
      (tester) async {
        await tester.pumpWidget(
          _app(
            const Offstage(
              child: _CloseScope(
                init: _becomesReady,
                body: _CloseScope(init: _becomesReady),
              ),
            ),
          ),
        );
        await settle(
          tester,
          until: () =>
              find.byType(_CloseScope, skipOffstage: false).evaluate().length ==
              2,
        );

        final outer = tester.element<_CloseScopeElement>(
          find.byType(_CloseScope, skipOffstage: false).first,
        );
        expect(outer.childrenCount, 1, reason: 'the child scope registered');

        var isClosed = false;
        unawaited(outer.close().whenComplete(() => isClosed = true));

        await settle(tester, until: () => isClosed);

        expect(
          isClosed,
          isTrue,
          reason: 'and the close finishes without waiting the children out',
        );
        expect(
          outer.childrenCount,
          0,
          reason: 'the subtree went away, so the scope under it finished its '
              'own teardown and unregistered',
        );
      },
    );

    testWidgets(
      'does not touch the disposed model when close() wins the race with the '
      'post-frame callback that applies the ready state',
      (tester) async {
        final binding = tester.binding;

        // Mount by driving the build phase directly, so the post-frame
        // callback that `_performAsyncInit` schedules for `AsyncScopeReady`
        // stays pending -- `pumpWidget` would drain it within the very frame
        // that schedules it (the same technique as in `async_scope_test.dart`).
        binding.attachRootWidget(
          binding.wrapWithDefaultView(
            const Directionality(
              textDirection: TextDirection.ltr,
              child: _CloseScope(init: _becomesReady),
            ),
          ),
        );
        binding.buildOwner!.buildScope(binding.rootElement!);

        // Lets `initScope()` deliver `AsyncScopeReady` -- so `_initSucceeded`
        // is set and the post-frame callback is scheduled -- without drawing a
        // frame.
        await binding.idle();

        final element = _scopeOf(tester);
        expect(
          element.state,
          isA<AsyncScopeWaiting>(),
          reason: 'the ready state must still be pending for this race',
        );

        var isClosed = false;
        unawaited(element.close().whenComplete(() => isClosed = true));

        // The disposal chain runs to `_model.dispose()`, and only then is the
        // stale post-frame callback drained by a real frame.
        await settle(tester, until: () => isClosed);

        expect(isClosed, isTrue);
        expect(
          tester.takeException(),
          isNull,
          reason: 'the pending ready callback must not use the disposed model',
        );
        // The ready state was never applied, but `initScope()` did succeed, so
        // `disposeScope()` still has to run exactly once (see task 7).
        expect(element.disposeScopeCount, 1);
        expect(element.state, isA<AsyncScopeWaiting>());
      },
    );

    // `close()` deliberately keeps the element mounted, so the `mounted`
    // guard on the post-frame callback that registers the scope with its
    // parent tells that callback nothing about a disposal that is already
    // over. The two sibling callbacks in `_performAsyncInit` got the
    // `_isDisposing` half of the guard; this one kept only `mounted`.
    //
    // The assertions are about effects: how many children the parent still
    // holds, and whether a later wait comes back on its own. The wait's limit
    // is set far beyond anything this test can advance, so an expiry cannot
    // be what releases it.
    testWidgets(
      'does not register with the parent again once close() has finished',
      (tester) async {
        final binding = tester.binding;

        // Mount by driving the build phase directly, so the post-frame
        // callback that `_performAsyncInit` schedules to register the scope
        // with its parent stays pending -- `pumpWidget` would drain it within
        // the very frame that schedules it (the same technique as in
        // `async_scope_test.dart`).
        binding.attachRootWidget(
          binding.wrapWithDefaultView(
            const Directionality(
              textDirection: TextDirection.ltr,
              child: AsyncScopeCoordinator(
                child: _CloseScope(init: _neverEmits),
              ),
            ),
          ),
        );
        binding.buildOwner!.buildScope(binding.rootElement!);

        final coordinator = tester.element(find.byType(AsyncScopeCoordinator))
            as AsyncScopeParent;
        final element = _scopeOf(tester);

        var isClosed = false;
        unawaited(element.close().whenComplete(() => isClosed = true));

        // Real time only, no frames: the whole disposal runs -- unregistering
        // an entry that does not exist yet -- while the registration callback
        // is still queued.
        for (var i = 0; i < 20 && !isClosed; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
        }
        expect(isClosed, isTrue, reason: 'close() must have finished first');

        // The first frame drains the pending callback.
        await tester.pump();

        expect(
          coordinator.childrenCount,
          0,
          reason: 'a scope that has finished disposing of itself must not '
              'register a fresh entry with its parent',
        );

        var waited = false;
        unawaited(
          coordinator
              .waitForChildren(timeout: const Duration(days: 1))
              .then((_) => waited = true),
        );
        await settle(tester, until: () => waited);

        expect(
          waited,
          isTrue,
          reason: 'nothing would ever complete an orphaned entry, so the wait '
              'could only end by giving up on a scope that is already gone',
        );
        expect(tester.takeException(), isNull);
      },
    );

    // A `close()`d element stays mounted, so it can still be moved in the
    // tree with a `GlobalKey`: the element is deactivated and reactivated
    // rather than unmounted, and `activate()` re-runs the registration with
    // the parent. The disposal's `finally` unregistered the parent entry but
    // never cleared the field, so that re-registration reached for an entry
    // that was already gone -- an assert in debug, and a `Future already
    // completed` in release, where that assert is not there to stop it.
    testWidgets(
      'survives being moved with a GlobalKey after close()',
      (tester) async {
        final scopeKey = GlobalKey();
        Widget build({required bool moved}) => Directionality(
              textDirection: TextDirection.ltr,
              child: AsyncScopeCoordinator(
                child: Column(
                  children: [
                    if (!moved)
                      SizedBox(
                        child: _CloseScope(key: scopeKey, init: _neverEmits),
                      ),
                    if (moved)
                      Center(
                        child: _CloseScope(key: scopeKey, init: _neverEmits),
                      ),
                  ],
                ),
              ),
            );

        await tester.pumpWidget(build(moved: false));
        await tester.pumpAndSettle();

        final coordinator = tester.element(find.byType(AsyncScopeCoordinator))
            as AsyncScopeParent;
        expect(coordinator.childrenCount, 1);

        final element = _scopeOf(tester);
        var isClosed = false;
        unawaited(element.close().whenComplete(() => isClosed = true));
        await settle(tester, until: () => isClosed);

        expect(isClosed, isTrue);
        expect(coordinator.childrenCount, 0);

        // The closed scope is moved under a different parent widget: its
        // element is retaken by the `GlobalKey` instead of being unmounted,
        // so `activate()` runs on an element whose disposal is over.
        await tester.pumpWidget(build(moved: true));

        expect(
          tester.takeException(),
          isNull,
          reason: 'reactivating a closed scope must not reach for the parent '
              'entry its disposal already unregistered',
        );
        expect(
          coordinator.childrenCount,
          0,
          reason: 'a scope that is done disposing of itself must not register '
              'with its new parent either -- nothing would complete the entry',
        );
      },
    );

    // `close()` keeps the element mounted on purpose -- so it can render a
    // closing screen, and so it can still be moved with a `GlobalKey` -- and a
    // scope that has finished closing has already `exit()`ed its `AccessEntry`.
    // It holds no key and asks for none, so the live-ownership diagnostic has
    // nothing left to be true about: the three tests below pin that it stays
    // quiet afterwards, and loud while the disposal is still in flight.
    group('with a scopeKey', () {
      testWidgets(
        'may be moved under another coordinator once it has finished closing',
        (tester) async {
          final scope = _CloseScope(
            key: GlobalKey(),
            init: _neverEmits,
            testKey: 'shared',
          );
          // `Expanded`, so an `ErrorWidget` substituted for a failed build has
          // bounded constraints and cannot bury the report under a `Column`
          // overflow.
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

          var isClosed = false;
          unawaited(
            _scopeOf(tester).close().whenComplete(() => isClosed = true),
          );
          await settle(tester, until: () => isClosed);

          expect(isClosed, isTrue, reason: 'the key has been released');
          expect(tester.takeException(), isNull);

          await tester.pumpWidget(build(moved: true));

          expect(
            tester.takeException(),
            isNull,
            reason: 'a scope that has released its key holds nothing that '
                'could be left parked on the coordinator it came from',
          );
        },
      );

      testWidgets(
        'may be rebuilt with a different scopeKey once it has finished closing',
        (tester) async {
          Widget build(Object key) => Directionality(
                textDirection: TextDirection.ltr,
                child: AsyncScopeCoordinator(
                  child: _CloseScope(init: _neverEmits, testKey: key),
                ),
              );

          await tester.pumpWidget(build('shared'));
          await tester.pumpAndSettle();

          var isClosed = false;
          unawaited(
            _scopeOf(tester).close().whenComplete(() => isClosed = true),
          );
          await settle(tester, until: () => isClosed);

          expect(isClosed, isTrue, reason: 'the key has been released');
          expect(tester.takeException(), isNull);

          await tester.pumpWidget(build('other'));

          expect(
            tester.takeException(),
            isNull,
            reason: 'the key it read is no longer holding anything, so there '
                'is nothing left for a new one to contradict',
          );
        },
      );

      testWidgets(
        'still reports a scopeKey that changes while close() is in flight',
        (tester) async {
          // The init stream refuses to finish cancelling until the gate is
          // opened, so the disposal parks inside `await subscription.cancel()`
          // -- `_isDisposing` is set and the `AccessEntry` is still in the
          // queue. The scope never leaves the waiting state, so no closing
          // overlay is built: the substituted `ErrorWidget` then deactivates a
          // subtree of one `Text`, instead of one with a running animation in
          // it, which trips framework asserts of its own.
          final gate = Completer<void>();
          Widget build(Object key) => Directionality(
                textDirection: TextDirection.ltr,
                child: AsyncScopeCoordinator(
                  child: _CloseScope(
                    init: _neverEmitsUntilCancelled(gate),
                    testKey: key,
                  ),
                ),
              );

          await tester.pumpWidget(build('shared'));
          await tester.pumpAndSettle();
          expect(find.text('waiting'), findsOneWidget);

          var isClosed = false;
          unawaited(
            _scopeOf(tester).close().whenComplete(() => isClosed = true),
          );
          await settle(tester, until: () => isClosed);

          expect(isClosed, isFalse, reason: 'the disposal is still in flight');
          expect(tester.takeException(), isNull);

          await tester.pumpWidget(build('other'));

          final exception = tester.takeException();
          expect(
            exception,
            isA<FlutterError>(),
            reason: 'the entry is still in the queue, so this is the real '
                'violation and turning the check off on disposal would hide it',
          );
          expect(
            exception.toString(),
            contains('changed while the scope was holding one'),
          );

          gate.complete();
          await settle(tester, until: () => isClosed);
          expect(isClosed, isTrue);
        },
        // The violation this test is written for is raised while the element
        // is being updated, and the subtree it breaks stays unmounted --
        // see [unmountableTree].
        experimentalLeakTesting: unmountableTree,
      );
    });

    // The same shape as the `AsyncScopeElementBase` deadlock covered in
    // `async_scope_test.dart`, one layer down: `LiteScopeCoreState`
    // synchronizes its disposal with its own initialization through a
    // completer, and `_performAsyncInit()` runs on a future discarded by
    // `initState()`. A failed `initScope()` used to leave that completer
    // unsettled, so `close()` -- which reaches it through
    // `LiteScopeElementBase.disposeScope()` -- never came back.
    for (final (kind, isAsync) in [('synchronously', false), ('async', true)]) {
      testWidgets(
        'completes when the state initScope throws $kind',
        (tester) async {
          // The failure surfaces as an uncaught error of the zone the build
          // ran in, exactly as for the scope-level initialization; a guarded
          // child zone catches it before `flutter_test` ends the test on it.
          // Nothing inside that zone may throw -- an assertion that fails
          // there is swallowed by the zone's error handler and the test hangs
          // instead of failing -- so every `expect` is made once it is gone.
          final errors = <Object>[];
          var isClosed = false;
          late _CloseScopeElement element;

          await runZonedGuarded(
            () async {
              await tester.pumpWidget(
                _app(
                  _CloseScope(
                    init: _becomesReady,
                    failStateInit: true,
                    failStateInitAsync: isAsync,
                  ),
                ),
              );
              element = _scopeOf(tester);
              // The state only exists once the scope is ready: it is created
              // by the widget `buildOnReady()` mounts.
              await settle(tester, until: () => element.createdState != null);

              unawaited(element.close().whenComplete(() => isClosed = true));
              await settle(tester, until: () => isClosed);
            },
            (error, stackTrace) => errors.add(error),
          );

          expect(
            element.createdState,
            isNotNull,
            reason: 'the state must have been created and initialized',
          );
          expect(
            isClosed,
            isTrue,
            reason: 'close() must not wait for an initialization that failed',
          );
          expect(
            element.createdState!.disposeStateAsyncCount,
            1,
            reason: 'the initializer ran, so the teardown runs too -- what '
                'it took before it failed has no second owner to give it back',
          );
          expect(
            errors.single,
            isA<StateError>(),
            reason: 'the failure is still reported, not swallowed',
          );
        },
      );

      // The half of that the old promise had backwards. "The initialization
      // failed" is not "the initialization never happened": the initializer
      // ran, and an initializer that takes a connection, a subscription or a
      // handle and falls over on the next line has taken it. Nobody else can
      // give it back -- the state is the only one holding it, and the scope
      // never becomes ready, so its owner never gets a reference either.
      //
      // The controller family next door has always said so out loud:
      // `ScopeController.dispose` is documented to run "on every path,
      // including the one where init failed halfway, so it has to expect a
      // partially initialized controller". This is the state layer brought to
      // the same rule.
      testWidgets(
        'disposes of a state whose initStateAsync failed $kind after taking '
        'something',
        (tester) async {
          final errors = <Object>[];
          var isClosed = false;
          late _CloseScopeElement element;

          await runZonedGuarded(
            () async {
              await tester.pumpWidget(
                _app(
                  _CloseScope(
                    init: _becomesReady,
                    failStateInit: true,
                    failStateInitAsync: isAsync,
                  ),
                ),
              );
              element = _scopeOf(tester);
              await settle(tester, until: () => element.createdState != null);

              unawaited(element.close().whenComplete(() => isClosed = true));
              await settle(tester, until: () => isClosed);
            },
            (error, stackTrace) => errors.add(error),
          );

          expect(
            element.createdState!.acquired,
            isTrue,
            reason: 'the initializer took something before it failed -- '
                'without that this test proves nothing',
          );
          expect(
            element.createdState!.released,
            isTrue,
            reason: 'and it was given back: a teardown skipped here is a leak '
                'with no second owner to notice it',
          );
          expect(isClosed, isTrue);
          expect(errors.single, isA<StateError>());
        },
      );
    }

    // `close()` reaches `_performAsyncDispose()` directly, without going
    // through the `unmount()` guard, so it is the one caller that meets a
    // scope whose synchronous `init()` failed and whose asynchronous phase
    // therefore never started. Nothing will ever complete `_initCompleter`
    // for such a scope, and the disposal waits for it.
    testWidgets('completes for a scope whose synchronous init failed', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(const _CloseScope(init: _neverEmits, failSyncInit: true)),
      );
      expect(tester.takeException(), isA<StateError>());

      final element = _scopeOf(tester);
      var closed = false;
      unawaited(element.close().then((_) => closed = true));

      // Not `settle`: the failure is terminal, so every rebuild the disposal
      // asks for reports it again, and a second pending exception is a test
      // failure of its own. This is about `close()` coming back at all.
      for (var i = 0; i < 20 && !closed; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 10));
        tester.takeException();
      }

      expect(closed, isTrue);
      expect(
        element.unmountCount,
        1,
        reason: 'the synchronous half of the teardown runs whether the '
            'initialization got anywhere or not, and `close()` is the only '
            'path that can show it: a scope taken off the tree has already '
            'been unmounted by the framework by the time the teardown starts',
      );
    });

    // The four stages of a teardown are guarded apart so that a failure in
    // one never skips the ones after it, and the comment over them promises
    // the caller hears the *first* of them. Two of the three `catch`es
    // assigned to `failure` rather than keeping what was already there, so
    // the last failure won and the first was left in a log that is off by
    // default.
    //
    // Only `close()` can show it. On a scope taken off the tree the framework
    // has run `unmountScope()` before the teardown even starts, so its first
    // stage is a no-op there and cannot fail at all.
    testWidgets('reports the first failure of a teardown, not the last',
        (tester) async {
      final childGate = Completer<void>();
      addTearDown(() {
        if (!childGate.isCompleted) childGate.complete();
      });

      await tester.pumpWidget(
        _app(
          _CloseScope(
            init: _becomesReady,
            // Stage one fails...
            failStateUnmount: true,
            waitForChildren: const Duration(milliseconds: 50),
            // ...and stage two fails after it, on a wait that can only
            // expire: the scope below is held open by a teardown of its own
            // that never finishes, so it never unregisters.
            failOnWaitForChildrenTimeout: true,
            body: _CloseScope(
              init: _becomesReady,
              disposeGate: childGate,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final outer = tester.element<_CloseScopeElement>(
        find.byType(_CloseScope, skipOffstage: false).first,
      );
      expect(outer.childrenCount, 1);

      // Two failures are reported here, one after the other -- the expiry of
      // the wait, and then the stage that failed behind the first one --
      // and `takeException` collapses several of them into one summary
      // string. Captured directly, so both can be seen.
      final reported = <FlutterErrorDetails>[];
      final previousOnError = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = previousOnError);

      Object? failure;
      var done = false;
      unawaited(
        outer.close().then(
          (_) => done = true,
          onError: (Object error) {
            failure = error;
            done = true;
          },
        ),
      );
      // The wait has to actually expire here, or the second stage never fails
      // and the test asks nothing -- so this needs a helper that moves the
      // fake clock as well as real time. The file used to carry a private
      // copy that pumped without a duration, which moved neither, and this
      // test had to say so; there is one helper now.
      await settle(tester, until: () => done);

      // Put back before the assertions, and not only by the tear-down: while
      // it is in place, a failing `expect` is reported through it and
      // collected instead of ending the test.
      FlutterError.onError = previousOnError;

      expect(
        failure,
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'state onUnmount failed',
        ),
        reason: 'the caller of close() hears the first failure of the '
            'teardown, which is what the four stages were written to promise',
      );

      expect(
        reported.map((details) => details.exception),
        [
          isA<TimeoutException>(),
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'onWaitForChildrenTimeout failed',
          ),
        ],
        reason: 'the expiry of the wait is reported on its own, as it always '
            'is, and the failure of the second stage goes the same way: the '
            'throw is taken by the first stage, so a report is the only way '
            'out it has left',
      );

      // The child was held open on purpose, and while it is held its own half
      // of the teardown cannot finish. Let it go and give it the rounds to
      // finish in, or the test ends on a scope that is still tearing down.
      childGate.complete();
      await tester.pumpWidget(_app(const SizedBox(width: 1, height: 1)));
      await settle(tester, until: () => false);
    });

    // `LiteScopeCoreState.close()` used to look its own scope up through
    // `State.context`, though the element it wants is already in a field of
    // the state -- the neighbouring `notifyDependents()` uses exactly that.
    // The lookup costs two things: it goes through a `context` that is gone
    // `State.widget` is part of the contract a scope state has to satisfy and
    // has no answer here: the parameters live on the scope widget, and
    // `params` is the way to them. Anything that reads `widget` all the same --
    // a `State` mixin written for ordinary widgets -- deserves to be told why
    // rather than handed a bare `UnimplementedError`.
    testWidgets('a scope state says it has no widget of its own',
        (tester) async {
      await tester.pumpWidget(_app(const _CloseScope(init: _becomesReady)));
      await tester.pumpAndSettle();

      final state = _scopeOf(tester).createdState!;

      expect(state.params, isA<_CloseScope>());
      expect(
        () => state.widget,
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'message',
            contains('`params`'),
          ),
        ),
      );

      await tester.pumpWidget(_app(const SizedBox(width: 1, height: 1)));
      await settle(tester, until: () => false);
    });

    // once the state has been unmounted, and it finds the *nearest* scope of
    // that type, which is not necessarily this one.
    testWidgets('close() on a state whose tree is gone is a no-op',
        (tester) async {
      await tester.pumpWidget(_app(const _CloseScope(init: _becomesReady)));
      await tester.pumpAndSettle();

      final state = _scopeOf(tester).createdState!;

      await tester.pumpWidget(_app(const SizedBox(width: 1, height: 1)));
      await settle(tester, until: () => false);

      Object? failure;
      var done = false;
      unawaited(
        state.close().then(
          (_) => done = true,
          onError: (Object error) {
            failure = error;
            done = true;
          },
        ),
      );
      await settle(tester, until: () => done);

      expect(
        failure,
        isNull,
        reason: 'the scope this state belongs to is a field, not something to '
            'go looking for through a context that no longer exists',
      );
      expect(done, isTrue);
    });

    // The state lives in the widget the ready branch mounts, so `of` and
    // `select` have nothing to answer with in any other state. They used to
    // say so with a bare `Null check operator used on a null value`, which
    // names neither the scope nor the phase it is in -- and the `base` topic
    // promises that both ways a lookup can fail carry the type that was asked
    // for.
    testWidgets('of() before the ready branch says which scope and which state',
        (tester) async {
      await tester.pumpWidget(_app(const _CloseScope(init: _neverEmits)));
      await tester.pump();

      final element = _scopeOf(tester);

      _CloseScopeState lookUp() =>
          LiteScopeCore.of<_CloseScope, _CloseScopeElement, _CloseScopeState>(
            element,
          );

      expect(
        lookUp,
        throwsA(
          isA<StateError>()
              .having(
                (error) => error.message,
                'names the scope',
                contains('_CloseScope'),
              )
              .having(
                (error) => error.message,
                'names the state it is in',
                contains('AsyncScopeWaiting'),
              ),
        ),
      );
    });

    // M5 of the sixth review. `close()` from the build of a descendant is a
    // mistake of the caller's -- the framework refuses `markNeedsBuild()`
    // there -- but the refusal used to be permanent. The whole run was sealed
    // into `_closeCompleter`, its synchronous prefix included, and every later
    // caller joined that failed future: the teardown at unmount was one of
    // them, so the scope was never disposed of at all. Nothing of it ran --
    // no `disposeScope`, no cancellation of `initScope`, no
    // `disposeStateAsync`, no leaving of the `scopeKey` queue -- and the leak
    // tracker saw what that left behind.
    testWidgets('a close() refused from a build does not poison the teardown',
        (tester) async {
      final closeNow = ValueNotifier(false);
      addTearDown(closeNow.dispose);

      late final _CloseScopeElement element;
      Object? refusal;

      await tester.pumpWidget(
        _app(
          _CloseScope(
            init: _becomesReady,
            // A listener of its own, so the rebuild it asks for starts from
            // *this* element. A rebuild driven from the root -- which is what
            // a second `pumpWidget` gives -- has the scope inside the build
            // target, and the framework allows the call from there.
            body: ListenableBuilder(
              listenable: closeNow,
              builder: (context, child) {
                if (closeNow.value) {
                  unawaited(
                    element.close().onError((error, stackTrace) {
                      refusal = error;
                    }),
                  );
                }

                return const SizedBox();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      element = _scopeOf(tester);
      closeNow.value = true;
      await tester.pump();

      expect(
        refusal,
        isNotNull,
        reason: 'the caller is told about its own mistake, and that much was '
            'never in question',
      );

      await tester.pumpWidget(_app(const SizedBox(width: 1, height: 1)));
      await settle(tester, until: () => false);

      expect(
        element.disposeScopeCount,
        1,
        reason: 'the scope leaving the tree runs its teardown all the same: '
            'what failed above happened before the teardown had begun, so it '
            'is not the answer every later caller gets',
      );
    });

    // Info-1 of the post-wave review. The test above takes one of the two
    // paths out of a refusal -- the tree coming down -- and the review's own
    // probe took the other, a second `close()` from somewhere the framework
    // allows it. Probed and working is not pinned, and this is the path a
    // caller actually retries on: the refusal came from their own build, so
    // the obvious next move is to call again from outside it.
    testWidgets('a close() that follows a refused one runs the teardown once',
        (tester) async {
      final closeNow = ValueNotifier(false);
      addTearDown(closeNow.dispose);

      late final _CloseScopeElement element;
      Object? refusal;

      await tester.pumpWidget(
        _app(
          _CloseScope(
            init: _becomesReady,
            body: ListenableBuilder(
              listenable: closeNow,
              builder: (context, child) {
                if (closeNow.value) {
                  unawaited(
                    element.close().onError((error, stackTrace) {
                      refusal = error;
                    }),
                  );
                }

                return const SizedBox();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      element = _scopeOf(tester);
      closeNow.value = true;
      await tester.pump();

      expect(refusal, isNotNull, reason: 'refused, as it must be');

      // Out of the build that was refused, and into the ordinary way of
      // asking.
      closeNow.value = false;
      await tester.pump();

      var isClosed = false;
      unawaited(element.close().whenComplete(() => isClosed = true));
      await settle(tester, until: () => isClosed);

      expect(
        element.disposeScopeCount,
        1,
        reason: 'the refusal was not sealed into the memo every later caller '
            'joins: this one ran the teardown, and ran it whole',
      );

      await tester.pumpWidget(_app(const SizedBox(width: 1, height: 1)));
      await settle(tester, until: () => false);

      expect(
        element.disposeScopeCount,
        1,
        reason: 'and the tree coming down after a close that finished does '
            'not run it a second time',
      );
    });
  });

  // L17 of the sixth review. The notification arrives late -- a subscription
  // the caller did not take off in `onUnmount`, a teardown of their own
  // reporting as it goes -- and the element it aims at is gone. What the
  // framework answers is `'_lifecycleState != _ElementLifecycle.defunct' is
  // not true`, which names neither the scope nor what was done to it; the
  // deferred half of the same method has always simply dropped it.
  testWidgets('a notification that arrives after the scope is gone is dropped',
      (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: _HalvesScope(child: _HalvesReader()),
      ),
    );
    await tester.pumpAndSettle();

    final state = _HalvesScope.of(tester.element(find.byType(_HalvesReader)));

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(width: 1, height: 1),
      ),
    );
    await settle(tester, until: () => false);

    state.bumpWithNotify();

    expect(
      tester.takeException(),
      isNull,
      reason: 'a report with nobody to hear it is dropped, not raised -- the '
          'rule this package follows everywhere else',
    );
  });

  // L18 of the sixth review. `null` from `buildOnWaiting` means "show the
  // initializing branch instead", and the default of that branch refuses with
  // a message about a scope that overrides `initScope()`. A `LiteScope` that
  // overrides nothing of the sort was told two things that are not true about
  // it, and neither of them was the branch it is actually missing.
  testWidgets(
    'a scope with no waiting branch is told which branch is missing',
    (tester) async {
      await tester.pumpWidget(_app(const _NoWaitingBranchScope()));

      expect(
        tester.takeException(),
        isA<UnimplementedError>().having(
          (error) => error.message,
          'names both branches, and blames neither on `initScope()`',
          allOf(
            contains('buildOnWaiting()'),
            contains('buildOnProgress()'),
            isNot(contains('initScope()')),
          ),
        ),
      );
    },
    // The refusal happens while the element is being inflated, and an element
    // abandoned half-built is never disposed of by anyone -- see
    // [unmountableTree], which covers exactly that case.
    experimentalLeakTesting: unmountableTree,
  );

  // `_performAsyncInit` hands the cancellation over to `_subscription`, and
  // `_performAsyncDispose` can only reach it through that field. A scope with
  // a `scopeKey` awaits `AsyncScopeCoordinator.enter()` before it subscribes,
  // so between the `await` and the assignment there is a window in which the
  // field is still `null` and a disposal that starts there has nothing to
  // cancel. A scope closed with `close()` stays mounted, so the `mounted`
  // guard on the far side of that `await` does not catch it either.
  //
  // The window is entered by driving the build phase directly and *not*
  // awaiting anything afterwards: `enter()` on a free key completes in a
  // microtask, so until the test yields, `_performAsyncInit` is parked at the
  // `await` with `_subscription == null`.
  group('AsyncScope initialization racing a disposal that already began', () {
    testWidgets(
      'control: a scope with a free scopeKey does start its initialization',
      (tester) async {
        var initCount = 0;
        final element = _mountInEnterWindow(
          tester,
          init: (ctx) {
            initCount++;

            return _becomesReady(ctx);
          },
        );

        expect(
          initCount,
          0,
          reason: 'the probe must observe the window: `initScope()` cannot '
              'have been called before the key was granted',
        );

        await settle(tester, until: () => element.state is AsyncScopeReady);

        expect(
          initCount,
          1,
          reason: 'a scope that is not being disposed of initializes as usual',
        );
        expect(element.state, isA<AsyncScopeReady>());
      },
    );

    testWidgets(
      'does not initialize when close() wins the race for a free scopeKey',
      (tester) async {
        var initCount = 0;
        final element = _mountInEnterWindow(
          tester,
          init: (ctx) {
            initCount++;

            return _becomesReady(ctx);
          },
        );

        // No `await` since the mount: the disposal starts inside the window,
        // while `_subscription` is still `null`.
        var isClosed = false;
        unawaited(element.close().whenComplete(() => isClosed = true));

        await settle(tester, until: () => isClosed);

        expect(isClosed, isTrue, reason: 'close() must still settle');
        expect(
          initCount,
          0,
          reason: 'a scope that is going away must not subscribe to its own '
              'initialization once the key finally arrives',
        );
        expect(
          element.disposeScopeCount,
          0,
          reason: 'an initialization that never ran has nothing to release',
        );
        expect(
          element.state,
          isA<AsyncScopeWaiting>(),
          reason: 'the scope never became ready',
        );
        expect(tester.takeException(), isNull);
      },
    );
  });

  // The two halves the `README.md` names: `notifyDependents()` reaches the
  // subscribers and not the state's own `build`, `setState` the other way
  // round. Nothing in the package touches `setState` -- a scope state is an
  // ordinary `State` -- and the README now says so, which is why it is pinned
  // here rather than left to be re-derived.
  group('notifyDependents and setState are separate halves', () {
    testWidgets('notifyDependents reaches the subscribers, not the own build',
        (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: _HalvesScope(child: _HalvesReader()),
        ),
      );
      await tester.pumpAndSettle();

      expect(_shown(tester), 'own 0 | reader 0');

      _HalvesScope.of(tester.element(find.byType(_HalvesReader)))
          .bumpWithNotify();
      await tester.pumpAndSettle();

      expect(
        _shown(tester),
        'own 0 | reader 1',
        reason: "the subscriber saw the new value and the state's own build "
            'did not run, so what it draws from the same field is stale',
      );

      await _teardown(tester);
    });

    testWidgets('setState reaches the own build, not the subscribers',
        (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: _HalvesScope(child: _HalvesReader()),
        ),
      );
      await tester.pumpAndSettle();

      _HalvesScope.of(tester.element(find.byType(_HalvesReader)))
          .bumpWithSetState();
      await tester.pumpAndSettle();

      expect(
        _shown(tester),
        'own 1 | reader 0',
        reason: 'setState is untouched by the package and does what it does '
            'on any State -- and a subscriber is not part of that',
      );

      await _teardown(tester);
    });
  });

  group('ScreenshotReplacer', () {
    testWidgets(
      'reports completion exactly once and releases the captured image',
      (tester) async {
        var completedCount = 0;

        await tester.pumpWidget(
          _app(
            ScreenshotReplacer(
              onCompleted: () => completedCount++,
              child: const SizedBox(
                width: 20,
                height: 20,
                child: ColoredBox(color: Color(0xFF00FF00)),
              ),
            ),
          ),
        );

        ui.Image? captured;
        await settle(
          tester,
          until: () {
            final images = find.byType(RawImage);
            if (images.evaluate().isEmpty) return false;
            captured = tester.widget<RawImage>(images).image;
            return captured != null;
          },
        );

        expect(
          captured,
          isNotNull,
          reason: 'the repaint boundary was never captured',
        );
        expect(
          completedCount,
          1,
          reason: 'completion is reported once, on the success path',
        );
        expect(captured!.debugDisposed, isFalse);

        // Removing the widget must not report completion a second time, and
        // must release the `ui.Image` handle owned by the state.
        await tester.pumpWidget(_app(const SizedBox.shrink()));

        expect(
          completedCount,
          1,
          reason: 'disposal must not report completion again',
        );
        expect(
          captured!.debugDisposed,
          isTrue,
          reason: 'the captured ui.Image must be disposed of with the state',
        );
      },
    );

    // `onCompleted` is the application's code, and the package calls it from
    // places nobody is waiting on: the capture runs in a post-frame callback as
    // an unawaited future, and the last resort is `dispose`. A raise left in the
    // first surfaced as an unhandled zone error far from the widget; a raise
    // left in the second came out of `State.dispose`, which the framework does
    // not guard, and took the unmount down halfway.
    testWidgets(
      'a raising onCompleted is reported, not left in the frame that captured',
      (tester) async {
        await tester.pumpWidget(
          _app(
            ScreenshotReplacer(
              onCompleted: () => throw StateError('the caller fell over'),
              child: const SizedBox(
                width: 20,
                height: 20,
                child: ColoredBox(color: Color(0xFF00FF00)),
              ),
            ),
          ),
        );

        ui.Image? captured;
        await settle(
          tester,
          until: () {
            final images = find.byType(RawImage);
            if (images.evaluate().isEmpty) return false;
            captured = tester.widget<RawImage>(images).image;
            return captured != null;
          },
        );

        expect(
          captured,
          isNotNull,
          reason: 'the screenshot is taken whatever the caller does with the '
              'news of it',
        );
        expect(tester.takeException(), isA<StateError>());

        await tester.pumpWidget(_app(const SizedBox.shrink()));

        expect(
          tester.takeException(),
          isNull,
          reason:
              'and it is reported once: the report is one-shot, raise or no '
              'raise',
        );
        expect(
          captured!.debugDisposed,
          isTrue,
          reason: 'the handle the state owns is released with it',
        );
      },
    );

    // The order `dispose` does its two jobs in was a finding of the third review
    // (P3-8): telling the application before releasing the `ui.Image` would lose
    // the native memory of the screenshot if the callback raised. The order is
    // the other way round now, and this is the reason it costs nothing: the two
    // never meet. A capture that produced an image reported completion in the
    // same synchronous step, so when `dispose` is the one to report, there is no
    // image at all.
    testWidgets(
      'when disposal is the one to report, there is no image to release',
      (tester) async {
        // Offstage is never painted, so the capture keeps retrying and nothing
        // has reported completion by the time the widget goes away.
        await tester.pumpWidget(
          _app(
            Offstage(
              child: ScreenshotReplacer(
                onCompleted: () => throw StateError('the caller fell over'),
                child: const SizedBox(width: 20, height: 20),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(
          find.byType(RawImage, skipOffstage: false),
          findsNothing,
          reason: 'nothing was captured, which is why the report is left to '
              'disposal',
        );

        await tester.pumpWidget(_app(const SizedBox.shrink()));

        expect(
          tester.takeException(),
          isA<StateError>(),
          reason:
              'and the raise is reported rather than carried out of dispose',
        );
        expect(find.byType(ScreenshotReplacer), findsNothing);
      },
    );

    testWidgets(
      'retries without reporting completion, then gives up after the retry cap',
      (tester) async {
        var completedCount = 0;

        // An offstage subtree is never painted, so `debugNeedsPaint` stays true
        // and every attempt takes the retry path.
        await tester.pumpWidget(
          _app(
            Offstage(
              child: ScreenshotReplacer(
                onCompleted: () => completedCount++,
                child: const SizedBox(
                  key: ValueKey('captured'),
                  width: 20,
                  height: 20,
                ),
              ),
            ),
          ),
        );

        // The first attempt already ran, in the post-frame callback of the
        // frame above.
        expect(
          completedCount,
          0,
          reason: 'the first attempt must not report completion',
        );

        // A retry must never release the barrier: there is no screenshot yet.
        // Counted to the cap rather than pumped "enough" times: `>=` and `>`
        // differ by exactly one frame, and a loop that pumps until something
        // happens cannot tell them apart. The frame after the last retry is
        // the one that gives up, so every frame before it has to be silent.
        for (var i = 1; i < ScreenshotReplacer.maxRetries; i++) {
          await tester.pump();
          expect(
            completedCount,
            0,
            reason: 'retry $i of ${ScreenshotReplacer.maxRetries} must not '
                'report completion',
          );
        }

        await tester.pump();

        expect(
          completedCount,
          1,
          reason: 'and the attempt after the last retry gives up, exactly '
              'once',
        );
        expect(find.byType(RawImage, skipOffstage: false), findsNothing);

        // Retrying must have stopped: no further frame reports again.
        for (var i = 0; i < 3; i++) {
          await tester.pump();
        }
        expect(completedCount, 1);
        expect(
          find.byKey(const ValueKey('captured'), skipOffstage: false),
          findsNothing,
          reason: 'and the child is gone with the picture that could not be '
              'taken of it: what waits on the report waits in order to let go '
              'of what the child holds',
        );
      },
    );
  });
}

Widget _app(Widget child) => MaterialApp(home: Center(child: child));

/// The scope element currently in the tree, offstage or not.
_CloseScopeElement _scopeOf(WidgetTester tester) =>
    tester.element<_CloseScopeElement>(
      find.byType(_CloseScope, skipOffstage: false),
    );

/// the budget runs out.
///
/// Some of the futures involved here are only completed outside the test's
/// fake-async zone -- the engine rasterization behind
/// `RenderRepaintBoundary.toImage()`, and the `StreamSubscription.cancel()`
/// chain of `AsyncScopeElementBase._performAsyncDispose` (the same `runAsync`
/// workaround is documented in `async_scope_test.dart`) -- so plain `pump()`
/// and `idle()` are not enough to let them make progress.
/// Mounts a scope holding a `scopeKey` and returns while its
/// `_performAsyncInit` is still parked on `AsyncScopeCoordinator.enter()`.
///
/// The build phase is driven directly, so no frame is drawn and no microtask
/// is drained: `enter()` on a free key completes one microtask later, which
/// cannot happen until the caller yields. Everything the caller does before
/// its next `await` therefore happens while `_subscription` is still `null`.
_CloseScopeElement _mountInEnterWindow(
  WidgetTester tester, {
  required Future<void> Function(ScopeInitContext ctx) init,
}) {
  final binding = tester.binding;
  binding.attachRootWidget(
    binding.wrapWithDefaultView(
      Directionality(
        textDirection: TextDirection.ltr,
        child: AsyncScopeCoordinator(
          child: _CloseScope(init: init, testKey: 'window'),
        ),
      ),
    ),
  );
  binding.buildOwner!.buildScope(binding.rootElement!);

  return _scopeOf(tester);
}

/// Keeps the scope in [AsyncScopeWaiting]: nothing is ever reported, and the
/// body never comes back on its own.
Future<void> _neverEmits(ScopeInitContext ctx) =>
    // Through the context, so the cancellation ends the wait at once -- what
    // a stream that emits nothing and cancels immediately used to do.
    ctx.wait(() => Completer<void>().future);

/// Like [_neverEmits], but the cancellation the disposal awaits does not
/// finish until [gate] is completed.
///
/// That parks `_performAsyncDispose` between `_isDisposing = true` and the
/// `finally` that releases the key -- the window in which the scope is closing
/// and still holding its `AccessEntry`.
Future<void> Function(ScopeInitContext) _neverEmitsUntilCancelled(
  Completer<void> gate,
) =>
    (ctx) async {
      // Not through `ctx.wait`: the body has to be still running when the
      // cancellation arrives, and to end only once the gate lets it.
      await gate.future;
    };

/// Moves the scope into [AsyncScopeProgress] and keeps it there.
Future<void> _emitsProgressOnly(ScopeInitContext ctx) {
  ctx.progress(1);

  return ctx.wait(() => Completer<void>().future);
}

/// Moves the scope into [AsyncScopeError].
Future<void> _failsImmediately(ScopeInitContext ctx) async {
  throw Exception('init failed');
}

/// Moves the scope into [AsyncScopeReady].
Future<void> _becomesReady(ScopeInitContext ctx) async {}

/// A minimal [LiteScopeCore] with an element type visible to the test, so
/// [LiteScopeElementBase.close] can be called in any state -- including the
/// states in which no [LiteScopeCoreState] exists yet.
final class _CloseScope
    extends LiteScopeCore<_CloseScope, _CloseScopeElement, _CloseScopeState> {
  final Future<void> Function(ScopeInitContext ctx) init;

  /// Makes [_CloseScopeState.initStateAsync] fail, the way a plain user error in a
  /// state initializer does.
  final bool failStateInit;

  /// Whether that failure is raised from a future ([_CloseScopeState.initStateAsync]
  /// returns a `FutureOr<void>`, so both are ordinary user code).
  final bool failStateInitAsync;

  /// Makes [_CloseScopeState.disposeStateAsync] fail, the way a resource that
  /// refuses to be released does.
  final bool failStateDispose;

  /// Makes the synchronous [ScopeInheritedElement.init] fail, so the scope
  /// never reaches its asynchronous phase at all.
  final bool failSyncInit;

  /// Makes [_CloseScopeState.onUnmount] fail. On the `close()` path this is
  /// the *first* stage of the teardown, and the only path on which that stage
  /// can fail at all: a scope taken off the tree has already been unmounted
  /// by the framework by the time the teardown gets there.
  final bool failStateUnmount;

  /// Becomes [AsyncScopeElementBase.waitForChildrenTimeout], so the second
  /// stage of the teardown can be made to expire.
  final Duration? waitForChildren;

  /// Makes the expiry callback of that wait fail, which is how the second
  /// stage raises: it is user code and it is not wrapped.
  final bool failOnWaitForChildrenTimeout;

  /// Built by the state instead of its usual leaf. A scope in here stays
  /// registered with this one for as long as it is mounted -- and `close()`
  /// keeps everything mounted -- so the wait for the children runs out.
  ///
  /// Not `child`: that name belongs to [ProxyWidget] and is not nullable.
  final Widget? body;

  /// Parks [_CloseScopeState.disposeStateAsync] on this. A scope below another
  /// one unregisters from it only once its own teardown is over, so a scope
  /// held here keeps its parent waiting -- which is the only way to make the
  /// parent's wait for its children expire.
  final Completer<void>? disposeGate;

  /// Becomes [AsyncScopeElementBase.scopeKey], so `close()` can be exercised
  /// on a scope that actually holds a key.
  final Object? testKey;

  /// Makes every branch build its own [MaterialApp], the way the topic and
  /// `example/minimal` build a root scope: `wrapState` returns the app, so
  /// every [Directionality] in the tree is *below* this scope rather than
  /// above it.
  final bool wrapInApp;

  /// Makes [_CloseScopeElement.buildOnClosing] fail, the way a closing screen
  /// that reads something the teardown has already released does.
  final bool failClosingBuild;

  /// Makes [_CloseScopeElement.buildOnClosing] return a widget that fails
  /// while it is being *mounted* rather than while it is being built — the one
  /// failure the guard around the closing build cannot see.
  final bool failClosingMount;

  const _CloseScope({
    super.key,
    required this.init,
    this.failStateInit = false,
    this.failStateInitAsync = false,
    this.failStateDispose = false,
    this.failSyncInit = false,
    this.failStateUnmount = false,
    this.waitForChildren,
    this.failOnWaitForChildrenTimeout = false,
    this.body,
    this.disposeGate,
    this.testKey,
    this.wrapInApp = false,
    this.failClosingBuild = false,
    this.failClosingMount = false,
  });

  @override
  _CloseScopeElement createScopeElement() => _CloseScopeElement(this);
}

final class _CloseScopeElement extends LiteScopeElementBase<_CloseScope,
    _CloseScopeElement, _CloseScopeState> {
  /// How many times [disposeScope] ran, to prove that a disposal racing the
  /// ready state still releases what `initScope()` acquired.
  int disposeScopeCount = 0;

  /// The state built by `buildOnReady()`, kept here because the widget that
  /// owns it is private to the package and cannot be found by type.
  _CloseScopeState? createdState;

  /// How many times the element's own `onUnmount` ran.
  int unmountCount = 0;

  _CloseScopeElement(super.widget);

  @override
  Object? get scopeKey => widget.testKey;

  @override
  void onUnmount() {
    unmountCount++;
    super.onUnmount();
  }

  @override
  Duration? get waitForChildrenTimeout => widget.waitForChildren;

  @override
  void onWaitForChildrenTimeout() {
    if (widget.failOnWaitForChildrenTimeout) {
      throw StateError('onWaitForChildrenTimeout failed');
    }
  }

  @override
  void init() {
    if (widget.failSyncInit) {
      throw StateError('controlled sync init failure');
    }
    super.init();
  }

  @override
  Future<void> initScopeAsync(ScopeInitContext ctx) => widget.init(ctx);

  @override
  Future<void> disposeScope() async {
    disposeScopeCount++;
    await super.disposeScope();
  }

  /// What the topic calls "a widget every branch needs": with no scope above
  /// this one, the app is built by each branch rather than around them.
  Widget _branch(Widget child) =>
      widget.wrapInApp ? MaterialApp(home: child) : child;

  @override
  Widget wrapState(Widget child) => _branch(child);

  @override
  Widget? buildOnClosing() {
    if (widget.failClosingBuild) {
      throw StateError('buildOnClosing failed');
    }
    if (widget.failClosingMount) {
      // Throws while it is being mounted rather than while it is being built:
      // a bare `Stack` resolves its alignment through a `Directionality`, and
      // under `wrapInApp` there is none above this point.
      return const Stack();
    }

    return null;
  }

  @override
  Widget? buildOnWaiting() => _branch(const Text('waiting'));

  @override
  Widget buildOnProgress(Object? progress) =>
      _branch(const Text('initializing'));

  @override
  Widget buildOnError(
    Object error,
    StackTrace stackTrace,
    Object? progress,
  ) =>
      _branch(const Text('error'));

  @override
  _CloseScopeState createState() => createdState = _CloseScopeState();
}

final class _CloseScopeState extends LiteScopeCoreState<_CloseScope,
    _CloseScopeElement, _CloseScopeState> {
  /// How many times [disposeStateAsync] ran, to prove that a state whose
  /// initialization failed is not disposed of.
  int disposeStateAsyncCount = 0;

  /// Whether [initStateAsync] got as far as taking something.
  ///
  /// Set before the failure below, so a test can tell "acquired, and then it
  /// failed" from "it failed having taken nothing" -- two different things
  /// that used to end the same way.
  bool acquired = false;

  /// Whether [disposeStateAsync] gave that back.
  bool released = false;

  @override
  FutureOr<void> initStateAsync() {
    if (!params.failStateInit) return null;

    // Taken and working, before the failure below.
    acquired = true;

    if (params.failStateInitAsync) {
      return Future<void>.error(StateError('state initStateAsync failed'));
    }

    throw StateError('state initStateAsync failed');
  }

  @override
  FutureOr<void> disposeStateAsync() {
    disposeStateAsyncCount++;
    released = true;
    if (params.disposeGate case final gate?) {
      return gate.future;
    }
    if (!params.failStateDispose) return null;

    // A real asynchronous failure, delivered through an awaited future one
    // microtask later, so it takes the same propagation path a resource that
    // refuses to be released would.
    return Future<void>.error(StateError('state disposeStateAsync failed'));
  }

  @override
  void onUnmount() {
    super.onUnmount();
    if (params.failStateUnmount) {
      throw StateError('state onUnmount failed');
    }
  }

  @override
  Widget build(BuildContext context) => params.body ?? const Text('ready');
}

/// Takes the scope off the tree and lets its asynchronous teardown finish.
///
/// The suite runs with the leak tracker on, and a `LiteScope` releases what it
/// holds on real futures rather than on the fake clock `pump` advances.
Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  // `until` that never holds: the scope is out of the tree the moment the
  // pump above returns, so there is nothing left to wait *for* -- what is
  // needed is the rounds themselves, which is the fair chance `settle` is
  // documented to give.
  await settle(tester, until: () => false);
}

/// What the two halves have put on screen, in one string.
String _shown(WidgetTester tester) =>
    tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).join(' | ');

/// A scope with nothing to show while it waits: `buildOnWaiting` answers
/// `null` and `buildOnProgress` was never written.
final class _NoWaitingBranchScope
    extends LiteScope<_NoWaitingBranchScope, _NoWaitingBranchState> {
  const _NoWaitingBranchScope();

  @override
  _NoWaitingBranchState createState() => _NoWaitingBranchState();

  @override
  Widget? buildOnWaiting(BuildContext context) => null;
}

final class _NoWaitingBranchState
    extends LiteScopeState<_NoWaitingBranchScope, _NoWaitingBranchState> {
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// A scope whose state draws one counter and hands the same counter to a
/// subscriber, so the two halves can be told apart on screen.
final class _HalvesScope extends LiteScope<_HalvesScope, _HalvesScopeState> {
  const _HalvesScope({super.child});

  @override
  _HalvesScopeState createState() => _HalvesScopeState();

  @override
  Widget? buildOnWaiting(BuildContext context) => const SizedBox.shrink();

  static _HalvesScopeState of(BuildContext context) =>
      LiteScope.of<_HalvesScope, _HalvesScopeState>(context);
}

final class _HalvesScopeState
    extends LiteScopeState<_HalvesScope, _HalvesScopeState> {
  int counter = 0;

  void bumpWithSetState() => setState(() => counter++);

  void bumpWithNotify() {
    counter++;
    notifyDependents();
  }

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text('own $counter'),
          params.child,
        ],
      );
}

final class _HalvesReader extends StatelessWidget {
  const _HalvesReader();

  @override
  Widget build(BuildContext context) => Text(
        'reader '
        '${LiteScope.select<_HalvesScope, _HalvesScopeState, int>(
          context,
          (state) => state.counter,
        )}',
      );
}
