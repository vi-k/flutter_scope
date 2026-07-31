# Task 14 report: pubspec.yaml — метаданные pub.dev

**Status:** DONE
**Commit:** 087622d — "add pub.dev metadata, honest flutter constraint"

## What changed

- `pubspec.yaml`: added `repository`, `issue_tracker`, `topics` after `homepage`;
  changed `environment.flutter` from `">=1.17.0"` to `">=3.16.0"` (Flutter 3.16
  ships Dart 3.2, matching `sdk: ^3.2.0` and the Dart-3 class modifiers already
  used in `lib/`). `version:` left at 0.9.6 as instructed.
- `analysis_options.yaml` (root) and `example/scopo_demo/analysis_options.yaml`:
  `include:` switched from `package:lints/recommended.yaml` to
  `package:flutter_lints/flutter.yaml`. The hand-written `linter.rules` block
  is unchanged (still overrides/wins) except for the one explicit addition
  below. `example/minimal/analysis_options.yaml` already used
  `package:flutter_lints/flutter.yaml` — untouched.
- `test/utils/my_fake_async.dart`: two debug-only `@visibleForTesting` helpers
  switched `print(...)` → `debugPrint(...)` (added
  `import 'package:flutter/foundation.dart' show debugPrint;`).
- `.gitignore`: added `/docs/` (see "unrelated fix" below).
- Ran `flutter pub get` in root + both examples. Neither example's
  `pubspec.lock` changed (already resolved consistently with
  `flutter_lints: ^5.0.0`), so no lockfile changes were needed/committed.

## Lint findings surfaced by the include switch (Step 3 triage)

Switching to `flutter_lints/flutter.yaml` activates flutter-specific rules
not present in `lints/recommended.yaml`. Ran `flutter analyze` in root and
both examples after the switch:

- `example/scopo_demo`: 0 new findings.
- `example/minimal`: 0 new findings (already on flutter_lints).
- root: **3 new findings**, all triaged and resolved without any
  `// ignore:` comments:

1. **`no_logic_in_create_state`** (warning) —
   `lib/src/scope/g_lite_scope/lite_scope_core.dart:288`,
   `S createState() => _createState();` inside `_LiteScopeCoreWidget`.
   Design-decision case: `_LiteScopeCoreWidget` is a generic internal
   `StatefulWidget` that receives an injected `S Function() createState`
   factory from its owner, because the generic type parameter `S` can't be
   instantiated directly (`new S()` isn't legal Dart). This is the
   intentional factory pattern used throughout the `*Core` widget hierarchy
   (same delegation shape appears in `scope_base.dart:222` and
   `lite_scope_base.dart:205`, but those override a different abstract
   `createState()` on the *State* class, not `StatefulWidget.createState()`,
   so the lint doesn't fire there). Restructuring to satisfy the rule would
   mean rearchitecting the generic factory injection — out of scope for a
   lint-config task. Resolved per the brief's "keep the hand-written rules
   block" guidance: added an explicit
   `no_logic_in_create_state: false # [flutter] ...` line with a comment in
   `analysis_options.yaml`'s `linter.rules`, replacing the old
   documentation-only commented line for this rule.

2. **`avoid_print`** (info) x2 — `test/utils/my_fake_async.dart:166,171`,
   inside `printPendingTimers()` / `printFakeAsyncPendingTimers()`
   (`@visibleForTesting` manual-debugging helpers, not called anywhere in
   the codebase; a pre-existing, already-tracked bug where their two bodies
   are swapped is noted in `TODO.md` and intentionally left alone — out of
   scope here). Trivially fixable: swapped `print()` for `debugPrint()`
   (standard Flutter idiom for the `avoid_print` lint, no behavior change
   in tests, no ignore comment needed).

## Unrelated fix required to hit "0 warnings"

`flutter pub publish --dry-run` reported a second, pre-existing warning
unrelated to lints: an untracked stray file
`docs/superpowers/plans/2026-07-30-audit-fixes.md` (a duplicate of this
project's planning doc, apparently written by generic planning-skill
tooling to its default `docs/` location instead of this project's actual
gitignored `.superpowers/sdd/` working directory) was being picked up by
`pub`'s file-selection (untracked-but-not-ignored counts as included), and
`pub` additionally flagged the top-level `docs/` (plural) directory as
violating the singular `doc/` naming convention. This file/directory
existed before this task started and is unrelated to any of task 14's
code changes, but it blocked the explicit "0 warnings" verification
requirement. Fixed minimally by adding `/docs/` to root `.gitignore`
(mirroring the existing `.superpowers/sdd/.gitignore`'s `*` pattern) — no
content was deleted, the file simply no longer ships in the package.

## Verification

- `flutter analyze`: 0 issues in root, `example/scopo_demo`, and
  `example/minimal`.
- `flutter test` (root): 54/54 passing.
- `flutter pub publish --dry-run`: **0 warnings** (clean git state after
  commit).
- Example `pubspec.lock` files unchanged by `flutter pub get` (already
  committed and consistent).
