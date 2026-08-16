import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scopo/scopo.dart';

void main() {
  group('AsyncScope post-frame callbacks', () {
    testWidgets(
      'does not assert when the element is removed from the tree before '
      'the post-frame callback that registers it with the parent scope '
      'has a chance to run',
      (tester) async {
        final binding = tester.binding;

        // Mount the scope by driving the build phase directly
        // (`BuildOwner.buildScope`) instead of `pumpWidget`. This is
        // necessary because `WidgetTester.pumpWidget`/`pump` always run a
        // full `handleDrawFrame()`, which unconditionally drains *every*
        // currently-queued post-frame callback right after the build
        // phase -- including the one the first `performRebuild()` schedules
        // synchronously, via `SchedulerBinding.addPostFrameCallback` in
        // `_performAsyncInit`.
        // That makes it impossible to get the element removed *before*
        // that specific callback runs using only `pumpWidget` calls: the
        // callback always fires within the very same frame it was
        // registered in.
        //
        // Calling `buildScope` directly mounts the widget (and schedules
        // the post-frame callback) without ever draining the post-frame
        // queue, since no `handleDrawFrame()` occurs.
        binding.attachRootWidget(
          binding.wrapWithDefaultView(
            const Directionality(
              textDirection: TextDirection.ltr,
              child: _RegisterRaceScope(),
            ),
          ),
        );
        binding.buildOwner!.buildScope(binding.rootElement!);

        // Remove it the same way: swap the root widget and rebuild, then
        // finalize the tree so the (now inactive) element is actually
        // unmounted -- all without drawing a frame, so the post-frame
        // callback registered above is still pending.
        binding.attachRootWidget(
          binding.wrapWithDefaultView(
            const Directionality(
              textDirection: TextDirection.ltr,
              child: SizedBox.shrink(),
            ),
          ),
        );
        binding.buildOwner!.buildScope(binding.rootElement!);
        binding.buildOwner!.finalizeTree();

        // Now draw the first real frame. It drains the pending post-frame
        // callback against the now-defunct element. Without the `mounted`
        // guard, `_registerWithParent()`'s call to `visitAncestorElements`
        // throws "Looking up a deactivated widget's ancestor is unsafe."
        // (verified to fail with exactly that assertion before the guard
        // was added).
        await tester.pump();

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'does not throw when the element is removed before the post-frame '
      'callback that applies the ready state runs, and still runs '
      'disposeAsync for the resources initAsync acquired',
      (tester) async {
        final binding = tester.binding;

        // Mount, again by driving `BuildOwner.buildScope` directly instead
        // of `pumpWidget`, for the same reason as above: this callback
        // (`addPostFrameCallback((_) { _model.update(state); })` in the
        // `AsyncScopeReady` branch of `_performAsyncInit`) is only
        // scheduled once `initAsync()` completes, which -- unlike the
        // `_registerWithParent` callback -- does not happen synchronously
        // during the first `performRebuild()`. `pumpWidget`/`pump` would
        // drain it within the very same call that schedules it, so we drive
        // things by hand.
        binding.attachRootWidget(
          binding.wrapWithDefaultView(
            const Directionality(
              textDirection: TextDirection.ltr,
              child: _ReadyRaceScope(),
            ),
          ),
        );
        binding.buildOwner!.buildScope(binding.rootElement!);

        // Captured before removal, so the assertion below can inspect the
        // (by-then-defunct, but still perfectly readable) element instance
        // directly instead of relying on a static/global counter.
        final element = tester.element(find.byType(_ReadyRaceScope))
            as _ReadyRaceScopeElement;

        // `TestWidgetsFlutterBinding.idle()` runs `FakeAsync.elapse
        // (Duration.zero)`: it flushes pending microtasks/zero-duration
        // timers *without* drawing a frame. This lets `initAsync()`
        // (`Stream.value(AsyncScopeReady())`) deliver its value and the
        // `AsyncScopeReady` branch run -- scheduling the post-frame
        // callback and calling `scheduleFrame()` -- while leaving that
        // callback pending, since nothing has drawn a frame yet.
        await binding.idle();

        // Remove the scope the same way as above: swap the root widget,
        // rebuild, and finalize -- all without drawing a frame, so the
        // post-frame callback scheduled above is still pending. This
        // starts `_performAsyncDispose()` (async, `dispose()` returns as
        // soon as it hits its first `await`).
        binding.attachRootWidget(
          binding.wrapWithDefaultView(
            const Directionality(
              textDirection: TextDirection.ltr,
              child: SizedBox.shrink(),
            ),
          ),
        );
        binding.buildOwner!.buildScope(binding.rootElement!);
        binding.buildOwner!.finalizeTree();

        // `idle()`/`FakeAsync.elapse` alone was not enough to let
        // `_performAsyncDispose()`'s chain (await subscription.cancel(),
        // then eventually `_model.dispose()`) run to completion in this
        // scenario -- verified experimentally, even after repeated
        // `idle()` calls. `runAsync` escapes the fake-async zone and runs
        // a real `Future.delayed` on the real event loop, which lets that
        // chain -- and any real microtask/timer continuations it depends
        // on -- actually finish before we drain the stale callback below.
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );

        // Now draw the first real frame. It drains the pending post-frame
        // callback, which calls `_model.update(state)`. Without the
        // `mounted` guard, this throws "A _AsyncScopeNotifier was used
        // after being disposed." (verified to fail with exactly that
        // message before the guard was added).
        await tester.pump();

        expect(tester.takeException(), isNull);

        // Guarding this callback with `mounted` must not come at the cost
        // of skipping `disposeAsync()`: since the callback never runs,
        // `model.state` never becomes `AsyncScopeReady`, so
        // `_performAsyncDispose` cannot rely on `model.state` to decide
        // whether `initAsync()` succeeded -- it must track that
        // separately. `initAsync()` did complete successfully here (it
        // acquired whatever `disposeAsync()` is meant to release), so
        // `disposeAsync()` must still run exactly once despite the
        // element having been removed in the same frame that would have
        // applied the ready state.
        expect(element.disposeCount, 1);
      },
    );
  });

  // Both tests below cover the same defect: `_performAsyncInit()` runs on a
  // discarded future, so a failure raised *before* `_subscription` is assigned
  // used to leave `_initCompleter` unsettled forever -- nothing else on that
  // path completes it. `_performAsyncDispose()` then parked on
  // `await _initCompleter.future`, never reached its `finally`, and never
  // unregistered the scope from its parent, which burned its whole
  // `waitForChildrenTimeout` on a child that was already gone.
  //
  // The assertions are about effects, never about timings: fake time in a
  // widget test advances instantly, so a wall-clock measurement proves nothing
  // about a stall. What proves it is that the parent's `waitForChildren` came
  // back on its own (the timeout is set far beyond the budget `_settle` can
  // advance, so an expiry cannot be what released it) and that the parent got
  // to `disposeAsync()` at all.
  group('AsyncScope failed initialization', () {
    testWidgets(
      'never starts the asynchronous phase when the synchronous init failed',
      (tester) async {
        final scopeKey = GlobalKey();

        Widget buildTree(String label) => Directionality(
              textDirection: TextDirection.ltr,
              child: _SyncInitAsyncScope(
                key: scopeKey,
                failSyncInit: true,
                label: label,
              ),
            );

        await tester.pumpWidget(buildTree('first'));

        final element = tester.element(find.byType(_SyncInitAsyncScope))
            as _SyncInitAsyncScopeElement;

        expect(element.syncInitAttempts, 1);
        expect(element.asyncInitStarts, 0);
        expect(
          tester.takeException(),
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'controlled sync init failure',
          ),
        );

        // The failure is terminal: a parent rebuild reports it again instead
        // of running the hook a second time.
        await tester.pumpWidget(buildTree('second'));
        await tester.pump();

        expect(tester.takeException(), isA<StateError>());
        expect(element.syncInitAttempts, 1);
        expect(element.asyncInitStarts, 0);

        await tester.pumpWidget(
          const Directionality(
            textDirection: TextDirection.ltr,
            child: SizedBox.shrink(),
          ),
        );
        await _settle(tester, until: () => false);

        expect(
          element.disposeCount,
          0,
          reason: 'nothing was initialized asynchronously, so nothing is '
              'disposed of asynchronously',
        );
      },
    );

    testWidgets(
      'starts the asynchronous phase once, after the successful sync init',
      (tester) async {
        final scopeKey = GlobalKey();

        Widget buildTree(String label) => Directionality(
              textDirection: TextDirection.ltr,
              child: _SyncInitAsyncScope(
                key: scopeKey,
                failSyncInit: false,
                label: label,
              ),
            );

        await tester.pumpWidget(buildTree('first'));
        await tester.pumpAndSettle();

        final element = tester.element(find.byType(_SyncInitAsyncScope))
            as _SyncInitAsyncScopeElement;

        expect(tester.takeException(), isNull);
        expect(element.syncInitAttempts, 1);
        expect(element.asyncInitStarts, 1);

        await tester.pumpWidget(buildTree('second'));
        await tester.pumpAndSettle();

        expect(element.syncInitAttempts, 1);
        expect(
          element.asyncInitStarts,
          1,
          reason: 'a rebuild does not start the async phase again',
        );

        await tester.pumpWidget(
          const Directionality(
            textDirection: TextDirection.ltr,
            child: SizedBox.shrink(),
          ),
        );
        await _settle(tester, until: () => element.disposeCount == 1);

        expect(element.disposeCount, 1);
      },
    );

    testWidgets(
      'a scope whose synchronous init failed is not left registered with its '
      'parent',
      (tester) async {
        final movedKey = GlobalKey();

        Widget buildTree({required bool left}) => Directionality(
              textDirection: TextDirection.ltr,
              child: _WaitingParentScope(
                child: SizedBox(
                  width: 100,
                  height: 100,
                  child: left
                      ? Align(
                          alignment: Alignment.topLeft,
                          child: SizedBox(
                            key: movedKey,
                            child: const _SyncInitAsyncScope(
                              failSyncInit: true,
                              label: 'child',
                            ),
                          ),
                        )
                      : Center(
                          child: SizedBox(
                            key: movedKey,
                            child: const _SyncInitAsyncScope(
                              failSyncInit: true,
                              label: 'child',
                            ),
                          ),
                        ),
                ),
              ),
            );

        await tester.pumpWidget(buildTree(left: true));
        expect(tester.takeException(), isA<StateError>());

        final parent = tester.element(find.byType(_WaitingParentScope))
            as _WaitingParentScopeElement;

        // The move re-activates the whole subtree, which is where a scope
        // registers itself with its parent again. A scope that never
        // initialized has nothing to register: nothing would ever take the
        // entry back, and the parent would wait out its whole timeout on it.
        await tester.pumpWidget(buildTree(left: false));
        tester.takeException();

        expect(parent.childrenCount, 0);

        await tester.pumpWidget(
          const Directionality(
            textDirection: TextDirection.ltr,
            child: SizedBox.shrink(),
          ),
        );
        await _settle(tester, until: () => parent.disposed);

        expect(
          parent.disposed,
          isTrue,
          reason: 'the parent got to its own disposal instead of waiting for a '
              'child that will never report back',
        );
        expect(
          parent.timedOut,
          isFalse,
          reason: 'and it was not an expiry that released it',
        );
      },
    );

    // Every other family hands the progress to the branches built while the
    // scope is not ready. This one computed it, kept it in the model, and then
    // left the builder to fish it back out of `AsyncScope.of`.
    testWidgets(
      'hands the progress to the initializing and error branches',
      (tester) async {
        final gate = Completer<void>();

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: AsyncScope(
              init: (context) async* {
                yield AsyncScopeProgress('connecting');
                await gate.future;

                throw StateError('init failed');
              },
              dispose: () {},
              initBuilder: (context, progress) =>
                  Text('initializing: $progress'),
              errorBuilder: (context, error, stackTrace, progress) =>
                  Text('error at $progress'),
              builder: (context) => const Text('ready'),
            ),
          ),
        );
        await tester.pump();

        expect(
          find.text('initializing: connecting'),
          findsOneWidget,
          reason: 'the progress the stream reported is what is shown',
        );

        gate.complete();
        await tester.pumpAndSettle();

        expect(
          find.text('error at connecting'),
          findsOneWidget,
          reason: 'the error branch is given the progress the scope reached',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'an error raised inside the init stream reaches the model with the last '
      'progress, and the error branch is built',
      (tester) async {
        // The other failure tests raise *before* the stream exists, so the
        // error goes through the `try` of `_performAsyncInit` and reaches
        // nobody but the zone. An error raised by the stream itself takes the
        // other path — the subscription's `onError`, which is what puts
        // `AsyncScopeError` into the model and keeps the last progress with
        // it — and nothing covered that path.
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: AsyncScope(
              init: (context) async* {
                yield AsyncScopeProgress('step');
                throw StateError('init failed');
              },
              dispose: () {},
              initBuilder: (context, progress) => const Text('initializing'),
              errorBuilder: (context, error, stackTrace, progress) =>
                  Text('error: $error'),
              builder: (context) => const Text('ready'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('error: Bad state: init failed'), findsOneWidget);

        final element = tester.element(find.byType(AsyncScope))
            as AsyncScopeContext<AsyncScope>;

        expect(element.hasError, isTrue);
        expect(element.error, isA<StateError>());
        expect(
          element.state,
          isA<AsyncScopeError>().having(
            (state) => state.progress,
            'progress',
            'step',
          ),
          reason: 'the progress the scope had reached is kept with the error',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'a scope whose initAsync throws synchronously still finishes disposing '
      'of itself, so its parent does not wait for it in vain',
      (tester) async {
        late _WaitingParentScopeElement parent;
        late _FailingInitScopeElement child;
        late int childrenBefore;

        // The failure reaches nobody but the zone: `_performAsyncInit()`'s
        // future is discarded, so it never gets to the framework's error
        // handling and `tester.takeException()` cannot see it. `flutter_test`'s
        // own `handleUncaughtError` would end the test on the spot, so
        // everything runs inside a guarded child zone that catches it first.
        //
        // Nothing inside that zone may throw: an assertion that fails there is
        // swallowed by the zone's error handler and the test hangs instead of
        // failing, so the body only ever collects, and every `expect` is made
        // once the zone is gone.
        final errors = <Object>[];
        await runZonedGuarded(
          () async {
            await tester.pumpWidget(
              const Directionality(
                textDirection: TextDirection.ltr,
                child: _WaitingParentScope(child: _FailingInitScope()),
              ),
            );
            await tester.pumpAndSettle();

            parent = tester.element(find.byType(_WaitingParentScope))
                as _WaitingParentScopeElement;
            child = tester.element(find.byType(_FailingInitScope))
                as _FailingInitScopeElement;
            childrenBefore = parent.childrenCount;

            await tester.pumpWidget(
              const Directionality(
                textDirection: TextDirection.ltr,
                child: SizedBox.shrink(),
              ),
            );
            await _settle(tester, until: () => parent.disposed);
          },
          (error, stackTrace) => errors.add(error),
        );

        expect(
          childrenBefore,
          1,
          reason: 'the scope registered with its parent before failing',
        );
        expect(
          parent.timedOut,
          isFalse,
          reason: 'the parent never had to give up on the failed scope',
        );
        expect(
          parent.childrenCount,
          0,
          reason: 'the failed scope finished disposing of itself and left',
        );
        expect(
          parent.disposed,
          isTrue,
          reason: 'the parent got past the wait and disposed of itself',
        );
        expect(
          child.disposeCount,
          0,
          reason: 'an initialization that never happened is not disposed of',
        );
        expect(
          errors.single,
          isA<StateError>(),
          reason: 'the failure is still reported, not swallowed',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'a scope with a scopeKey and no coordinator still finishes disposing '
      'of itself, so its parent does not wait for it in vain',
      (tester) async {
        late _WaitingParentScopeElement parent;
        late _FailingInitScopeElement child;
        late int childrenBefore;

        // Same guarded zone as above, and the same rule about it: the
        // `FlutterError` raised by the coordinator lookup surfaces as an
        // uncaught error of the zone the mount ran in, and nothing inside the
        // zone may throw.
        final errors = <Object>[];
        await runZonedGuarded(
          () async {
            await tester.pumpWidget(
              const Directionality(
                textDirection: TextDirection.ltr,
                // No `AsyncScopeCoordinator` anywhere above: the lookup in
                // `AsyncScopeCoordinator._elementOf` throws, and it throws
                // before
                // `_subscription` exists.
                child: _WaitingParentScope(
                  child: _FailingInitScope(testKey: 'shared'),
                ),
              ),
            );
            await tester.pumpAndSettle();

            parent = tester.element(find.byType(_WaitingParentScope))
                as _WaitingParentScopeElement;
            child = tester.element(find.byType(_FailingInitScope))
                as _FailingInitScopeElement;
            childrenBefore = parent.childrenCount;

            await tester.pumpWidget(
              const Directionality(
                textDirection: TextDirection.ltr,
                child: SizedBox.shrink(),
              ),
            );
            await _settle(tester, until: () => parent.disposed);
          },
          (error, stackTrace) => errors.add(error),
        );

        expect(
          childrenBefore,
          1,
          reason: 'the scope registered with its parent before failing',
        );
        expect(
          parent.timedOut,
          isFalse,
          reason: 'the parent never had to give up on the failed scope',
        );
        expect(
          parent.childrenCount,
          0,
          reason: 'the failed scope finished disposing of itself and left',
        );
        expect(
          parent.disposed,
          isTrue,
          reason: 'the parent got past the wait and disposed of itself',
        );
        expect(
          child.disposeCount,
          0,
          reason: 'an initialization that never happened is not disposed of',
        );
        expect(
          errors,
          hasLength(1),
          reason: 'the entry that never made it into a queue is dropped, so '
              'the disposal does not `exit()` it and raise a second error',
        );
        expect(errors.single, isA<FlutterError>());
        expect(
          errors.single.toString(),
          contains('No `AsyncScopeCoordinator`'),
          reason: 'the original failure is still reported, not swallowed',
        );
        expect(tester.takeException(), isNull);
      },
    );

    // The two tests above ask where the failure goes and what the teardown
    // does with it. This one asks what the user sees, which is the half
    // nobody was asking: a failure raised while the stream is being built
    // never reached the model, so the scope stayed in `AsyncScopeWaiting` and
    // went on showing its loading branch for good. Loud in the console,
    // silent on screen.
    testWidgets(
      'a scope whose initialization fails synchronously shows its error branch',
      (tester) async {
        final errors = <Object>[];

        await runZonedGuarded(
          () async {
            await tester.pumpWidget(
              Directionality(
                textDirection: TextDirection.ltr,
                // No `AsyncScopeCoordinator` above a scope that asks for a
                // `scopeKey`: the lookup throws, and it throws before the
                // subscription exists. This is the likeliest way an
                // initialization fails synchronously, and it is a mistake in
                // the tree rather than in the work.
                child: AsyncScope(
                  scopeKey: 'k',
                  init: (context) => Stream.value(AsyncScopeReady()),
                  dispose: () {},
                  initBuilder: (context, progress) => const Text('init'),
                  errorBuilder: (context, error, stackTrace, progress) =>
                      const Text('error'),
                  builder: (context) => const Text('ready'),
                ),
              ),
            );
            await tester.pumpAndSettle();
          },
          (error, stackTrace) => errors.add(error),
        );

        expect(
          find.text('error'),
          findsOneWidget,
          reason: 'the state table says a failure before the ready state '
              'builds `buildOnError`, and this is such a failure',
        );
        expect(
          find.text('init'),
          findsNothing,
          reason: 'the loading branch is not what a scope that will never '
              'load should be left showing',
        );
        expect(
          errors.single,
          isA<FlutterError>(),
          reason: 'and the failure is still reported, as it was',
        );
        expect(
          errors.single.toString(),
          contains('No `AsyncScopeCoordinator`'),
        );

        await tester.pumpWidget(
          const Directionality(
            textDirection: TextDirection.ltr,
            child: SizedBox.shrink(),
          ),
        );
        await _settle(tester, until: () => false);
      },
    );
  });

  // Both tests below cover the same defect: an event that arrives *after*
  // `initAsync()` has already reached `AsyncScopeReady` used to complete
  // `_initCompleter` a second time. The `Bad state: Future already completed`
  // that raised replaced the failure being reported, so the real one never
  // reached anybody.
  //
  // The assertions are about effects, never about timings: what proves the
  // defect is which error the app receives, which state the scope is left in,
  // and whether `disposeAsync()` still runs.
  group('the model of a scope', () {
    testWidgets('is one object rather than a wrapper made on every read',
        (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: _ReadyRaceScope(),
        ),
      );
      await tester.pumpAndSettle();

      final element = tester.element(find.byType(_ReadyRaceScope))
          as _ReadyRaceScopeElement;

      expect(
        element.model,
        same(element.model),
        reason: '`state`, `isInitialized`, `hasError`, `error`, `stackTrace`, '
            '`buildChild` and every run of every selector go through this',
      );
    });
  });

  group('a child scope moved with a GlobalKey', () {
    Widget treeWith({required GlobalKey childKey, required bool underSecond}) =>
        Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: [
              _WaitingParentScope(
                child: underSecond
                    ? const SizedBox.shrink()
                    : _MovableScope(key: childKey),
              ),
              _WaitingParentScope(
                child: underSecond
                    ? _MovableScope(key: childKey)
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        );

    (_WaitingParentScopeElement, _WaitingParentScopeElement) parents(
      WidgetTester tester,
    ) =>
        (
          tester.element(find.byType(_WaitingParentScope).at(0))
              as _WaitingParentScopeElement,
          tester.element(find.byType(_WaitingParentScope).at(1))
              as _WaitingParentScopeElement,
        );

    testWidgets(
      'hands itself over to the new parent and lets the old one go',
      (tester) async {
        final childKey = GlobalKey();

        await tester.pumpWidget(
          treeWith(childKey: childKey, underSecond: false),
        );
        await tester.pumpAndSettle();

        final (first, second) = parents(tester);

        expect(first.childrenCount, 1, reason: 'the child started here');
        expect(second.childrenCount, 0);

        // The move goes through `deactivate` + `activate`, and it is
        // `activate()` that has to unregister the scope from the parent it
        // left and register it with the one it arrived at. A failed handoff
        // is invisible from the child's side: it shows up as the old parent
        // waiting out its whole `waitForChildrenTimeout` on a scope that is
        // alive and well elsewhere.
        await tester.pumpWidget(
          treeWith(childKey: childKey, underSecond: true),
        );
        await tester.pumpAndSettle();

        expect(
          first.childrenCount,
          0,
          reason: 'the scope unregistered from the parent it left',
        );
        expect(
          second.childrenCount,
          1,
          reason: 'the scope registered with the parent it arrived at',
        );
        expect(
          find.byKey(childKey),
          findsOneWidget,
          reason: 'the scope itself survived the move',
        );
      },
    );

    testWidgets(
      'is awaited by the new parent, not by the old one',
      (tester) async {
        final childKey = GlobalKey();

        await tester.pumpWidget(
          treeWith(childKey: childKey, underSecond: false),
        );
        await tester.pumpAndSettle();
        await tester.pumpWidget(
          treeWith(childKey: childKey, underSecond: true),
        );
        await tester.pumpAndSettle();

        final (first, second) = parents(tester);
        final child =
            tester.element(find.byType(_MovableScope)) as _MovableScopeElement;

        // The child holds its own disposal open, so the parent that awaits it
        // cannot finish while it is held.
        final held = Completer<void>();
        child.disposalGate = held.future;

        await tester.pumpWidget(
          const Directionality(
            textDirection: TextDirection.ltr,
            child: SizedBox.shrink(),
          ),
        );
        await _settle(tester, until: () => first.disposed);

        expect(
          first.disposed,
          isTrue,
          reason: 'the parent it left had nothing left to wait for',
        );
        expect(
          first.timedOut,
          isFalse,
          reason: 'and it did not have to give up on anything',
        );
        expect(
          second.disposed,
          isFalse,
          reason: 'the parent it moved to is held by the child it now awaits',
        );

        held.complete();
        await _settle(tester, until: () => second.disposed);

        expect(
          second.disposed,
          isTrue,
          reason: 'and it finishes once the child is done',
        );
        expect(second.timedOut, isFalse);
      },
    );
  });

  group('AsyncScope initialization that raises while it is cancelled', () {
    testWidgets(
      'still finishes disposing of itself, so its parent does not wait for it '
      'in vain',
      (tester) async {
        late _WaitingParentScopeElement parent;
        late int childrenBefore;

        // Same guarded zone as the other failure tests, and the same rule
        // about it: nothing inside may throw, every expectation is made once
        // the zone is gone.
        final errors = <Object>[];
        await runZonedGuarded(
          () async {
            await tester.pumpWidget(
              const Directionality(
                textDirection: TextDirection.ltr,
                child: _WaitingParentScope(child: _RaisingOnCancelScope()),
              ),
            );
            await tester.pump();

            parent = tester.element(find.byType(_WaitingParentScope))
                as _WaitingParentScopeElement;
            childrenBefore = parent.childrenCount;

            await tester.pumpWidget(
              const Directionality(
                textDirection: TextDirection.ltr,
                child: SizedBox.shrink(),
              ),
            );
            await _settle(tester, until: () => parent.disposed);
          },
          (error, stackTrace) => errors.add(error),
        );

        expect(
          childrenBefore,
          1,
          reason: 'the scope registered with its parent before it was removed',
        );
        expect(
          parent.childrenCount,
          0,
          reason: 'the scope left its parent despite the failed cancellation',
        );
        expect(
          parent.disposed,
          isTrue,
          reason: 'the parent got past the wait and disposed of itself',
        );
        expect(
          errors,
          isEmpty,
          reason: 'the failure no longer escapes into the zone',
        );
        expect(
          tester.takeException(),
          isA<StateError>(),
          reason: 'the failure is reported, not swallowed',
        );
      },
    );
  });

  group('AsyncScope initialization that fails after the ready state', () {
    testWidgets(
      'reports the failure raised after the ready state instead of a '
      'double-completed init completer, and leaves the scope ready',
      (tester) async {
        late _ErrorAfterReadyScopeElement scope;

        // `_performAsyncInit()`'s subscription callbacks run in the zone the
        // mount ran in, so a failure raised there surfaces as an uncaught
        // error of that zone and `flutter_test`'s own `handleUncaughtError`
        // would end the test on the spot. A guarded child zone catches it
        // first. Nothing inside that zone may throw -- an assertion that
        // fails there is swallowed by the zone's error handler and the test
        // hangs instead of failing -- so every `expect` is made once it is
        // gone.
        final zoneErrors = <Object>[];
        await runZonedGuarded(
          () async {
            await tester.pumpWidget(
              const Directionality(
                textDirection: TextDirection.ltr,
                child: _ErrorAfterReadyScope(),
              ),
            );
            await tester.pumpAndSettle();

            scope = tester.element(find.byType(_ErrorAfterReadyScope))
                as _ErrorAfterReadyScopeElement;
          },
          (error, stackTrace) => zoneErrors.add(error),
        );

        expect(
          zoneErrors,
          isEmpty,
          reason: 'completing the init completer twice must not raise on top '
              'of the failure being reported',
        );

        final exception = tester.takeException();
        expect(
          exception,
          isA<StateError>(),
          reason: 'the failure the stream raised is what reaches the app',
        );
        expect((exception! as StateError).message, 'failed after ready');
        expect(
          scope.state,
          isA<AsyncScopeReady>(),
          reason: 'a scope that did initialize must not be flipped into the '
              'error state -- `buildOnError` would replace the widgets that '
              'are already on screen',
        );

        await tester.pumpWidget(
          const Directionality(
            textDirection: TextDirection.ltr,
            child: SizedBox.shrink(),
          ),
        );
        await _settle(tester, until: () => scope.disposeCount > 0);

        expect(
          scope.disposeCount,
          1,
          reason: 'the initialization succeeded, so what it acquired is still '
              'released exactly once',
        );
      },
    );

    testWidgets(
      'reports a second ready state as the already-initialized diagnostic',
      (tester) async {
        late _TwiceReadyScopeElement scope;

        final zoneErrors = <Object>[];
        await runZonedGuarded(
          () async {
            await tester.pumpWidget(
              const Directionality(
                textDirection: TextDirection.ltr,
                child: _TwiceReadyScope(),
              ),
            );
            await tester.pumpAndSettle();

            scope = tester.element(find.byType(_TwiceReadyScope))
                as _TwiceReadyScopeElement;
          },
          (error, stackTrace) => zoneErrors.add(error),
        );

        expect(
          zoneErrors,
          isEmpty,
          reason: "the package's own diagnostic must not turn into a `Bad "
              'state: Future already completed` crash',
        );

        final exception = tester.takeException();
        expect(exception, isA<StateError>());
        expect(
          (exception! as StateError).message,
          '$_TwiceReadyScope already initialized',
          reason: 'the second ready state is caught even though it arrives '
              'before the post-frame callback that applies the first one',
        );
        expect(scope.state, isA<AsyncScopeReady>());

        await tester.pumpWidget(
          const Directionality(
            textDirection: TextDirection.ltr,
            child: SizedBox.shrink(),
          ),
        );
        await _settle(tester, until: () => scope.disposeCount > 0);

        expect(
          scope.disposeCount,
          1,
          reason: 'the ready branch ran once, so the disposal runs once',
        );
      },
    );
  });
}

/// Pumps frames interleaved with slices of *real* time, until [until] holds or
/// the budget runs out.
///
/// The `StreamSubscription.cancel()` chain of
/// `AsyncScopeElementBase._performAsyncDispose` only makes progress outside the
/// test's fake-async zone, so `pumpAndSettle()` alone never reaches
/// `disposeAsync()`. The same workaround is documented in
/// `async_scope_coordinator_test.dart` and `lite_scope_test.dart`.
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

/// A scope that can be moved between parents with a [GlobalKey], and can hold
/// its own disposal open so that the parent awaiting it can be observed
/// waiting.
final class _MovableScope
    extends AsyncScopeCore<_MovableScope, _MovableScopeElement> {
  const _MovableScope({super.key});

  @override
  _MovableScopeElement createScopeElement() => _MovableScopeElement(this);
}

final class _MovableScopeElement
    extends AsyncScopeElementBase<_MovableScope, _MovableScopeElement> {
  /// Awaited by [disposeAsync], so a test can keep the disposal — and with it
  /// the parent that waits for this scope — open for as long as it likes.
  Future<void>? disposalGate;

  _MovableScopeElement(super.widget);

  @override
  Future<void> disposeAsync() async {
    if (disposalGate case final gate?) {
      await gate;
    }
  }

  @override
  Widget buildOnState(AsyncScopeState state) => const SizedBox.shrink();
}

/// A scope whose initialization raises *while it is being cancelled*: the
/// `finally` of its generator throws, and an `async*` generator delivers that
/// failure through the `cancel()` future — the one `_performAsyncDispose`
/// awaits before it has unregistered anything.
final class _RaisingOnCancelScope extends AsyncScopeCore<_RaisingOnCancelScope,
    _RaisingOnCancelScopeElement> {
  const _RaisingOnCancelScope();

  @override
  _RaisingOnCancelScopeElement createScopeElement() =>
      _RaisingOnCancelScopeElement(this);
}

final class _RaisingOnCancelScopeElement extends AsyncScopeElementBase<
    _RaisingOnCancelScope, _RaisingOnCancelScopeElement> {
  _RaisingOnCancelScopeElement(super.widget);

  @override
  Stream<AsyncScopeInitState> initAsync() async* {
    try {
      yield AsyncScopeProgress('step');
      // Short enough for the disposal to catch the generator here, and
      // bounded, so the cancellation can finish: a generator parked on a
      // future that never completes can never be cancelled at all, which is
      // a different problem from the one this scope is about.
      await Future<void>.delayed(const Duration(milliseconds: 10));
      yield AsyncScopeReady();
    } finally {
      // The `finally` is where a cancelled generator resumes, so throwing
      // here is the whole point of this fixture: it is how a failure reaches
      // the `cancel()` future the disposal awaits.
      // ignore: throw_in_finally
      throw StateError('raised while being cancelled');
    }
  }

  @override
  Widget buildOnState(AsyncScopeState state) => const SizedBox.shrink();
}

/// Minimal [AsyncScopeCore] used to test the `_registerWithParent()`
/// post-frame callback (async_scope_core.dart, in `_performAsyncInit`).
final class _RegisterRaceScope
    extends AsyncScopeCore<_RegisterRaceScope, _RegisterRaceScopeElement> {
  const _RegisterRaceScope();

  @override
  _RegisterRaceScopeElement createScopeElement() =>
      _RegisterRaceScopeElement(this);
}

final class _RegisterRaceScopeElement extends AsyncScopeElementBase<
    _RegisterRaceScope, _RegisterRaceScopeElement> {
  _RegisterRaceScopeElement(super.widget);

  @override
  Widget buildOnState(AsyncScopeState state) => const SizedBox.shrink();
}

/// Minimal [AsyncScopeCore] used to test the `_model.update(state)`
/// post-frame callback scheduled once `initAsync()` completes
/// (async_scope_core.dart, in `_performAsyncInit`'s `AsyncScopeReady`
/// case), and the corresponding `disposeAsync()` call in
/// `_performAsyncDispose`. Uses the default `initAsync()`
/// (`Stream.value(AsyncScopeReady())`) and default `pauseAfterInitialization`
/// (`null`), so it takes the immediate `scheduleFrame()` +
/// `addPostFrameCallback` branch rather than the delayed one.
final class _ReadyRaceScope
    extends AsyncScopeCore<_ReadyRaceScope, _ReadyRaceScopeElement> {
  const _ReadyRaceScope();

  @override
  _ReadyRaceScopeElement createScopeElement() => _ReadyRaceScopeElement(this);
}

final class _ReadyRaceScopeElement
    extends AsyncScopeElementBase<_ReadyRaceScope, _ReadyRaceScopeElement> {
  int disposeCount = 0;

  _ReadyRaceScopeElement(super.widget);

  @override
  FutureOr<void> disposeAsync() {
    disposeCount++;
  }

  @override
  Widget buildOnState(AsyncScopeState state) => const SizedBox.shrink();
}

/// A scope that waits for the scopes below it, and says so when the wait had
/// to be given up on.
///
/// [_WaitingParentScopeElement.waitForChildrenTimeout] is set far beyond
/// anything the tests can advance, so an expired wait is something the
/// assertions can rule out rather than something they race against.
final class _WaitingParentScope
    extends AsyncScopeCore<_WaitingParentScope, _WaitingParentScopeElement> {
  const _WaitingParentScope({required super.child});

  @override
  _WaitingParentScopeElement createScopeElement() =>
      _WaitingParentScopeElement(this);
}

final class _WaitingParentScopeElement extends AsyncScopeElementBase<
    _WaitingParentScope, _WaitingParentScopeElement> {
  bool timedOut = false;
  bool disposed = false;

  _WaitingParentScopeElement(super.widget);

  @override
  Duration? get waitForChildrenTimeout => const Duration(days: 1);

  @override
  void onWaitForChildrenTimeout() => timedOut = true;

  @override
  FutureOr<void> disposeAsync() {
    disposed = true;
  }

  @override
  Widget buildOnState(AsyncScopeState state) => widget.child;
}

/// A scope whose synchronous setup can fail before its normal base setup.
///
/// The [label] is what makes a rebuild carry a different widget, so a test can
/// tell a repeated build apart from a repeated hook.
final class _SyncInitAsyncScope
    extends AsyncScopeCore<_SyncInitAsyncScope, _SyncInitAsyncScopeElement> {
  final bool failSyncInit;
  final String label;

  const _SyncInitAsyncScope({
    super.key,
    required this.failSyncInit,
    required this.label,
  });

  @override
  _SyncInitAsyncScopeElement createScopeElement() =>
      _SyncInitAsyncScopeElement(this);
}

final class _SyncInitAsyncScopeElement extends AsyncScopeElementBase<
    _SyncInitAsyncScope, _SyncInitAsyncScopeElement> {
  int syncInitAttempts = 0;
  int asyncInitStarts = 0;
  int disposeCount = 0;

  _SyncInitAsyncScopeElement(super.widget);

  @override
  void init() {
    syncInitAttempts++;
    if (widget.failSyncInit) {
      throw StateError('controlled sync init failure');
    }
    super.init();
  }

  @override
  Stream<AsyncScopeInitState> initAsync() {
    asyncInitStarts++;
    return Stream.value(AsyncScopeReady());
  }

  @override
  FutureOr<void> disposeAsync() {
    disposeCount++;
  }

  @override
  Widget buildOnState(AsyncScopeState state) => const SizedBox.shrink();
}

/// A scope whose initialization fails before `_subscription` exists.
///
/// With a [testKey] and no [AsyncScopeCoordinator] above it, the coordinator
/// lookup fails first and `initAsync()` is never even called; without one,
/// `initAsync()` itself throws synchronously.
final class _FailingInitScope
    extends AsyncScopeCore<_FailingInitScope, _FailingInitScopeElement> {
  final Object? testKey;

  const _FailingInitScope({this.testKey});

  @override
  _FailingInitScopeElement createScopeElement() =>
      _FailingInitScopeElement(this);
}

final class _FailingInitScopeElement
    extends AsyncScopeElementBase<_FailingInitScope, _FailingInitScopeElement> {
  int disposeCount = 0;

  _FailingInitScopeElement(super.widget);

  @override
  Object? get scopeKey => widget.testKey;

  // Deliberately not `async*`: the point is a plain user error raised while
  // the stream is being built, before there is anything to subscribe to.
  @override
  Stream<AsyncScopeInitState> initAsync() =>
      throw StateError('initAsync failed');

  @override
  FutureOr<void> disposeAsync() {
    disposeCount++;
  }

  @override
  Widget buildOnState(AsyncScopeState state) => const SizedBox.shrink();
}

/// A scope whose `initAsync()` raises *after* it has reached
/// [AsyncScopeReady] -- the shape of a stream that keeps working once the
/// scope is usable and then fails.
final class _ErrorAfterReadyScope extends AsyncScopeCore<_ErrorAfterReadyScope,
    _ErrorAfterReadyScopeElement> {
  const _ErrorAfterReadyScope();

  @override
  _ErrorAfterReadyScopeElement createScopeElement() =>
      _ErrorAfterReadyScopeElement(this);
}

final class _ErrorAfterReadyScopeElement extends AsyncScopeElementBase<
    _ErrorAfterReadyScope, _ErrorAfterReadyScopeElement> {
  int disposeCount = 0;

  _ErrorAfterReadyScopeElement(super.widget);

  @override
  Stream<AsyncScopeInitState> initAsync() async* {
    yield AsyncScopeReady();
    throw StateError('failed after ready');
  }

  @override
  FutureOr<void> disposeAsync() {
    disposeCount++;
  }

  @override
  Widget buildOnState(AsyncScopeState state) => const SizedBox.shrink();
}

/// A scope whose `initAsync()` emits [AsyncScopeReady] twice, both events
/// arriving before the post-frame callback that applies the first one to the
/// model -- the case the `already initialized` diagnostic exists for.
final class _TwiceReadyScope
    extends AsyncScopeCore<_TwiceReadyScope, _TwiceReadyScopeElement> {
  const _TwiceReadyScope();

  @override
  _TwiceReadyScopeElement createScopeElement() => _TwiceReadyScopeElement(this);
}

final class _TwiceReadyScopeElement
    extends AsyncScopeElementBase<_TwiceReadyScope, _TwiceReadyScopeElement> {
  int disposeCount = 0;

  _TwiceReadyScopeElement(super.widget);

  @override
  Stream<AsyncScopeInitState> initAsync() async* {
    yield AsyncScopeReady();
    yield AsyncScopeReady();
  }

  @override
  FutureOr<void> disposeAsync() {
    disposeCount++;
  }

  @override
  Widget buildOnState(AsyncScopeState state) => const SizedBox.shrink();
}
