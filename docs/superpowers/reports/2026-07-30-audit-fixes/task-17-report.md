# Task 17 report: CHANGELOG + dartdoc-страницы категорий

Status: DONE
Commit: `ba37c6b` — "changelog per-version sections, debug and scope doc pages"

Files changed (6): `CHANGELOG.md`, `doc/i_debug.md`, `doc/h_scope.md`,
`lib/src/environment/scope_logger.dart`, `lib/src/scope/a_base/base.dart`,
`TODO.md`.

## Step 1 — CHANGELOG: version attribution evidence

`## 0.9.3-0.9.5` was split into three sections. Every release between v0.9.2 and
v0.9.6 is exactly one commit, so attribution is unambiguous:

```
$ git log v0.9.2..v0.9.6 --oneline --decorate
ea66419 (tag: v0.9.6) upgrade logger_builder ...
7487ca5 (tag: v0.9.5) replace ellipsis characters
3c46950 (tag: v0.9.4) minor logging changes
d23316e (tag: v0.9.3) fix bug on dispose AsyncScopeElementBase
```

The CHANGELOG as it stood at each tag shows how the two existing bullets
accumulated, which fixes the attribution:

```
$ git show d23316e:CHANGELOG.md | head -4
## 0.9.3

* Fix some bug on dispose `AsyncScopeElementBase`.

$ git show 3c46950:CHANGELOG.md | head -5
## 0.9.3-0.9.4

* Fix some bug on dispose `AsyncScopeElementBase`.
* Minor logging changes.
```

So:

| version | commit    | bullet                                             | evidence |
| ------- | --------- | -------------------------------------------------- | -------- |
| 0.9.3   | `d23316e` | `Fix some bug on dispose `AsyncScopeElementBase`.` | the bullet was introduced by this commit under a `## 0.9.3` heading; the diff touches `async_scope_core.dart` + `screenshot_replacer.dart` |
| 0.9.4   | `3c46950` | `Minor logging changes.`                           | this commit added exactly this bullet and renamed the heading to `0.9.3-0.9.4`; diff is 20 changed log strings in `async_scope_core.dart`, plus `async_scope_coordinator.dart`, `scope_auto_dependency.dart`, `scope_dependency_group.dart` |
| 0.9.5   | `7487ca5` | `Replace ellipsis characters in log messages.` (new bullet) | this commit added **no** bullet — its only CHANGELOG change was `-## 0.9.3-0.9.4` / `+## 0.9.3-0.9.5`. Its lib/ diff is `'initialize...'` → `'initialize…'`, `'dispose...'` → `'dispose…'` in `async_scope_core.dart` and `scope_auto_dependency.dart` (plus the same in the demo widgets) |

Note on 0.9.5: it also bumped `ansi_escape_codes` from `^3.0.2` to `^3.1.2`, but
that is a **dev_dependency** (confirmed in `pubspec.yaml`), so it is not
user-visible and got no bullet. This is why 0.9.5 got a real one-line bullet
instead of the fallback `* Minor changes.` — the ellipsis change is genuinely
user-visible (it is in the log output of the published library).

Normalization applied file-wide: exactly one blank line after every `## `
heading (11 sections had none: 0.7.0, 0.6.3, 0.6.2, 0.6.1, 0.6.0, 0.5.0, 0.4.1,
0.4.0, 0.3.3, 0.3.2, 0.3.1). Also collapsed the stray double blank line between
`## 0.7.0` and `## 0.6.3`. Verified with a script: 30 headings, zero
non-conforming, zero double blank lines anywhere. No bullet text of an old
section was rewritten.

