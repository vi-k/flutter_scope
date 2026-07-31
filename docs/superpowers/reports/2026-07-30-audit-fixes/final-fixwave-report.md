# Final fix-wave report

Branch: worktree-audit-fixes (worktree at
/Users/user/development/my/scopo/.claude/worktrees/audit-fixes)

## 1. Documentation overstates the closing screenshot

Did not touch `lib/src/utils/screenshot_replacer.dart` (pre-existing defect,
already tracked in TODO.md).

Changed:
- `README.md` feature bullet ("Graceful closing"): now says the freeze is
  "(debug builds only, best-effort)".
- `README.md` "Also in the box" `ScreenshotReplacer` bullet: added
  "(currently only succeeds in debug builds; elsewhere `buildOnClosing`
  renders over the live subtree instead)".
- `doc/h_scope.md` phase table row for `close()`: now reads "`buildOnClosing`,
  over a frozen screenshot of the ready subtree when one can be taken (debug
  builds only)".
- `doc/h_scope.md` "Disposal, unmount and close" section: appended "Taking the
  screenshot is best-effort and currently only works in debug builds; when it
  fails, `buildOnClosing` still runs, but over the live subtree instead of a
  frozen one."

No version promised for a future fix, per instructions.

## 2. CHANGELOG marker corrections (0.10.0 section)

a) Verified `typeToShortString` was never exported: `git show
   ea66419:lib/scopo.dart` (commit right before the 0.10.0 work started) shows
   the same export list as today's `lib/scopo.dart` — no `typeToShortString`
   anywhere, and no separate file exporting it either
   (`git log --all -S"typeToShortString"` shows the symbol only ever existed
   internally and was removed in `077fbb6`, "remove dead code, fix
   ScopeDependencyNoDisposalRequired typo"). Restructured the changelog: the
   `[breaking changes]` bullet now covers only the exported removals
   (`LiteScopeInitState`/`Waiting`/`Progress`/`Ready`) and the
   `ScopeDependencyNoDisposalRequred`→`Required` rename. Added a new, unmarked
   bullet: "Remove the internal, never-exported `typeToShortString`."

b) Split the pubspec bullet: "Add `repository`, `issue_tracker` and `topics`
   to pubspec." stays unmarked; the Flutter constraint tightening is now its
   own `[breaking changes]` bullet: "Tighten the Flutter constraint to
   `>=3.16.0` (was `>=1.17.0`), the version the package actually requires."
   Verified the actual before/after values with `git log -p -- pubspec.yaml`
   (diff shows `flutter: ">=1.17.0"` → `">=3.16.0"` in the same commit that
   added repository/issue_tracker/topics).

c) Reworded the logger_builder 0.5.0 bullet to state explicitly that scopo's
   own API is unaffected: "scopo's own API is unaffected, since
   `ScopeLogPublisher` and `ScopeLogFormatter` are unchanged in 0.5.0." Did
   not add `[breaking changes]` — confirmed by reading
   `~/.pub-cache/hosted/pub.dev/logger_builder-0.5.0/lib/src/custom_logger/custom_level_logger.dart`
   that `publisher`/`CustomLogPublisher` signatures are unchanged from 0.4.0,
   and scopo's `publishLog` (the new protected method) isn't part of the
   public API surface a consumer would call.

## 3. Contradictory timeout dartdoc

`lib/src/environment/scope_config.dart`: for both `defaultScopeKeysTimeout`
and `defaultWaitForChildrenTimeout`, changed "If zero, then the timeout is
disabled." to "If zero, then the timeout expires immediately." and clarified
the `null` case as "no timeout and the wait is unbounded." Verified against
`async_scope_core.dart:326` and `async_scope_coordinator.dart:164`: both do
`if (timeout != null) { future = future.timeout(timeout); }` — a zero
`Duration` is not `null`, so it goes through `Future.timeout(Duration.zero)`
and fires immediately, confirming the fix matches the code (and now matches
`doc/i_debug.md:161`, which was already correct).

## 4. Russian dartdoc on `ScopeDependencyException.name`

Translated the 3-line Russian dartdoc on
`lib/src/scope/h_scope/scope_auto_dependency/scope_dependency/scope_dependency_exception.dart`
to English, matching the wording already used in `doc/h_scope.md` (~198,
~231): "The path of the dependency that raised the error, without a leading
slash." / "An empty string means the anonymous root dependency itself
failed."

