# Task 15 report: README.md — переписать

**Status:** DONE
**Commit:** 3e64af2 — "rewrite README" (`README.md` + `TODO.md`, 345 insertions / 98 deletions)

## What changed

`README.md` rewritten from scratch (98 old lines → 345). New structure:

1. Title + badges (`pub version`, `license`) + a 4-line intro.
2. **Features** — 7 bullets, each checked against `lib/` (see "Claims" below).
3. **Installation** — `flutter pub add scopo` + the import line.
4. **Scope** — the three parts of a scope, then
   `1. Dependencies` / `2. State` / `3. The scope widget` /
   `4. Access from descendants`.
5. **Specialized scopes** — `ScopeWidgetBase`, `ScopeModel`, `ScopeNotifier`,
   `AsyncScope`, `AsyncDataScope`, `LiteScope` (a paragraph + a compiled
   snippet each), closing with a link to `scopo_demo`.
6. **scopeKey** — the serialization semantics + the mandatory
   `AsyncScopeCoordinator`.
7. **Logging and configuration** — level, per-level publisher, both timeouts,
   `pauseAfterInitializationEnabled`.
8. **Also in the box** — `NavigationNode`, `ProgressIterator`,
   `ScreenshotReplacer`.
9. **Examples** — `minimal` and `scopo_demo` on GitHub.
10. **Documentation** — API reference, pub.dev page, changelog.

`TODO.md`: the `- Update README!!!` line removed (Step 4).

Brief items resolved:

| Brief item | Resolution |
| --- | --- |
| `:76-78` `init(BuildContext)` → `initDependencies(BuildContext)` | done (`scope_base.dart:83`) |
| `:29-48` add `@override void unmount() {}` | done (`scope_dependencies.dart:9`) |
| `:118-129` `class` → `final class`, drop own `child`, add `super.key` | done — `final class ApiConfig extends ScopeWidgetBase<ApiConfig>` with `required super.child` (the field is inherited from `ScopeInheritedWidget`) |
| `:175-201` delete `ScopeAsyncInitializer` / `ScopeStreamInitializer` | done — both sections gone; replaced by the real `AsyncScope` / `AsyncDataScope` sections |
| `:210` `// Get State (listen: true by default)` | done — the sample now says `// Reads the state without subscribing to it.` and the prose states "`Scope.of` never subscribes" (`scope_base.dart:158-163`, hard-coded `listen: false`) |
| `:46,141` `Dipose` → `Dispose` | done — both lines were rewritten; `grep -rn Dipose` over `lib/`, `example/`, `*.md` now only hits the plan/brief documents themselves |
| Step 3: remove `> [!WARNING] README needs updating!` | done |
| Step 2: Installation / Logging / family overview / example links / badges | done |

## Sample verification

Method: a throwaway Flutter package outside the repo,
`/private/tmp/.../scratchpad/readme-check/`, with
`scopo: {path: <worktree>}`, `shared_preferences: ^2.5.5`, `flutter_lints: ^5.0.0`,
`flutter_test`, and an `analysis_options.yaml` that includes
`package:flutter_lints/flutter.yaml` plus the package's own strictness
(`strict-casts`, `strict-inference`, `strict-raw-types`). Every fenced Dart
block was pasted into `lib/sample_*.dart` with the imports it shows or implies;
where a snippet references an object the reader is expected to own
(`connection`, `Database`, `HomeScreen`, `UserModel`, `Counter`, `ApiKeyView`)
a minimal stub was added to the sample file and marked as such.

`flutter analyze` in the scratch package: **No issues found** (0 errors,
0 warnings, 0 infos). Six of the snippets were additionally pumped in widget
tests (`test/samples_test.dart`) — **6/6 pass**, so they are runtime-correct,
not merely type-correct.

A script then checked that every one of the 13 fenced `dart` blocks in
`README.md` appears verbatim (ignoring blank/comment lines) inside a verified
sample file — **13/13 matched**, so no block drifted from what was compiled.

