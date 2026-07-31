# Task 8 report: `LiteScope.close()` hang + `ScreenshotReplacer` lifecycle

Branch: `worktree-audit-fixes` (worktree `.claude/worktrees/audit-fixes`).

## Files touched

- `lib/src/scope/g_lite_scope/lite_scope_core.dart` (Bug A)
- `lib/src/utils/screenshot_replacer.dart` (Bug B)
- `test/lite_scope_test.dart` (new, 6 tests)

## The exact "will `buildOnReady()` render" condition

Derived from the state machine, not guessed:

1. `ScopeWidgetElementBase.build() => buildChild()` (`b_scope_widget/scope_widget_core.dart:247`).
2. `AsyncScopeElementBase.buildChild() => buildOnState(model.state)`
   (`e_async_scope/async_scope_core.dart:370`).
3. `LiteScopeElementBase.buildOnState()` is an exhaustive switch over the sealed
   `AsyncScopeState`, and **only** `AsyncScopeReady()` maps to `buildOnReady()`
   (`g_lite_scope/lite_scope_core.dart:186-192`). `AsyncScopeWaiting` →
   `buildOnWaiting()`/`buildOnInitializing(null)`, `AsyncScopeProgress` →
   `buildOnInitializing(progress)`, `AsyncScopeError` → `buildOnError(...)`.
4. `buildOnReady()` is the only place that mounts a `ScreenshotReplacer`, and the
   replacer's `onCompleted` is the only thing that releases
   `_screenshotCompleter`.

So the barrier can only ever be released if **both** hold:

- `state is AsyncScopeReady` (`state` ⇒ `model.state`, a plain field read — safe
  even after `_model.dispose()`), **and**
- the element is still in the tree, i.e. the `markNeedsBuild()` that
  `_performAsyncDispose` issues actually results in another `buildChild()` call.

The second half is not a hypothetical: `markNeedsBuild()` only queues the
element; if the parent removes the subtree in the same frame, `buildScope`
skips the (now inactive) element and the `ScreenshotReplacer` is never mounted
at all. That case is covered by the third test and by the `dispose()` guard
below (before the fix it hung exactly like the non-ready states).

## Fix A — `lite_scope_core.dart`

- `close()` now installs the barrier only when it can be released:
  `if (mounted && state is AsyncScopeReady) { _screenshotCompleter = Completer(); }`.
  In every other state `close()` goes straight to `_performAsyncDispose()`,
  which still calls `markNeedsBuild()` (so `buildOnClosing()`-less non-ready
  builders keep rebuilding as before) but no longer awaits anything.
- Extracted `_completeScreenshot()` (idempotent) out of the inline closure in
  `buildOnReady()`, and call it from a new `dispose()` override, so an element
  that leaves the tree mid-close releases the barrier instead of deadlocking
  the in-flight `close()` (and, with it, `disposeAsync()` of the scope state).
  `dispose()` runs from `ScopeWidgetElementBase.unmount()` **before**
  `AsyncScopeElementBase.dispose()` re-enters `_performAsyncDispose()`, so the
  barrier is already released when that chain resumes.
- `markNeedsBuild()` from the unmount path stays a no-op (Flutter returns early
  for non-`active` elements), unchanged behaviour.

## Fix B — `screenshot_replacer.dart`

- `onCompleted` is reported through `_reportCompleted()`, guarded by
  `_isCompletionReported`, so it fires **exactly once** for the lifetime of the
  state (previously: once from `finally` + once from `dispose()` = twice, and
  also once per retry attempt).
- The retry paths (`boundary == null`, `boundary.debugNeedsPaint`) now `return`
  **without** reporting completion, so the barrier is not released before the
  screenshot exists. `boundary == null` used to be a terminal path; since it is
  now a retry path, the reschedule also calls `scheduleFrame()` (same idiom as
  `async_scope_core.dart`) — an `addPostFrameCallback` alone only runs if
  something else happens to schedule a frame.
