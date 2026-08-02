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