| # | README block | Sample file | analyze | runtime test |
| --- | --- | --- | --- | --- |
| 1 | `import 'package:scopo/scopo.dart';` | all | clean | n/a |
| 2 | `AppDependencies implements ScopeDependencies` (§1) | `sample_1_quickstart.dart` | clean | — |
| 3 | `AppState extends ScopeState` (§2) | `sample_1_quickstart.dart` | clean | — |
| 4 | `App extends Scope` (§3) | `sample_1_quickstart.dart` | clean | — |
| 5 | `HomeScreen` with `select`/`selectParam`/`of` (§4) | `sample_1_quickstart.dart` | clean | — |
| 6 | `ApiConfig extends ScopeWidgetBase` | `sample_5_scope_widget.dart` | clean | PASS (renders its `child`, `apiKeyOf` resolves) |
| 7 | `ScopeModel<UserModel>` + `of`/`select` | `sample_6_scope_model.dart` | clean | PASS |
| 8 | `ScopeNotifier<Counter>` + `select`/`of` | `sample_7_scope_notifier.dart` | clean | PASS (tap → rebuild) |
| 9 | `AsyncScope(init/dispose/…)` | `sample_8_async_scope.dart` | clean | PASS (reaches the ready branch) |
| 10 | `AsyncDataScope<Database>(…)` | `sample_9_async_data_scope.dart` | clean | PASS (incl. `AsyncDataScope.of<Database>(context, listen: false).data`) |
| 11 | `ScreenScope extends LiteScope` + state | `sample_10_lite_scope.dart` | clean | PASS |
| 12 | `AsyncScopeCoordinator(child: MaterialApp(...))` | `sample_12_coordinator.dart` | clean | — |
| 13 | `main()` logging/timeouts config | `sample_11_logging.dart` | clean | — |

Blocks 2-5 are one progressive app, so they were verified together in a single
file (they reference each other; verifying them separately is impossible).
Sample 12 also covers the inline `ScopeConfig.pauseAfterInitializationEnabled`
claim.

The scratch directory is outside the repo; nothing in the worktree was deleted
or moved. The old README's three broken samples are gone, so there is no
"before" column to compare.

## Claims checked against the code

- `Scope.of` is hard-coded `listen: false` (`scope_base.dart:158-163`) — README
  says so explicitly.
- `ScopeDependencies` has both `unmount()` and `dispose()`
  (`scope_dependencies.dart:7-13`).
- `ScopeWidgetBase` is `abstract base class`, and `ScopeInheritedWidget` already
  owns `child` with a `_NullWidget` default (`a_base/base.dart:4-14`);
  `ScopeWidgetElementBase.build() => buildChild()`
  (`scope_widget_core.dart:247`), so returning the inherited `child` from
  `build` is legitimate — confirmed by the widget test.
- `scopeKey` requires `AsyncScopeCoordinator` in the context, otherwise a
  `FlutterError` is thrown (`async_scope_coordinator.dart:29-36`). This is a
  real trap for a first-time user and was not mentioned anywhere in the old
  README; it now has its own short section.
- Timeout defaults are 3 s each and `null` means "no timeout"
  (`scope_config.dart:18-25`).
- `ScopeLogger` levels: `verbose`/`debug`/`info`/`error` + `off`/`all`;
  `logger[level].publisher` is the per-level publisher
  (`scope_logger.dart:9-16`, `logger_builder-0.4.0` `CustomLogger.operator []`).
- Closing: `LiteScopeCore` wraps the subtree in `ScreenshotReplacer` and
  overlays `buildOnClosing()` (`lite_scope_core.dart:202-224`) — the
  "Graceful closing" feature bullet.
- `LiteScope.buildOnWaiting` is abstract and its `null` result falls through to
  `buildOnInitializing(null)`, which throws `UnimplementedError` unless `init`
  is overridden (`lite_scope_base.dart:60-77`, `lite_scope_core.dart:185`), so
  the README sample returns a real widget instead of `null`.

## Brief-vs-code discrepancies

