# Task 18: Release 0.10.0 (version bump + CHANGELOG + verification)

## Scope note

Per controller override, only Steps 1 and 2 of the brief were executed
(version bump + CHANGELOG section + full verification). Step 3 (git tag,
`git push origin main v0.10.0`, `flutter pub publish --force`) is
**deferred** — the branch merges to `main` first. No tag was created, no
push was made, no real publish was performed (dry-run only).

## Changes Made

### pubspec.yaml
`version: 0.9.6` → `version: 0.10.0`.

### CHANGELOG.md
Added a new `## 0.10.0` section at the top (blank line after heading, `*`
bullets, sentence case, trailing periods, matching the style of the
existing `## 0.9.6` section below it). Existing sections were left
untouched. Content is the brief's bullet list plus three bullets added per
controller instructions to reflect implementation-time changes:

```markdown
## 0.10.0

* [breaking changes] Unify dependency path format: no leading `/` in
  `ScopeDependencyException.name`, `ScopeDependencyInfo.path` and progress
  paths; anonymous groups add no separator.
* [breaking changes] Remove dead API: `LiteScopeInitState`/`Waiting`/
  `Progress`/`Ready`, `typeToShortString`; rename
  `ScopeDependencyNoDisposalRequred` to `ScopeDependencyNoDisposalRequired`.
* Fix infinite recursion in `CompareUtils.identical`.
* Fix hang in `ScopeAutoDependencies.dispose()` when no dependency requires
  disposal.
* Fix `ScopeNotifier.value` not subscribing to a new listenable on update.
* Fix `LiteScope.close()` hang outside the Ready state; fix
  `ScreenshotReplacer` completing early and leaking `ui.Image`.
* Fix a double close() race in LiteScope orphaning the screenshot barrier;
  cap ScreenshotReplacer retries (new public ScreenshotReplacer.maxRetries).
* Base the disposeAsync() decision on successful initialization instead of
  the applied model state (resources are now disposed of when the element
  is removed in the init-completion frame).
* Guard AsyncScope post-frame callbacks with `mounted`.
* Log dependency disposal errors instead of swallowing them.
* Fix unbalanced parenthesis in `AsyncScopeError.toString()`.
* Add `repository`, `issue_tracker` and `topics` to pubspec; honest Flutter
  constraint.
* Switch analysis to flutter_lints in the package and demo.
* Rewrite README; sync the pub.dev example; real `debug`/`Scope` doc pages.

## 0.9.6
```

New bullets added (verified against source before inclusion):
- `ScreenshotReplacer.maxRetries` — confirmed present as a public static
  const in `lib/src/utils/screenshot_replacer.dart:17` and used in the
  retry-cap check at line 86.
- `disposeAsync()` decision base — confirmed `disposeAsync` usage across
  the scope core/base files (async_scope, async_data_scope, lite_scope,
  h_scope).

Note: `flutter_lints` was already the `include:` in all three
`analysis_options.yaml` files (root, `example/minimal`,
`example/scopo_demo`) at the start of this task — that switch was made in
an earlier task; this task only records it in the CHANGELOG per the
controller's instruction.

## Incidental side effects reverted (not committed)

Running `flutter pub get` (root + both examples) and
`flutter build macos --debug` for verification touched generated/lock
files unrelated to this task's scope:
- `example/minimal/pubspec.lock`, `example/scopo_demo/pubspec.lock`
  (scopo path-dep version bump 0.9.6 → 0.10.0 — expected, but not part of
  the instructed commit)
- `example/scopo_demo/macos/Podfile.lock`,
  `example/scopo_demo/macos/Runner.xcodeproj/project.pbxproj`,
  `example/scopo_demo/macos/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme`
  (Xcode/CocoaPods regeneration side effects of the debug build)

These were reverted with `git checkout --` before committing, since the
instructions were to commit only `pubspec.yaml` + `CHANGELOG.md` together.

## Verification Results

### Root `flutter analyze`
```
Analyzing audit-fixes...
No issues found! (ran in 1.8s)
```

### `example/minimal` `flutter analyze`
```
Analyzing minimal...
No issues found! (ran in 1.0s)
```

### `example/scopo_demo` `flutter analyze`
```
Analyzing scopo_demo...
No issues found! (ran in 1.2s)
```

