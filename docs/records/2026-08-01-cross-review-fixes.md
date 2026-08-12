# cross-review — четыре волны исправлений

> **Состояние на 2026-08-12:** все описанные исправления смержены в `main` (cf62561 и 2ec6809), тест-сьют зелёный (92 теста). Исторический документ, не поддерживается.
> **Что это:** склейка отчётов четырёх волн кросс-ревью версии 0.10.0 в порядке работ: `initfix` (дедлок при провале инициализации), `coordfix` (5 дефектов жизненного цикла координации), `batch2` (ревью coordfix и его регрессии), `batch3` (три оставшихся известных дефекта). Тексты сохранены дословно, границы исходных файлов отмечены заголовками `## Файл: …`.
> **Связанные записи:** предшествующие эпизоды — `2026-07-30-audit-fixes-plan.md`, `2026-07-31-async-scope-coordinator-design.md`.

## Файл: initfix-report.md

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


---

## Файл: coordfix-report.md

# coordfix — three coordination/disposal defects

Branch `coordfix`, based on `05f9bee`. Baseline: 65 tests green.
Final: **69 tests green**, `flutter analyze` clean in the package and both
examples, `dart format` clean, `dart doc` 0 warnings / 0 errors.

One commit per defect, each with its test written first, watched fail, then
fixed, then watched pass — and each fix hand-reverted afterwards to prove the
new test is load-bearing (file copy/restore, not `git stash`).

---

## A — `0b0e36a` fix(coordination): drop only the children an expired wait awaited

`lib/src/scope/e_async_scope/scope_coordination.dart`,
`ChildRegistry.waitForChildren`.

**Defect.** The futures a wait awaits are snapshotted when `.wait` consumes the
iterable, but the timeout handler cleared the *live* `_children` list. A child
that registered while the wait was running — one the wait deliberately does not
await, per the method's own contract — was wiped along with the stragglers.
After the expiry `hasChildren` was `false` and the next `waitForChildren()`
returned immediately, although that child never unregistered and was still
disposing of itself. With `ScopeConfig.defaultWaitForChildrenTimeout` at 3s and
the README recommending repeated `AsyncScopeCoordinator.waitForChildren(context)`
calls (e.g. before tearing a test down), this is reachable in ordinary use.

**Fix.** The awaited set is captured explicitly (`final awaited = List.of(_children)`),
and on expiry only its still-unfinished entries are removed. The removal sits in
a `finally` around the `onTimeout` call, so a reporter that throws cannot leave
the registry holding entries nobody will ever complete. The exception message now
names only the children that actually held the wait up.

Doc comments on `ChildRegistry.waitForChildren`,
`AsyncScopeParent.waitForChildren` and `AsyncScopeCoordinator.waitForChildren`
were updated to state that a mid-wait registration survives.

**Tests** (`test/scope_coordination_test.dart`, plain-Dart, `fake_async`, no
wall-clock assertions — effects only):

- `a timeout drops only the children the wait was awaiting` — after the expiry
  the registry still holds the late child, the reported message does not name
  it, and a second `waitForChildren()` blocks until that child unregisters.
- `an onTimeout that throws still gives up on the children left` — the reporter's
  failure propagates, and the registry is still emptied.

Reverted-fix check: both fail (`Expected: not contains 'later'` / `Expected:
false, Actual: <true>`).

---

## B — `6306cf1` fix(lite-scope): give every close() caller the same disposal outcome

`lib/src/scope/g_lite_scope/lite_scope_core.dart`,
`LiteScopeElementBase._performAsyncDispose`.

**Defect.** The first caller awaited the real disposal; every later caller
awaited `_closeCompleter.future`, which was completed *successfully* in a
`finally` even when the disposal threw. So a failing `disposeAsync()` rejected
the first `close()` and resolved the second one — for the same run. The implicit
disposal on unmount funnels through the same completer and diverged from an
explicit `close()` identically.

**Fix.** The disposal run is memoized once (`_runAsyncDispose()`), and the shared
completer is completed *with that future*: `Completer.complete(future)` forwards
its value, or its error **and stack trace**, to every listener alike. The
completer is still installed before the run starts, so a caller arriving while
the run is still synchronous joins it rather than starting a second one, and
`markNeedsBuild()` still happens synchronously on the first call.

**Test** (`test/lite_scope_test.dart`): `hands the same disposal failure to every
close() caller`. Two `close()` calls issued back to back against a scope whose
state `disposeAsync()` returns `Future.error`; the second caller's error must be
`same()` instance as the first's. `_CloseScope` gained a `failStateDispose` flag.
The pre-existing `completes both futures when close() is called twice` test still
passes.

Reverted-fix check: fails with `Expected: same instance as StateError:<Bad state:
state disposeAsync failed>  Actual: <null>`.

---

## C — `b075108` fix(async-scope): report an expired AsyncScopeParent.waitForChildren by default