1. **Brief says the `ScopeWidget` snippet should keep a `child` field "already
   present in `ScopeInheritedWidget`" — it is present, but it is not wired to
   the element.** `ScopeWidgetElementBase.build()` ignores `widget.child` and
   uses `buildChild() => widget.build(this)`; the in-repo comment says "Not
   used by default. You can use it at your own discretion." So `required
   super.child` + `build => child` works (verified at runtime) but it is a
   convention, not a framework guarantee. The demo's own
   `ScopeWidgetBase` example (`scope_widget_example.dart`) does not use `child`
   at all. Code followed, brief's intent preserved.
2. **Brief calls the section "ScopeWidget"; no such class exists** — the public
   API is `ScopeWidgetBase` (+ `ScopeWidgetCore`). The heading was renamed to
   `ScopeWidgetBase`. (`{@category ScopeWidget}` is only the dartdoc category
   name.)
3. **Brief's logging snippet source (`example/minimal/lib/main.dart:9-33`) uses
   `package:ansi_escape_codes`**, a dev-only dependency of the example. Copying
   it verbatim would put a third-party package into the README's first
   configuration snippet, so the snippet keeps the same API calls
   (`ScopeConfig.logger.level`, `ScopeConfig.logger[level].publisher =
   ScopeLogFormatter(format: ScopeLogger.defaultFormat, output: …)`) with
   `debugPrint` as the output.
4. **`example/README.md` is stale** (out of scope here, it is Task 16): its
   copy of `minimal/lib/main.dart` still shows `class AppDependencies` without
   `unmount()` and `buildOnError(..., Object? progress)`. Not touched.
5. `pubspec.yaml` is still at `0.9.6` (Task 18 bumps it); the README does not
   mention a version, so no coupling.

## Style decisions

- English only, concise how-to tone, one snippet per concept; depth is left to
  the dartdoc category pages (Task 17) and the two example apps.
- `…` (U+2026) instead of `...` in prose and in the one progress string, to
  match commit 7487ca5 ("replace ellipsis characters"), which deliberately
  converted `...` → `…` across the repo.
- All lines ≤ 80 chars except the two badge lines (unsplittable).
- Snippet formatting follows `dart format` output (that is what the scratch
  package was analyzed with), so the blocks can be copy-pasted into a project
  without reformatting.

## Verification (worktree, after the commit)

- `flutter analyze` → **No issues found** (0 issues).
- `flutter test` → **54/54 pass**.
- `flutter pub publish --dry-run` → **Package has 0 warnings.**
- Scratch package: `flutter analyze` → 0 issues; `flutter test` → 6/6 pass.

## Fix after review (commit 2)

**Finding (Important):** `README.md:365` and `:374` misdescribed the `LiteScope`
waiting phase.

**Re-verified empirically**, not just read: a probe added to the scratch package
(`test/lite_scope_waiting_test.dart`, 3 tests, all pass) measured

- a `LiteScope` with **no** `scopeKey` and no `init` override: `buildOnWaiting`
  is built once and its widget stays mounted for **2 frames**; the ready branch
  first appears on the 3rd pump. The default
  `init() => Stream.value(AsyncScopeReady())` (`lite_scope_base.dart:51`) is
  delivered asynchronously, so the waiting branch is *always* rendered — the old
  wording "the state is created immediately" was wrong;
- the same scope **with** a `scopeKey` (under an `AsyncScopeCoordinator`):
  identical waiting branch, so the branch is not scopeKey-specific — the old
  comment "Shown while waiting for `[scopeKey]` to be released" was wrong by
  omission;
- `buildOnWaiting` returning `null` with no `init`/`buildOnInitializing`
  override: **`UnimplementedError` on the first frame**, reproducible
  (`buildOnState`: `buildOnWaiting() ?? buildOnInitializing(null)` —
  `lite_scope_core.dart:185`; the default `buildOnInitializing` throws —
  `lite_scope_base.dart:65-66`).

**Changes** (nothing else touched):

- prose: "the state is created immediately and gets the full scope lifecycle" →
  "the state is created without an async dependency phase, and still gets the
  full scope lifecycle";
- snippet comment: "Shown while waiting for `[scopeKey]` to be released." →
  "Shown on the first frames, and while waiting for `[scopeKey]`. Returning
  `null` here requires overriding `[buildOnInitializing]`."

**Re-verification:** the amended block was re-extracted into
`sample_10_lite_scope.dart` — scratch `flutter analyze` 0 issues, scratch
`flutter test` 9/9 pass (6 original + 3 new probes), `dart format` clean, and the
13/13 README-block containment check still passes. Root `flutter analyze`
0 issues, `flutter test` 54/54, `flutter pub publish --dry-run` 0 warnings.
