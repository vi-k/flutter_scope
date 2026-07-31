# Task 6 report: ScopeNotifier addListener при смене value

## Bug

`lib/src/scope/d_scope_notifier/scope_notifier_base.dart`, `_ScopeNotifierElement.update`:
on a `value` swap, the old listener was removed correctly, but the new value's
listener was attached with `removeListener` instead of `addListener`. Since
`init()` (`scope_notifier_core.dart:46-49`) only runs once (on first mount),
no code path ever subscribed to the replacement `Listenable`, so
`ScopeNotifier.of`/`.select` consumers silently stopped updating forever
after any `.value` swap.

## API read before writing the test

Read `scope_notifier.dart`, `scope_notifier_base.dart`, `scope_notifier_core.dart`,
`c_scope_model/base.dart`, `c_scope_model/scope_model_base.dart`,
`a_base/base.dart`, `b_scope_widget/scope_widget_core.dart`, and the demo
usages in `example/scopo_demo/lib/home/demos/c_scope_notifier/`. Confirmed
actual signatures differ from the brief's sketch:

- `ScopeNotifier<M>.value({key, tag, required M value, required Widget Function(BuildContext) builder})`
  — no `child` param on the `.value` constructor.
- `ScopeNotifier.of<M>(context, {required bool listen})` returns `M` directly
  (not a wrapper context).
- `ScopeNotifier.select<M, V>(context, V Function(M model) selector)` — static
  generic method, selector receives the model directly.
- The `builder` is invoked with the `InheritedElement` itself as
  `BuildContext` (`_ScopeModelElementMixin.buildChild` → `widget.build(this)`),
  and descendants further down the tree use their own `BuildContext` to call
  `select`, exactly as in `scope_notifier_example1.dart`.

Test file: `test/scope_notifier_test.dart`. Uses `ScopeNotifier<ValueNotifier<int>>.value`,
pumping the *same* widget position (same type, no key) with listenable `first`
then `second`, so Flutter's element diffing calls `update()` in place rather
than remounting. A descendant `_ValueView` widget (its own `BuildContext`,
not the element) reads the value via `ScopeNotifier.select`.

Assertions, in order (pinpointing exactly the swap path):
1. Initial build shows `first`'s value (`0`).
2. Mutating `first` *before* the swap still rebuilds the dependent (`1`) —
   guards the pre-existing/working path.
3. Swap to `second` (`pumpWidget` with `second`) shows `100`.
4. Mutating the **old** `first` after swap does **not** rebuild (`100`
   persists, `2` never appears) — guards that old-listener removal keeps
   working.
5. Mutating the **new** `second` after swap **does** rebuild to `101` — this
   is the regression assertion; failed before the fix, passes after.

## Failing run (before lib fix)

```
$ flutter test test/scope_notifier_test.dart
00:00 +0: ScopeNotifier.value re-subscribes to the new listenable on swap
══╡ EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK ╞═══════════════════════════
The following TestFailure was thrown running a test:
Expected: exactly one matching candidate
  Actual: _TextWidgetFinder:<Found 0 widgets with text "101": []>
   Which: means none were found but one was expected
...
    file:///.../test/scope_notifier_test.dart line 47   (the `second.value = 101` assertion)
════════════════════════════════════════════════════════════════════════════
00:00 +0 -1: ScopeNotifier.value re-subscribes to the new listenable on swap [E]
Some tests failed.
```

All assertions up to and including "old listenable no longer triggers
rebuilds" passed; only the final "new listenable triggers rebuild" assertion
failed — confirming the failure pinpoints the swap re-subscription path, not
the whole feature.

## Fix

One-line change in `_ScopeNotifierElement.update`:

```diff
-      newWidget.value?.removeListener(notifyDependents);
+      newWidget.value?.addListener(notifyDependents);
```

## Passing run (after lib fix)

```
$ flutter test test/scope_notifier_test.dart
00:00 +0: ScopeNotifier.value re-subscribes to the new listenable on swap
00:00 +1: All tests passed!
```

## Full verification

```
$ flutter test
...
00:00 +40: All tests passed!
```
40 tests total = baseline 39 + 1 new test. No other test regressed.

```
$ flutter analyze
Analyzing audit-fixes...
warning • invalid_annotation_target • example/.../scope_notifier_example2.dart:91:4
   info • avoid_classes_with_only_static_members • lib/src/environment/scope_config.dart:7:22
   info • unnecessary_this • lib/src/scope/h_scope/scope_auto_dependency/scope_auto_dependency.dart:25:36
3 issues found.
```
Same 3 pre-existing issues as baseline, unchanged.

## Self-review

- `dart format --set-exit-if-changed` on both changed files: no changes
  needed.
- Diff is exactly the one-line swap (`removeListener` → `addListener`) plus
  the new test file; no other lib files touched.
- An unrelated untracked `docs/superpowers/` directory appeared in the
  worktree (not created by this task) — left untouched and not staged/committed.

## Commit

```
347603b fix listener re-subscription on ScopeNotifier.value swap
```
Files: `lib/src/scope/d_scope_notifier/scope_notifier_base.dart`,
`test/scope_notifier_test.dart`.
