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
        // phase -- including the one `mount()` schedules synchronously via
        // `SchedulerBinding.addPostFrameCallback` in `_performAsyncInit`.
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
        // during `mount()`. `pumpWidget`/`pump` would drain it within the
        // very same call that schedules it, so we drive things by hand.
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
