# Task 5 report: dispose/init hang on empty concurrent stream set

## Commit

`f6e8cda` — "fix hang on empty concurrent stream set"

Files changed:
- `lib/src/scope/h_scope/scope_auto_dependency/scope_dependency/scope_dependency_group.dart`
- `test/scope_auto_dependencies_test.dart`

## Bug

`_mergeStreams()` (extension on `Iterable<Stream<T>>`, used by both `_ScopeDependencyConcurrent.init()` and `.dispose()`) had two defects in its `onListen`:

1. On an empty iterable, the `for (final stream in this)` loop never runs, so `controller.close()` is never called — the returned stream (and everything awaiting it, transitively `ScopeAutoDependencies.dispose()`'s `completer.future`) never completes.
2. `subscription.onDone(...)` was wired immediately after each `stream.listen(...)` call but *before* `subscriptions.add(subscription)`. For a synchronously-completing child stream (e.g. a nested empty concurrent group, once fixed for defect 1, closes its `sync: true` controller synchronously inside `onListen`), the `done` event fires before the handler is attached and is silently dropped, or `subscriptions.remove(subscription)` runs against a list state one entry short — same class of hang/race.

Reachability: `_ScopeDependencyImpl.disposalRequired` is `state is ScopeDependencyInitialized && _helper?.dispose != null`. If a dependency's init callback never sets `dep.dispose`, it's Initialized but not disposal-required. `_ScopeDependencyConcurrent.dispose()` filters children with `.where((dep) => dep.disposalRequired)` before merging — a concurrent group whose children all skip `dep.dispose` produces an empty stream set, hitting defect 1 directly via `ScopeAutoDependencies.dispose()`.

## Fix

In `_mergeStreams()`'s `onListen`:
- Added an `if (isEmpty) { controller.close(); return; }` guard at the top (with the existing `// ignore: discarded_futures` convention used elsewhere in the same file, since `discarded_futures` is an enabled lint).
- Restructured to two loops: first collect all subscriptions into the list, then attach `onDone` handlers in a second loop — guaranteeing `subscriptions` is fully populated before any `onDone` callback can fire.

Diff (lib):
```dart
controller.onListen = () {
  if (isEmpty) {
    controller.close(); // ignore: discarded_futures
    return;
  }

  final subscriptions = <StreamSubscription<T>>[];

  for (final stream in this) {
    final subscription =
        stream.listen(controller.add, onError: controller.addError);
    subscriptions.add(subscription);
  }

  for (final subscription in subscriptions) {
    subscription.onDone(() {
      subscriptions.remove(subscription);
      if (subscriptions.isEmpty) {
        controller.close(); // ignore: discarded_futures
      }
    });
  }

  controller
    ..onPause = ...
```

## Test

Added `TestDependenciesConcurrentNoDispose` (root `ScopeDependency` is directly a `concurrent('g', [dep('depA', ...), dep('depB', ...)])`, neither `initDep` sets `dep.dispose`) and a new test:

`concurrent group with empty stream set > dispose completes when no child requires disposal` in `test/scope_auto_dependencies_test.dart`.

The test brings the dependencies to Ready via the existing `handleInitFor` helper (Task-1 helper, reused as-is), then calls `dependencies.dispose()` unawaited with a `disposed` completion flag, drives the fake-async event loop with `async.flushMicrotasks()`, and asserts `disposed` is `true`. This avoids calling `async.waitFuture()` directly on the hung `dispose()` future (which would throw `StateError('No more timers...')` from `MyFakeAsync._waitFutureResult` instead of demonstrating the actual hang), matching the brief's sketch pattern.

### Failing run (pre-fix, lib change stashed via `git stash push -- lib/.../scope_dependency_group.dart`)

```
00:00 +0 -1: concurrent group with empty stream set dispose completes when no child requires disposal [E]
  Expected: true
    Actual: <false>
```

### Passing run (post-fix, `git stash pop`)

```
00:00 +1: All tests passed!
```

## Full verification (post-fix)

- `flutter test`: `00:00 +39: All tests passed!` (38 baseline + 1 new).
- `flutter analyze`: exactly the same 3 pre-existing issues as baseline, no new issues introduced:
  - `invalid_annotation_target` — `example/scopo_demo/lib/home/demos/c_scope_notifier/scope_notifier_example2.dart:91:4`
  - `avoid_classes_with_only_static_members` — `lib/src/environment/scope_config.dart:7:22`
  - `unnecessary_this` — `lib/src/scope/h_scope/scope_auto_dependency/scope_auto_dependency.dart:25:36`

## Decisions / notes

- Kept the fix minimal and in the existing style (comments in Russian matching the surrounding file, same `// ignore: discarded_futures` convention).
- Root of the test's dependency tree is the concurrent group itself (not nested under a `sequential(...)` wrapper), so `ScopeAutoDependencies.dispose()` calls `dependencies.runDispose()` directly on the concurrent group — this exercises the exact reported path (top-level empty concurrent stream set) without needing to reach through additional layers.
- Did not add a second test explicitly targeting defect 2 (the nested synchronous-completion ordering race) since the brief only requested one failing test for the reported hang (defect 1), and the flat 2-leaf-dependency test never enters the `for` loop body at all (guarded by the `isEmpty` check), so it doesn't exercise defect 2. Defect 2 was still fixed per the brief's explicit instruction, since it's fully described and located in the same code block and only becomes reachable once nested empty concurrent groups exist after the defect-1 fix.
- Left the untracked `docs/` directory in the worktree untouched — unrelated to this task, not staged or committed.