No `## 0.10.0` section was added — left for Task 18 per the parent's
instruction (this overrides the brief's Step 1, which asked for a placeholder).

## Step 2 — `doc/i_debug.md`

Written from the source, not from memory. Sections: **Levels** (threshold table
with the real numeric values from `logger_builder`'s `Levels`, and what the
package actually writes at each), **Output** (per-level publisher,
`ScopeLogFormatter`, the `ScopeLog` fields, the `ScopeLogger.defaultFormat`
layout, path composition and `pathSeparator`, `ScopeLogFn` laziness,
`ScopeLevelLogger`), **Per-level colors** (the `ansi_escape_codes` pattern from
both example apps), **Timeouts**, **pauseAfterInitializationEnabled**, **In
tests**.

Ground truth used:

- `lib/src/environment/scope_config.dart`, `scope_logger.dart`;
- `example/minimal/lib/main.dart:9-33` and `example/scopo_demo/lib/main.dart:15-52`;
- `test/utils/logging.dart`;
- the actual log-level call sites: `grep '_log.v('` → **zero hits in lib/**, so
  the page states honestly that `verbose` is registered but unused by the
  package. `_log.d` → 21 calls, `_log.i` → 8, `_log.e` → 3;
- a **real** captured log line rather than an invented one, from
  `flutter test test/scope_auto_dependencies_test.dart --reporter expanded`:
  `[d] scopo | TestDependencies(#25f53) | progress: dep1 (1/10)`;
- timeout semantics read from `async_scope_core.dart:322-348` and
  `async_scope_coordinator.dart:150-186`: `null` ⇒ no `.timeout()` at all ⇒
  waits indefinitely; an expiry is reported via `FlutterError.reportError` and
  is **non-fatal** (the scope proceeds). The page documents `null` and a
  `Duration`; it deliberately does not repeat the source dartdoc's claim that
  "if zero, then the timeout is disabled", because `Duration.zero` actually
  makes the wait give up immediately rather than removing the timeout — see
  "Concerns" below.

## Step 3 — `doc/h_scope.md`

Sections: the three parts of a scope; **The initialization branch** (the stream
contract, a phase→builder table, `wrapState`, `pauseAfterInitialization`, a
hand-written container, `asStream`, the four named function types);
**ScopeAutoDependencies** (`buildDependencies`, `dep`/`sequential`/`concurrent`,
`DepHelper`, the context type parameter, the wiring call,
`ScopeAutoDependenciesProgress`, `autoDisposeOnError`, `root` /
`flattenDependencies` / `flattenDependenciesWithErrors` /
`ScopeDependencyInfo` / the `ScopeDependencyState` family);
**Dependency paths**; **Errors**; **Disposal, unmount and close** (the six
ordered steps); **Access from the subtree**.

Ground truth: `lib/src/scope/h_scope/**` (`scope_base.dart`,
`scope_core.dart`, `scope_dependencies.dart`, `scope_init_state.dart`,
`scope_auto_dependency/**`), plus `example/scopo_demo/lib/home/home_dependencies.dart`,
`home.dart`, `demos/g_scope/counter_scope.dart` and
`test/scope_auto_dependencies_test.dart`.

Canonical dependency-path format documented as required: segments joined by `/`,
**no leading slash**, and an anonymous group (`name == ''`) contributes neither a
segment nor a separator. Grounded in `scope_dependency_mixin.dart:104-111`
(`name.isEmpty ? error.name : '$name/${error.name}'`, the Task 1 fix),
`scope_auto_dependency.dart:111` (`dependency.name.isEmpty ? path : '$path${dependency.name}/'`),
`scope_dependency_group.dart:27` (`_path`), and confirmed against real output
from the test run above:
`progress: concurrent1/sequential1/concurrent2/dep5 (5/10)`. The page states the
format without naming a version number, since 0.10.0 is not released yet.

The teardown order (unmount → cancel/await init → await children → state
`disposeAsync` → `dependencies.dispose` → release `scopeKey`) was verified by
reading the call chain rather than assumed:
`ScopeElementBase.unmount()` (`scope_core.dart:171`) calls
`_dependencies?.unmount()` **before** `super.unmount()`, which is
`ScopeWidgetElementBase.unmount()` (`scope_widget_core.dart:83`) → `dispose()` →
`AsyncScopeElementBase.dispose()` (`async_scope_core.dart:156`) →
`_performAsyncDispose()`; and `ScopeElementBase.disposeAsync()`
(`scope_core.dart:177`) awaits `super.disposeAsync()` (the state) before
`_dependencies.dispose()`.

### Code snippets are type-checked, not eyeballed

Every Dart snippet from both pages was assembled into a scratch file
(`test/zz_doc_snippets_probe.dart`, deleted afterwards) and run through
`flutter analyze`. This caught two real defects in my first draft:

1. `HomeDependencies().init(context)` on a `ScopeAutoDependencies<…, void>`
   container triggers `void_checks` ("Assignment to a variable of type 'void'").
   Fixed in the page to `init(null)`, with a following sentence explaining that
   a `BuildContext` container forwards the `context` instead. (The demo dodges
   this by passing the `init` tear-off through a `ScopeInitFunction` field —
   too indirect for an introductory page.)
2. `ScopeLogFormatter(format: ScopeLogger.defaultFormat, output: print)`
   triggers `prefer_const_constructors`. Fixed to `const ScopeLogFormatter(…)`
   in the tests snippet. (The `debugPrint` and `printer.print` variants are
   correctly non-const, since neither is a constant expression.)

Final probe run: 1 issue, and it was `avoid_classes_with_only_static_members` on
my throwaway `SharedPreferences` stub, i.e. an artifact of the probe file, not
of any documented snippet.

## Step 4 — `{@category debug}` annotations

`lib/src/environment/scope_logger.dart`: added `{@category debug}` to all seven
elements from the brief. Five had no dartdoc at all and got a one-line English
description in the style of `scope_config.dart`:

| element             | dartdoc before | added |
| ------------------- | -------------- | ----- |
| `ScopeLogPublisher` | none           | "The destination of the log events of a single level." |
| `ScopeLogFormatter` | none           | "A [ScopeLogPublisher] that converts a [ScopeLog] into an [Out] …" |
| `ScopeLogLevel`     | none           | "The logging level thresholds used by the package." |
| `ScopeLogFn`        | none           | "The signature of the logging methods of a [ScopeLogger]." + the laziness note |
| `ScopeLog`          | none           | "A single log event produced by a [ScopeLogger]." |
| `ScopeLevelLogger`  | none           | "The logger of one level of a [ScopeLogger] …" |
| `ScopeLogger`       | none           | "The logger of the package, rooted at `ScopeConfig.logger`." |

Result on the generated `topics/debug-topic.html`: it listed **one** element
before (`ScopeConfig`) and now lists **eight** — classes `ScopeConfig`,
`ScopeLevelLogger`, `ScopeLog`, `ScopeLogger`, `ScopeLogLevel`; typedefs
`ScopeLogFn`, `ScopeLogFormatter`, `ScopeLogPublisher`.

Also removed the junk dartdoc `/// saaa` from
`lib/src/scope/a_base/base.dart:7` (brief Step 4). See "Concerns" — this file
was in the brief's header but missing from the parent's commit-file list, so it
was committed together with the rest.

Note: `ScopeConfig.logger` cannot be used as a doc reference target from the
part file's dartdoc in every position, and `[message]` on a function typedef is
not a resolvable element, so both are written as inline code. Verified by build,
not by guesswork.

## CRITICAL verification — `dart doc`

`dartdoc_options.yaml` escalates `unresolved-doc-reference` to an error, so this
was checked twice.

**Probe first** (before writing the pages), to learn whether `[Foo]` references
resolve inside category markdown at all:

```
$ printf '# debug\n\nProbe: [ScopeLogger] and [ScopeConfig.logger] and [ScopeLogLevel.debug].\n' > doc/i_debug.md
$ dart doc --output …/dartdoc-probe
Generating docs for category debug from package:scopo...
  error: unresolved doc reference [ScopeLogger]
    from debug: (…/doc/i_debug.md)
  error: unresolved doc reference [ScopeConfig.logger]
    from debug: (…/doc/i_debug.md)
  error: unresolved doc reference [ScopeLogLevel.debug]
    from debug: (…/doc/i_debug.md)
Found 0 warnings and 3 errors.
dartdoc … failed: encountered 3 errors
```

They do **not** resolve — category markdown has no library scope. So both pages
use inline code spans for identifiers and absolute GitHub URLs for the two
example links; there is not a single `[…]` doc reference in either page. (In
`lib/`, where references do resolve, `[ScopeLog]`, `[ScopeLogPublisher]`,
`[Out]`, `[ScopeLogger]`, `[withAddedName]`, `[path]` and the inherited
`[publisher]` were all used and all resolved.)

**Final build, after all edits:**

```
$ dart doc --output /private/tmp/claude-502/…/scratchpad/dartdoc-out
Documenting scopo...
Generating docs for category base from package:scopo...
… (all nine categories) …
Generating docs for library scopo.dart from package:scopo/scopo.dart...
Found 0 warnings and 0 errors.
Documented 1 public library in 13.5 seconds
Success! Docs generated into …/dartdoc-out
```

**Zero errors and zero warnings**, from my files or anywhere else — there are no
pre-existing dartdoc warnings in this package to record.

Rendering spot-checked in the generated HTML: both pages produce
`<pre class="language-dart">` blocks (4 on debug, 5 on Scope) and one
`language-text` block each, and both markdown tables rendered as real
`<table>`s.

## Step 5 — TODO.md

Appended a `Документация:` section (Russian, matching the file) with the three
items from the brief, plus one gap found while verifying the category pages:

- the remaining 7 `doc/*.md` stubs, named explicitly (a_base, b_scope_widget,
  c_scope_model, d_scope_notifier, e_async_scope, f_async_data_scope,
  g_lite_scope);
- `screenshots:` missing from `pubspec.yaml` (verified absent);
- the Russian comments in `lib/`. The brief said 78 lines; the measured numbers
  are **107** Cyrillic lines across **9** files, of which **80** are dartdoc
  (`///`) and therefore public. The accurate numbers went into TODO.md;
- **added beyond the brief:** `ScopeState`, `ScopeDependencyException`,
  `ScopeDependencyInfo`, `DepHelper`, `ScopeDependenciesExtension` and
  `ScopeDependencyExtension` are missing `{@category Scope}`, so they do not
  appear on the Scope topic page even though the new `doc/h_scope.md` documents
  them. Recorded rather than fixed, since the brief scoped the annotation work
  to `scope_logger.dart` only.

## Baselines — all held

| check | result |
| ----- | ------ |
| `flutter test` | `00:00 +54: All tests passed!` (54/54) |
| `flutter analyze` (root) | `No issues found!` |
| `flutter analyze` (example/minimal) | `No issues found!` |
| `flutter analyze` (example/scopo_demo) | `No issues found!` |
| `flutter pub publish --dry-run` | `Package has 0 warnings.` (re-run after the commit; the pre-commit run's single warning was the "uncommitted changes" notice) |
| `dart doc` | `Found 0 warnings and 0 errors.` |

## Concerns / deviations

1. **`lib/src/scope/a_base/base.dart` is in the commit but was not in the
   parent's file list.** It *is* in the brief's `**Files:**` header and in the
   brief's Step 4 ("удалить мусорный dartdoc `/// saaa` в `base.dart:7`"), so I
   treated the omission as an oversight and included the one-line deletion.
   Flagging it explicitly in case the parent wants it split out.
2. **Source dartdoc for the timeouts is misleading.** `ScopeConfig`'s dartdoc
   says "If zero, then the timeout is disabled" for both
   `defaultScopeKeysTimeout` and `defaultWaitForChildrenTimeout`. Reading the
   code, `Duration.zero` is passed straight to `future.timeout(...)`, so it
   makes the wait give up almost immediately (reporting a `TimeoutException`
   through `FlutterError.reportError`) — the *waiting* is disabled, not the
   timeout. `null` is the value that removes the timeout. `doc/i_debug.md`
   documents `null` and a positive `Duration` accurately and stays silent about
   zero rather than contradicting the API docs on their own page. Fixing the
   `scope_config.dart` wording is a separate one-line change, out of scope here.
3. **Category markdown H1s kept.** Both pages keep their `# debug` / `# Scope`
   H1, which dartdoc renders *below* its own `<h1>debug topic</h1>`, so the
   heading appears twice on the generated page. Kept for consistency with the
   seven remaining stub files (all of which are just `# Name`); worth deciding
   once, for all nine pages, when the stubs get filled in.
4. The relative-link option for cross-references (e.g.
   `../scopo/ScopeLogger-class.html`) was deliberately not used: it works in the
   generated output but is coupled to dartdoc's output layout and breaks when
   the `.md` is read in the repo.
