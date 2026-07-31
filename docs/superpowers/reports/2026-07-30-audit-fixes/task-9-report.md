# Task 9 Report: swallowed disposal errors + AsyncScopeError.toString parenthesis bug

## Status: PASS

## Changes

### 1. `lib/src/scope/e_async_scope/async_scope_state.dart` (~line 53)

Confirmed constructor signature first: `AsyncScopeError(this.error, this.stackTrace, {this.progress});` — positional `error`, `stackTrace`, named optional `progress`.

Root cause: the old `toString()` had a stray `)` baked into the ternary's non-null branch *and* another `)` outside the interpolation, so the `progress != null` case emitted two closing parens for one opening paren:

```dart
// before
String toString() => '$AsyncScopeError($error, $stackTrace'
    '${progress == null ? '' : ', progress: $progress)'})';
```

Fixed by moving the closing paren out of the ternary's non-null branch (matches the brief exactly):

```dart
// after
String toString() => '$AsyncScopeError($error, $stackTrace'
    '${progress == null ? '' : ', progress: $progress'})';
```

Now both branches (`progress == null` and `progress != null`) produce exactly one `(`/`)` pair.

### 2. `lib/src/scope/h_scope/scope_auto_dependency/scope_auto_dependency.dart` (~line 67)

`dispose()`'s `dependencies.runDispose().listen(...)` had `onError: (Object e) {}` — disposal errors vanished silently. Checked `ScopeLogFn` in `lib/src/environment/scope_logger.dart`: `bool Function(Object? message, {Object? error, StackTrace? stackTrace})`, and the file's existing `_log.d(...)` usage style. Changed to:

```dart
onError: (Object error, StackTrace stackTrace) {
  _log.e('dispose error', error: error, stackTrace: stackTrace);
},
```

Kept the two-argument `(Object error, StackTrace stackTrace)` signature since `StreamSubscription.onError` requires it to match what the stream can throw, and passed both through to `_log.e` per its named-parameter signature.

## Tests

Added `test/async_scope_state_test.dart` (new file) with two cases (brief only asked for the `progress != null` case per its Step 1 snippet; added the `progress == null` case too as a quick regression guard since the old code was accidentally balanced in that branch):

```dart
test('balanced parens without progress', () { ... });
test('balanced parens with progress', () { ... });
```

Both assert `'('.allMatches(s).length == ')'.allMatches(s).length`. Both pass against the fixed code.

For the `onError` logging fix: did **not** add a new log-emission test. Per the brief's "minimum: log" framing and the task instructions calling this optional, I instead verified there is no dispose-path test in `test/scope_auto_dependencies_test.dart` that ever makes `dep.dispose()` throw — grepped `dispose = \|dispose:` and `throw\|Exception` across the file; all throwing scenarios (`dep5`, `dep6`, `dep7`, `depB`, etc.) are **init**-phase failures (`initDep` throws before assigning `dep.dispose`), never disposal-phase failures. So the `onError` callback in `ScopeAutoDependencies.dispose()` is never exercised by the existing suite either before or after the change — confirmed via full `flutter test` run showing identical pass count/behavior, no new failures, no behavior change for any existing scenario. Adding a synthetic dispose-throwing dependency + `ScopeConfig.logger`/`test/utils/logging.dart` capture just to test this one log call was judged not worth the added test-infrastructure churn for this small, narrowly-scoped task; flagging this as the one open item below.

## Verification

- `flutter test test/async_scope_state_test.dart`: 2/2 pass.
- `flutter test` (full suite): **54/54 pass** (52 baseline + 2 new).
- `flutter analyze`: **3 issues**, identical to baseline (unrelated pre-existing items in `example/scopo_demo/...`, `scope_config.dart:7`, `scope_auto_dependency.dart:25` — none touch the lines changed by this task).

## Commit

- Only `lib/src/scope/e_async_scope/async_scope_state.dart`, `lib/src/scope/h_scope/scope_auto_dependency/scope_auto_dependency.dart`, and the new `test/async_scope_state_test.dart` were staged and committed.
- An untracked `docs/superpowers/` directory was present in the worktree before this task started (unrelated artifact) and was deliberately left untouched/unstaged.
- Commit hash: `2120927f3e92117ead41a694cf0cd367cf61f7d9`
- Message: `log disposal errors, fix AsyncScopeError.toString`

## Concerns

- No direct unit test exercises the new `_log.e('dispose error', ...)` call path (no existing fixture makes a dependency's `dispose()` throw). Behavior is correct by inspection and signature-matches `ScopeLogFn`, and the change is behavior-neutral for all currently passing tests, but the log emission itself is unverified by an automated test. Flagging for whoever reviews/closes out this task in case they want a dedicated regression test added later.
