# Final fix-wave report — pre-merge review of the coordinator redesign

> **Состояние на 2026-08-12:** замечания закрыты, редизайн смержен в `main` (12b4c9f); часть найденного здесь довели уже после мержа — см. `2026-08-01[1]-cross-review-fixes-report.md`. Исторический документ, не поддерживается.
> **Что это:** отчёт предмержевого ревью редизайна координации.
> **Связанные записи:** план — `2026-07-31[2]-async-scope-coordinator-plan.md`, задачи — `2026-07-31[3]-async-scope-coordinator-log.md`.

One commit on top of `e9acbca`, branch `coordinator`, worktree
`/Users/user/development/my/scopo/.claude/worktrees/coordinator` (the hash of
the fix-wave commit itself cannot be written into a file that is part of it).

Result: `flutter analyze` → 0 issues in the root package, in `example/minimal`
and in `example/scopo_demo`. `flutter test` → **59 passed** (55 before + 4
new). `dart format` → clean on `lib` and `test`. `dart doc` → **0 warnings, 0
errors**. `flutter pub publish --dry-run` → **0 warnings**.

Rejected by the controller and therefore not done: the reviewer's
`isWaitRootFallback` member on `AsyncScopeParent` (a public member on a public
mixin for an internal rule). The private `is _AsyncScopeCoordinatorElement`
check in `_registerWithParent` and its comment stay as they are.

---

## IMPORTANT 1 — CHANGELOG 0.10.0

`CHANGELOG.md`, `## 0.10.0`, the coordinator bullet. Four sub-bullets added
under the existing text; no historical section touched (the `asyncScopeRoot`
mentions under `## 0.6.1`/`## 0.6.2` are release history and stay).

- **Migration**: `asyncScopeRoot.waitForChildren()` →
  `AsyncScopeCoordinator.waitForChildren(context, {timeout, onTimeout})`, with
  its two defaults spelled out.
- `AsyncScopeCoordinator.enter` is no longer public.
- `AsyncScopeParent.registerChild` is no longer public, with the note that it
  was a public member of a public mixin, so code that mixed the mixin in and
  called or overrode `registerChild` no longer compiles; `hasChildren`,
  `childrenCount` and `waitForChildren` stay public.
- **Silent behaviour change** (the line the design doc required — see
  `docs/superpowers/specs/2026-07-31-async-scope-coordinator-design.md`,
  "Ошибки и краевые случаи"): a scope with neither a parent scope nor a
  coordinator above it now registers nowhere, so nothing awaits its disposal;
  the code keeps compiling unchanged and behaves differently. The fix (put an
  `AsyncScopeCoordinator` above them and await
  `AsyncScopeCoordinator.waitForChildren(context)`) is named on the spot.

Since 0.9.6 is the last published version, every one of these was public API a
user is on today.

## IMPORTANT 2 — the public `waitForChildren` no longer waits forever

`lib/src/scope/e_async_scope/async_scope_coordinator.dart`. The static helper
now resolves both of its optional parameters instead of passing `null` down:

- `timeout ?? ScopeConfig.defaultWaitForChildrenTimeout` — the same expression
  every internal wait uses (`async_scope_core.dart:343`,
  `waitForChildrenTimeout ?? ScopeConfig.defaultWaitForChildrenTimeout`).
  Removing the limit entirely is now a `ScopeConfig` decision, not a per-call
  one; that is stated in the dartdoc.
- `onTimeout ?? (report through FlutterError.reportError, library: 'scopo')` —
  so an expiry is never silent. The reported `TimeoutException` is rebuilt with
  the coordinator's own name in front of the registry's message, exactly the
  way `_performAsyncDispose` does it for a scope (the registry message knows
  nothing about the widget tree).

Both defaults are documented in the dartdoc of the method, together with the
policy itself (an expiry is not fatal: the children left behind are dropped and
the future completes normally).