## 5. doc/h_scope.md path-format site count

Changed "The same strings appear in three places" to "four places" and added
the missing `ScopeDependencyInfo.path` entry to the list (alongside
`ScopeAutoDependenciesProgress.name`, the `debug` log, and
`ScopeDependencyException.name`).

## 6. README.md AsyncScope.of state access

Verified `lib/src/scope/e_async_scope/async_scope_context.dart`:
`AsyncScopeContext` declares `AsyncScopeState get state;` — there's no
`.data`-like passthrough, so `.of()` returns the context and `.state` is the
actual state getter. Changed "read the current state with
`AsyncScope.of(context, listen: …)`." to "...`AsyncScope.of(context, listen:
…).state`.", matching the style of the `AsyncDataScope.of<Database>(context,
listen: false).data` example a few lines below.

## 7. README Documentation section — topic page links

Built the docs with `dart doc --output
/private/tmp/claude-502/-Users-user-development-my-scopo/a9a276dc-ace9-420b-b3b4-033004554e9b/scratchpad/dartdoc-fixwave`
(0 warnings, 0 errors) and inspected `<output>/topics/`. Actual generated
filenames: `Scope-topic.html` and `debug-topic.html` (also present:
`AsyncDataScope-topic.html`, `AsyncScope-topic.html`, `LiteScope-topic.html`,
`ScopeModel-topic.html`, `ScopeNotifier-topic.html`, `ScopeWidget-topic.html`,
`base-topic.html` — all following the same `<CategoryName>-topic.html`
pattern, which is dartdoc's standard, stable convention). Added to the README
Documentation section:
- `[Scope topic](https://pub.dev/documentation/scopo/latest/topics/Scope-topic.html)`
- `[debug topic](https://pub.dev/documentation/scopo/latest/topics/debug-topic.html)`

Not skipped — filenames were established directly from the generated build,
not guessed.

## 8. test/scope_logger_test.dart global logger leak

Moved the capture/restore into `setUp`/`tearDown`: now captures
`ScopeConfig.logger.level`, `ScopeConfig.logger.transformer`, and (the
previously-missed) `ScopeConfig.logger[ScopeLogLevel.debug].publisher` before
the test runs, and restores all three afterward, replacing the old ad hoc
`ScopeConfig.logger.level = ScopeLogLevel.off;` reset at the end of the test
body (which never restored the publisher, leaving it pointed at the test's
local `out` list/closure for any later test).

Load-bearing check (hand-revert, not git stash): edited
`lib/src/environment/scope_logger.dart`'s `ScopeLevelLogger.processLog` to
call `publisher.publish(ScopeLog(...))` directly instead of
`publishLog(ScopeLog(...))`, then ran `flutter test
test/scope_logger_test.dart`:

```
00:00 +0 -1: transformer rewrites and drops logs [E]
  Expected: ['scopo|kept', 'scopo | child|kept from sub']
    Actual: [
              'scopo|kept',
              'scopo|noisy one',
              'scopo | child|kept from sub',
              'scopo | child|noisy from sub'
            ]
     Which: at location [1] is 'scopo|noisy one' instead of 'scopo | child|kept from sub'
Some tests failed.
```

Confirmed the test fails as expected (the transformer is bypassed when
`publisher.publish` is called directly, since `publishLog` is what applies
`CustomLogger.transformer` before publishing — see
`logger_builder-0.5.0/lib/src/custom_logger/custom_level_logger.dart`).
Restored the one-line edit by hand afterward; `git diff --
lib/src/environment/scope_logger.dart` showed no diff, confirming a clean
revert. Re-ran the test with the fix in place: passes.

## Verification (after all changes, before commit)

- `flutter analyze` (root): No issues found!
- `flutter analyze` (example/minimal): No issues found!
- `flutter analyze` (example/scopo_demo): No issues found!
- `flutter test` (root): 00:00 +55: All tests passed!
- `dart format --output=none --set-exit-if-changed` on the 3 changed `.dart`
  files: 0 changed, exit 0.
- `dart doc --output <scratchpad>/dartdoc-fixwave`: Found 0 warnings and 0
  errors.
- `flutter pub publish --dry-run`: 1 warning before commit (only the
  "6 checked-in files are modified in git" advisory, which disappears once
  committed — no content/lint warnings from the package validator itself).

## Commit

Single commit: `address final review findings`.