`lib/src/scope/e_async_scope/async_scope_parent.dart`.

**Defect.** The mixin forwarded a nullable `onTimeout` straight to the
Flutter-free core, so a caller who supplied none had the children dropped and
the future completed with nothing reported anywhere. The method is public API in
its own right — `AsyncScopeCore.of` hands out the element, and every user
`AsyncScopeElementBase` subclass exposes `waitForChildren` as a public instance
method — so this was the unwrapped counterpart of
`AsyncScopeCoordinator.waitForChildren`, which has reported by default since it
was added.

**Fix.** `onTimeout` now defaults to `FlutterError.reportError` with
`library: 'scopo'`, prefixing the message the registry builds with the parent's
own short description. The mixin lives in the Flutter-side library, so
`FlutterError` is available there and the core stays Flutter-free.

The name is read **when the wait starts**, not at expiry:
`AsyncScopeElementBase` nulls its cached `_widget` at the end of disposal and
this wait routinely outlives the tree, so reading `widget` from the callback
would throw — the same trap already fixed once in this release for the
coordinator helper. `toStringShort()` is only computed when the default is
actually going to be used (`onTimeout == null`), so callers that pass a callback
pay nothing.

No double prefixing: both internal call sites (`async_scope_core.dart`'s
`_performAsyncDispose` and the coordinator's static helper) always pass their own
`onTimeout`, so the mixin default never stacks on top of theirs.

**Test** (`test/async_scope_coordinator_test.dart`): `the mixin waitForChildren
reports an expiry by default`. A parent scope over a still-mounted child scope;
`parent.waitForChildren(timeout: 50ms)` with no callback must complete normally,
surface a `TimeoutException` through `tester.takeException()` whose message
starts with the element's short description, while the dropped child is still in
the tree.

Reverted-fix check: fails with `Expected: <Instance of 'TimeoutException'>
Actual: <null>`.

---

## Verification

| Check | Result |
| --- | --- |
| `flutter test` | 69 passed (65 baseline + 4 new) |
| `flutter analyze` (package) | No issues found |
| `flutter analyze` (example/minimal) | No issues found |
| `flutter analyze` (example/scopo_demo) | No issues found |
| `dart format --set-exit-if-changed lib test` | clean |
| `dart doc` | 0 warnings, 0 errors |

`flutter pub get` was run in both examples first — a fresh worktree has no
`.dart_tool` there and the analyzer otherwise reports ~51 false errors.

CHANGELOG: three bullets added under `## 0.10.0` (unpublished). No historical
section touched.


---

## Файл: batch2-report.md

# batch2 — five coordination/lifecycle defects, plus three found in review

Branch `coordfix`, based on `0fe8261`. Baseline: 69 tests green.
Final: **82 tests green**, `flutter analyze` clean in the package and both
examples, `dart format` clean, `dart doc` 0 warnings / 0 errors.

The five defects of the original brief are sections 1–5. Sections 6–8 are what
two rounds of review then found by execution, each confirmed by running the
code: a regression section 5 introduced (6), a hole in its diagnostic (7), and
a false positive that closing the hole introduced (8). The verification table
at the end is the current one.

One commit per defect, each with its test written first, watched fail, then
fixed, then watched pass — and each fix hand-reverted afterwards to prove the
new test is load-bearing (file copy/restore, not `git stash`). Where a fix has
more than one moving part, each part was reverted on its own.

Every assertion is about effects — which error the app receives, which state a
scope is left in, whether a hook ran, whether a wait came back — never about
elapsed time: fake time in a widget test advances instantly. Every `expect`
sits outside the `runZonedGuarded` blocks, since an assertion that fails inside
one is swallowed by the zone handler and hangs the run.

---

## 1 — `618898f` fix(async-scope): stop a failure after Ready double-completing the init completer

`lib/src/scope/e_async_scope/async_scope_core.dart`, `_performAsyncInit`.

**Defect.** The stream's `onError` handler called `_initCompleter.complete()`
unguarded, while `onDone` and the outer handler both check `isCompleted` first.
A stream that reaches `AsyncScopeReady` and then raises therefore got
`Bad state: Future already completed` thrown *on top of* the failure being
reported — the app received the crash and the real error reached nobody.

Reachable a second way through the package's own diagnostic: the
`already initialized` guard tested `_model.state`, which only becomes
`AsyncScopeReady` inside a post-frame callback. A second `AsyncScopeReady`
arriving before that callback slipped past the guard and re-ran the whole ready
branch — a second `_initSucceeded`, a second pending update, a second
`complete()` — so the diagnostic itself became the crash.

**Fix.** Three parts:

- The `already initialized` guard now tests `_initSucceeded`, not the applied
  model state. (`AsyncScopeError` still produces the
  `initialization failed` diagnostic.)
- Both remaining unguarded `complete()` calls — the ready branch and `onError` —
  check `isCompleted` first, like their two siblings already did.
- `onError` bails out when `_initSucceeded` is set. A scope that did initialize
  is not flipped into `AsyncScopeError`: `buildOnError` would replace the
  widgets already on screen while `disposeAsync()` still had to release what
  `initAsync()` acquired.

**Decision beyond the brief.** The bail-out reports the failure through
`FlutterError.reportError` (library `scopo`) instead of only logging it. A
silent bail-out would swallow both the user's real error and the package's own
`already initialized` diagnostic — the diagnostic exists to be seen, and the
brief's own complaint was that "the real error never reaches the zone".
`FlutterError.reportError` is the mechanism this file already uses for the two
timeout reports.

**Tests** (`test/async_scope_test.dart`, new group
`AsyncScope initialization that fails after the ready state`):

- `reports the failure raised after the ready state instead of a
  double-completed init completer, and leaves the scope ready` — no uncaught
  zone error, the reported exception is the user's `StateError`, the scope is
  still `AsyncScopeReady`, and `disposeAsync()` still runs exactly once.
- `reports a second ready state as the already-initialized diagnostic` — the
  second `AsyncScopeReady` produces `_TwiceReadyScope already initialized`
  rather than a crash, and the ready branch ran once, so the disposal runs once.

Reverted-fix checks: pre-fix, both fail with
`Actual: [StateError:Bad state: Future already completed]`. With only the
`isCompleted` guards restored, test 1 still fails (`Expected: <Instance of
'StateError'> Actual: <null>`); with the model-state guard restored, test 2 still
fails the same way.

---

## 2 — `cf41079` fix(async-scope): never drop an attached scopeKey entry when entering fails

`lib/src/scope/e_async_scope/async_scope_core.dart`,
`lib/src/scope/e_async_scope/async_scope_coordinator.dart`.

**Defect.** `_AccessQueue.enter` attaches the entry before it awaits anything,
and an expired wait lets the scope into the key anyway and *then* calls
`onScopeKeyTimeout()` — ordinary user code, running with the entry already in
the queue. The blanket `on Object` handler around the coordinator call cleared
`_asyncScopeEntry` on any throw, so a hook that failed left the entry in the
queue with nothing left to release it: `_performAsyncDispose`'s `finally` had
nothing to `exit()`, and every later scope on that key waited for an entry
nobody would ever complete, with no rescue.

**Fix.** The approved (cleaner) option: the coordinator lookup — the only step
that can fail before the entry reaches a queue, and the sole reason the handler
existed — is hoisted above the `AccessEntry`, and the handler is gone. Once the
entry is in `_asyncScopeEntry` it is in a queue too, and nothing drops it. The
fallback `isAttached` getter was not needed.

`AsyncScopeCoordinator._enter` had no other caller and was removed; its doc
comment about per-coordinator keys moved to `_elementOf`, which is now what the
scope calls.

**Test** (`test/async_scope_coordinator_test.dart`): `a failing
onScopeKeyTimeout does not leak the scopeKey`. A holder takes `'shared'`; a
waiter with a 50 ms limit queues behind it, expires, and its
`onScopeKeyTimeout()` throws; both leave; a third scope then asks for the same
key. The third scope must reach `AsyncScopeReady` with `keyTimedOut == false`,
and its own limit is one day — far beyond anything `_settle` can advance — so an
expiry cannot be what let it in.

Reverted-fix check: with the blanket handler restored (lookup still hoisted),
`Expected: <Instance of 'AsyncScopeReady'> Actual: AsyncScopeWaiting`.

`_TestScope` gained `keyTimeout` and `throwOnKeyTimeout`; `_TestScopeElement`
gained `keyTimedOut`.

---

## 3 — `8190a1a` fix(async-scope): stop close() leaving an orphaned entry with the parent

`lib/src/scope/e_async_scope/async_scope_core.dart`, `_performAsyncInit`.

**Defect.** The post-frame callback that registers a scope with its parent was
guarded by `mounted` alone, and `close()` keeps the element mounted on purpose.
A disposal that finished before that callback was drained registered a *fresh*
`ChildEntry` after the `finally` had already unregistered the previous one — an
entry nobody will ever complete. The parent, or
`AsyncScopeCoordinator.waitForChildren`, then burned its whole timeout naming a
scope that was already gone. The two sibling post-frame callbacks got the
`_isDisposing` half of the guard earlier in this release; this one kept only
`mounted`.

**Fix.** `if (!mounted || _isDisposing) return;`.

**Test** (`test/lite_scope_test.dart`): `does not register with the parent again
once close() has finished`. The scope is mounted by driving
`BuildOwner.buildScope` directly, so the registration callback stays pending
(`pumpWidget` drains it within the very frame that schedules it — the technique
already documented in `async_scope_test.dart`). `close()` is then driven to
completion with `runAsync` slices only, with no frame drawn, and the first
`pump()` afterwards drains the stale callback. The coordinator must hold zero
children, and a `waitForChildren(timeout: 1 day)` must come back on its own.

Reverted-fix check: `Expected: <0> Actual: <1>`.

---

## 4 — `351bfe2` fix(async-scope): stop a closed scope crashing when it is reparented

`lib/src/scope/e_async_scope/async_scope_core.dart`,
`lib/src/scope/e_async_scope/scope_coordination.dart`.

**Defect.** `close()` keeps the element mounted, so a closed scope can still be
moved in the tree with a `GlobalKey`: the element is retaken instead of
unmounted and `activate()` runs. The disposal's `finally` unregistered
`_asyncScopeParentEntry` but never cleared it, and `activate()` re-registered
unconditionally, so the move called `unregister()` on an entry that was already
gone — `'_registry != null': Entry is already unregistered` in debug and, with
the asserts compiled out, `_completer.complete()` on a completed completer: a
release-only crash hiding behind a debug assert.

**Fix.** Three parts:

- The disposal clears the field where it unregisters it.
- `activate()` skips the re-registration once `_isDisposing` is set —
  registering there would hand the new parent an entry nobody will ever
  complete.
- `ChildEntry.unregister()` is idempotent (defence in depth): a second release
  is a no-op rather than a failure, with an assert that a detached entry is at
  least a completed one.

**Tests.**

- `test/lite_scope_test.dart`: `survives being moved with a GlobalKey after
  close()` — a closed scope moved under a different parent widget must raise
  nothing and must not register with its new parent. `_CloseScope` gained
  `super.key`.
- `test/scope_coordination_test.dart`: `unregistering a second time is a no-op`
  — plain-Dart, covers the idempotency directly, since the two element-side
  guards mean nothing in the package reaches it any more.

Reverted-fix checks: with all three reverted, the widget test fails with
`_AssertionError: '_registry != null': Entry is already unregistered` and the
registry test fails with the same assert. With only the `activate()` guard
reverted, the widget test fails with `Expected: <0> Actual: <1>` — the closed
scope registers with its new parent.

---

## 5 — `a2368e8` feat(async-scope): report a scopeKey that changes under a live scope

`lib/src/scope/e_async_scope/async_scope_core.dart`.

**Defect.** A place in a queue is taken once and cannot be moved. Both ways of
changing the pair (`scopeKey`, owning coordinator) under a live element — a
`scopeKey` getter that starts returning something else, and a `GlobalKey` move
under a different coordinator — left the `AccessEntry` parked on the old key of
the old queue in complete silence. The old key stayed held by a scope that no
longer claimed it, and another scope asking for the new key entered at once:
the mutual exclusion the key exists for stopped working with nothing to show
for it.

**Fix (the owner's loud-invariant option, not re-acquisition).** The pair is
cached when the entry is created (`_acquiredScopeKey`, `_acquiredCoordinator`)
and checked by `_debugCheckScopeKeyOwnership()` from `performRebuild()` and
`activate()`, both behind an `assert`, so release builds pay nothing. The check
raises a `FlutterError` naming both pairs, explaining that the entry cannot
follow, and saying what to do instead: give the widget a different `key`, so
the framework builds a new element that takes the new key from scratch and
releases the old one on its way out. No async release-and-reacquire is
attempted — releasing and taking a key again is asynchronous and a rebuild is
not. The invariant is documented in the `scopeKey` dartdoc, which had no
documentation at all before.

**Choice of hooks.** `performRebuild()` rather than `update()`, so a `scopeKey`
derived from the element's own state is covered too, not only one that changes
with the widget. `activate()` is *not* redundant next to it: after a `GlobalKey`
move the framework normally calls `update()` → `performRebuild()`, but when the
new widget is the identical instance, `Element.updateChild` short-circuits on
`child.widget == newWidget` and no rebuild follows — `activate()` is then the
only place left to notice the new coordinator. The test is written to hit
exactly that shortcut, which is what makes both hooks individually
load-bearing.

**Tests** (`test/async_scope_coordinator_test.dart`, new group `the scopeKey of
a live scope`):

- `cannot change` — the same scope rebuilt with a different `testKey` reports a
  `FlutterError` that says what happened and what to do instead.
- `cannot move under another coordinator` — the same widget instance moved with
  a `GlobalKey` from one coordinator to another reports the same way. The
  coordinators sit in `Expanded`s so the substituted `ErrorWidget` has bounded
  constraints; an unbounded one overflows the `Column` and buries the report
  under a second, unrelated exception.

Reverted-fix checks: with the `activate()` assert removed, `cannot move under
another coordinator` fails (`Expected: <Instance of 'FlutterError'> Actual:
<null>`); with the `performRebuild()` assert removed, `cannot change` fails the
same way. `_TestScope` gained `super.key`.

---

## Verification

| Check | Result |
| --- | --- |
| `flutter test` | 77 passed (69 baseline + 8 new) |
| `flutter analyze` (package) | No issues found |
| `flutter analyze` (example/minimal) | No issues found |
| `flutter analyze` (example/scopo_demo) | No issues found |
| `dart format --set-exit-if-changed lib test` | clean |
| `dart doc` | 0 warnings, 0 errors |

`flutter pub get` was run in both examples first — a fresh worktree has no
`.dart_tool` there and the analyzer otherwise reports ~51 false errors.

CHANGELOG: five bullets added under `## 0.10.0` (unpublished). No historical
section touched.

## Review follow-up — two issues found by execution

Both reported against the batch above; the first is a regression `a2368e8`
introduced. Same method throughout: failing test first, fix, green, then the
fix hand-reverted to prove the test load-bearing.

### 6 — `b567551` fix(async-scope): keep the parent handoff when a reparented scope is reported

`lib/src/scope/e_async_scope/async_scope_core.dart`, `activate()`.

**Defect (regression from `a2368e8`).** `_debugCheckScopeKeyOwnership()` raises
rather than returning `false`, and `activate()` ran it *before*
`_registerWithParent()`. So in exactly the case the diagnostic exists for — a
`GlobalKey` move of a keyed scope to another coordinator — the throw unwound
`activate()` and the re-registration never happened. The scope left the old
parent's subtree without ever unregistering from it: `childrenCount` stayed at
one forever and the old parent waited out its whole `waitForChildrenTimeout` on
a child that was alive and well somewhere else. Before `a2368e8`, `activate()`
re-registered unconditionally and the handoff worked on every move.

**Fix.** The handoff happens first and the check follows it, on both paths —
the `_isDisposing` early return keeps its own check:

```dart
void activate() {
  super.activate();
  if (_isDisposing) {
    assert(_debugCheckScopeKeyOwnership());
    return;
  }
  _registerWithParent();
  assert(_debugCheckScopeKeyOwnership());
}
```

The report is unchanged; only what survives it is.

**Test.** `cannot move under another coordinator` (already present) now pins
both halves: the `FlutterError` still fires, **and** the coordinator the scope
left drops to zero children while the one it moved under holds one, **and**
`oldParent.waitForChildren(timeout: 1 day)` comes back on its own — a limit far
beyond what the test can advance, so only an empty registry can have released
it.

Reverted-fix check (assert moved back above `_registerWithParent()`):
`Expected: <0> Actual: <1>`, `the coordinator the scope left must not keep
waiting for it`.

### 7 — `265aa47` fix(async-scope): report a scopeKey that appears after the scope has mounted

`lib/src/scope/e_async_scope/async_scope_core.dart`.

**Defect.** The check returned early whenever `_asyncScopeEntry == null`, and an
entry is only ever created at mount, inside `if (scopeKey case final scopeKey?)`.
A scope that mounted key-less and later claimed a contested key therefore got no
entry, no exclusion and no diagnostic at all — it simply coexisted with the
holder on the same key under the same coordinator, `takeException()` null. Not
exotic: `scopeKey` is a plain constructor field on the public `AsyncScope`, and
`AsyncScope(scopeKey: userId)` with a `userId` that is null until an async load
finishes is ordinary usage.

**Fix (the real check, not a documentation retreat).** `scopeKey` is read
exactly once in `_performAsyncInit`, into `_acquiredScopeKey`, with a separate
`_scopeKeyObserved` flag recording that it was read — `null` is an *answer*,
not the absence of one, and a scope that gave it never takes a place in any
queue. The check is measured against that answer rather than against the entry,
so all four ways it can go stale report alike, each with its own message:

| what changed | message |
| --- | --- |
| `null` → key | `... appeared after the scope had already initialized without one.` |
| key → `null` | `... was given up while the scope was still holding it.` |
| key → other key | `... changed while the scope was holding one.` |
| coordinator | `The AsyncScopeCoordinator above ... changed while the scope was holding a scopeKey.` |

An appearing key is deliberately worded apart from the rest: there is no
misplaced entry to point at, only a key nobody ever took. The coordinator half
is compared only once a queue is actually holding an entry
(`_acquiredCoordinator != null`), so a scope that needs no key — and one whose
coordinator lookup failed and never got an entry — may still be moved wherever
the tree likes without a spurious report.

**Tests** (`test/async_scope_coordinator_test.dart`, group `the scopeKey of a
live scope`):

- `cannot appear after the scope has mounted` — a holder on `'shared'` plus a
  key-less scope under the same coordinator (`initialized == 2`, so they really
  did coexist); the key then appears on the second scope and must be reported
  with wording that says it was never taken.
- `cannot be given up while the scope is holding it` — a keyed scope whose key
  becomes `null` must be reported as *given up*, which is not the same as
  changed: the entry is still held, by a scope that no longer claims to need
  it.

Reverted-fix checks: with the entry-only guard restored, `cannot appear` fails
with `Expected: <Instance of 'FlutterError'> Actual: <null>` — total silence,
the reviewer's finding exactly. With the single fixed message restored, `cannot
be given up` fails with `Actual: 'The scopeKey of _TestScope changed while it
was holding one.'`.

**Docs.** Both the `scopeKey` dartdoc and the `## 0.10.0` CHANGELOG bullet were
rewritten in the same commit. Both previously claimed the key was "fixed for
the lifetime of the element" without saying it is *read once* — which is what
makes an appearing key unhonourable rather than merely misplaced — and neither
mentioned the appearing or disappearing cases at all. They now enumerate all
four, and say plainly that none of them is repaired.

### 8 — `f1ac421` fix(async-scope): stop the scopeKey diagnostic firing on a scope that has finished closing

`lib/src/scope/e_async_scope/async_scope_core.dart`.

**Defect (false positive introduced by `265aa47`).** The guard that section 7
replaced — `if (_asyncScopeEntry == null) return true;` — happened to mean two
things at once: "no key was ever taken" *and* "the disposal has already
released everything", since the `finally` nulls that field. The new guard,
`if (!_scopeKeyObserved) return true;`, only kept the first: once a real key
had been read the flag stayed true forever, and the three key-tracking fields
were never cleared by `_performAsyncDispose`.

So a scope that had *fully* disposed of itself through the public, documented
`LiteScope.close()` — which deliberately keeps the element mounted, so it can
render a closing screen and can still be moved with a `GlobalKey` — was still
held to a live-ownership invariant it no longer took part in. `exit()` had
already run on its `AccessEntry`; it held nothing and asked for nothing. Two
confirmed repros, both legitimate usage:

1. closed, then moved with the same `GlobalKey` under a different coordinator →
   `The AsyncScopeCoordinator above ... changed while the scope was holding a
   scopeKey`, from `activate()`'s `_isDisposing` branch;
2. closed, then merely rebuilt by its parent with a different key-backing value
   → `The scopeKey of ... changed while the scope was holding one`, from
   `performRebuild()`, which has no `_isDisposing` guard at all.

Firing on correct code is worse than the hole section 7 closed.

**Fix.** A `_scopeKeySettled` flag, set in `_performAsyncDispose`'s `finally`
right where `_asyncScopeEntry` is nulled, and short-circuiting the check:
`if (!_scopeKeyObserved || _scopeKeySettled) return true;`.

The flag is deliberately **not** tied to `_isDisposing`. Between
`_isDisposing = true` and that `finally` the entry is still sitting in its
queue, so a key that changes there is the very violation the diagnostic exists
for and stays loud. Only the release makes it moot.

Also in the same block: the `exit from [...]` log now names `_acquiredScopeKey`
rather than calling the `scopeKey` getter — what is being released is the key
the queue was entered on, whatever the getter says by then, and it is a plain
field rather than user code running in a half-torn-down element.

**Tests** (`test/lite_scope_test.dart`, new group `LiteScope.close() with a
scopeKey` — the suite paired `scopeKey` with `close()` nowhere before, since
`_CloseScope` never overrode `scopeKey`). `_CloseScope` gained `testKey`, and
`_neverEmitsUntilCancelled` gates the stream's cancellation.

- `may be moved under another coordinator once it has finished closing` —
  repro 1, must be silent.
- `may be rebuilt with a different scopeKey once it has finished closing` —
  repro 2, must be silent.
- `still reports a scopeKey that changes while close() is in flight` — the
  disposal is parked inside `await subscription.cancel()`, so `_isDisposing` is
  set and the entry is still in its queue; the key change there must still be
  reported.

Reverted-fix checks, two of them, because the two halves of the requirement
pull in opposite directions:

- with the `_scopeKeySettled` short-circuit removed, both silent-after-close
  tests fail with the exact repro messages above, and the in-flight test still
  passes;
- with the short-circuit widened to `_isDisposing` — the naive "turn the check
  off on disposal" fix — both silent-after-close tests pass and the in-flight
  test fails with `Expected: <Instance of 'FlutterError'> Actual: <null>`.

Only the committed version satisfies both.

**Docs.** The `scopeKey` dartdoc and the `## 0.10.0` bullet said the answer is
fixed "for the lifetime of the element"; both now say it is binding *until the
scope has finished disposing of itself*, and both spell out that an element
outliving its own disposal may be rebuilt and reparented freely while a key
that changes mid-`close()` is still reported.

**Note on the test tree.** The in-flight test uses a bare `Directionality` and
never reaches the ready state. Two earlier shapes were discarded after being
observed to fail for reasons unrelated to the defect: under `MaterialApp` the
substituted `ErrorWidget` tears down the focus machinery and trips
`'_dependents.isEmpty'`, and in the ready state the closing overlay's
`CircularProgressIndicator` is left animating in an orphaned subtree and trips
`Tried to build dirty widget in the wrong build scope`.

### Verification after the follow-up

| Check | Result |
| --- | --- |
| `flutter test` | 82 passed (69 baseline + 13 new) |
| `flutter analyze` (package) | No issues found |
| `flutter analyze` (example/minimal) | No issues found |
| `flutter analyze` (example/scopo_demo) | No issues found |
| `dart format --set-exit-if-changed lib test` | clean |
| `dart doc` | 0 warnings, 0 errors |

## Deviations from the brief

1. **Defect 1** — the file has one `onError` handler, not two; the two
   unguarded `complete()` calls are the one in `onError` and the one in the
   ready branch, and both are now guarded. The `onError` bail-out additionally
   *reports* the failure through `FlutterError.reportError` rather than
   swallowing it; see the reasoning under defect 1.
2. **Defect 2** — the primary (approved) option worked, so there is no
   `AccessEntry.isAttached` getter and no precise handler. The now-unused
   private `AsyncScopeCoordinator._enter` was removed rather than left dead.
3. **Defect 5** — the rebuild hook is `performRebuild()`, not `update()`, for
   the reason given above.
4. **Follow-up 7** — none. The controller's decision (record the observed key,
   including `null`, and compare against it) was implemented as stated; the
   only judgement call was to word the appearing-key report differently from
   the other three, since there is no misplaced entry to point at.
5. **Follow-up 8** — none. Of the two mechanisms offered, the `_scopeKeySettled`
   flag was chosen over clearing the observed state: clearing it would have
   made a settled scope indistinguishable from one whose initialization has not
   read `scopeKey` yet, and the two deserve different comments if not different
   behaviour. One unrequested line came with it — the `exit from [...]` log now
   names the recorded key instead of calling the `scopeKey` getter during
   teardown.


---

## Файл: batch3-report.md

# batch3 — remaining known defects

Branch `batch3`, based on 5bf2f9c. Three defects, one commit each, TDD
throughout: failing probe first, then the fix, then a hand-revert of the fix to
prove the probe load-bearing (never `git stash` — the revert was applied and
undone in place with a scripted string replacement).

All three reproduced.

## Verification

| Check | Result |
| --- | --- |
| `flutter test` | 92 passed (baseline 82, +10 new) |
| `flutter analyze` (root) | No issues found |
| `flutter analyze` (example/minimal) | No issues found |
| `flutter analyze` (example/scopo_demo) | No issues found |
| `dart format` on `lib` and `test` | 0 changed |
| `dart doc` | 0 warnings, 0 errors |

## Defect 1 — initialization not cancelled before the subscription exists

`lib/src/scope/e_async_scope/async_scope_core.dart`

**Reproduced.** `_performAsyncInit` hands the cancellation over to
`_subscription`, and `_performAsyncDispose` can only reach it through that
field. A scope with a `scopeKey` awaits `AsyncScopeCoordinator.enter()` before
it subscribes, so between the `await` and the assignment the field is still
`null` and a disposal that starts there has nothing to cancel. The guard on
the far side of the await checked `entry.isCancelled || !mounted`, and neither
covers it: a free key is never cancelled, and `close()` keeps the element
mounted on purpose.

The probe drives the build phase directly and then does not `await` anything:
`enter()` on a free key completes one microtask later, so everything the test
does before it yields happens inside the window. Before the fix a scope that
was already closing went on to call `initAsync()` (`initCount == 1`) and to run
`disposeAsync()` on resources it had acquired for a scope that no longer
existed.

**Fix.** The guard after the await now also checks `_isDisposing`. The normal
path is untouched — proved by the control test, which shows the same scope
initializing as usual when nothing closes it.

Tests (`test/lite_scope_test.dart`, group *AsyncScope initialization racing a
disposal that already began*):

* `control: a scope with a free scopeKey does start its initialization`
* `does not initialize when close() wins the race for a free scopeKey`

The probe lives with the `LiteScope` harness because `close()` is the only
public API that begins a disposal while the element stays mounted: a scope
removed from the tree has `mounted == false` by the time the continuation runs,
which the existing guard already caught.

### Deviation: the `TODO(nashol)` comment was kept

The brief said to remove it if the defect is closed. It was not removed,
because it does not mark this defect. Its text is
`// TODO(nashol): errors raised after the cancellation land here`, sitting on
`await subscription.cancel()`; the original Russian (commit acc96d7,
`сюда прилетят ошибки, возникшие уже после отмены`) says the same thing. That
is about errors surfacing from the cancellation itself, which unwind
`_performAsyncDispose` before the `finally` that unregisters the parent entry,
releases the `AccessEntry` and disposes of the model — a separate, still-open
concern that this work did not touch. `TODO.md` referenced the comment as a
*location*, and that entry was removed.

## Defect 2 — `ScopeAutoDependencies` re-init, and lost group errors

`lib/src/scope/h_scope/scope_auto_dependency/…`

**Both halves reproduced.**

### (a) `_root` was never rebuilt

A second `init()` reused the tree the previous disposal had left behind and
tripped `assert(_state is ScopeDependencyInitial)` in the first dependency it
reached.

Chosen: rebuild, as the brief preferred. Nothing else in `ScopeAutoDependencies`
goes stale — the class holds only `_log` and `_root`, and `ProgressIterator` is
created fresh per run — so a new tree is all a second run needs.

The rebuild happens in the new `_prepareDependencies`, on the next `init()`,
rather than by nulling `_root` in `dispose()`: dropping it there would have
made `flattenDependencies()` throw right after a disposal, which is exactly
when defect 2b makes the tree worth reading.

A second `init()` on a tree that is **still alive** now raises a `StateError`
that says so, instead of the opaque assert — replacing a live tree would
abandon everything it holds with nothing left to dispose of it. "Still alive"
is `disposalRequired`, which is exactly the question being asked.

### (b) the group-level error list was overwritten

`runDispose` replaced every state with `ScopeDependencyDisposed`. A group is
disposed of *because* something under it failed —
`ScopeDependencyGroup.disposalRequired` covers `ScopeDependencyFailed` — so the
disposal threw away the one record of what had failed, and with the default
`autoDisposeOnError == true` that happened before the caller ever saw it.

Fix: a state that carries errors survives the disposal untouched. This is not a
new rule but an existing one made consistent — a failed *leaf* is never
disposed of (`disposalRequired` needs `ScopeDependencyInitialized`) and so
always kept its errors; and `ScopeDependencyDisposalFailed` was already exempt.
A `ScopeDependencyCancelled` with no errors still becomes
`ScopeDependencyDisposed`.

Because the state can no longer answer "has the disposal run", the mixin got
`_isDisposalDone`, and `ScopeDependencyGroup.disposalRequired` consults it — a
group that keeps saying `ScopeDependencyFailed` must not be disposed of a
second time.

**Observable change, recorded in the CHANGELOG as breaking:** after disposing
of a tree that failed, the root reports `isFailed == true` /
`isDisposed == false` where it used to report the opposite. 15 existing tests
asserted the old behaviour and were updated; the transformation was mechanical
(each post-disposal `[group] disposed` became the string that group already had
before the disposal) and the whole diff was reviewed line by line.

Tests (`test/scope_auto_dependencies_test.dart`):

* `control: a first init() builds the tree and initializes it`
* `a second init() rebuilds the tree the disposal left behind`
* `a second init() on a live tree fails with a clear error`
* `control: a tree that succeeded ends up disposed`
* `keeps the group-level error list readable`
* `a second dispose() does not release anything twice`

Each of the three code changes was reverted on its own: `_prepareDependencies`
→ the two re-init tests fail; the `runDispose` state rule → the two failure
tests plus the updated legacy tests fail; the `disposalRequired` flag → the
`disposalRequired` assertion in *keeps the group-level error list readable*
fails.

## Defect 3 — a closing `LiteScope` waiting on a screenshot that never arrives

`lib/src/scope/g_lite_scope/lite_scope_core.dart`

**Reproduced.** `notifyDependents()` sets `_shouldOnlyNotify` and marks the
element dirty. On the next `performRebuild`, `_shouldOnlyNotify` survives
(`!autoSelfDependence && !_forceRebuild`, and `buildOnReady()` has already
cleared `_autoSelfDependence`), so `updateChild` returns the old child and the
widget `buildOnReady()` just built — the one carrying the `ScreenshotReplacer`
— is thrown away. `close()` had installed the barrier on
`mounted && state is AsyncScopeReady`, the `markNeedsBuild()` in
`_runAsyncDispose` was a no-op on an already-dirty element, and a scope closed
in place stays mounted, so the `dispose()` fallback never ran. `close()` never
came back.

The probe calls `notifyDependents()` and then `close()` with no frame in
between, and asserts on the effect — whether the returned future settles — not
on elapsed time. The control test, the same shape without the
`notifyDependents()`, finds the `ScreenshotReplacer` on the closing frame and
settles, so the harness is known to detect the correct behaviour.

**Fix.** The closing frame sets `_forceRebuild` before `markNeedsBuild()`, but
only when a barrier is actually installed, so the notify-only path of a scope
that takes no screenshot is unchanged. `notifyClients` still runs, so the
pending notification is delivered.

Tests (`test/lite_scope_test.dart`):

* `control: a plain close() mounts the ScreenshotReplacer`
* `completes when a pending notifyDependents() would skip the subtree the
  closing frame has to rebuild`

## TODO.md

Removed exactly the three entries closed here:

* `AsyncScopeElementBase: окно между enter() и присвоением _subscription …`
* `ScopeAutoDependencies: _root не сбрасывается после dispose() …`
* `LiteScope: markNeedsBuild при _shouldOnlyNotify …`

Nothing was added; the `subscription.cancel()` concern noted under defect 1 is
recorded here and in the surviving source comment only.

