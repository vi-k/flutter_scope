# Task 3 report — the coordinator owns the queues and the wait root

Commit: `00b1460` — `refactor: make the coordinator own the queues and the wait root`
(parent `fc5c0f4`). Branch `coordinator`, worktree
`/Users/user/development/my/scopo/.claude/worktrees/coordinator`.

Result: `flutter analyze` → 0 issues in the root package **and** in
`example/minimal` and `example/scopo_demo`. `flutter test` → **51 passed**
(46 before + the 5 new widget tests).

---

## Step 1-2: the five widget tests, written first, run before touching `lib/`

`flutter test test/async_scope_coordinator_test.dart` on the untouched `lib/`:
**0 passed, 5 failed.** The brief predicted 2 failures; all 5 failed. Two of
them for the reason the brief named, three for reasons that turned out to be
about the *test framework*, not about our code (details and fixes below).

| # | test | before `lib/` changes | after |
| - | ---- | --------------------- | ----- |
| 1 | two coordinators do not share a key | FAIL `Expected: <2> Actual: <1>` | PASS |
| 2 | the nearest coordinator serves the key | FAIL `Expected: <2> Actual: <0>` | PASS |
| 3 | a scopeKey without a coordinator is an error | FAIL `takeException()` → `null` | PASS (test rewritten, see D-2) |
| 4 | a parent scope waits for the scope below it | FAIL `Expected: ['child','parent'] Actual: []` | PASS (test rewritten, see D-3) |
| 5 | a scope with no parent and no coordinator disposes cleanly | FAIL `Expected: ['lonely'] Actual: []` | PASS (test rewritten, see D-3) |

Notes on the "before" evidence:

- **#1** `initialized == 1`: with the process-wide `static _queues`, the second
  scope queued behind the first one even though it lived under a different
  coordinator, and it was still waiting when the test asserted. Exactly the
  defect the redesign removes.
- **#2** `initialized == 0`: worse than #1, and a second symptom of the same
  cause — the static map survives *between tests*, so the entry test #1 left
  behind (its scope was never disposed of before the test ended) kept the key
  `'shared'` held, and even the *first* scope of test #2 was made to wait.
  After the fix each `_AsyncScopeCoordinatorElement` owns its own
  `KeyedAccessQueues`, which dies with the element, and the tests are
  independent.

---

## Steps 3-6: the rewiring (as specified)

- **`lib/src/scope/e_async_scope/async_scope_parent.dart`** — rewritten verbatim
  from the brief. `ScopeChildEntry` deleted; the mixin now delegates to
  `ChildRegistry` and `waitForChildren` takes `timeout`/`onTimeout`.
- **`lib/src/scope/e_async_scope/async_scope_coordinator.dart`** —
  `_AsyncScopeCoordinatorElement` mixes in `AsyncScopeParent` and holds
  `final _queues = KeyedAccessQueues()` (per-instance, **not** static — binding
  controller decision 1). `AsyncScopeCoordinatorEntry` and
  `_AsyncScopeCoordinatorQueue` deleted wholesale (including the dead
  `close()`). New private static `_elementOf(BuildContext)` holds the single
  copy of the `maybeOf(...) ?? throw FlutterError(...)` lookup; the `FlutterError`
  text is byte-identical to the old one. `enter` now takes an `AccessEntry` and
  the richer `onTimeout` signature; new static `waitForChildren(context, …)`.
- **`lib/src/scope/e_async_scope/async_scope_root.dart`** — `git rm`'d.
- **`lib/src/scope/scope.dart`** — `part 'e_async_scope/async_scope_root.dart';`
  removed, `import 'e_async_scope/scope_coordination.dart';` added.