- Terminal paths still report: the success path (after `setState`) and any
  throw from the capture (`on Object { _reportCompleted(); rethrow; }`).
  **The whole boundary lookup + `toImage()` is inside that `try` on purpose:**
  `RenderObject.debugNeedsPaint` reads a `late` local that is only assigned
  inside an `assert`, so it throws `LateInitializationError` when asserts are
  disabled. Keeping it inside the `try` preserves today's release-mode
  behaviour (barrier released, no screenshot) instead of turning it into a hang.
- Post-dispose safety: `_capture()` returns early when `!mounted`; if the state
  is disposed of while `toImage()` is in flight, the resulting image is disposed
  of on the spot (nobody will show it) and completion is not reported again
  (`dispose()` already did).
- Leak fix: `dispose()` now calls `_image?.dispose()`. Verified that this is not
  a double dispose: `RawImage.createRenderObject`/`updateRenderObject` pass
  `image?.clone()` to `RenderImage`, so `RenderImage.dispose()` releases *its
  own* handle and the state owns the original (`RawImage`'s own doc comment says
  the creator must dispose of it).

## Evidence

Baseline before the task: `flutter test` 42 passing, `flutter analyze` exactly
3 known issues.

### Failing (final test file, `lib/` reverted to HEAD via `git checkout --`, no stash)

```
00:00 +1 -5: Some tests failed.

Failing tests:
  test/lite_scope_test.dart: LiteScope.close() completes while the scope is in the waiting state
  test/lite_scope_test.dart: LiteScope.close() completes while the scope is in the initializing state
  test/lite_scope_test.dart: LiteScope.close() completes while the scope is in the error state
  test/lite_scope_test.dart: LiteScope.close() completes when the element leaves the tree before the closing frame is built
  test/lite_scope_test.dart: ScreenshotReplacer reports completion exactly once and releases the captured image
```

with, respectively:

```
Expected: true
  Actual: <false>
close() must not wait for a screenshot that buildOnReady() never takes in the waiting state
...initializing state
...error state
a scope removed from the tree while closing must not keep close() waiting for a screenshot that can no longer be taken

Expected: <1>
  Actual: <2>
disposal must not report completion again
```

The 6th test (`completes in the ready state once the screenshot has been
captured`) passes before the fix too — it is the regression guard proving the
barrier is still installed and still released on the happy path.

### Passing (after the fix)

```
flutter test test/lite_scope_test.dart   ->  00:00 +6: All tests passed!   (x3 runs, no flakiness)
flutter test                             ->  00:00 +48: All tests passed!  (42 baseline + 6 new)
flutter analyze                          ->  3 issues found.               (the same 3 pre-existing)
```

## Test-authoring notes (things that cost time)

- **`close()` is never awaited directly** in the tests; it is fired with
  `unawaited(... .whenComplete(() => isClosed = true))` and asserted through the
  flag, so the pre-fix behaviour is a *failing* test, not a hung test run.
- The test scope is a `LiteScopeCore` with a test-visible element type
  (`_CloseScopeElement extends LiteScopeElementBase`), because
  `LiteScope`'s element is library-private and `close()` must be reachable in
  states where no `LiteScopeCoreState` exists yet.
- `RenderRepaintBoundary.toImage()` **does** work in widget tests, but only
  inside `tester.runAsync` (`OffsetLayer.toImage` awaits `ui.Scene.toImage`,
  which the engine completes on the real event loop). The same applies to the
  `await subscription.cancel()` chain in
  `AsyncScopeElementBase._performAsyncDispose` — the identical `runAsync`
  workaround is already documented in `async_scope_test.dart`. Hence the
  `_settle(tester, until: ...)` helper (real-time slice + `pump()`, budgeted).
- Init-stream helpers must be *cancellable*: an `async*` generator suspended on
  a never-completing future makes `StreamSubscription.cancel()` itself hang
  (unrelated to this bug, but it masked it). Used `Stream.multi` instead.
- `Stream<T>.error(...)` as the init stream never reached the model in a widget
  test (state stayed `AsyncScopeWaiting`, no exception surfaced) — worked fine
  in a plain `test()`. Sidestepped by using an `async*` that throws, which does
  reach `AsyncScopeError`. Not investigated further; flagged below.

## Concerns / follow-ups (candidates for Task 10 / TODO.md)