`README.md`, the `scopeKey` section: the snippet used to present
`await AsyncScopeCoordinator.waitForChildren(context)` as an unqualified wait.
A paragraph after it now says what it awaits (the scopes registered at the
moment of the call), that it is bounded by `timeout` or by
`ScopeConfig.defaultWaitForChildrenTimeout`, and that an expiry completes the
future normally and is reported through `FlutterError.reportError` unless
`onTimeout` is given.

## IMPORTANT 3 — tests for the one new public API

`test/async_scope_coordinator_test.dart`, two `testWidgets`, both on the
existing `_TestScope`/`_TestScopeElement` fixtures and the existing `_settle`
helper.

New fixture field: `_TestScope.disposeGate` (a `Completer<void>` awaited at the
top of `disposeAsync`). A gate, not a long `disposeDelay`, because a timer that
outlives the widget tree fails the test in the binding.

**`waitForChildren completes only after disposeAsync has finished`** — a
coordinator over a `Column` holding the scope and a `Builder` that captures a
context which survives the scope's removal. The scope is removed, then
`waitForChildren(context)` is started: it must not complete while the gated
`disposeAsync` is still running, and must complete right after the gate opens.
Also asserts `childrenCount` 1 before and 0 after.

> Evidence: moved `_asyncScopeParentEntry?.unregister()` in
> `async_scope_core.dart` from the `finally` block to just before the `try`
> (i.e. unregister before `disposeAsync` instead of after) →
> `expect(waited, isFalse, reason: 'disposeAsync has not finished yet')` fails
> at line 302, `Expected: false / Actual: <true>`. Restored by hand; the file
> is byte-identical to `e9acbca` (`git diff` on it is empty).

**`waitForChildren without a coordinator is an error`** — a `Builder` context
with no coordinator above it; the call must throw a `FlutterError` whose text
contains ``No `AsyncScopeCoordinator` `` (it throws synchronously, before the
future is created, so `throwsA` on the closure is enough).

> Evidence: changed `_elementOf`'s `?? (throw FlutterError(…))` to
> `?? (throw StateError(…))` → the test fails at line 329 on the `isA<
> FlutterError>` matcher. Restored by hand.

## IMPORTANT 4 — the timeout reporting is pinned at both call sites

`FlutterError.reportError` lives in the two `onTimeout` callbacks that
`async_scope_core.dart` passes to the core; the core itself is silent by
design. Two `testWidgets` now fail if either callback stops reporting. Both set
the relevant `ScopeConfig` default to 50 ms; a `tearDown` restores both
defaults from values captured at library load, so the tests cannot leak into
the rest of the suite.

**`an expired wait for a scopeKey is reported`** (the `scopeKey` path) — two
scopes with the same key under one coordinator; the first never releases the
key, so the second times out. Asserts `tester.takeException()` is a
`TimeoutException` whose message contains
`couldn't wait to get access to [shared]`, and that the scope that timed out
was let in anyway (`initialized == 2`).

> Evidence: deleted the `FlutterError.reportError(…)` call from the `onTimeout`
> of the `scopeKey` wait (leaving `onScopeKeyTimeout()`) → the test fails at
> line 365 (`takeException()` is `null`, so `isA<TimeoutException>` fails).
> Restored by hand.

**`an expired wait for children is reported`** (the children path) — a parent
scope over a gated child; the parent's wait for children expires, it disposes
of itself alone (`disposalOrder == ['parent']`), and the reported
`TimeoutException` says `couldn't wait for the children to complete`. The gate
is opened at the end so the child finishes and leaves no pending work behind.

> Evidence: deleted the `FlutterError.reportError(…)` call from the `onTimeout`
> of the children wait (leaving `onWaitForChildrenTimeout()`) → the test fails
> at line 411 the same way. Restored by hand; `async_scope_core.dart` is
> byte-identical to `e9acbca`.

`tester.takeException()` turned out to be reliable for both — unlike the
`FlutterError` thrown out of `mount()` (the pre-existing
`runZonedGuarded` test), a reported error goes through `FlutterError.onError`,
which the test binding parks for `takeException()`.

## MINOR

