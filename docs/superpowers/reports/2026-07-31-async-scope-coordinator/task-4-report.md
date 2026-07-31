# Task 4 report — public surface, documentation, release notes

Commit: `e9acbca` — `docs: describe coordinator-owned scopeKey scoping`
(parent `fff12ad`). Branch `coordinator`, worktree
`/Users/user/development/my/scopo/.claude/worktrees/coordinator`.

Result: `flutter analyze` → 0 issues in the root package and in
`example/minimal` and `example/scopo_demo`. `flutter test` → **55 passed**
(54 before + 1 new nested-coordinator test). `dart doc` → **0 warnings, 0
errors**. `flutter pub publish --dry-run` → **0 warnings**.
`example/scopo_demo` builds for macOS debug.

---

## Item 1 — shrink the public surface

`AsyncScopeCoordinator.enter` → `AsyncScopeCoordinator._enter` (static method,
`lib/src/scope/e_async_scope/async_scope_coordinator.dart`).
`AsyncScopeParent.registerChild` → `AsyncScopeParent._registerChild`
(`lib/src/scope/e_async_scope/async_scope_parent.dart`). Both were public
methods whose signatures named `AccessEntry` / `ChildEntry` —
types defined in `scope_coordination.dart`, which `scope.dart` only
`import`s (not `export`s), so they were never part of the package's public
API and the methods were already uncallable from outside. Renaming just makes
that explicit.

Call sites updated in `async_scope_core.dart` (both are `part of
'../scope.dart'`, so the rename is invisible to them beyond the identifier):
`AsyncScopeCoordinator.enter(...)` → `AsyncScopeCoordinator._enter(...)`, and
`(parentScope ?? coordinator)?.registerChild(...)` →
`?._registerChild(...)`.

Kept public, as instructed: the `AsyncScopeCoordinator` widget, the static
`AsyncScopeCoordinator.waitForChildren(context, ...)`, and
`AsyncScopeParent.hasChildren` / `childrenCount` / `waitForChildren`.

Verified two ways:
- `grep -rn "AccessEntry\|ChildEntry" lib` — the only remaining hits are
  inside `scope_coordination.dart` itself (that library's own public API,
  out of scope for this item) and on now-private members/fields.
- Generated dartdoc: `AsyncScopeCoordinator-class.html` no longer mentions
  `enter` at all; `AsyncScopeParent-mixin.html`'s member-id list is exactly
  `childrenCount, debugFillProperties, hasChildren, hashCode, noSuchMethod,
  runtimeType, toDiagnosticsNode, toString, toStringShort, waitForChildren`
  plus Diagnosticable operators — no `registerChild`.

## Item 2 — `dart doc`

Added a full class-level dartdoc comment to `AsyncScopeCoordinator` (previously
just `{@category AsyncScope}`) covering: it owns the `scopeKey` queues of its
own subtree, the nearest coordinator above a scope always serves it, and it is
independently the wait root for scopes with no parent scope above them, with
`[waitForChildren]` linked. Ran:

```
dart doc --output <scratch>/dartdoc-task4
```

→ `Found 0 warnings and 0 errors.` Confirmed by inspecting the rendered HTML:
both `[AsyncScopeCoordinator]` and `[AsyncScopeParent]` self/cross-references
and `[waitForChildren]` resolved to real anchors, no dangling links.

## Item 3 — CHANGELOG

Added exactly the bullet given in the brief to the top of `## 0.10.0` (nothing
else in that section reordered). Left every historical section — including
`## 0.6.1`'s `asyncScopeRoot` entry and `## 0.6.2`'s `AsyncScopeCoordinator`
entry — untouched; confirmed via `git diff CHANGELOG.md` showing only an
insertion at the top.

## Item 4 — nested-coordinator test