- **`lib/src/scope/e_async_scope/async_scope_core.dart`** — fields retyped to
  `AccessEntry`/`ChildEntry`; `(parent ?? asyncScopeRoot).registerChild(…)` →
  `parent?.registerChild(…)`; both timeout call sites now always pass a
  reporting callback (controller decision 2); the manual
  `future.timeout` / `try` / `on TimeoutException` / `_children.clear()` block is
  gone. `_children` no longer appears anywhere outside `scope_coordination.dart`
  (verified by grep over `lib/`).

The two `_log.d('queue for [key] created/removed')` diagnostics were **not**
re-added, as instructed.

---

## Deviations

### D-1 — `waitForChildren` timeout message keeps the widget prefix (controller decision 4)

The brief's Step 6.5 snippet reports `error` as the core built it. The core's
message is `"couldn't wait for the children to complete: <children>"`, with no
widget context, whereas the old code prefixed
`widget.toStringShort(showHashCode: true)`. Per the binding controller decision,
the callback rebuilds the exception:

```dart
exception: TimeoutException(
  '${widget.toStringShort(showHashCode: true)} ${error.message}',
  error.duration,
),
```

`prefix + ' ' + core message` reproduces the old string exactly
(`_Widget(#abc) couldn't wait for the children to complete: [...]`), and
`error.duration` carries the timeout through unchanged. The `scopeKey` path
needs no such treatment: the `AccessEntry` debug name already *is* the widget's
short string, so the core's message is self-identifying and `error` is reported
as-is.

### D-2 — test #3 rewritten: the "no coordinator" error is an *uncaught zone error*, not a framework-reported one

**This is the framework being different from the brief's assumption, not our
code being wrong. The assertion was not weakened.**

`AsyncScopeCoordinator.enter` throws `FlutterError` synchronously inside the
`async` body of `_performAsyncInit`, which `mount()` starts and *discards*
(`// ignore: discarded_futures`). The error therefore never reaches the
framework's `_debugReportException`; it becomes an unhandled error of the zone
the mount ran in. `flutter_test`'s zone `handleUncaughtError`
(`packages/flutter_test/lib/src/binding.dart:1814-1910`) does **not** park it in
`_pendingExceptionDetails` — it reports it and immediately ends the test through
`testCompletionHandler`. Consequently `tester.takeException()` can never return
it: the observed run showed the test failing at `pumpWidget` and then a second
failure at the `expect` line marked *"running a test (but after the test had
completed)"*, with `takeException()` → `null`.

Rewrite: the mount runs inside `runZonedGuarded`, whose handler catches the
error first, and the test asserts on what was caught:

```dart
expect(errors, hasLength(1));
expect(errors.single, isA<FlutterError>());
```

That is strictly stronger than the original (it also pins that there is exactly
one error). Verified against the *unmodified* `lib/` in a scratch probe: the
guarded zone receives the "No `AsyncScopeCoordinator`" `FlutterError` while
`takeException()` returns `null`.

### D-3 — tests #4/#5 rewritten: `pumpAndSettle()` cannot drive the async disposal chain

**Also framework behavior, already documented in this repo. Assertions
unchanged.**

`_performAsyncDispose` awaits `subscription.cancel()` on the `async*` stream
returned by `initAsync()`. That future only completes on the *real* event loop;
`FakeAsync` microtask flushing and elapsing never complete it. Minimal repro
with no scopo code at all (scratch probe, since deleted):

```dart
final sub = gen().asyncMap((e) {}).listen((_) {}, cancelOnError: true);
unawaited(chain(sub));               // logs 'before cancel' / 'after cancel'
for (var i = 0; i < 5; i++) { await tester.pump(); }
// → [before cancel]                 (5 pumps change nothing)
await tester.runAsync(() => Future<void>.delayed(Duration.zero));
// → [before cancel, after cancel]
```

With scopo, the probe showed the log stopping at `prepare for disposal` through
`pumpWidget` + `pumpAndSettle`, and only reaching `dispose…` / `disposed` after
a `runAsync`. `pumpAndSettle` makes this worse than an ordinary pump loop: with
no frame scheduled it performs exactly **one** pump and returns.

