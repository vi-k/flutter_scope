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

    // A regression test for the second unguarded callback --
    // `addPostFrameCallback((_) { _model.update(state); })`, scheduled in
    // the `AsyncScopeReady` branch of `_performAsyncInit` once
    // `initAsync()` completes -- was deliberately NOT added here. It could
    // not be made to fail deterministically, despite trying the same
    // "drive `BuildOwner` directly" technique used above, plus
    // `TestWidgetsFlutterBinding.idle()` (which flushes microtasks/timers
    // without drawing a frame) to let the element's disposal progress as
    // far as possible before the pending callback is drained:
    //
    // - `SchedulerBinding.addPostFrameCallback` callbacks always run
    //   during the very next `handleDrawFrame()` after being scheduled
    //   (this code path also calls `scheduleFrame()`), and
    //   `handleDrawFrame()` performs build, `finalizeTree()` (which
    //   unmounts removed elements) and post-frame-callback draining
    //   synchronously, with no yield point in between.
    // - `AsyncScopeElementBase.dispose()` -- invoked from that same
    //   synchronous `finalizeTree()` when the element is removed --
    //   removes the `_model` listener immediately
    //   (`ScopeNotifierElementBase.dispose()`), but only *starts* the
    //   async `_performAsyncDispose()` chain (it suspends at its first
    //   `await`, on `subscription.cancel()`).
    // - Experimentally, even after repeatedly calling `binding.idle()`
    //   between removal and the draining frame, `_model.dispose()` (the
    //   call that would make a subsequent `notifyListeners()` throw) was
    //   only reached *after* `tester.pump()` drained the stale callback,
    //   never before it -- so whenever this callback is removed and
    //   drained in the same frame, `notifyListeners()` from
    //   `_model.update(state)` reliably finds the listener already
    //   detached and `_model` not yet disposed, i.e. becomes a silent
    //   no-op rather than a crash.
    //
    // So this exact "removed before its post-frame callback runs" race
    // could not be observed to fail before the fix. The guard is still
    // added defensively, mirroring the existing `mounted` check in the
    // adjacent `pauseAfterInitialization` branch a few lines above it,
    // since relying on `_model`/`this` being safely usable from a
    // post-frame callback registered before disposal completes is not an
    // invariant worth depending on.
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
