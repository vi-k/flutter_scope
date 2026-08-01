# batch2 — five coordination/lifecycle defects, plus two found in review

Branch `coordfix`, based on `0fe8261`. Baseline: 69 tests green.
Final: **79 tests green**, `flutter analyze` clean in the package and both
examples, `dart format` clean, `dart doc` 0 warnings / 0 errors.

The five defects of the original brief are sections 1–5; the two issues a
review then found by execution — one of them a regression section 5
introduced — are sections 6–7, and the verification table at the end of that
part is the current one.

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

### Verification after the follow-up

| Check | Result |
| --- | --- |
| `flutter test` | 79 passed (69 baseline + 10 new) |
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
