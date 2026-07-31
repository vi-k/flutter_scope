# Task 16 report: sync example/README.md with example/minimal/lib/main.dart

## Summary

`example/README.md` is what pana renders as pub.dev's Example tab (it can't
find `example/minimal` or `example/scopo_demo` at its fixed candidate depth).
The README previously inlined a hand-maintained, drifted copy of
`example/minimal/lib/main.dart`: missing the entire logging block (old lines
1-33 of the real file), missing `@override void unmount() {}`, `class`
instead of `final class` for `AppDependencies`, and the old 3-argument
`buildOnError` signature (missing the third `covariant String? progress`
parameter — real file has 4 args).

## Changes

### 1. `example/minimal/lib/main.dart`

Translated the sole Russian dartdoc to English, matching the plain
declarative style of the surrounding comments (e.g. "Increases the counter
and notifies subscribers (dependents).")

```
-  /// Метод инициализации зависимостей.
+  /// Dependencies initialization method.
```

`cd example/minimal && flutter analyze` → **No issues found!**

### 2. `example/README.md`

- Replaced the inlined ```dart``` block with an exact, verbatim copy of the
  now-current `example/minimal/lib/main.dart` (272 lines) — logging block,
  `final class AppDependencies`, `unmount()`, 4-arg `buildOnError`, and the
  translated dartdoc all included.
- Rewrote the prose: `scopo_demo` link is now the first thing in the file
  (previously it was buried after the minimal blurb and the inline code),
  described as "9 interactive demos covering every scope family, nested
  scopes, `scopeKey`, deferred closing, and navigation nodes." The "9" was
  verified by counting `_tabs` entries in
  `example/scopo_demo/lib/home/home.dart:21-31` (ScopeWidget, ScopeModel,
  ScopeNotifier, AsyncScope, AsyncDataScope, LiteScope, Scope, Deferred
  closing, NavigationNode = 9).
- Kept the `minimal` counter-app intro and its GitHub link.
- Both GitHub links verified to resolve on `main`:
  `git ls-tree -d origin/main -- example/minimal example/scopo_demo` returned
  tree objects for both paths (commit `ea66419`, origin/main HEAD at time of
  check).

## Verbatim-copy evidence (empty diff)

```
$ awk '/^```dart$/{flag=1;next}/^```$/{flag=0}flag' example/README.md > extracted_main.dart
$ diff extracted_main.dart example/minimal/lib/main.dart
$ echo "EXIT CODE: $?"
EXIT CODE: 0
```

Re-ran after the commit against the committed `main.dart` — diff still empty,
both files 272 lines.

## Baseline verification

| Check | Result |
|---|---|
| `flutter analyze` (root) | No issues found! |
| `cd example/minimal && flutter analyze` | No issues found! |
| `cd example/scopo_demo && flutter analyze` | No issues found! |
| `flutter test` | `+54: All tests passed!` (54/54) |
| `flutter pub publish --dry-run` (pre-commit) | 1 warning — "2 checked-in files are modified in git" (expected before commit) |
| `flutter pub publish --dry-run` (post-commit) | **Package has 0 warnings.** |

## Commit

```
d594f48 sync example README with minimal app
 2 files changed, 44 insertions(+), 11 deletions(-)
```

Files: `example/README.md`, `example/minimal/lib/main.dart`.

## Concerns

None. `git status --short` showed only the two intended files touched before
committing; no unrelated changes were swept in.