This is a known constraint of this codebase, already written down in
`test/async_scope_test.dart:124-133` and `test/lite_scope_test.dart:364-383`
(which carries a `_settle` helper for precisely this). Both tests now use a
local `_settle` of the same shape, interleaving real time with fake time so the
`Duration(milliseconds: 50)` `disposeDelay` (a *fake* timer, created inside the
fake zone) also fires:

```dart
for (var i = 0; i < 20 && !until(); i++) {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
  await tester.pump(const Duration(milliseconds: 10));
}
```

The assertions are untouched — still the exact
`expect(disposalOrder, ['child', 'parent'])` and
`expect(disposalOrder, ['lonely'])`, plus `expect(tester.takeException(), isNull)`.

### D-4 — the test fixture uses `super.child` instead of declaring its own `child`

The brief's fixture declares `final Widget child;` on `_TestScope`. `ProxyWidget`
(via `InheritedWidget` → `ScopeInheritedWidget`) already declares `child`, so the
analyzer flagged `overridden_fields` + `annotate_overrides`. Fixed by taking the
inherited one, whose default `ScopeInheritedWidget` sets to `_NullWidget()`:

```dart
const _TestScope({
  this.testKey,
  this.disposeLabel,
  this.disposeDelay = Duration.zero,
  super.child = const SizedBox.shrink(),
});
```

`buildOnState` still returns `widget.child` and the widget stays `const`.
No behavioral difference.

---

## Observations for Task 4 (not acted on here)

1. **`AccessEntry` / `ChildEntry` are no longer part of the package's public
   API.** `scope_coordination.dart` is `import`ed by `scope.dart`, not exported
   from `lib/scopo.dart` — which is what the design doc calls for
   (`docs/superpowers/specs/2026-07-31-async-scope-coordinator-design.md:50,181,182`:
   "из публичного API уходит"). The consequence is that the still-public
   `AsyncScopeCoordinator.enter(context, key, entry, …)` cannot be *called* by a
   package consumer any more, because they cannot name or construct an
   `AccessEntry`. It remains reachable from inside the package
   (`async_scope_core.dart`), which is its only real caller. If that is not the
   intent, Task 4 should either export the coordination library or mark `enter`
   as internal.
2. **`AsyncScopeCoordinator.waitForChildren` has no caller yet.** It is the
   replacement for what `asyncScopeRoot` existed for (an app awaiting its
   top-level scopes) and is only exercised indirectly, through the mixin, by
   test #4. Worth a documented example.
3. **Stale docs mentioning the removed API**: `CHANGELOG.md:120` mentions
   `asyncScopeRoot`; `TODO.md:7-8,16` still lists this task's items as pending.

---

# Fix round — review of `00b1460`

Commit: `fff12ad` — `fix: keep a parent scope as the wait root when a coordinator sits below it`.

`flutter analyze` → 0 issues in the root package and in `example/minimal` and
`example/scopo_demo`. `flutter test` → **54 passed** (51 → 54; the
coordinator file went from 5 tests to 8).

## Critical — a coordinator below a scope shadowed that scope as the wait root

`_registerWithParent` stopped at the nearest ancestor carrying
`AsyncScopeParent`. Since `00b1460` gave the coordinator element that mixin, a
coordinator sitting *between* two scopes captured the child, and the parent
scope stopped waiting for it. This is the package's own demo shape
(`example/scopo_demo/lib/app/app.dart:65-79` wraps `MaterialApp` in a
coordinator *inside* the root `App` scope), and the "place it above
`MaterialApp`" advice in our error text pushes users straight into it.

Fixed as directed: walk past coordinators, remember the nearest one, keep
looking for a real scope, and fall back to the remembered coordinator only when
no scope ancestor exists (`async_scope_core.dart:175-196`). The dartdoc on
`AsyncScopeParent` already described exactly this, so it needed no change.

### Before / after, all four arrangements

