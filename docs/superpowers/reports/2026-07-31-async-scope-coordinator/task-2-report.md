# Task 2 report — ядро реестра детей

## Summary

Implemented `ChildRegistry`/`ChildEntry` in
`lib/src/scope/e_async_scope/scope_coordination.dart`, with the timeout for
waiting on children now owned by `waitForChildren` itself (registry cleared
only on timeout — mirroring the semantics currently split across
`AsyncScopeParent` and the timeout block in `async_scope_core.dart`, without
modifying either file). Applied the Task-1-review-driven `final class`
convention to all classes in the file, including the new ones. Committed as
`fc5c0f4`.

## TDD evidence

**Step 2 — tests fail first** (`flutter test test/scope_coordination_test.dart --name ChildRegistry`):

```
test/scope_coordination_test.dart:164:24: Error: Method not found: 'ChildRegistry'.
test/scope_coordination_test.dart:172:24: Error: Method not found: 'ChildRegistry'.
test/scope_coordination_test.dart:195:26: Error: Method not found: 'ChildRegistry'.
00:00 +0 -1: Some tests failed.
```

Confirms the group was absent from the implementation before Step 3, exactly
as expected.

**Step 4 — tests pass after implementation** (`flutter test test/scope_coordination_test.dart`):

```
00:00 +0: KeyedAccessQueues the first entry gets in immediately
00:00 +1: KeyedAccessQueues the second entry waits for the first to exit
00:00 +2: KeyedAccessQueues the queue is removed once the last entry exits
00:00 +3: KeyedAccessQueues entries are let in in the order they arrived
00:00 +4: KeyedAccessQueues cancelling stops the wait but keeps the place in the queue
00:00 +5: KeyedAccessQueues a timeout reports and lets the entry in anyway
00:00 +6: KeyedAccessQueues a key can be taken again after it was released
00:00 +7: KeyedAccessQueues different keys do not block each other
00:00 +8: ChildRegistry waiting with no children completes at once
00:00 +9: ChildRegistry waiting completes when every child has unregistered
00:00 +10: ChildRegistry a timeout reports and gives up on the children left
00:00 +11: All tests passed!
```

11/11 in this file (8 baseline `KeyedAccessQueues` + 3 new `ChildRegistry`).

**Full suite** (`flutter test`): `00:00 +46: All tests passed!` — 43 baseline
+ 3 new = 46, matches expectation.

**Analyze** (`flutter analyze`): `No issues found!` (0 issues, baseline
maintained).

**Format**: `dart format --output=none --set-exit-if-changed` on both
touched files reports 0 changed — already correctly formatted.

## `final class` conversion

Per the Task 1 review note, converted the plain `class` declarations to
`final class` (repo convention, 61 existing occurrences in `lib/`):

- `KeyedAccessQueues` → `final class KeyedAccessQueues`
- `AccessEntry` → `final class AccessEntry`
- `_AccessQueue` → `final class _AccessQueue`
- New `ChildRegistry` and `ChildEntry` were declared `final class` from the
  start.

Verified nothing subclasses any of these (only `scope_coordination_test.dart`
and, later, `AsyncScopeParent`/`async_scope_core.dart` in Task 3 reference
them) and the full suite plus analyze stayed green after the change.

## Deviation from the brief (and why)

The brief's Step-1 test code is verbatim except for one line, changed to
satisfy the repo's own lint config (`analysis_options.yaml:139` enables
`cascade_invocations`) and the "flutter analyze 0" baseline requirement,
which take priority over an incidental two-statement layout in the brief.

Brief's literal code:

```dart
final registry = ChildRegistry();
registry.registerChild('slow');
TimeoutException? reported;
```

Committed code:

```dart
final registry = ChildRegistry()..registerChild('slow');
TimeoutException? reported;
```

Reasoning: `flutter analyze` flagged this exact spot —
`test/scope_coordination_test.dart:196:9 • cascade_invocations` (info) —
because the statement right after `final registry = ChildRegistry();`
invokes a method on `registry` and discards the result, which is precisely
the pattern the enabled `cascade_invocations` lint targets (as verified by
testing: the same shape does not recur elsewhere in this file, e.g. the
`ChildRegistry` "unregistered" test assigns `registerChild`'s result to
`first`/`second` instead of discarding it, so it never trips the rule).
Folding the two lines into one cascade is behaviorally identical — same
call, same order, same registry — and is literally the fix the linter itself
suggests. No other line in the brief's code needed touching; `dart format`
made zero changes to either file after the edit.

No other deviations. `waitForChildren`'s timeout-only-clear behavior and the
`onTimeout` callback shape were implemented exactly as specified in Step 3,
and match the semantics of the current `async_scope_core.dart:320-347` /
`async_scope_parent.dart` code they will replace in Task 3 (success path:
every child already removes itself via `unregister`, so clearing only on the
`TimeoutException` branch is a no-op-preserving change, not a behavior
change).

## Files touched

- `/Users/user/development/my/scopo/.claude/worktrees/coordinator/lib/src/scope/e_async_scope/scope_coordination.dart`
- `/Users/user/development/my/scopo/.claude/worktrees/coordinator/test/scope_coordination_test.dart`

## Not touched (per instructions)

- `/Users/user/development/my/scopo/.claude/worktrees/coordinator/lib/src/scope/e_async_scope/async_scope_parent.dart`
- `/Users/user/development/my/scopo/.claude/worktrees/coordinator/lib/src/scope/e_async_scope/async_scope_core.dart`

These are Task 3's responsibility (rewiring `AsyncScopeParent` to delegate to
`ChildRegistry`/`ChildEntry` and moving the timeout call site).

## Commit

```
fc5c0f4 feat: add a child registry that owns its wait timeout
```