- **`doc/i_debug.md`** — the `debug` paragraph no longer claims the package
  logs "the queues of the `AsyncScopeCoordinator`" (those two `_log.d` lines
  were deliberately dropped in Task 1 and the core library has no logging at
  all). The rest of the sentence is unchanged.
- **`scope_coordination.dart`, `ChildRegistry.waitForChildren`** — "Completes
  once every registered child has unregistered" → "Completes once the children
  registered at the time of the call have unregistered", plus a sentence saying
  the children are snapshotted when the wait starts. The same over-promise was
  in the dartdoc of the *public* `AsyncScopeParent.waitForChildren`, so it is
  reworded there too — that is the copy users read, and it is the same claim.
- **`README.md`, `scopeKey` section** — a sentence that the queues belong to
  the coordinator's element, so serialization holds only across a stable
  coordinator: replacing the coordinator itself (a different `ValueKey`, a
  different position) throws its queues away with it, which is why it belongs
  above anything replaceable.
- **`TODO.md:14`** — `async_scope_core.dart:279` → `:326`. Verified:
  `grep -rn TODO lib` reports exactly one `TODO(nashol)`, at line 326.
- **`TODO.md`, "Известные проблемы (0.10.x)"** — new entry: the post-frame
  registration checks `mounted` but not `_isDisposing`, so a scope closed via
  `close()` before its first frame can register a `ChildEntry` nobody
  unregisters; with the redesign it lands on the coordinator's registry instead
  of a process-global root, but it can still burn the whole wait-for-children
  timeout.
- **`test/async_scope_coordinator_test.dart`, the no-coordinator test** — a
  second assertion that the message also explains the `scopeKey` case, so the
  body of the error text is pinned, not only its first line.

  > Evidence: deleted the sentence "A scope with a `scopeKey` needs it to be
  > coordinated with the other scopes that share the key." from the
  > `FlutterError` → the test fails at line 88 on the new
  > ``contains('`scopeKey`')``. Restored by hand.

- **`test/scope_coordination_test.dart`, the queue-timeout test** — after the
  timeout fires, two assertions: the timed-out entry is still not completed,
  and `queues.length` is still 1. "A timed-out entry keeps its slot, so `exit()`
  is still required" is load-bearing: `async_scope_core.dart` calls `exit()`
  unconditionally in its `finally`.

  > Evidence, two hand-reverts of `_AccessQueue.enter`'s
  > `on TimeoutException` branch. (1) release the slot the way `_exit` does
  > (remove the entry, complete its completer) → `expect(second.isCompleted,
  > isFalse)` fails, `Expected: false / Actual: <true>`. (2) drop the queue
  > (`_entries.clear(); onEmpty?.call();`) without completing the entry →
  > `expect(queues.length, 1)` fails, `Expected: <1> / Actual: <0>`. Both
  > restored by hand.

## Verification

```
flutter analyze                       # root:            No issues found!
flutter analyze  (example/minimal)    #                  No issues found!
flutter analyze  (example/scopo_demo) #                  No issues found!
flutter test                          # 59 passed (55 before + 4 new)
dart format --output=none --set-exit-if-changed lib test   # clean
dart doc --output <scratchpad>/dartdoc-finalfix            # 0 warnings, 0 errors
flutter pub publish --dry-run                              # 0 warnings
```

No hand-revert survived: `grep -rn HAND-REVERT lib test` is empty, and
`git diff` against `e9acbca` touches only `CHANGELOG.md`, `README.md`,
`TODO.md`, `doc/i_debug.md`, `async_scope_coordinator.dart`,
`async_scope_parent.dart`, `scope_coordination.dart` and the two test files —
`async_scope_core.dart` is untouched by this wave.

---

# Fix wave 2 — findings of the scoped re-review of `3374917`

Second commit on top of `3374917`. `flutter test` → **61 passed** (59 + 2 new);
`flutter analyze` → 0 in the root and both examples; `dart format` clean;
`dart doc` → 0 warnings, 0 errors; `flutter pub publish --dry-run` → 0
warnings.