Added `'a scope under nested coordinators registers with the nearest one'` to
`test/async_scope_coordinator_test.dart`, right after the existing
`'a scope with no parent scope registers with the coordinator'` arrangement
test. Pumps `Coordinator > Coordinator > _TestScope()`, reads both
coordinator elements via `tester.elementList(find.byType(AsyncScopeCoordinator))`
(document order → `[outer, inner]`) cast to `AsyncScopeParent`, and asserts
`inner.childrenCount == 1` / `outer.childrenCount == 0`. Passes; also verified
it fails without the fix by temporarily reading only `.first` — not needed
here since the underlying behavior already shipped in task 3, this test just
closes the coverage gap the reviewer flagged.

## README — `scopeKey` section / `waitForChildren`

Added two paragraphs after the existing `AsyncScopeCoordinator(child:
MaterialApp(...))` snippet: one on coordinators scoping `scopeKey` to their
own subtree (nearest wins), one on `AsyncScopeCoordinator.waitForChildren
(context)` being the way to await top-level scopes — the direct replacement
for the removed `asyncScopeRoot`.

Both Dart snippets (`AsyncScopeCoordinator(child: MaterialApp(home:
HomeScreen()))` and `await AsyncScopeCoordinator.waitForChildren(context);`)
were verified by compiling them in a throwaway package outside the repo
(`<scratch>/readme_check`, `scopo` pulled in via a `path:` dependency pointing
at this worktree) — `flutter analyze` on that package reported "No issues
found!". The scratch package was deleted afterward; it never touched the
repo.

## TODO.md

Removed the two items closed by this work: the `waitForChildren`/
`asyncScopeRoot` redesign line under the top-level list, and the
`AsyncScopeCoordinator: глобальный static _queues без очистки...` line under
"Известные проблемы (0.10.x)". Left the unrelated test-coverage line that
merely *mentions* `AsyncScopeCoordinator` in passing (`e_async_scope
(особенно AsyncScopeCoordinator)`), since that's about missing tests in
general, not the bug this task fixed — and task 3/4 together did add
`AsyncScopeCoordinator` test coverage, but the line covers the whole
`e_async_scope` group, not just that class.

---

## Full verification

| Check | Result |
| ----- | ------ |
| `flutter analyze` (root) | 0 issues |
| `flutter analyze` (`example/minimal`) | 0 issues |
| `flutter analyze` (`example/scopo_demo`) | 0 issues |
| `flutter test` (root) | 55 passed |
| `dart format` on the 4 files this task touched in `lib`/`test` | 0 changes |
| `dart doc --output <scratch>/dartdoc-task4` | 0 warnings, 0 errors |
| `flutter pub publish --dry-run` | 0 warnings |
| `cd example/scopo_demo && flutter build macos --debug` | succeeds (`Built .../scopo_demo.app`) |
| `grep -rn "asyncScopeRoot\|AsyncScopeRoot\|AsyncScopeCoordinatorEntry\|ScopeChildEntry" lib test example` | empty |
| `grep -c "package:flutter" lib/src/scope/e_async_scope/scope_coordination.dart` | `0` |

### Note on `dart format` scope

Repo-wide `dart format --set-exit-if-changed .` reports 6 files it would
reformat, all in `example/scopo_demo/lib/**` (e.g. `box.dart`,
`code_block.dart`). This is **pre-existing** — confirmed by stashing this
task's changes and re-running the same command against `fff12ad` (the task 3
tip): identical 6 files, identical diffs (a Dart-formatter "tall style" line-
break difference, e.g. `color:\n    borderColor ??` vs `color: borderColor
??`). None of these files were touched by task 4, so they're left alone;
formatting them would mix an unrelated cosmetic change into a docs commit.
The 4 files this task actually edited under `lib/`/`test/` format clean.

### Note on the macOS build command

`flutter build macos --debug` triggered a one-time "Adding Swift Package
Manager integration" migration that modified
`example/scopo_demo/macos/Podfile.lock`,
`Runner.xcodeproj/project.pbxproj`, and `Runner.xcscheme`. These were reverted
with `git checkout --` after the build succeeded, since they're a local
tooling side effect unrelated to this task, not something requested by the
brief.

## Concerns

None blocking. The pre-existing `dart format` drift in `example/scopo_demo`
(noted above) is worth a follow-up if the team wants the whole repo
format-clean under the current Dart SDK, but it predates this task and isn't
part of its scope.
