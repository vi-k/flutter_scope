# Task 7 report: mounted-guards post-frame колбэков AsyncScope

## Bug

`lib/src/scope/e_async_scope/async_scope_core.dart`, `_performAsyncInit`, has
two `SchedulerBinding.addPostFrameCallback` registrations that touch `this`/
`_model` without checking `mounted` first, unlike the sibling
`pauseAfterInitialization` branch a few lines below (which already does
`if (mounted) { _model.update(state); }`):

1. `:172-174` (before fix) — registers `_registerWithParent()` unconditionally
   on every mount. If the element is removed before this callback fires,
   `_registerWithParent` calls `visitAncestorElements` on a defunct element,
   which asserts: *"Looking up a deactivated widget's ancestor is unsafe."*
2. `:229-233` (before fix) — in the `AsyncScopeReady` branch's `else` arm
   (taken whenever `pauseAfterInitialization` is unset/disabled), registers
   `_model.update(state)` unconditionally.

## API read before writing the test

Read `async_scope_core.dart` fully, `async_scope.dart`, `async_scope_base.dart`,
`async_scope_model.dart`, `async_scope_state.dart`, and the class hierarchy it
sits on (`c_scope_model/scope_model_core.dart`, `c_scope_model/base.dart`,
`b_scope_widget/scope_widget_core.dart`, `g_lite_scope/lite_scope_core.dart`),
plus a working usage in
`example/scopo_demo/lib/home/demos/d_async_scope/counter_scope.dart` (a
`CounterScope extends AsyncScopeCore<CounterScope, CounterScopeElement>` with
a `CounterScopeElement extends AsyncScopeElementBase<...>` overriding
`initAsync()`/`disposeAsync()`/`buildOnState()`). Confirmed `AsyncScopeCore`/
`AsyncScopeElementBase` can be subclassed minimally (`scopeKey`,
`pauseAfterInitialization`, etc. all default to `null`) — this is the pattern
used for the test's `_RegisterRaceScope`/`_RegisterRaceScopeElement`.

Also traced Flutter's own `Element` lifecycle
(`framework.dart`: `mount`/`activate`/`deactivate`/`unmount`,
`_ElementLifecycle`, `Element.mounted => _widget != null`) and
`SchedulerBinding.handleDrawFrame` (persistent callbacks — which drive
`WidgetsBinding.drawFrame()`'s `buildScope()` + `finalizeTree()` — always run
to completion **before** the post-frame callback queue is drained, and both
happen synchronously with no yield point in between) to understand exactly
when these callbacks can observe a removed element, and why a plain
`pumpWidget(scope)` → `pumpWidget(SizedBox())` sequence (as sketched in the
brief) cannot reproduce the race: `SchedulerBinding.addPostFrameCallback`
callbacks always fire during the very next `handleDrawFrame()` after being
scheduled, and `WidgetTester.pumpWidget`/`pump()` always run a **full**
`handleDrawFrame()` — so a callback registered synchronously during `mount()`
(as callback 1 always is) is always drained within that same `pumpWidget`
call, before the test gets a chance to remove the widget in a *following*
call.

## Test approach

`test/async_scope_test.dart` mounts and removes the widget by driving
`BuildOwner.buildScope`/`finalizeTree` directly via
`tester.binding.buildOwner!`/`tester.binding.attachRootWidget(...)`, instead
of `pumpWidget`. This mounts the scope (scheduling the post-frame callback)
and later removes+unmounts it, all **without** ever calling
`handleDrawFrame()` — so the post-frame callback queue is never drained by
these steps. Only the final `await tester.pump()` actually draws a frame,
draining the now-stale callback against the already-defunct element.

This was chosen over an initially-attempted "have the scope's own `mount()`
synchronously call `setState()` on an ancestor to hide itself mid-build"
trick: that trick trips an *unrelated* Flutter framework invariant
(`Element.rebuild()`'s trailing `assert(!_dirty)`, since `markNeedsBuild()`
called on the currently-rebuilding element from deeper in its own
`updateChild()` call re-dirties it before that same `rebuild()` call
returns) — confirmed by reproducing that separate assertion failure while
building the test, unrelated to the guard being tested. The manual
`buildScope`/`finalizeTree` approach avoids that pitfall entirely and was
verified (see below) to reproduce the exact bug deterministically.

## Failing run (before lib fix)

```
$ flutter test test/async_scope_test.dart
00:00 +0: AsyncScope post-frame callbacks does not assert when the element is removed from the tree before the post-frame callback that registers it with the parent scope has a chance to run
══╡ EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK ╞════════════════════════════
The following TestFailure was thrown running a test:
Expected: null
  Actual: FlutterError:<Looking up a deactivated widget's ancestor is unsafe.
          At this point the state of the widget's element tree is no longer stable.
          To safely refer to a widget's ancestor in its dispose() method, save a reference to the
ancestor by calling dependOnInheritedWidgetOfExactType() in the widget's didChangeDependencies()
method.>
...
    file:///.../test/async_scope_test.dart line 62   (expect(tester.takeException(), isNull))
════════════════════════════════════════════════════════════════════════════
00:00 +0 -1: ... [E]
Some tests failed.
```

