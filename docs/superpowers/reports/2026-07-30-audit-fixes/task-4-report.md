# Task 4 Report: `CompareUtils.identical` infinite recursion

## Status: DONE

Commit: `f277ab9` — "fix infinite recursion in CompareUtils.identical"
Files: `lib/src/utils/compare_utils.dart`, `test/compare_utils_test.dart`

## Context / handoff note

Picked up mid-task from a prior implementer that was killed by an API error.
State found in the worktree:

- `test/compare_utils_test.dart` was already created and matched the brief — kept as-is.
- `lib/src/utils/compare_utils.dart` had a **half-applied, broken** fix:
  ```dart
  import 'dart:core' as core;
  // ...
  static bool identical(Object? a, Object? b) => core.identical(a, b);
  static bool notIdentical(Object? a, Object? b) => !core.identical(a, b);
  ```
  A prefix-only explicit `dart:core` import suppresses the implicit unprefixed
  `dart:core` import, which undefines `Object`/`bool` in the file. This was
  confirmed conceptually (and is exactly why the corrected two-import approach
  below is needed) — the fix was corrected before ever re-running analyze in
  that broken state, per the controller's resolution.

The brief's own Step 2 snippet (`import 'dart:core' as core;` alone) is the
same flawed pattern — it was not usable verbatim. Used the controller-provided
resolution instead: keep the qualified `core.identical` calls, but restore the
default (unprefixed) `dart:core` namespace by adding both imports.

## Step 1 — TDD evidence: failing test on original recursive code

Backed up the (broken, half-applied) working-tree file, then ran
`git checkout -- lib/src/utils/compare_utils.dart` to restore the last
committed version, which contains the original bug (unqualified `identical`
call inside the static method of the same name resolves to itself):

```dart
// ignore: avoid_classes_with_only_static_members
abstract final class CompareUtils {
  static bool equals(Object? a, Object? b) => a == b;

  static bool notEquals(Object? a, Object? b) => a != b;

  static bool identical(Object? a, Object? b) => identical(a, b);

  static bool notIdentical(Object? a, Object? b) => !identical(a, b);
}
```

Ran `flutter test test/compare_utils_test.dart`:

```
00:00 +0: loading /Users/user/development/my/scopo/.claude/worktrees/audit-fixes/test/compare_utils_test.dart
00:00 +0: CompareUtils.identical does not recurse
00:00 +0 -1: CompareUtils.identical does not recurse [E]
  Stack Overflow
  package:scopo/src/utils/compare_utils.dart 7:3   CompareUtils.identical
  package:scopo/src/utils/compare_utils.dart 7:50  CompareUtils.identical
  package:scopo/src/utils/compare_utils.dart 7:50  CompareUtils.identical
  ... (repeats hundreds of times) ...
  test/compare_utils_test.dart 7:25                main.<fn>

00:00 +0 -1: Some tests failed.

Failing tests:
  /Users/user/development/my/scopo/.claude/worktrees/audit-fixes/test/compare_utils_test.dart: CompareUtils.identical does not recurse
```

Confirms the expected `StackOverflowError` from infinite recursion at
`compare_utils.dart:7` (`CompareUtils.identical`).

## Step 2 — Applied fix

```dart
import 'dart:core';
import 'dart:core' as core;

// ignore: avoid_classes_with_only_static_members
abstract final class CompareUtils {
  static bool equals(Object? a, Object? b) => a == b;

  static bool notEquals(Object? a, Object? b) => a != b;

  static bool identical(Object? a, Object? b) => core.identical(a, b);

  static bool notIdentical(Object? a, Object? b) => !core.identical(a, b);
}
```

Checked `flutter analyze lib/src/utils/compare_utils.dart` immediately after
applying — no `unnecessary_import` (or any other) lint fired for the
unprefixed `import 'dart:core';` line, so the dual-import approach from the
brief's controller resolution was usable as-is; the top-level
`_identical`-helper alternative was not needed.

```
Analyzing compare_utils.dart...
No issues found! (ran in 0.1s)
```

## Step 3 — Passing test

```
$ flutter test test/compare_utils_test.dart
00:00 +0: loading /Users/user/development/my/scopo/.claude/worktrees/audit-fixes/test/compare_utils_test.dart
00:00 +0: CompareUtils.identical does not recurse
00:00 +1: All tests passed!
```

## Step 4 — Full `flutter analyze`

```
$ flutter analyze
Analyzing audit-fixes...
warning • The annotation 'override' can only be used on fields, getters, methods, or setters • example/scopo_demo/lib/home/demos/c_scope_notifier/scope_notifier_example2.dart:91:4 • invalid_annotation_target
   info • Classes should define instance members. Try adding instance behavior or moving the members out of the class • lib/src/environment/scope_config.dart:7:22 • avoid_classes_with_only_static_members
   info • Unnecessary 'this.' qualifier. Try removing 'this.' • lib/src/scope/h_scope/scope_auto_dependency/scope_auto_dependency.dart:25:36 • unnecessary_this

3 issues found. (ran in 1.5s)
```

Exactly the 3 known pre-existing issues (`invalid_annotation_target` in
`example/scopo_demo`, `avoid_classes_with_only_static_members` in
`scope_config.dart`, `unnecessary_this` in `scope_auto_dependency.dart`).
Zero issues in `compare_utils.dart`.

## Step 5 — Full `flutter test`

```
$ flutter test
...
00:00 +38: All tests passed!
```
Exit code 0. 38 tests total across `compare_utils_test.dart`,
`notifier_test.dart`, `scope_auto_dependencies_test.dart` — all green.

## Step 6 — Commit

Staged only the two files owned by this task (left untracked `docs/` alone —
not part of this task):

```
$ git status --porcelain
M  lib/src/utils/compare_utils.dart
A  test/compare_utils_test.dart
?? docs/
```

```
$ git commit -m "fix infinite recursion in CompareUtils.identical"
$ git log -1 --stat
f277ab9 fix infinite recursion in CompareUtils.identical
 lib/src/utils/compare_utils.dart |  7 +++++--
 test/compare_utils_test.dart     | 11 +++++++++++
 2 files changed, 16 insertions(+), 2 deletions(-)
```

## Concerns

None. The dual-import approach worked cleanly with no lint fallout, so the
alternative top-level-helper approach from the brief's controller note was
not exercised. `docs/` remains untracked/uncommitted in the worktree as found
— out of scope for this task.
