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