Confirms the assertion fires exactly as the brief describes, from
`AsyncScopeElementBase._registerWithParent` via the unguarded post-frame
callback in `_performAsyncInit`.

## Fix

Two one-line guards in `_performAsyncInit`, mirroring the existing
`if (mounted) { _model.update(state); }` style used a few lines below in the
`pauseAfterInitialization` branch:

```diff
     // Register with parent scope.
     SchedulerBinding.instance.addPostFrameCallback((_) {
+      if (!mounted) return;
       _registerWithParent();
     });
...
             SchedulerBinding.instance
               ..scheduleFrame()
               ..addPostFrameCallback((_) {
+                if (!mounted) return;
                 _model.update(state);
               });
```

## Passing run (after lib fix)

```
$ flutter test test/async_scope_test.dart
00:00 +0: AsyncScope post-frame callbacks does not assert when the element is removed from the tree before the post-frame callback that registers it with the parent scope has a chance to run
00:00 +1: All tests passed!
```

## Full verification

```
$ flutter test
...
00:00 +41: All tests passed!
```
41 tests total = baseline 40 + 1 new test. No other test regressed.

```
$ flutter analyze
Analyzing audit-fixes...
warning • invalid_annotation_target • example/.../scope_notifier_example2.dart:91:4
   info • avoid_classes_with_only_static_members • lib/src/environment/scope_config.dart:7:22
   info • unnecessary_this • lib/src/scope/h_scope/scope_auto_dependency/scope_auto_dependency.dart:25:36
3 issues found.
```
Same 3 pre-existing issues as baseline, unchanged.

```
$ dart format --set-exit-if-changed lib/src/scope/e_async_scope/async_scope_core.dart test/async_scope_test.dart
Formatted 2 files (0 changed) in 0.01 seconds.
```

## Why the second callback (`_model.update(state)` for `AsyncScopeReady`) has no test

Per the brief's fallback clause, this is deliberately **not** covered by a
test, only fixed defensively. It was not skipped for lack of trying — the
same `buildScope`/`finalizeTree`-driven technique used for callback 1 was
extended with `TestWidgetsFlutterBinding.idle()` (which runs `FakeAsync`'s
`elapse(Duration.zero)` — flushes all pending microtasks/zero-duration
timers **without** drawing a frame) to drive `initAsync()` to
`AsyncScopeReady()` and get this second callback scheduled, then remove the
element (again without drawing a frame), then call `idle()` repeatedly
(verified up to 10x) to let `_performAsyncDispose()` progress as far as
possible, before finally calling `pump()` to drain the stale callback.

Empirically (confirmed with temporary instrumentation, removed before
finalizing the diff — this repo's `flutter test`/`flutter analyze` reflect
the clean state):

- The callback *is* reached with `mounted == false`, matching the intended
  race.
- It never throws, before or after the fix. Root cause: element removal
  (`finalizeTree()` → `unmount()` → `AsyncScopeElementBase.dispose()`)
  synchronously calls `model.removeListener(notifyDependents)`
  (`ScopeNotifierElementBase.dispose()`) as part of the very same
  synchronous call that *starts* `_performAsyncDispose()` (which suspends at
  its first `await`, on `subscription.cancel()`). So by the time any
  post-frame callback in that same removal frame runs,
  the `_model` listener is already gone, making `notifyListeners()` (called
  from `_model.update(state)`) a harmless no-op — while `_model.dispose()`
  itself (the call that would make a subsequent `notifyListeners()` throw
  regardless of listener count, per `ChangeNotifier.notifyListeners()`'s
  `assert(debugAssertNotDisposed(this))`) sits at the *end* of that async
  chain and, experimentally, was only reached *after* `pump()` had already
  drained the stale callback — never before it, even with 10 extra `idle()`
  calls in between.
- Because `SchedulerBinding.addPostFrameCallback` callbacks always fire on
  the very next `handleDrawFrame()` after being scheduled (this code path
  also calls `scheduleFrame()`), and removal-driven disposal can only start
  (not finish) synchronously within that same `handleDrawFrame()`, there is
  no way to interleave "callback pending" + "disposal fully complete" that a
  deterministic widget test can construct: whichever frame drains the
  callback is necessarily the same frame (or an earlier/later one with
  nothing stale left to trigger) that starts disposal too late for it to
  race ahead.

The guard is still correct and worth keeping: relying on `_model`/`this`
being usable from a post-frame callback registered before disposal completes
is not an invariant worth depending on, even though this specific interleaving
of "stale + disposed" could not be forced to fail in-test.

