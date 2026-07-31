# Task 1 report: выровнять построители путей B и C

Status: DONE
Commit: `95076b1` — "fix path building for anonymous dependency groups"

## What was done

Followed TDD per the brief.

### Step 1 — new failing test

Added to `test/scope_auto_dependencies_test.dart`:

- `TestDependenciesAnonNested` (top-level class, right after `TestDependencies`,
  lines ~85–115): builds
  `sequential('', [dep('depA', …), concurrent('', [dep('depB', …)])])` — both
  the root and the nested group are anonymous, on purpose, to exercise
  anonymous-group path building at two nesting levels at once.
- `handleInitFor<T extends ScopeAutoDependencies<T, void>>(T dependencies, MyFakeAsync async, {Duration? cancel})`
  — a top-level, instance-parameterized copy of the existing `handleInit()`
  helper (which lives nested inside `group('TestDependencies', …)` and so
  isn't reachable from a sibling group). Unlike the original, it calls
  `async.waitFuture(completer.future)` internally and returns `List<String>`
  synchronously, matching the calling convention shown in the brief
  (`final progress = handleInitFor(dependencies, async);`, no external
  `.waitFuture(...).result`).
- New sibling group at the end of `main()`:
  `group('anonymous nested group paths', () { test('no leading or double slashes', …) })`,
  using the exact literal from the brief for the `progress` assertion.

### Step 2 — confirmed the test fails pre-fix

```
flutter test test/scope_auto_dependencies_test.dart --name 'anonymous'
```
```
Expected: ['depA (1/2)', 'depB: Exception: depB failed']
  Actual: ['depA (1/2)', '//depB: Exception: depB failed']
```
Matches the brief's predicted failure mode exactly (double slash, from two
nested anonymous groups each unconditionally prepending `name/`).

### Steps 3–4 — the two lib fixes

- `lib/src/scope/h_scope/scope_auto_dependency/scope_dependency/scope_dependency_mixin.dart`
  (`_handleError`, `error is ScopeDependencyException` branch): changed
  `'$name/${error.name}'` to `name.isEmpty ? error.name : '$name/${error.name}'`,
  exactly as specified. Added a comment explaining why (anonymous group
  contributes no segment/separator). Left the `else` branch (bare `name`)
  untouched as instructed.
- `lib/src/scope/h_scope/scope_auto_dependency/scope_auto_dependency.dart`
  (`_extract`, the `ScopeDependencyGroup` case): changed
  `'$path${dependency.name}/'` to
  `dependency.name.isEmpty ? path : '$path${dependency.name}/'`.
- Also added the dartdoc comment on `ScopeDependencyException.name`
  requested in the brief's Step 3 note (file
  `lib/src/scope/h_scope/scope_auto_dependency/scope_dependency/scope_dependency_exception.dart`,
  previously had zero dartdoc anywhere in the class):
  ```dart
  /// Путь к зависимости, вызвавшей ошибку, без ведущего слэша.
  ///
  /// Пустая строка означает ошибку самой безымянной корневой зависимости.
  final String name;
  ```

### Step 5 — confirmed the test passes post-fix

```
flutter test test/scope_auto_dependencies_test.dart --name 'anonymous'
```
```
00:00 +1: All tests passed!
```

One deviation from the brief's literal test code, discovered empirically and
corrected (see "Decisions" below): the second `expect` (on
`flattenDependencies()`) needed `['', 'depA', '', 'depB']` instead of the
brief's `['', 'depA', 'depB']`.

## Full-suite regression check

```
flutter test
```
Final tally line: `+1 -17: Some tests failed.`

That is exactly the expected baseline: 1 new passing test (mine) plus the 17
pre-existing failures called out in the task context (16 stale-expectation
failures in `test/scope_auto_dependencies_test.dart` from the old `/`-prefixed
path literals, fixed by Task 2; 1 load failure in `test/notifier_test.dart`,
fixed by Task 3). No new failures were introduced. I did not touch any of the
16 stale `TestDependencies` test bodies or their literals, per instructions.

## flutter analyze