1. **`ScreenshotReplacer` cannot capture anything in release/profile builds.**
   `boundary.debugNeedsPaint` throws `LateInitializationError` without asserts,
   so `_capture()` always fails outside debug: the closing overlay is drawn over
   the *live* widget and an unhandled async error is reported. My change
   deliberately preserves that (rather than hanging), but the real fix is to
   read `debugNeedsPaint` only inside an `assert(() {...}())`, or to drop the
   check. Out of this brief's scope — untestable from a debug-mode test suite.
2. **Retry loop has no cap.** If the boundary never becomes paintable, the
   replacer now reschedules (and schedules a frame) forever instead of releasing
   the barrier early. That is the intended barrier semantics, but a bounded
   number of attempts (or a timeout that reports completion) would be safer for
   `close()`.
3. `Stream.error` not being delivered to the async-scope model under
   `AutomatedTestWidgetsFlutterBinding` (see above) may hide a real
   fake-async/scheduling issue in `_performAsyncInit`'s error path. Worth a look
   independently.
4. `_isCaptured` in `_ScreenshotReplacerState` is now fully redundant with
   `_image != null`; left as is to keep the diff focused.

---

# Fix report: three regressions from `6cf403f`

All three review findings reproduced, fixed, and each fix verified to be
load-bearing by hand-reverting *only* that fix and re-running only its test (no
`git stash`). New commit, not an amend.

Files touched by this round:

- `lib/src/scope/g_lite_scope/lite_scope_core.dart` (finding 1)
- `lib/src/utils/screenshot_replacer.dart` (finding 2)
- `lib/src/scope/e_async_scope/async_scope_core.dart` (finding 3, new file for
  this task — the approved fix direction)
- `test/lite_scope_test.dart` (+4 tests: 6 -> 10)

## Finding 1 (CRITICAL) — double `close()` orphaned the barrier

`close()` assigned `_screenshotCompleter` unconditionally, while
`_performAsyncDispose()` captures the completer in a local
(`if (_screenshotCompleter case final screenshotCompleter?) await ...`) and
`_completeScreenshot()` reads the *field*. A second `close()` therefore swapped
in C2, the replacer released C2, and C1 — the one the first `close()` awaits —
stayed pending forever; `_closeCompleter` never completed either, so the second
`close()` (which returns `_closeCompleter.future`) hung too, and `disposeAsync()`
never ran.

Fix: `_screenshotCompleter ??= Completer<void>();` — the barrier is installed at
most once per element, so the field and the captured local are always the same
object. Repeated `close()` calls simply join the in-flight one via
`_closeCompleter`.

Test: `LiteScope.close() completes both futures when close() is called twice`.
Note on the repro — it is *not* enough to `await tester.pump()` before the second
`close()`: in this environment `RenderRepaintBoundary.toImage()` resolves within
that pump, so the barrier is already released and the race closes. The test
builds the closing frame with `buildOwner.buildScope(rootElement)` instead
(mounting the replacer without drawing), so the capture is still pending when
the second `close()` arrives.

Evidence — reverting only `??=` back to `=`:

```
Expected: true
  Actual: <false>
the first close() must not be orphaned by the second one
00:00 +0 -1: Some tests failed.
```

## Finding 2 (IMPORTANT) — unbounded retry loop

The `boundary == null || debugNeedsPaint` retry path had no cap and called
`scheduleFrame()` on every attempt, so a child that is built but never painted
(`Offstage`, unselected `IndexedStack` branch) meant `close()` never completed
*and* frames busy-looped forever. Pre-`6cf403f` these paths released the barrier
and scheduled nothing.

Fix: `ScreenshotReplacer.maxRetries = 5` (public, documented on the widget) plus
a `_retries` counter. On the 6th attempt the capture gives up: it reports
completion once (barrier released, `child` left in place, no screenshot) and
stops rescheduling. `onCompleted`'s doc comment now states the exactly-once
contract and all three ways it can fire.

Tests:
- `ScreenshotReplacer retries without reporting completion, then gives up after
  the retry cap` — asserts `onCompleted` is not fired for the first attempt nor
  for 3 subsequent retries, is fired exactly once after the cap, that no
  `RawImage` appears, and that no further frame reports again.