## Self-review

- Diff is exactly the two `if (!mounted) return;` guards plus the new test
  file; no other lib files touched. All temporary print-based instrumentation
  used during investigation was reverted before finalizing.
- An unrelated untracked `docs/` directory exists in the worktree (not
  created by this task) — left untouched and not staged/committed.
- No `git stash` was used for the final failing-evidence capture: the two
  guards were removed with plain `Edit` calls, the failing run was captured,
  then the guards were reinstated with plain `Edit` calls and re-verified
  (target test, full suite, `flutter analyze`) before committing.

## Commit

```
550a338 guard async scope post-frame callbacks with mounted
```
Files: `lib/src/scope/e_async_scope/async_scope_core.dart`,
`test/async_scope_test.dart`.

---

## Follow-up fix (commit `6eb72a0`): review findings addressed

Task review on `550a338` returned two Important findings. Both are addressed
here; commit `6eb72a0`.

### Finding 1 — the "path 2 is untestable" claim above was wrong

The reviewer was right and built a deterministic failing test. My dead end
was real (`TestWidgetsFlutterBinding.idle()`/`FakeAsync.elapse(Duration.zero)`
genuinely cannot drive `_performAsyncDispose()`'s chain to completion — see
the now-corrected reasoning below), but I stopped one step short:
`WidgetTester.runAsync` escapes the `FakeAsync` zone entirely and runs a
**real** `Future.delayed` on the real event loop. That's enough for the real
Dart runtime to finish the pending `subscription.cancel()` continuation and
everything chained after it, including `_model.dispose()` — something
`FakeAsync.elapse`, even repeated, never did in this scenario.

The incorrect "Why the second callback ... has no test" section above (now
superseded by this section) was deleted from `test/async_scope_test.dart`
(it was a comment block only, never shipped as an assertion) and replaced
with a real test, `does not throw when the element is removed before the
post-frame callback that applies the ready state runs, and still runs
disposeAsync ...`. Recipe, matching the reviewer's:

1. Mount `_ReadyRaceScope` via `BuildOwner.buildScope` directly (as in the
   first test) — no frame drawn yet.
2. `await binding.idle();` — lets `initAsync()` (`Stream.value
   (AsyncScopeReady())`) deliver its value and the `AsyncScopeReady` branch
   run, scheduling the post-frame callback + `scheduleFrame()`, without
   drawing a frame (so the callback stays pending).
3. Remove the scope the same way (`attachRootWidget` + `buildScope` +
   `finalizeTree`, no frame drawn) — starts `_performAsyncDispose()`, which
   suspends at its first `await`.
4. `await tester.runAsync(() => Future<void>.delayed(const Duration
   (milliseconds: 20)));` — escapes `FakeAsync`, lets the real disposal
   chain (and `_model.dispose()`) actually finish.
5. `await tester.pump();` — draws the first real frame, draining the stale
   callback.
6. `expect(tester.takeException(), isNull);`

**Failing run (guard 2 removed by hand, no `git stash`):**

```
$ flutter test test/async_scope_test.dart
...
══╡ EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK ╞════════════════════════════
The following TestFailure was thrown running a test:
Expected: null
  Actual: FlutterError:<A _AsyncScopeNotifier was used after being disposed.
          Once you have called dispose() on a _AsyncScopeNotifier, it can no longer be used.>
...
    file:///.../test/async_scope_test.dart line 143   (expect(tester.takeException(), isNull))
════════════════════════════════════════════════════════════════════════════
00:00 +1 -1: ... [E]
Some tests failed.
```

Matches the reviewer's report verbatim (`A _AsyncScopeNotifier was used
after being disposed.`). Guard 2 was then restored by hand (`Edit`, no
`git stash`) and the run repeated:

```
$ flutter test test/async_scope_test.dart
00:00 +0: ... does not assert when the element is removed from the tree before the post-frame callback that registers it with the parent scope has a chance to run
00:00 +1: ... does not throw when the element is removed before the post-frame callback that applies the ready state runs, and still runs disposeAsync for the resources initAsync acquired
00:00 +2: All tests passed!
```

### Finding 2 — guard 2 suppresses `disposeAsync()` in a real leak window

Confirmed by construction: `_performAsyncDispose`'s
`if (model.state case AsyncScopeReady())` check (~line 324 before this fix)
reads `model.state`, which is only ever updated by the very callback guard 2
may skip. So: element removed in the frame that would drain the
init-completion callback → `_model.update(state)` never runs → `model.state`
stays at whatever it was before (e.g. `AsyncScopeWaiting`) → `_performAsyncDispose`
takes the "do not dispose of" branch → `disposeAsync()` (and whatever
resources a successful `initAsync()` acquired) leaks. This is a real
regression introduced by guard 2 in commit `550a338`, not a pre-existing bug
(before guard 2, `_model.update(state)` always ran and always set `_state`
to `AsyncScopeReady` *before* any crash from a dead listener, since
`ScopeStateNotifier.update` assigns `_state = value` before calling
`notifyListeners()`).

**Fix**, per the approved direction — track success independently of
`model.state`:

```diff
   final _initCompleter = Completer<void>();