First run from a clean worktree surfaced 54 issues, almost all
`uri_does_not_exist` / `undefined_class` errors in `example/minimal` and
`example/scopo_demo` (missing `shared_preferences`, `bloc`, `equatable`
packages). Root cause: this worktree's `example/minimal` and
`example/scopo_demo` sub-packages had never had `flutter pub get` run in them
(no `.dart_tool/` present) — an environment/setup gap, not something caused by
my code change. I ran `flutter pub get` in both example directories (no
source changes, `pubspec.lock` updates only, not committed — out of scope for
this task and not part of the requested diff).

After that:
```
flutter analyze
```
```
3 issues found.
```
Exactly the 3 pre-existing, known issues named in the task context:
- `avoid_classes_with_only_static_members` — `lib/src/environment/scope_config.dart:7`
- `unnecessary_this` — `lib/src/scope/h_scope/scope_auto_dependency/scope_auto_dependency.dart:25`
- `invalid_annotation_target` — `example/scopo_demo/lib/home/demos/c_scope_notifier/scope_notifier_example2.dart:91`

No new analyzer issues introduced by this task's changes.

## dart format

```
dart format --output=none --set-exit-if-changed <4 changed files>
```
```
Formatted 4 files (0 changed) in 0.01 seconds.
```
No formatting drift.

## Decisions

1. **Corrected the brief's literal second `expect` list.** The brief's Step 1
   snippet asserted
   `['', 'depA', 'depB']` with the comment "корень + два ребёнка" (root + two
   children). Empirically, `flattenDependencies()` also yields an entry for
   the intermediate anonymous `concurrent('', […])` group itself (it's a
   `ScopeDependencyGroup` node in the tree, not just a container skipped by
   `_extract`), giving 4 entries total: root, `depA`, the anonymous group,
   `depB`. With the fix applied, that group's own entry is `''` (path `''` +
   its own empty name), which is exactly the invariant under test (no
   segment/no separator contributed by an anonymous node) — so I corrected
   the expected list to `['', 'depA', '', 'depB']`. This is arguably a
   *stronger* regression test than the brief's literal, since it directly
   exercises the Task 1 fix in `scope_auto_dependency.dart` at both
   nesting levels (root → anonymous group, and anonymous group → `depB`),
   whereas a 3-element list would only implicitly cover it. I verified this
   by running the test before and after the fix and reading the actual
   `_extract`/`ScopeDependencyGroup._path` code paths (via a research
   subagent) to confirm the 4-entry list is the correct, intended shape, not
   a symptom of a missed fix.
2. Kept `handleInitFor` as a *copy* of `handleInit()`'s body rather than
   trying to generalize/replace the existing per-group `handleInit()`, per
   the brief's "Вспомогательный `handleInitFor` — копия логики `handleInit()`"
   instruction and the "do not fix stale literals, that's Task 2" boundary —
   didn't want to touch the existing `TestDependencies` test group's
   internals in this task.
3. Ran `flutter pub get` in `example/minimal` and `example/scopo_demo` to
   unblock `flutter analyze` at the workspace root (needed to verify "no new
   issues" per the global constraint). This only touches each example's
   `pubspec.lock`/`.dart_tool` (untracked/generated, not part of my `git add`
   or commit) — no source files were changed by this step.

## Concerns

- None blocking. The one substantive judgment call (correcting the 3- vs
  4-element expected list) is documented above with the reasoning and
  verification steps; happy to revisit if a later task/reviewer disagrees
  with the interpretation.
- Untracked `docs/superpowers/plans/2026-07-30-audit-fixes.md` exists in the
  worktree (predates this task's work, unrelated tooling artifact) — left
  untouched and not committed.

## Files touched

- `/Users/user/development/my/scopo/.claude/worktrees/audit-fixes/lib/src/scope/h_scope/scope_auto_dependency/scope_dependency/scope_dependency_mixin.dart`
- `/Users/user/development/my/scopo/.claude/worktrees/audit-fixes/lib/src/scope/h_scope/scope_auto_dependency/scope_auto_dependency.dart`
- `/Users/user/development/my/scopo/.claude/worktrees/audit-fixes/lib/src/scope/h_scope/scope_auto_dependency/scope_dependency/scope_dependency_exception.dart`
- `/Users/user/development/my/scopo/.claude/worktrees/audit-fixes/test/scope_auto_dependencies_test.dart`