Measured with a scratch probe (since deleted) that mounts each tree, reads the
coordinator's `childrenCount`, then unmounts and records the order in which
`disposeAsync()` completed. The child scope carries a 50 ms `disposeDelay`, so
a parent that fails to wait finishes first and the order inverts.

| # | arrangement | metric | at `00b1460` | after the fix | expected |
| - | ----------- | ------ | ------------ | ------------- | -------- |
| 1 | `Coordinator > Scope` | coordinator `childrenCount` | 1 | 1 | 1 |
| 1 | | disposal order | `[only]` | `[only]` | `[only]` |
| 2 | `Scope(parent) > Scope(child)` | disposal order | `[child, parent]` | `[child, parent]` | `[child, parent]` |
| 3 | `Scope(parent) > Coordinator > Scope(child)` | coordinator `childrenCount` | **1** | **0** | 0 |
| 3 | | disposal order | **`[parent, child]`** | **`[child, parent]`** | `[child, parent]` |
| 4 | bare `Scope`, no coordinator | disposal order / exception | `[lonely]` / `null` | `[lonely]` / `null` | `[lonely]` / `null` |

Only row 3 changed, and it changed in the intended direction. Rows 1, 2 and 4
are unchanged, which is the point: the fallback to the coordinator and the
"registers nowhere" case both survive.

### Regression tests added (3 new, 1 of 3 failing before the `lib/` fix)

- **`a coordinator between two scopes does not take the place of the parent`** —
  arrangement 3. Asserts both halves: `coordinator.childrenCount == 0` *and*
  `disposalOrder == ['child', 'parent']`. Before the fix it failed on the first
  assertion with `Expected: <0> Actual: <1>`.
- **`a scope with no parent scope registers with the coordinator`** —
  arrangement 1, the `asyncScopeRoot` replacement, now asserted directly
  (`coordinator.childrenCount == 1`) instead of only implied.
- **`a coordinator above a parent scope leaves the pair alone`** — the old
  `a parent scope waits for the scope below it` body, kept as-is under a name
  that says what it actually covers.

`a parent scope waits for the scope below it` was retargeted to arrangement 2
(the bare `Scope(parent) > Scope(child)` pair, no coordinator anywhere), which
no test covered before.

The coordinator's element is reached through the public part of its role:

```dart
AsyncScopeParent _coordinatorOf(WidgetTester tester) =>
    tester.element(find.byType(AsyncScopeCoordinator)) as AsyncScopeParent;
```

`_AsyncScopeCoordinatorElement` stays private; `AsyncScopeParent.childrenCount`
is already public.

## Defect 1 — the shared `_elementOf` error text assumed `scopeKey`

`_elementOf` is now also the lookup for `AsyncScopeCoordinator.waitForChildren`,
where `scopeKey` is irrelevant, so the leading sentence was made neutral and the
`scopeKey` note moved to the end, where it stays true for both entry points:

```
No `AsyncScopeCoordinator`.
The `AsyncScopeCoordinator` is missing in the context. Add it to the widget
tree so that all your scopes that need it can access it. The most universal
solution is to place it above `MaterialApp`. A scope with a `scopeKey` needs
it to be coordinated with the other scopes that share the key.
```

The first line is unchanged, so the test's `contains('No `AsyncScopeCoordinator`')`
assertion pins a stable prefix.

## Defect 2 — test #3 accepted any `FlutterError`

`a scopeKey without a coordinator is an error` now also asserts
`expect(errors.single.toString(), contains('No `AsyncScopeCoordinator`'))`,
so an unrelated `FlutterError` can no longer keep it green.

## Notes

- The "place it above `MaterialApp`" advice was kept. With this fix that shape
  is correct again: a coordinator above `MaterialApp` but below a root scope no
  longer steals the root scope's children.
- No change was needed in `example/scopo_demo`; it analyzes clean and its
  arrangement is now the one covered by the new regression test.
