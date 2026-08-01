# initfix — deadlock on a failed asynchronous initialization

Branch `initfix` (worktree `.claude/worktrees/initfix`), based on `aef3bbc`.

## The defect

`AsyncScopeElementBase._performAsyncInit()` is started from `mount()` and its
future is discarded. Every path that ends well settles `_initCompleter` — the
cancelled-access path does it inline, the stream subscription does it from
`asyncMap`, `onError` and `onDone`. A failure raised *before* `_subscription`
is assigned settled nothing:

* `_performAsyncDispose()` only settles the completer inside
  `if (_subscription case final subscription?)`, so it fell through to
  `await _initCompleter.future` and parked there forever;
* it therefore never reached its `finally`, so `_asyncScopeParentEntry` was
  never unregistered;
* the parent scope's `waitForChildren` then waited out its whole
  `waitForChildrenTimeout` on a child that was already gone, reported the
  expiry, and only then disposed of itself.

Two reachable triggers, both now covered by tests:

1. `initAsync()` throwing synchronously — a plain user error in an
   initializer. `initAsync()` is called with no `await` in front of it, so the
   throw happens while `_subscription` is still `null`.
2. A scope with a `scopeKey` and no `AsyncScopeCoordinator` above it. The
   `FlutterError` from `AsyncScopeCoordinator._elementOf` is raised inside
   `_enter`, i.e. before the stream is ever built. This one has a second
   consequence: `_asyncScopeEntry` was left pointing at an `AccessEntry` that
   never made it into a queue, and `AccessEntry.exit()` throws
   `StateError('AccessEntry is not attached')` on such an entry — so once the
   completer was settled, the `finally` of `_performAsyncDispose` raised a
   second, unrelated error and skipped `_model.dispose()`.

## The fix

`lib/src/scope/e_async_scope/async_scope_core.dart`

* The body of `_performAsyncInit` after the parent-registration callback is
  wrapped in `try { … } on Object catch (error, stackTrace) { … rethrow; }`.
  The handler logs the failure (same message the stream's `onError` uses) and
  settles `_initCompleter` if nothing else did.
* The `await AsyncScopeCoordinator._enter(…)` call has its own inner
  `on Object` handler that clears `_asyncScopeEntry` before rethrowing: the
  entry never reached a queue, so there is nothing to release and nothing that
  may be `exit()`ed. The handler wraps only that call, so an entry that *did*
  get attached is never dropped.
* `_initSucceeded` is untouched on these paths, so `disposeAsync()` is not
  called for an initialization that never happened.

## The error surface is unchanged (deliberately)

The error is re-thrown untouched, so it still surfaces as an uncaught error of
the zone the mount ran in — which is exactly what
`test/async_scope_coordinator_test.dart`'s "a scopeKey without a coordinator is
an error" asserts, and that test is untouched. Nothing is swallowed.

I considered also applying the failure to the model as `AsyncScopeError`, which
would make a synchronous `initAsync()` failure render `buildOnError` the way an
error *emitted by* the same stream already does. I did not do it: it is a
change of observable behaviour that the deadlock does not require, and the
brief was to preserve the surface unless there is a strong reason. It is worth
doing as its own change, with the coordinator test updated deliberately — the
inconsistency between "the stream failed" and "building the stream failed" is
real, but it is a separate decision from the hang.

## The same shape one layer down (also fixed)

`LiteScopeCoreState` (`lib/src/scope/g_lite_scope/lite_scope_core.dart`) has
the identical shape: `_performAsyncInit()` is discarded by `initState()`,
`_performAsyncDispose()` waits on `_initCompleter`, and a failing
`initAsync()` — synchronous or from the returned future — left it unsettled.
It is reached through `LiteScopeElementBase.disposeAsync()`, so a failed state
initializer hung `close()` and, with it, the element's own disposal and its
parent's wait. Verified with a probe before fixing.

* The initialization is wrapped the same way and settles the completer on
  failure, re-throwing untouched.
* A separate `_initSucceeded` flag now records success, and
  `_performAsyncDispose` skips `disposeAsync()` when it is false — the rule
  `AsyncScopeElementBase` already applies to its own `disposeAsync()`.
  `isInitialized` is now that flag rather than `_initCompleter.isCompleted`,
  which keeps its meaning exactly as it was: before the fix the completer was
  only ever settled on success.

Other completers checked and left alone:

* `LiteScopeElementBase._closeCompleter` / `_screenshotCompleter` — the close
  completer is settled in a `finally`, and the screenshot barrier is released
  by `dispose()` as well as by the replacer.
* `ScopeAutoDependencies.dispose()` — the completer is completed by `onDone`,
  and a synchronous failure of `runDispose()` propagates out of `dispose()`
  before the `await` is reached, so it fails rather than hangs.
* `KeyedAccessQueues` / `ChildRegistry` — every wait there is bounded by a
  timeout and completes normally on expiry.

## Tests

`test/async_scope_test.dart`, group "AsyncScope failed initialization" — one
test per trigger. `test/lite_scope_test.dart` — two more for the
`LiteScopeCoreState` variant (synchronous and future failure).

The assertions are about effects, never about timings: fake time in a widget
test advances instantly. Each test pins that the parent's
`onWaitForChildrenTimeout` did *not* fire (its `waitForChildrenTimeout` is one
day, far beyond anything `_settle` can advance, so an expiry cannot be what
released the wait), that the failed scope unregistered from its parent
(`childrenCount` back to 0), that the parent got past the wait and ran its own
`disposeAsync()`, that the failed scope's `disposeAsync()` did *not* run, and
that the original error is still reported exactly once.

Each was checked by hand-reverting the corresponding hunk (no `git stash`) and
re-running:

| reverted hunk | failing assertion |
| --- | --- |
| `_initCompleter.complete()` in `_performAsyncInit`'s handler | both async-scope tests: "the failed scope finished disposing of itself and left" (childrenCount 1) |
| `_asyncScopeEntry = null` in the `_enter` handler | missing-coordinator test: `errors` has length 2 (the `StateError` from `exit()`) |
| `_initCompleter.complete()` in `LiteScopeCoreState` | both lite-scope tests: "close() must not wait for an initialization that failed" |
| `if (!_initSucceeded) return;` in `LiteScopeCoreState._performAsyncDispose` | both lite-scope tests: "an initialization that never happened is not disposed of" |

### Method note for whoever writes the next test here

An assertion that fails *inside* `runZonedGuarded` does not fail the test — the
zone's error handler swallows it and the test hangs so hard that even
`flutter test --timeout 15s` never fires (the run has to be killed). Cost an
hour here via `tester.state<S>(find.text(…))` on a `Text`. The guarded zone is
unavoidable (the uncaught zone error is the error surface under test), so the
rule is: inside the zone, only pump and collect; every `expect` goes after it.
Both new async-scope tests and the lite-scope ones follow that, and the
existing "a scopeKey without a coordinator is an error" already did.

`LiteScopeCoreState` cannot be found with a finder — the widget that owns it is
private to the package — so the fixture element records it from `createState()`.

## Verification

* `flutter test` — 65 passed (61 baseline + 4 new), 0 failed.
* `flutter analyze` — no issues in the root, in `example/minimal` and in
  `example/scopo_demo` (both examples need `flutter pub get` first in a fresh
  worktree, otherwise the analyzer reports ~51 false errors).
* `dart format --set-exit-if-changed` — clean on all four touched files.
* `dart doc` — 0 warnings, 0 errors.