### `flutter test` (root)
```
00:00 +54: All tests passed!
```
54/54 passing, no regressions.

### `flutter pub publish --dry-run`
Run once before committing — flagged the (expected, pre-commit) dirty
git state as 1 warning:
```
Package validation found the following potential issue:
* 2 checked-in files are modified in git. ...
Package has 1 warning.
```
Re-run after the `release 0.10.0` commit, on a clean tree:
```
Validating package...
The server may enforce additional checks.

Package has 0 warnings.
```
Exit code 0. **0 warnings**, as required.

### `dart doc`
```
dart doc --output <scratchpad>/dartdoc-18
...
Found 0 warnings and 0 errors.
Documented 1 public library in 13.6 seconds
Success!
```
**0 errors**, as required.

### `example/scopo_demo` macOS debug build (substitutes the manual
`flutter run -d macos` GUI check per controller instruction — a GUI run
from an agent is not appropriate)
```
cd example/scopo_demo && flutter build macos --debug
...
✓ Built build/macos/Build/Products/Debug/scopo_demo.app
```
Compiles cleanly.

**Deferred to a human**: the manual interactive check from the brief's
Step 2 — running `flutter run -d macos` and clicking through the
Scope/LiteScope/AsyncScope tabs to eyeball that progress paths in the
console have no leading `/` and that closing tabs doesn't hang. The
build above proves the demo compiles against scopo 0.10.0; it does not
exercise the runtime UI.

## Commit

```
93c22e9 release 0.10.0
 CHANGELOG.md | 27 +++++++++++++++++++++++++++
 pubspec.yaml |  2 +-
 2 files changed, 28 insertions(+), 1 deletion(-)
```

## Result

- pubspec.yaml bumped to 0.10.0
- CHANGELOG.md has a new `## 0.10.0` section, existing sections untouched
- `flutter analyze`: 0 issues (root + both examples)
- `flutter test`: 54/54 passing
- `flutter pub publish --dry-run`: 0 warnings (clean git state, post-commit)
- `dart doc`: 0 warnings, 0 errors
- `example/scopo_demo` macOS debug build: compiles successfully
- Manual `flutter run -d macos` interactive tab check: **deferred to a human**
- Step 3 (tag/push/publish): **deferred** per controller override — not
  performed

## Post-review fix: missing CHANGELOG bullet

Task review flagged that commit `69aea2b` ("fix double close race, cap
screenshot retries, guard ready callback during dispose") contained a
third, uncovered fix: a new `_isDisposing` flag in
`lib/src/scope/e_async_scope/async_scope_core.dart` guarding both
Ready-application callbacks so `_model.update(state)` is skipped once
`_performAsyncDispose` has started. This is distinct from the existing
"Guard AsyncScope post-frame callbacks with `mounted`" bullet: an
`AsyncScope` element closed via `close()` (rather than removed from the
tree) stays mounted while `_model` is being disposed, so the `mounted`
guard alone doesn't cover this race. The gap originated in the
controller's bullet list, not this task's original work, but was fixed
here as instructed.

Confirmed against source (`git show 69aea2b -- lib/src/scope/e_async_scope/async_scope_core.dart`):
adds `bool _isDisposing = false;`, changes both Ready-callback guards to
`mounted && !_isDisposing` / `!mounted || _isDisposing`, and sets
`_isDisposing = true;` at the start of the disposal-prep method.

Added bullet to the `## 0.10.0` section of CHANGELOG.md (right after the
double-close-race bullet, since both come from the same commit):

```markdown
* Guard the Ready-state model update against running after disposal has
  started (an element closed via close() stays mounted while its model is
  being disposed of).
```

Only `CHANGELOG.md` was touched (per instruction — pubspec.yaml was not
modified).

Re-verification after the fix:
- `flutter pub publish --dry-run 2>&1 | tail -3` → `Package has 0
  warnings.` (run on a clean git tree, after committing)
- `git status --porcelain` clean before and after the dry-run (no
  incidental side-effect files this time)

New commit:
```
415d41f add missing changelog bullet for close-time ready guard
 CHANGELOG.md | 3 +++
 1 file changed, 3 insertions(+)
```