- `LiteScope.close() completes in the ready state even when the screenshot can
  never be taken` — a Ready scope inside `Offstage`: `close()` completes.

Evidence — reverting only the cap block:

```
Expected: <1>
  Actual: <0>
giving up must report completion exactly once
00:00 +0 -1: Some tests failed.

Expected: true
  Actual: <false>
the capture must give up after a bounded number of retries instead of keeping close() waiting forever
00:00 +0 -1: Some tests failed.
```

## Finding 3 (IMPORTANT) — pending ready callback hit the disposed model

Skipping the barrier made disposal reach `finally { _model.dispose(); }` inside
the one-frame window where `initAsync()` has already produced `AsyncScopeReady`
(post-frame `_model.update(Ready)` scheduled, `model.state` still
`AsyncScopeWaiting`). Task 7's `mounted` guard does not help: an element closed
via `close()` — as opposed to removed from the tree — is still mounted, so the
stale callback ran and threw *"A `_AsyncScopeNotifier` was used after being
disposed."*

Fix (as approved): `AsyncScopeElementBase._isDisposing`, set at the very top of
`_performAsyncDispose()`, and checked *in addition to* `mounted` in both
Ready-path callbacks — the post-frame one and the `pauseAfterInitialization`
delayed one. Documented on the field.

Ordering note: `LiteScopeElementBase._performAsyncDispose` awaits the barrier
before calling `super`, so `_isDisposing` is only set after the capture on the
Ready-state path. That is harmless — the barrier is only ever installed when
`state` is *already* `AsyncScopeReady`, i.e. after the callback in question has
run.

Test: `LiteScope.close() does not touch the disposed model when close() wins the
race with the post-frame callback that applies the ready state`. It mounts via
`attachRootWidget` + `buildScope` + `binding.idle()` (the technique documented in
`async_scope_test.dart`) so the callback stays pending, asserts the window is
real (`element.state is AsyncScopeWaiting`), calls `close()`, then asserts:
`takeException()` is null, `close()` completed, `disposeAsyncCount == 1` (task
7's `_initSucceeded` must still run `disposeAsync()` even though the ready state
was never applied), and `state` remains `AsyncScopeWaiting` (disposal won the
race, so the ready state is correctly never published).

Evidence — reverting only the two `_isDisposing` checks:

```
Expected: null
  Actual: FlutterError:<A _AsyncScopeNotifier was used after being disposed.
          Once you have called dispose() on a _AsyncScopeNotifier, it can no longer be used.>
the pending ready callback must not use the disposed model
00:00 +0 -1: Some tests failed.
```

## Verification

```
flutter test test/lite_scope_test.dart  ->  00:00 +10: All tests passed!   (x3 runs, no flakiness)
flutter test                            ->  00:00 +52: All tests passed!   (42 baseline + 10)
flutter analyze                         ->  3 issues found.                (the same 3 pre-existing)
dart format <4 changed files>           ->  Formatted 4 files (1 changed)
```

All 6 tests from `6cf403f` stayed green throughout; the 4 new tests all fail at
`6cf403f` (captured before the fixes) and pass now.

## Concerns

1. The release-mode `debugNeedsPaint` issue from the first round still stands and
   is now *entangled with the cap*: without asserts, `debugNeedsPaint` throws, so
   the very first attempt goes to the `on Object` branch, reports completion, and
   rethrows — the retry cap is debug-only behaviour in practice. Still a TODO/task-10
   candidate (`assert(() { needsPaint = boundary.debugNeedsPaint; return true; }())`).
2. `maxRetries = 5` is a deterministic frame count, not a deadline. A scope that
   legitimately needs more than 6 frames to paint (very heavy first frame) would
   now close without a screenshot instead of waiting. That is the intended
   trade-off (bounded wait beats an infinite one), but if it ever bites, a
   deadline-based cap would be the fix.
3. `_isDisposing` is set inside `AsyncScopeElementBase._performAsyncDispose`, so
   `LiteScope`'s barrier wait happens before the flag is set. Not exploitable
   today (see the ordering note above), but if a future change installs the
   barrier in a non-Ready state, the flag would want to move earlier.