+  /// Whether [initAsync] has definitively completed successfully (reached
+  /// [AsyncScopeReady]). Tracked separately from `model.state` because the
+  /// `_model.update(state)` call that applies it is behind a `mounted`
+  /// guard and may never run.
+  bool _initSucceeded = false;
+
   AsyncScopeCoordinatorEntry? _asyncScopeEntry;
...
           }
+          _initSucceeded = true;
           _log.i('initialized');
           _initCompleter.complete();
...
     try {
-      if (model.state case AsyncScopeReady()) {
+      if (_initSucceeded) {
         _log.i('dispose…');
```

`_initSucceeded = true` is set unconditionally in the `AsyncScopeReady`
case, after the `pauseAfterInitialization`/immediate-callback branching but
before `_initCompleter.complete()` — i.e. synchronously, regardless of
`mounted`, so it always reflects whether `initAsync()` itself succeeded,
independent of whether the (possibly guarded) UI-state update ever landed.
Since it's set at the exact point that *would* lead to `model.state`
becoming `AsyncScopeReady`, every case where the old check was `true` still
has `_initSucceeded == true` — this only *adds* correct `disposeAsync()`
calls, it never removes one that used to happen (also verified this
incidentally covers the pre-existing analogous risk in the
`pauseAfterInitialization` delayed branch, which has its own `mounted`
guard on the same `_model.update(state)` call).

**Error path checked** (asyncMap's `onError` branch, `AsyncScopeError`):
does not set `_initSucceeded`, so a failed `initAsync()` still correctly
skips `disposeAsync()`. Verified with a probe (`initAsync` that throws):
`disposeCount` stayed `0` and no exception leaked, both before and after
this fix — unchanged behavior.

**Leak made observable** — extended the same test
(`does not throw when the element is removed before the post-frame
callback that applies the ready state runs, and still runs disposeAsync
...`) with a `_ReadyRaceScopeElement.disposeCount` counter and a final
assertion: `expect(element.disposeCount, 1);`.

**Failing run (only the flag fix reverted by hand, guard 2 left in place, no
`git stash`)** — i.e. `_performAsyncDispose` restored to
`if (model.state case AsyncScopeReady())`:

```
$ flutter test test/async_scope_test.dart
...
══╡ EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK ╞════════════════════════════
The following TestFailure was thrown running a test:
Expected: <1>
  Actual: <0>
...
    file:///.../test/async_scope_test.dart line 155   (expect(element.disposeCount, 1))
════════════════════════════════════════════════════════════════════════════
00:00 +1 -1: ... [E]
Some tests failed.
```

Confirms the leak is real and observable (`initAsync()` ran, `disposeAsync()`
never did). The flag fix was then restored by hand and the run repeated —
passes (`disposeCount == 1`), shown above.

### Full verification after both fixes

```
$ flutter test
...
00:00 +42: All tests passed!
```
42 tests total = baseline 40 + 2 new tests in `async_scope_test.dart`
(the pre-existing `_registerWithParent` test, unchanged, plus the new
combined ready-state/disposeAsync test). No other test regressed.

```
$ flutter analyze
Analyzing audit-fixes...
warning • invalid_annotation_target • example/.../scope_notifier_example2.dart:91:4
   info • avoid_classes_with_only_static_members • lib/src/environment/scope_config.dart:7:22
   info • unnecessary_this • lib/src/scope/h_scope/scope_auto_dependency/scope_auto_dependency.dart:25:36
3 issues found.
```
Same 3 pre-existing issues as baseline, unchanged.

```
$ dart format --set-exit-if-changed lib/src/scope/e_async_scope/async_scope_core.dart test/async_scope_test.dart
Formatted 2 files (0 changed) in 0.01 seconds.
```
(One run reformatted a line that was too long; re-run after confirmed clean,
and tests were re-verified to still pass post-format.)

### Self-review (follow-up)

- No `git stash` used anywhere in this follow-up: both guard 2 and the
  `_initSucceeded`-based condition were reverted/restored with plain `Edit`
  calls, one at a time, to capture each failing run in isolation before
  restoring and moving to the next.
- `docs/` remains untracked/untouched, unrelated to this task.
- New commit only (`6eb72a0`), nothing amended.

### Commit

```
6eb72a0 fix disposeAsync suppression and add path-2 regression test
```
Files: `lib/src/scope/e_async_scope/async_scope_core.dart`,
`test/async_scope_test.dart`.
