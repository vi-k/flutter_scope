# Task 12 report: мёртвый код

Status: DONE. Commit: `077fbb6` — "remove dead code, fix ScopeDependencyNoDisposalRequired typo"

## Per-item evidence

### 1. Delete `lib/src/utils/type_to_string.dart`

Pre-delete grep (source dirs only, lib/test/example):

```
$ grep -rn 'type_to_string\|typeToShortString' lib test example --include='*.dart'
lib/src/utils/type_to_string.dart:1:String typeToShortString(Type type) {
```

Only the definition itself, no importers, no `part of`/`part` reference anywhere in `lib/**/*.dart`. Confirmed dead. Deleted via `git rm`.

Post-delete verification: 0 hits for `typeToShortString` across lib/test/example (see combined verification below).

### 2. Delete `lib/src/scope/g_lite_scope/lite_scope_init_state.dart` (+ part directive)

Pre-delete grep:

```
$ grep -rn 'LiteScopeInitState\|LiteScopeWaiting\|LiteScopeProgress\|LiteScopeReady' lib test example --include='*.dart'
```
All 12 matches were inside the file being deleted itself (class decls + doc comments referencing sibling classes). No usage elsewhere in lib/test/example. `LiteScope` itself uses `AsyncScopeInitState` (per brief), confirmed by absence of any external reference.

Deleted the file via `git rm`, and removed its `part` directive from `lib/src/scope/scope.dart`:
```
- part 'g_lite_scope/lite_scope_init_state.dart';
```

Post-delete verification: 0 hits for `LiteScopeInitState|LiteScopeWaiting|LiteScopeProgress|LiteScopeReady` across lib/test/example.

### 3. Rename typo `ScopeDependencyNoDisposalRequred` → `ScopeDependencyNoDisposalRequired`

Pre-change grep (repo-wide, source only):

```
$ grep -rn 'Requred' lib test example --include='*.dart'
lib/src/scope/h_scope/scope_auto_dependency/scope_dependency/scope_dependency_state.dart:170:final class ScopeDependencyNoDisposalRequred extends ScopeDependencyDisposed {
lib/src/scope/h_scope/scope_auto_dependency/scope_dependency/scope_dependency_state.dart:171:  const ScopeDependencyNoDisposalRequred();
```
Only 2 occurrences, both the class name/constructor in the same file — no other spelling of "Requred" anywhere in lib/test/example, and none in doc/CHANGELOG.md/README.md/TODO.md. No constructor calls found (class is never instantiated, matches brief's note).

Renamed both occurrences to `ScopeDependencyNoDisposalRequired`.

Post-change verification: 0 hits for `NoDisposalRequred` (old spelling) across lib/test/example.

### 4. Remove duplicate assignment in `scope_dependency_impl.dart`

Before:
```dart
final helper = _helper = DepHelper._(this);
_helper = helper;
final result = _init(helper);
```
`_helper = helper` is redundant — `_helper` was already assigned to the same `DepHelper._(this)` instance on the prior line via the `_helper = DepHelper._(this)` sub-assignment; `helper` and `_helper` are already the same object. Removed the redundant second statement:
```dart
final helper = _helper = DepHelper._(this);
final result = _init(helper);
```

### 5. `ScopeDependencyExtension.isGroup`, `ListenableView`, `Notifier`

Not touched, per brief's explicit decision to keep them (harmless public API / reserved for other tasks).

## Combined final verification

```
$ grep -rn 'LiteScopeInitState\|LiteScopeWaiting\|LiteScopeProgress\|LiteScopeReady\|typeToShortString\|NoDisposalRequred' lib test example --include='*.dart'
(no output — 0 matches)
```

```
$ flutter analyze                        # root
No issues found! (ran in 2.1s)

$ (cd example/minimal && flutter analyze)
No issues found! (ran in 0.6s)

$ (cd example/scopo_demo && flutter analyze)
No issues found! (ran in 0.8s)
```

```
$ flutter test
...
00:00 +54: All tests passed!
```

54/54 tests green, 0 analyze issues in root + both examples.

## Commit

```
077fbb6 remove dead code, fix ScopeDependencyNoDisposalRequired typo
 5 files changed, 2 insertions(+), 45 deletions(-)
 delete mode 100644 lib/src/scope/g_lite_scope/lite_scope_init_state.dart
 delete mode 100644 lib/src/utils/type_to_string.dart
```

Files touched:
- `lib/src/utils/type_to_string.dart` (deleted)
- `lib/src/scope/g_lite_scope/lite_scope_init_state.dart` (deleted)
- `lib/src/scope/scope.dart` (removed part directive)
- `lib/src/scope/h_scope/scope_auto_dependency/scope_dependency/scope_dependency_state.dart` (typo rename, class + ctor)
- `lib/src/scope/h_scope/scope_auto_dependency/scope_dependency/scope_dependency_impl.dart` (removed duplicate assignment)

No NEEDS_CONTEXT items — all sub-items applied cleanly with no hidden usages found.