## CRITICAL — the default `onTimeout` read `element.widget` at expiry time

`lib/src/scope/e_async_scope/async_scope_coordinator.dart`. The closure
captured the element and formatted its name when the timeout *fired*.
`Element.unmount()` nulls `_widget`, so once the coordinator had left the tree
the read threw `Null check operator used on a null value` out of the
`on TimeoutException` block of `ChildRegistry.waitForChildren` — which
completed the caller's future *with an error* (both the dartdoc and the README
promise normal completion), skipped the `FlutterError.reportError` that
Important 2 exists for, and skipped `_children.clear()`, so a second wait would
re-hang on dead children. The prefix pattern was copied from
`_performAsyncDispose` without the thing that makes it safe there:
`AsyncScopeElementBase` deliberately keeps `_widget` alive across its
asynchronous disposal (`async_scope_core.dart:71-74`); the coordinator has no
equivalent.

Fix: read the name once, eagerly, while the element is still mounted, and
capture the `String`:

```dart
final element = _elementOf(context);
final name = element.widget.toStringShort(showHashCode: true);
...
exception: TimeoutException('$name ${error.message}', error.duration),
```

The comment that used to sit inside the closure moved up to the read and now
also says *why* it is read there.

## Two new tests pin the defaults (and the fix)

Both in `test/async_scope_coordinator_test.dart`, both on the existing
fixtures. Their shared tree — a coordinator over an optional gated scope plus a
`Builder` whose context outlives that scope — is now the file-level helper
`_coordinatorTree`, which the earlier "completes only after disposeAsync has
finished" test uses as well.

**`waitForChildren gives up on time and reports the expiry`** — the coordinator
stays mounted while a gated scope burns
`ScopeConfig.defaultWaitForChildrenTimeout` (50 ms in the test). The call
passes neither `timeout` nor `onTimeout`: both defaults are what is under test.
Asserts the future completes *normally* (an `onError` handler records anything
else), that the scope indeed never finished, and that `takeException()` is a
`TimeoutException` whose message starts with `AsyncScopeCoordinator`.

> Evidence, two hand-reverts of `waitForChildren`. (1) `timeout: timeout`
> (unbounded again) → fails at line 338, `Expected: true / Actual: <false>`,
> "the wait is bounded by ScopeConfig.defaultWaitForChildrenTimeout". (2)
> `onTimeout: onTimeout` (silent again) → fails at line 351,
> `Expected: <Instance of 'TimeoutException'> / Actual: <null>`, "an expiry is
> reported even without an onTimeout callback". Both restored by hand.

**`waitForChildren reports an expiry that outlives the coordinator`** — the
wait is started, then the *whole* tree is pumped away (the documented "before
tearing down a test" case), so the coordinator's element is unmounted when the
timeout fires. Same assertions: normal completion plus the prefixed report.

> Evidence: restored the expiry-time read (`String name() =>
> element.widget.toStringShort(...)`, called from inside the closure) → fails
> at line 405, `Expected: null / Actual: _TypeError:<Null check operator used
> on a null value>` — the reviewer's repro, surfacing exactly as a future that
> completed with an error. Restored by hand.

> **Correction to the brief.** The re-review said the mounted-coordinator test
> would also fail against the unmounted-crash variant. It does not: with the
> coordinator still mounted, `element.widget` resolves fine and that test
> passes green under the reverted read (verified — the run is clean, `+1 All
> tests passed`). The crash is only reachable once the element is gone, which
> is why the second test above exists. Without it the critical fix would be
> unpinned.

## MINOR — the `ScopeConfig` save/restore was lazy

`test/async_scope_coordinator_test.dart`. The two top-level `final`s
initialized on first *read*, i.e. inside the first `tearDown`, which was safe
only because the two tests that mutate `ScopeConfig` happened to be last in the
file; moving either one earlier would have captured the 50 ms value as
"pristine" and turned the restore into a no-op leaking into every later test.
They are now locals captured eagerly in `setUpAll`, with a comment naming the
trap.
