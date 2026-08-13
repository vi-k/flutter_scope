# audit-fixes — журнал и отчёты по задачам

> **Состояние на 2026-08-12:** работа завершена и смержена в `main` (9ee497d). Исторический документ, не поддерживается.
> **Что это:** склейка 37 файлов эпизода 2026-07-30 — журнал хода работ (`progress.md`) и брифы/отчёты 18 задач. Тексты сохранены дословно, границы исходных файлов отмечены заголовками `## Файл: …`.
> **Связанные записи:** план — `2026-07-30[1]-audit-fixes-plan.md`, итог — `2026-07-30[3]-audit-fixes-final-report.md`.

## Файл: progress.md

# SDD ledger — plan: docs/superpowers/plans/2026-07-30-audit-fixes.md

Worktree: /Users/user/development/my/scopo/.claude/worktrees/audit-fixes (branch worktree-audit-fixes)
Baseline: тесты красные by design (17 failed) — план это чинит; flutter analyze: 3 pre-existing issues (чинятся Task 11).
Pre-flight note: Task 18 Step 3 (push тега + pub publish) выполняется НЕ из worktree — отложено до finishing-a-development-branch, где пользователь решает про merge/публикацию. Version bump/CHANGELOG/dry-run — выполняются.
Task 1: minor (deferred): handleInitFor(cancel) не задействован новым тестом; dartdoc у ScopeDependencyException.name описывает структурно недостижимый сегодня случай пустого имени (формулировка из brief).
Task 1: complete (commits ea66419..95076b1, review clean)
Task 2: complete (commits 95076b1..c24fcca, review clean)
Task 3: complete (commits c24fcca..98c39fe, review clean) — весь flutter test впервые зелёный
Task 4: fix round 0 note — сниппет брифа был дефектен (prefix-only import dart:core глушит неявный импорт); первый имплементер (haiku) умер на API-ошибке; передиспатч на sonnet с dual-import решением.
Task 4: complete (commits 98c39fe..f277ab9, review clean)
Task 5: minor (deferred): (1) комментарий в scope_dependency_group.dart:143-146 и отчёт описывают defect 2 как живой баг, хотя sync-controller буферизует done — переформулировать как defensive invariant; (2) init() имеет ту же empty-set дыру — guard добавлен, теста нет; (3) тест проверяет только флаг disposed, не состояние группы.
Task 5: complete (commits f277ab9..f6e8cda, review clean)
Task 6: complete (commits f6e8cda..347603b, review clean)
Task 7: fix round 1/5 (2 addressed, 0 open — path-2 тест по runAsync-рецепту + флаг _initSucceeded вместо model.state; commits 550a338..6eb72a0); направление одобрено пользователем (AskUserQuestion).
Task 7: minor (deferred): isInitialized теперь намеренно расходится с _initSucceeded (задокументировано); событие после Ready (StateError→error state) теперь получает disposeAsync — правильное направление, но не отражено в отчёте имплементера.
Task 7: complete (commits 347603b..6eb72a0, re-review approved)
Task 8: fix round 1/5 (3 addressed, 0 open — ??= для _screenshotCompleter, кап retry (maxRetries=5), _isDisposing guard; commits 6cf403f..69aea2b)
Task 8: minor (deferred): (1) maxRetries — счётчик кадров, не дедлайн: сцена, честно рисующаяся >6 кадров, закроется без скриншота; (2) give-up оставляет _isCaptured=false — живой child под оверлеем (осознанный трейд-офф); (3) ScreenshotReplacer.maxRetries — НОВОЕ публичное API, нужно упомянуть в CHANGELOG (передать в Task 18); (4) тесты используют внутренние harness-API (attachRootWidget/buildScope) — связь с версией Flutter; (5) опциональное усиление: ставить _isDisposing до await барьера в LiteScopeElementBase.
Task 8: в Task 10 (TODO.md) добавить: release-mode debugNeedsPaint кидает LateInitializationError (кап фактически debug-only); событие стрима после Ready → 'Bad state: Future already completed' (рядом с TODO в async_scope_core.dart:306); Stream.error не доходит до модели под AutomatedTestWidgetsFlutterBinding.
Task 8: complete (commits 6eb72a0..69aea2b, re-review approved)
Task 9: minor (deferred): путь _log.e('dispose error') не покрыт тестом (ни одна фикстура не кидает в dispose) — прозрачно зафиксировано имплементером.
Task 9: complete (commits 69aea2b..2120927, review clean)
Task 10: complete (commits 2120927..44b9bd5, review clean) — TODO.md пополнен 10 пунктами (5 из брифа + 5 из ревью Task 5-8)
Task 11: complete (commits 44b9bd5..0f97e03, review clean) — flutter analyze теперь 0 issues в корне и обоих примерах (новый baseline для последующих задач)
Task 12: complete (commits 0f97e03..077fbb6, review clean)
Task 13: complete (commits 077fbb6..c7ef8bc, review clean)
Task 14: note — попутно добавлен /docs/ в .gitignore (нетрекаемый план тулинга ломал pub dry-run doc-check); проверено, /doc/ пакета не задет.
Task 14: complete (commits c7ef8bc..087622d, review clean) — flutter_lints включён в корне и scopo_demo, no_logic_in_create_state отключён документированно, print→debugPrint в тест-хелпере
Task 15: minor (deferred): (1) README:316 — «AsyncScope.of(context).state», а не сам of() возвращает состояние; (2) README:23-24 — «never rebuilds own subtree» слегка абсолютизировано (_forceRebuild/autoSelfDependence); (3) авто-зависимости (ScopeAutoDependencies) и ScopeStateModel/ListenableView в README не упомянуты — кандидат для doc-страниц Task 17.
Task 15: fix round 1/5 запущен (1 Important: описание waiting-фазы LiteScope; README:365,374)
Task 15: fix round 1/5 (1 addressed — LiteScope waiting-фаза; commits 3e64af2..c959326)
Task 15: minor (deferred): [buildOnInitializing] в README-сниппете — dartdoc-ссылка рендерится как текст (стилистически совместимо с pre-existing [scopeKey]/[App]).
Task 15: complete (commits 087622d..c959326, re-review approved)
Task 16: complete (commits c959326..d594f48, review clean)
Task 17: minor (deferred): doc/h_scope.md:203-210 — иллюстративный dart-фенс с '…' как плейсхолдером (не компилируется дословно; сборку не ломает).
Task 17: complete (commits d594f48..ba37c6b, review clean) — dart doc: 0 warnings 0 errors
Task 18: fix round 1/5 (1 addressed — недостающий буллет _isDisposing; commits 93c22e9..415d41f)
Task 18: complete (commits ba37c6b..415d41f, re-review approved) — версия 0.10.0, tag/push/publish отложены до finishing
=== Все 18 задач исполнены. Финальное whole-branch ревью. ===
Post-plan (запрос пользователя): logger_builder 0.4.0 -> 0.5.0 (commit 1e7f96c). Breaking в 0.5.0: processLog обязан звать publishLog(...) вместо publisher.publish(...), иначе transformer игнорируется — правка в ScopeLevelLogger.processLog. Добавлен typedef ScopeLogTransformer + раздел «Filtering and rewriting» в doc/i_debug.md + регрессионный тест test/scope_logger_test.dart (55 тестов). Верификация: analyze 0 (корень+2 примера), test 55/55, dry-run 0 warnings, dart doc 0/0. Буллет добавлен в секцию 0.10.0 CHANGELOG.
Финальное whole-branch ревью: первый заход (agent ac82b2a55b56550fc) оборван лимитом сессии — нужен повторный прогон, включая этот коммит.
Финальное ревью: заход 2 (agent ac82b2a55b56550fc, fable) упал на лимите Fable 5. Заход 3 — на opus, с сужением фокуса: покоммитная корректность уже покрыта по-задачными ревью (task-N-report.md + скоуп-ре-ревью), финальному отданы кросс-задачная целостность, точность CHANGELOG/публичного API, триаж отложенных minor и готовность к релизу.
Финальное ревью (заход 3, opus): READY TO MERGE. Critical 0. Important 2 (#1 README/doc обещают работающий screenshot-freeze, хотя в release debugNeedsPaint кидает LateInitializationError -> capture недоступен; #2 три правки маркеров [breaking changes] в CHANGELOG). Minor 3,4,5,7,8,9 — мелкие правки в файлах ветки. Все 18 отложенных minor протриажены как ship; 8.5 (_isDisposing до барьера) признан ИЗБЫТОЧНЫМ (доказано), 8.3 (maxRetries в CHANGELOG) — закрыт. ScopeLogTransformer признан оправданным, не scope creep.
Решение контроллера по Important #1: выбран путь честной документации (вариант b), а НЕ кодовый фикс (вариант a) — assert-gate + retry-на-падении-toImage непроверяем в debug-харнессе, а публиковать неверифицированное изменение в путь закрытия рискованно; кодовый фикс остаётся в TODO.md.
Fix-волна (одна, по правилам SDD) запущена.
Fix-волна: commit 5d07fda (все 8 пунктов). Скоуп-ре-ревью: все findings ADDRESSED, новых поломок нет, НО найден блокер публикации — обоснование в буллете про Flutter-констрейнт было ложным: lite_scope_core.dart зовёт Color.withValues, которого нет ниже Flutter 3.27, т.е. >=3.16.0 резолвился бы у тех, кто затем не соберётся. Причина промаха Task 14: пол выводился только из Dart-констрейнта, без аудита framework-API.
Проверка версии (контроллер, локально и авторитетно): первый framework-коммит с withValues (52bb0c4, 2024-09-03) содержится в теге 3.27.0 и ни в одном более раннем; 3.29.2 несёт Dart 3.7.2 => 3.27 <-> Dart 3.6.
Исправлено контроллером в commit f7a3696: pubspec sdk ^3.6.0 + flutter >=3.27.0, тот же пол в обоих примерах, буллет CHANGELOG переписан на правду, добавлено предложение в doc/h_scope.md о том, что провал скриншота не молчаливый (ошибка уходит в зону). Верификация: analyze 0 (корень+2 примера), test 55/55, dry-run 0 warnings.
Остаточный minor (ревьюер: ship as-is): TODO.md попадает в архив пакета с русской секцией известных проблем.
СТАТУС: ветка готова к мержу и к публикации. Ждём решения пользователя.


---

## Файл: task-1-brief.md

### Task 1: выровнять построители B и C по пустому имени

**Files:**
- Modify: `lib/src/scope/h_scope/scope_auto_dependency/scope_dependency/scope_dependency_mixin.dart:100-116`
- Modify: `lib/src/scope/h_scope/scope_auto_dependency/scope_auto_dependency.dart:106`
- Test: `test/scope_auto_dependencies_test.dart` (новый тест в конце `main`)

**Interfaces:**
- Produces: `ScopeDependencyException.name` и `ScopeDependencyInfo.path` больше не содержат ведущий `/` и двойные `//`. Задача 2 опирается на этот формат.

- [ ] **Step 1: падающий тест на безымянную вложенную группу**

```dart
group('anonymous nested group paths', () {
  test('no leading or double slashes', () {
    final dependencies = TestDependenciesAnonNested(failed: {'depB'});
    myFakeAsync((async) {
      final progress = handleInitFor(dependencies, async);
      expect(progress, ['depA (1/2)', 'depB: Exception: depB failed']);
      expect(
        dependencies
            .flattenDependencies()
            .map((info) => '${info.path}${info.dependency.name}')
            .toList(),
        ['', 'depA', 'depB'], // корень + два ребёнка, без '/' и '//'
      );
    });
  });
});
```

где `TestDependenciesAnonNested` строит `sequential('', [dep('depA', …), concurrent('', [dep('depB', …)])])` — по образцу существующего `TestDependencies` (строки 14–83). Вспомогательный `handleInitFor` — копия логики `handleInit()` (строки 89–127), параметризованная экземпляром.

- [ ] **Step 2: убедиться, что тест падает** — `flutter test test/scope_auto_dependencies_test.dart --name 'anonymous'`; ожидаемое падение: `'/depB: …'` или `'//depB…'` вместо `'depB: …'`.

- [ ] **Step 3: фикс построителя B** — `scope_dependency_mixin.dart`, ветка `error is ScopeDependencyException`:

```dart
ScopeDependencyException(
  name.isEmpty ? error.name : '$name/${error.name}',
  error.error,
  error.stackTrace,
),
```

(Ветку `else` с голым `name` не менять: для безымянной группы её собственная ошибка даёт `name == ''` — допустимо, `toString()` выведет `': <error>'`; поведение зафиксировать dartdoc-комментарием у `ScopeDependencyException.name`: «путь без ведущего слэша; пустая строка — ошибка безымянного корня».)

- [ ] **Step 4: фикс построителя C** — `scope_auto_dependency.dart:106`:

```dart
yield* _extract(
  child,
  level + 1,
  dependency.name.isEmpty ? path : '$path${dependency.name}/',
);
```

- [ ] **Step 5:** `flutter test … --name 'anonymous'` → PASS. Остальные 16 тестов всё ещё красные (чинятся Задачей 2). Коммит: `fix path building for anonymous dependency groups`.



---

## Файл: task-1-report.md

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


---

## Файл: task-2-brief.md

### Task 2: обновить 139 устаревших литералов в тестах

**Files:**
- Modify: `test/scope_auto_dependencies_test.dart` (1235 строк; 107 литералов с ведущим `/`, 32 литерала `[root]`)

- [ ] **Step 1: механическая замена**

```bash
sed -i '' \
  -e "s|'/dep|'dep|g" \
  -e "s|'/concurrent|'concurrent|g" \
  -e "s|'/sequential|'sequential|g" \
  -e 's|\[root\]|[group]|g' \
  test/scope_auto_dependencies_test.dart
```

- [ ] **Step 2: ревью diff'а** — `git diff test/` глазами: меняться должны только строковые литералы-ожидания (включая закомментированные блоки — не страшно); суффиксы вида `failed: concurrent1/dep2` внутри `states(...)`-строк остаются без изменений (у них и не было ведущего слэша).

- [ ] **Step 3:** `flutter test test/scope_auto_dependencies_test.dart` → **17/17 passed** (16 старых + тест Задачи 1). Если какой-то литерал не покрыт sed'ом — поправить вручную по фактическому diff'у из вывода теста.

- [ ] **Step 4:** Коммит: `update dependency path expectations after 3c46950`.



---

## Файл: task-2-report.md

# Task 2 Report: Update Dependency Path Expectations

## Summary
Successfully updated 140 dependency path expectations in `test/scope_auto_dependencies_test.dart` using sed replacements. All 17 tests pass without requiring hand-fixes.

## Commands Run

### Step 1: Mechanical Replacement
```bash
sed -i '' \
  -e "s|'/dep|'dep|g" \
  -e "s|'/concurrent|'concurrent|g" \
  -e "s|'/sequential|'sequential|g" \
  -e 's|\[root\]|[group]|g' \
  test/scope_auto_dependencies_test.dart
```

**Result:** Completed successfully with no output (as expected).

### Step 2: Git Diff Review
```bash
git diff test/scope_auto_dependencies_test.dart
```

**Analysis:** 
- Total changes: 140 insertions, 140 deletions across 509 diff lines
- All changes are to string literal expectations exactly as intended:
  - `'/dep` → `'dep` (removed leading slash from dependency names)
  - `'/concurrent` → `'concurrent` (removed leading slash)
  - `'/sequential` → `'sequential` (removed leading slash)
  - `[root]` → `[group]` (renamed group)
- Paths in "failed: ..." error messages remain unchanged (correct—they had no leading slashes)
- No unintended changes to other code

### Step 3: Test Execution
```bash
flutter test test/scope_auto_dependencies_test.dart
```

**Result:**
```
00:00 +17: All tests passed!
```

**Test count verification:**
- 16 original tests (from before Task 1)
- 1 new test from Task 1: "anonymous nested group paths no leading or double slashes"
- Total: 17 tests, all passing

**Hand-fixes needed:** None. All sed replacements were correct and comprehensive.

### Step 4: Commit
```bash
git commit -m "update dependency path expectations after 3c46950"
```

**Commit hash:** `c24fcca`
**Changed files:** 1 file changed, 140 insertions(+), 140 deletions(-)

## Statistics
- **Lines changed in diff:** 280 (140 insertions + 140 deletions)
- **String literals updated:** 140
  - Path expectations with leading `/` removed: ~107
  - `[root]` → `[group]` replacements: 32
  - Total matched expectation: 139-140 literals per brief
- **Hand-fixes applied:** 0
- **Test pass rate:** 17/17 (100%)

## Validation
✓ Sed replaced only expectation string literals
✓ Commented-out blocks were correctly updated (acceptable per brief)
✓ No lib/ code was modified
✓ No syntax errors introduced
✓ All 17 tests pass (16 old + 1 from Task 1)
✓ Only remaining failure is Task 3 (notifier_test.dart load failure)

## Conclusion
Task 2 complete. Dependency path expectations have been successfully updated from leading-slash format (`'/dep1`, `/concurrent1/dep2`, etc.) to the new format (`'dep1`, `'concurrent1/dep2`, etc.) with `[root]` renamed to `[group]`. All tests pass without requiring manual fixes.


---

## Файл: task-3-brief.md

### Task 3: оживить test/notifier_test.dart

Файл (201 строка) полностью закомментирован и валит сьют ошибкой «Missing definition of `main`». Он тестирует упаковку массива слушателей в `Notifier` (`lib/src/utils/listenable/notifier.dart`) — 19 тестов на хитрую логику `_packListeners()`; `TestNotifier` существует в lib **только** ради этого файла. Все символы на месте.

**Files:**
- Modify: `test/notifier_test.dart`

- [ ] **Step 1: раскомментировать весь файл.**
- [ ] **Step 2: исправить импорт** — `package:scopo/scopo.dart` не экспортирует `Notifier`; заменить на прямой путь (такой стиль уже используется в `scope_auto_dependencies_test.dart:6`):

```dart
import 'package:scopo/src/utils/listenable/notifier.dart';
```

- [ ] **Step 3:** `flutter test test/notifier_test.dart`. Если какие-то из 19 захардкоженных раскладок массива (`[f1,f2,f3,null]` и т.п.) не совпадают с текущим `_packListeners()` — сверить с реализацией и обновить ожидания (реализация первична: тест описывает internal layout).
- [ ] **Step 4:** Полный `flutter test` → все зелёные. Коммит: `revive notifier_test`.

---

## Фаза 2 — баги корректности (каждый с регрессионным тестом)



---

## Файл: task-3-report.md

# Task 3 report: revive test/notifier_test.dart

## Steps taken

1. Uncommented the entire file (previously 201 lines, all commented out, causing
   "Missing definition of `main`").
2. Fixed the import: replaced `import 'package:scopo/scopo.dart';` with
   `import 'package:scopo/src/utils/listenable/notifier.dart';` per the brief
   (matches the style already used in `test/scope_auto_dependencies_test.dart:6`
   for internal, non-exported symbols). Kept
   `import 'package:flutter_test/flutter_test.dart';` unchanged — `flutter_test`
   is already a `dev_dependency` in `pubspec.yaml` and re-exports `test`,
   `group`, `expect`, `setUp`, so no additional import was needed.
3. Ran `flutter test test/notifier_test.dart`.

## Result: no expectation changes needed

All 20 tests (5 in "add listeners", 15 in "remove listeners") passed on the
first run against the current `lib/src/utils/listenable/notifier.dart`
implementation. Every hardcoded array layout (including null-padding) already
matches what `_packListeners()` actually produces — I read `notifier.dart` in
full (the `addListener`, `removeListener`, and `_packListeners` bodies) and
traced the shrink-vs-compact-in-place branching (`newLength <= _listeners
.length ~/ 2`) against several of the trickier remove sequences (e.g. "f1
twice and f2 once", "f1 and f2 twice and f3 once") to confirm the compaction
algorithm's swap-and-null behavior lines up with the expected arrays before
trusting the green run. No `expect(...)` lines were altered — the test file's
logic is byte-for-byte the same as the commented-out original, only the
comment markers and the one import line were changed.

## Full suite

`flutter test` → all green (37 top-level test groups load, no failures).

## flutter analyze

3 issues found, identical to the pre-existing known set (no new issues
introduced):
- `invalid_annotation_target` warning in
  `example/scopo_demo/lib/home/demos/c_scope_notifier/scope_notifier_example2.dart:91`
- `avoid_classes_with_only_static_members` info in
  `lib/src/environment/scope_config.dart:7`
- `unnecessary_this` info in
  `lib/src/scope/h_scope/scope_auto_dependency/scope_auto_dependency.dart:25`

## lib/ changes

None. Only `test/notifier_test.dart` was modified.

## Commit

`98c39fe revive notifier_test` — 1 file changed (test/notifier_test.dart),
201 insertions(+), 201 deletions(-) (uncomment + import fix, net line count
unchanged).


---

## Файл: task-4-brief.md

### Task 4: `CompareUtils.identical` — бесконечная рекурсия (StackOverflow в публичном API)

`lib/src/utils/compare_utils.dart:7`: неквалифицированный вызов `identical` резолвится в сам статический метод, а не в `dart:core.identical`. Любой вызов → `StackOverflowError`. Экспортируется из `lib/scopo.dart:7`.

**Files:**
- Modify: `lib/src/utils/compare_utils.dart`
- Test: Create `test/compare_utils_test.dart`

- [ ] **Step 1: падающий тест**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:scopo/scopo.dart';

void main() {
  test('CompareUtils.identical does not recurse', () {
    final a = Object();
    expect(CompareUtils.identical(a, a), isTrue);
    expect(CompareUtils.identical(a, Object()), isFalse);
    expect(CompareUtils.notIdentical(a, Object()), isTrue);
  });
}
```

Ожидаемое падение: `StackOverflowError`.

- [ ] **Step 2: фикс** — квалифицировать ядро:

```dart
import 'dart:core' as core;
// …
static bool identical(Object? a, Object? b) => core.identical(a, b);
static bool notIdentical(Object? a, Object? b) => !core.identical(a, b);
```

- [ ] **Step 3:** тест PASS. Коммит: `fix infinite recursion in CompareUtils.identical`.



---

## Файл: task-4-report.md

# Task 4 Report: `CompareUtils.identical` infinite recursion

## Status: DONE

Commit: `f277ab9` — "fix infinite recursion in CompareUtils.identical"
Files: `lib/src/utils/compare_utils.dart`, `test/compare_utils_test.dart`

## Context / handoff note

Picked up mid-task from a prior implementer that was killed by an API error.
State found in the worktree:

- `test/compare_utils_test.dart` was already created and matched the brief — kept as-is.
- `lib/src/utils/compare_utils.dart` had a **half-applied, broken** fix:
  ```dart
  import 'dart:core' as core;
  // ...
  static bool identical(Object? a, Object? b) => core.identical(a, b);
  static bool notIdentical(Object? a, Object? b) => !core.identical(a, b);
  ```
  A prefix-only explicit `dart:core` import suppresses the implicit unprefixed
  `dart:core` import, which undefines `Object`/`bool` in the file. This was
  confirmed conceptually (and is exactly why the corrected two-import approach
  below is needed) — the fix was corrected before ever re-running analyze in
  that broken state, per the controller's resolution.

The brief's own Step 2 snippet (`import 'dart:core' as core;` alone) is the
same flawed pattern — it was not usable verbatim. Used the controller-provided
resolution instead: keep the qualified `core.identical` calls, but restore the
default (unprefixed) `dart:core` namespace by adding both imports.

## Step 1 — TDD evidence: failing test on original recursive code

Backed up the (broken, half-applied) working-tree file, then ran
`git checkout -- lib/src/utils/compare_utils.dart` to restore the last
committed version, which contains the original bug (unqualified `identical`
call inside the static method of the same name resolves to itself):

```dart
// ignore: avoid_classes_with_only_static_members
abstract final class CompareUtils {
  static bool equals(Object? a, Object? b) => a == b;

  static bool notEquals(Object? a, Object? b) => a != b;

  static bool identical(Object? a, Object? b) => identical(a, b);

  static bool notIdentical(Object? a, Object? b) => !identical(a, b);
}
```

Ran `flutter test test/compare_utils_test.dart`:

```
00:00 +0: loading /Users/user/development/my/scopo/.claude/worktrees/audit-fixes/test/compare_utils_test.dart
00:00 +0: CompareUtils.identical does not recurse
00:00 +0 -1: CompareUtils.identical does not recurse [E]
  Stack Overflow
  package:scopo/src/utils/compare_utils.dart 7:3   CompareUtils.identical
  package:scopo/src/utils/compare_utils.dart 7:50  CompareUtils.identical
  package:scopo/src/utils/compare_utils.dart 7:50  CompareUtils.identical
  ... (repeats hundreds of times) ...
  test/compare_utils_test.dart 7:25                main.<fn>

00:00 +0 -1: Some tests failed.

Failing tests:
  /Users/user/development/my/scopo/.claude/worktrees/audit-fixes/test/compare_utils_test.dart: CompareUtils.identical does not recurse
```

Confirms the expected `StackOverflowError` from infinite recursion at
`compare_utils.dart:7` (`CompareUtils.identical`).

## Step 2 — Applied fix

```dart
import 'dart:core';
import 'dart:core' as core;

// ignore: avoid_classes_with_only_static_members
abstract final class CompareUtils {
  static bool equals(Object? a, Object? b) => a == b;

  static bool notEquals(Object? a, Object? b) => a != b;

  static bool identical(Object? a, Object? b) => core.identical(a, b);

  static bool notIdentical(Object? a, Object? b) => !core.identical(a, b);
}
```

Checked `flutter analyze lib/src/utils/compare_utils.dart` immediately after
applying — no `unnecessary_import` (or any other) lint fired for the
unprefixed `import 'dart:core';` line, so the dual-import approach from the
brief's controller resolution was usable as-is; the top-level
`_identical`-helper alternative was not needed.

```
Analyzing compare_utils.dart...
No issues found! (ran in 0.1s)
```

## Step 3 — Passing test

```
$ flutter test test/compare_utils_test.dart
00:00 +0: loading /Users/user/development/my/scopo/.claude/worktrees/audit-fixes/test/compare_utils_test.dart
00:00 +0: CompareUtils.identical does not recurse
00:00 +1: All tests passed!
```

## Step 4 — Full `flutter analyze`

```
$ flutter analyze
Analyzing audit-fixes...
warning • The annotation 'override' can only be used on fields, getters, methods, or setters • example/scopo_demo/lib/home/demos/c_scope_notifier/scope_notifier_example2.dart:91:4 • invalid_annotation_target
   info • Classes should define instance members. Try adding instance behavior or moving the members out of the class • lib/src/environment/scope_config.dart:7:22 • avoid_classes_with_only_static_members
   info • Unnecessary 'this.' qualifier. Try removing 'this.' • lib/src/scope/h_scope/scope_auto_dependency/scope_auto_dependency.dart:25:36 • unnecessary_this

3 issues found. (ran in 1.5s)
```

Exactly the 3 known pre-existing issues (`invalid_annotation_target` in
`example/scopo_demo`, `avoid_classes_with_only_static_members` in
`scope_config.dart`, `unnecessary_this` in `scope_auto_dependency.dart`).
Zero issues in `compare_utils.dart`.

## Step 5 — Full `flutter test`

```
$ flutter test
...
00:00 +38: All tests passed!
```
Exit code 0. 38 tests total across `compare_utils_test.dart`,
`notifier_test.dart`, `scope_auto_dependencies_test.dart` — all green.

## Step 6 — Commit

Staged only the two files owned by this task (left untracked `docs/` alone —
not part of this task):

```
$ git status --porcelain
M  lib/src/utils/compare_utils.dart
A  test/compare_utils_test.dart
?? docs/
```

```
$ git commit -m "fix infinite recursion in CompareUtils.identical"
$ git log -1 --stat
f277ab9 fix infinite recursion in CompareUtils.identical
 lib/src/utils/compare_utils.dart |  7 +++++--
 test/compare_utils_test.dart     | 11 +++++++++++
 2 files changed, 16 insertions(+), 2 deletions(-)
```

## Concerns

None. The dual-import approach worked cleanly with no lint fallout, so the
alternative top-level-helper approach from the brief's controller note was
not exercised. `docs/` remains untracked/uncommitted in the worktree as found
— out of scope for this task.


---

## Файл: task-5-brief.md

### Task 5: вечное зависание dispose/init на пустом наборе стримов concurrent-группы

`scope_dependency_group.dart:129-141`: в `onListen` при пустом iterable цикл не выполняется, `controller.close()` не вызывается — стрим не завершается никогда. Достижимо: `concurrent('g', [...])`, где ни один `dep` не назначил `dep.dispose` → фильтр `.where((dep) => dep.disposalRequired)` пуст → `ScopeAutoDependencies.dispose()` ждёт вечно. Там же вторая гонка: `subscription.onDone(...)` навешивается **до** `subscriptions.add(subscription)` при sync-контроллере — синхронно завершившийся стрим видит пустой список и закрывает контроллер раньше времени.

**Files:**
- Modify: `lib/src/scope/h_scope/scope_auto_dependency/scope_dependency/scope_dependency_group.dart:129-141`
- Test: `test/scope_auto_dependencies_test.dart`

- [ ] **Step 1: падающий тест** (по образцу существующих, через `MyFakeAsync`):

```dart
test('dispose completes when no dependency requires disposal', () {
  // TestDependencies-вариант, где ни один initDep не задаёт dep.dispose
  final dependencies = TestDependenciesNoDispose();
  myFakeAsync((async) {
    // init до Ready, затем:
    var disposed = false;
    unawaited(dependencies.dispose().then((_) => disposed = true));
    async.waitFuture(...); // прокрутить все таймеры
    expect(disposed, isTrue); // сейчас: false — висит вечно
  });
});
```

- [ ] **Step 2: фикс** — в начале `onListen`:

```dart
controller.onListen = () {
  if (isEmpty) {
    controller.close();
    return;
  }
  // …
```

и переставить `subscriptions.add(subscription);` **до** навешивания `onDone` (собрать подписки циклом, обработчики `onDone` навесить после заполнения списка).

- [ ] **Step 3:** тест PASS, весь сьют зелёный. Коммит: `fix hang on empty concurrent stream set`.



---

## Файл: task-5-report.md

# Task 5 report: dispose/init hang on empty concurrent stream set

## Commit

`f6e8cda` — "fix hang on empty concurrent stream set"

Files changed:
- `lib/src/scope/h_scope/scope_auto_dependency/scope_dependency/scope_dependency_group.dart`
- `test/scope_auto_dependencies_test.dart`

## Bug

`_mergeStreams()` (extension on `Iterable<Stream<T>>`, used by both `_ScopeDependencyConcurrent.init()` and `.dispose()`) had two defects in its `onListen`:

1. On an empty iterable, the `for (final stream in this)` loop never runs, so `controller.close()` is never called — the returned stream (and everything awaiting it, transitively `ScopeAutoDependencies.dispose()`'s `completer.future`) never completes.
2. `subscription.onDone(...)` was wired immediately after each `stream.listen(...)` call but *before* `subscriptions.add(subscription)`. For a synchronously-completing child stream (e.g. a nested empty concurrent group, once fixed for defect 1, closes its `sync: true` controller synchronously inside `onListen`), the `done` event fires before the handler is attached and is silently dropped, or `subscriptions.remove(subscription)` runs against a list state one entry short — same class of hang/race.

Reachability: `_ScopeDependencyImpl.disposalRequired` is `state is ScopeDependencyInitialized && _helper?.dispose != null`. If a dependency's init callback never sets `dep.dispose`, it's Initialized but not disposal-required. `_ScopeDependencyConcurrent.dispose()` filters children with `.where((dep) => dep.disposalRequired)` before merging — a concurrent group whose children all skip `dep.dispose` produces an empty stream set, hitting defect 1 directly via `ScopeAutoDependencies.dispose()`.

## Fix

In `_mergeStreams()`'s `onListen`:
- Added an `if (isEmpty) { controller.close(); return; }` guard at the top (with the existing `// ignore: discarded_futures` convention used elsewhere in the same file, since `discarded_futures` is an enabled lint).
- Restructured to two loops: first collect all subscriptions into the list, then attach `onDone` handlers in a second loop — guaranteeing `subscriptions` is fully populated before any `onDone` callback can fire.

Diff (lib):
```dart
controller.onListen = () {
  if (isEmpty) {
    controller.close(); // ignore: discarded_futures
    return;
  }

  final subscriptions = <StreamSubscription<T>>[];

  for (final stream in this) {
    final subscription =
        stream.listen(controller.add, onError: controller.addError);
    subscriptions.add(subscription);
  }

  for (final subscription in subscriptions) {
    subscription.onDone(() {
      subscriptions.remove(subscription);
      if (subscriptions.isEmpty) {
        controller.close(); // ignore: discarded_futures
      }
    });
  }

  controller
    ..onPause = ...
```

## Test

Added `TestDependenciesConcurrentNoDispose` (root `ScopeDependency` is directly a `concurrent('g', [dep('depA', ...), dep('depB', ...)])`, neither `initDep` sets `dep.dispose`) and a new test:

`concurrent group with empty stream set > dispose completes when no child requires disposal` in `test/scope_auto_dependencies_test.dart`.

The test brings the dependencies to Ready via the existing `handleInitFor` helper (Task-1 helper, reused as-is), then calls `dependencies.dispose()` unawaited with a `disposed` completion flag, drives the fake-async event loop with `async.flushMicrotasks()`, and asserts `disposed` is `true`. This avoids calling `async.waitFuture()` directly on the hung `dispose()` future (which would throw `StateError('No more timers...')` from `MyFakeAsync._waitFutureResult` instead of demonstrating the actual hang), matching the brief's sketch pattern.

### Failing run (pre-fix, lib change stashed via `git stash push -- lib/.../scope_dependency_group.dart`)

```
00:00 +0 -1: concurrent group with empty stream set dispose completes when no child requires disposal [E]
  Expected: true
    Actual: <false>
```

### Passing run (post-fix, `git stash pop`)

```
00:00 +1: All tests passed!
```

## Full verification (post-fix)

- `flutter test`: `00:00 +39: All tests passed!` (38 baseline + 1 new).
- `flutter analyze`: exactly the same 3 pre-existing issues as baseline, no new issues introduced:
  - `invalid_annotation_target` — `example/scopo_demo/lib/home/demos/c_scope_notifier/scope_notifier_example2.dart:91:4`
  - `avoid_classes_with_only_static_members` — `lib/src/environment/scope_config.dart:7:22`
  - `unnecessary_this` — `lib/src/scope/h_scope/scope_auto_dependency/scope_auto_dependency.dart:25:36`

## Decisions / notes

- Kept the fix minimal and in the existing style (comments in Russian matching the surrounding file, same `// ignore: discarded_futures` convention).
- Root of the test's dependency tree is the concurrent group itself (not nested under a `sequential(...)` wrapper), so `ScopeAutoDependencies.dispose()` calls `dependencies.runDispose()` directly on the concurrent group — this exercises the exact reported path (top-level empty concurrent stream set) without needing to reach through additional layers.
- Did not add a second test explicitly targeting defect 2 (the nested synchronous-completion ordering race) since the brief only requested one failing test for the reported hang (defect 1), and the flat 2-leaf-dependency test never enters the `for` loop body at all (guarded by the `isEmpty` check), so it doesn't exercise defect 2. Defect 2 was still fixed per the brief's explicit instruction, since it's fully described and located in the same code block and only becomes reachable once nested empty concurrent groups exist after the defect-1 fix.
- Left the untracked `docs/` directory in the worktree untouched — unrelated to this task, not staged or committed.


---

## Файл: task-6-brief.md

### Task 6: `ScopeNotifierBase.update` не подписывается на новый Listenable

`lib/src/scope/d_scope_notifier/scope_notifier_base.dart:82-89`: при смене `widget.value` старый слушатель снимается, а на новый вызывается `removeListener` вместо `addListener` — все `select`/`of(listen: true)` навсегда перестают обновляться.

**Files:**
- Modify: `lib/src/scope/d_scope_notifier/scope_notifier_base.dart:86`
- Test: Create `test/scope_notifier_test.dart`

- [ ] **Step 1: падающий widget-тест**

```dart
testWidgets('swapping ScopeNotifier.value re-subscribes', (tester) async {
  final first = ValueNotifier(0);
  final second = ValueNotifier(100);
  Widget app(ValueNotifier<int> v) => MaterialApp(
        home: ScopeNotifier<ValueNotifier<int>>.value(
          value: v,
          child: Builder(
            builder: (context) => Text(
              '${ScopeNotifier.of<ValueNotifier<int>>(context).value}',
            ),
          ),
        ),
      );
  await tester.pumpWidget(app(first));
  await tester.pumpWidget(app(second));
  second.value = 101;
  await tester.pump();
  expect(find.text('101'), findsOneWidget); // сейчас: '100', обновления не приходят
});
```

(Точную сигнатуру конструктора/`of` сверить с `scope_notifier.dart` — примеры использования: `example/scopo_demo/lib/home/demos/c_scope_notifier/`.)

- [ ] **Step 2: фикс** — строка 86: `newWidget.value?.removeListener(...)` → `newWidget.value?.addListener(notifyDependents);`
- [ ] **Step 3:** PASS. Коммит: `fix listener re-subscription on ScopeNotifier.value swap`.



---

## Файл: task-6-report.md

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


---

## Файл: task-7-brief.md

### Task 7: post-frame колбэки AsyncScope без guard'ов

`lib/src/scope/e_async_scope/async_scope_core.dart`:
- `:227-236` — `addPostFrameCallback((_) { _model.update(state); })` без `mounted`-проверки (соседняя ветка `:222-226` проверяет). Если элемент снят в том же кадре, `_model` уже disposed → `notifyListeners` на мёртвом notifier + `markNeedsBuild` на defunct element.
- `:172-174` — `addPostFrameCallback((_) { _registerWithParent(); })` без guard'а; `visitAncestorElements` на неактивном элементе → assert.

**Files:**
- Modify: `lib/src/scope/e_async_scope/async_scope_core.dart:172-174, 227-236`
- Test: Create `test/async_scope_test.dart`

- [ ] **Step 1: падающий тест** — смонтировать `AsyncScope`-наследника и удалить его из дерева в том же кадре (`pumpWidget(scope)` → `pumpWidget(SizedBox())` без промежуточного кадра), убедиться, что нет исключений в `tester.takeException()` после `pump()`.
- [ ] **Step 2: фикс** — обе точки: `addPostFrameCallback((_) { if (!mounted) return; … });` (в `:227-236` — по образцу соседней ветки `:222-226`).
- [ ] **Step 3:** PASS. Коммит: `guard async scope post-frame callbacks with mounted`.



---

## Файл: task-7-report.md

# Task 7 report: mounted-guards post-frame колбэков AsyncScope

## Bug

`lib/src/scope/e_async_scope/async_scope_core.dart`, `_performAsyncInit`, has
two `SchedulerBinding.addPostFrameCallback` registrations that touch `this`/
`_model` without checking `mounted` first, unlike the sibling
`pauseAfterInitialization` branch a few lines below (which already does
`if (mounted) { _model.update(state); }`):

1. `:172-174` (before fix) — registers `_registerWithParent()` unconditionally
   on every mount. If the element is removed before this callback fires,
   `_registerWithParent` calls `visitAncestorElements` on a defunct element,
   which asserts: *"Looking up a deactivated widget's ancestor is unsafe."*
2. `:229-233` (before fix) — in the `AsyncScopeReady` branch's `else` arm
   (taken whenever `pauseAfterInitialization` is unset/disabled), registers
   `_model.update(state)` unconditionally.

## API read before writing the test

Read `async_scope_core.dart` fully, `async_scope.dart`, `async_scope_base.dart`,
`async_scope_model.dart`, `async_scope_state.dart`, and the class hierarchy it
sits on (`c_scope_model/scope_model_core.dart`, `c_scope_model/base.dart`,
`b_scope_widget/scope_widget_core.dart`, `g_lite_scope/lite_scope_core.dart`),
plus a working usage in
`example/scopo_demo/lib/home/demos/d_async_scope/counter_scope.dart` (a
`CounterScope extends AsyncScopeCore<CounterScope, CounterScopeElement>` with
a `CounterScopeElement extends AsyncScopeElementBase<...>` overriding
`initAsync()`/`disposeAsync()`/`buildOnState()`). Confirmed `AsyncScopeCore`/
`AsyncScopeElementBase` can be subclassed minimally (`scopeKey`,
`pauseAfterInitialization`, etc. all default to `null`) — this is the pattern
used for the test's `_RegisterRaceScope`/`_RegisterRaceScopeElement`.

Also traced Flutter's own `Element` lifecycle
(`framework.dart`: `mount`/`activate`/`deactivate`/`unmount`,
`_ElementLifecycle`, `Element.mounted => _widget != null`) and
`SchedulerBinding.handleDrawFrame` (persistent callbacks — which drive
`WidgetsBinding.drawFrame()`'s `buildScope()` + `finalizeTree()` — always run
to completion **before** the post-frame callback queue is drained, and both
happen synchronously with no yield point in between) to understand exactly
when these callbacks can observe a removed element, and why a plain
`pumpWidget(scope)` → `pumpWidget(SizedBox())` sequence (as sketched in the
brief) cannot reproduce the race: `SchedulerBinding.addPostFrameCallback`
callbacks always fire during the very next `handleDrawFrame()` after being
scheduled, and `WidgetTester.pumpWidget`/`pump()` always run a **full**
`handleDrawFrame()` — so a callback registered synchronously during `mount()`
(as callback 1 always is) is always drained within that same `pumpWidget`
call, before the test gets a chance to remove the widget in a *following*
call.

## Test approach

`test/async_scope_test.dart` mounts and removes the widget by driving
`BuildOwner.buildScope`/`finalizeTree` directly via
`tester.binding.buildOwner!`/`tester.binding.attachRootWidget(...)`, instead
of `pumpWidget`. This mounts the scope (scheduling the post-frame callback)
and later removes+unmounts it, all **without** ever calling
`handleDrawFrame()` — so the post-frame callback queue is never drained by
these steps. Only the final `await tester.pump()` actually draws a frame,
draining the now-stale callback against the already-defunct element.

This was chosen over an initially-attempted "have the scope's own `mount()`
synchronously call `setState()` on an ancestor to hide itself mid-build"
trick: that trick trips an *unrelated* Flutter framework invariant
(`Element.rebuild()`'s trailing `assert(!_dirty)`, since `markNeedsBuild()`
called on the currently-rebuilding element from deeper in its own
`updateChild()` call re-dirties it before that same `rebuild()` call
returns) — confirmed by reproducing that separate assertion failure while
building the test, unrelated to the guard being tested. The manual
`buildScope`/`finalizeTree` approach avoids that pitfall entirely and was
verified (see below) to reproduce the exact bug deterministically.

## Failing run (before lib fix)

```
$ flutter test test/async_scope_test.dart
00:00 +0: AsyncScope post-frame callbacks does not assert when the element is removed from the tree before the post-frame callback that registers it with the parent scope has a chance to run
══╡ EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK ╞════════════════════════════
The following TestFailure was thrown running a test:
Expected: null
  Actual: FlutterError:<Looking up a deactivated widget's ancestor is unsafe.
          At this point the state of the widget's element tree is no longer stable.
          To safely refer to a widget's ancestor in its dispose() method, save a reference to the
ancestor by calling dependOnInheritedWidgetOfExactType() in the widget's didChangeDependencies()
method.>
...
    file:///.../test/async_scope_test.dart line 62   (expect(tester.takeException(), isNull))
════════════════════════════════════════════════════════════════════════════
00:00 +0 -1: ... [E]
Some tests failed.
```

Confirms the assertion fires exactly as the brief describes, from
`AsyncScopeElementBase._registerWithParent` via the unguarded post-frame
callback in `_performAsyncInit`.

## Fix

Two one-line guards in `_performAsyncInit`, mirroring the existing
`if (mounted) { _model.update(state); }` style used a few lines below in the
`pauseAfterInitialization` branch:

```diff
     // Register with parent scope.
     SchedulerBinding.instance.addPostFrameCallback((_) {
+      if (!mounted) return;
       _registerWithParent();
     });
...
             SchedulerBinding.instance
               ..scheduleFrame()
               ..addPostFrameCallback((_) {
+                if (!mounted) return;
                 _model.update(state);
               });
```

## Passing run (after lib fix)

```
$ flutter test test/async_scope_test.dart
00:00 +0: AsyncScope post-frame callbacks does not assert when the element is removed from the tree before the post-frame callback that registers it with the parent scope has a chance to run
00:00 +1: All tests passed!
```

## Full verification

```
$ flutter test
...
00:00 +41: All tests passed!
```
41 tests total = baseline 40 + 1 new test. No other test regressed.

```
$ flutter analyze
Analyzing audit-fixes...
warning • invalid_annotation_target • example/.../scope_notifier_example2.dart:91:4
   info • avoid_classes_with_only_static_members • lib/src/environment/scope_config.dart:7:22
   info • unnecessary_this • lib/src/scope/h_scope/scope_auto_dependency/scope_auto_dependency.dart:25:36
3 issues found.
```
Same 3 pre-existing issues as baseline, unchanged.

```
$ dart format --set-exit-if-changed lib/src/scope/e_async_scope/async_scope_core.dart test/async_scope_test.dart
Formatted 2 files (0 changed) in 0.01 seconds.
```

## Why the second callback (`_model.update(state)` for `AsyncScopeReady`) has no test

Per the brief's fallback clause, this is deliberately **not** covered by a
test, only fixed defensively. It was not skipped for lack of trying — the
same `buildScope`/`finalizeTree`-driven technique used for callback 1 was
extended with `TestWidgetsFlutterBinding.idle()` (which runs `FakeAsync`'s
`elapse(Duration.zero)` — flushes all pending microtasks/zero-duration
timers **without** drawing a frame) to drive `initAsync()` to
`AsyncScopeReady()` and get this second callback scheduled, then remove the
element (again without drawing a frame), then call `idle()` repeatedly
(verified up to 10x) to let `_performAsyncDispose()` progress as far as
possible, before finally calling `pump()` to drain the stale callback.

Empirically (confirmed with temporary instrumentation, removed before
finalizing the diff — this repo's `flutter test`/`flutter analyze` reflect
the clean state):

- The callback *is* reached with `mounted == false`, matching the intended
  race.
- It never throws, before or after the fix. Root cause: element removal
  (`finalizeTree()` → `unmount()` → `AsyncScopeElementBase.dispose()`)
  synchronously calls `model.removeListener(notifyDependents)`
  (`ScopeNotifierElementBase.dispose()`) as part of the very same
  synchronous call that *starts* `_performAsyncDispose()` (which suspends at
  its first `await`, on `subscription.cancel()`). So by the time any
  post-frame callback in that same removal frame runs,
  the `_model` listener is already gone, making `notifyListeners()` (called
  from `_model.update(state)`) a harmless no-op — while `_model.dispose()`
  itself (the call that would make a subsequent `notifyListeners()` throw
  regardless of listener count, per `ChangeNotifier.notifyListeners()`'s
  `assert(debugAssertNotDisposed(this))`) sits at the *end* of that async
  chain and, experimentally, was only reached *after* `pump()` had already
  drained the stale callback — never before it, even with 10 extra `idle()`
  calls in between.
- Because `SchedulerBinding.addPostFrameCallback` callbacks always fire on
  the very next `handleDrawFrame()` after being scheduled (this code path
  also calls `scheduleFrame()`), and removal-driven disposal can only start
  (not finish) synchronously within that same `handleDrawFrame()`, there is
  no way to interleave "callback pending" + "disposal fully complete" that a
  deterministic widget test can construct: whichever frame drains the
  callback is necessarily the same frame (or an earlier/later one with
  nothing stale left to trigger) that starts disposal too late for it to
  race ahead.

The guard is still correct and worth keeping: relying on `_model`/`this`
being usable from a post-frame callback registered before disposal completes
is not an invariant worth depending on, even though this specific interleaving
of "stale + disposed" could not be forced to fail in-test.

## Self-review

- Diff is exactly the two `if (!mounted) return;` guards plus the new test
  file; no other lib files touched. All temporary print-based instrumentation
  used during investigation was reverted before finalizing.
- An unrelated untracked `docs/` directory exists in the worktree (not
  created by this task) — left untouched and not staged/committed.
- No `git stash` was used for the final failing-evidence capture: the two
  guards were removed with plain `Edit` calls, the failing run was captured,
  then the guards were reinstated with plain `Edit` calls and re-verified
  (target test, full suite, `flutter analyze`) before committing.

## Commit

```
550a338 guard async scope post-frame callbacks with mounted
```
Files: `lib/src/scope/e_async_scope/async_scope_core.dart`,
`test/async_scope_test.dart`.

---

## Follow-up fix (commit `6eb72a0`): review findings addressed

Task review on `550a338` returned two Important findings. Both are addressed
here; commit `6eb72a0`.

### Finding 1 — the "path 2 is untestable" claim above was wrong

The reviewer was right and built a deterministic failing test. My dead end
was real (`TestWidgetsFlutterBinding.idle()`/`FakeAsync.elapse(Duration.zero)`
genuinely cannot drive `_performAsyncDispose()`'s chain to completion — see
the now-corrected reasoning below), but I stopped one step short:
`WidgetTester.runAsync` escapes the `FakeAsync` zone entirely and runs a
**real** `Future.delayed` on the real event loop. That's enough for the real
Dart runtime to finish the pending `subscription.cancel()` continuation and
everything chained after it, including `_model.dispose()` — something
`FakeAsync.elapse`, even repeated, never did in this scenario.

The incorrect "Why the second callback ... has no test" section above (now
superseded by this section) was deleted from `test/async_scope_test.dart`
(it was a comment block only, never shipped as an assertion) and replaced
with a real test, `does not throw when the element is removed before the
post-frame callback that applies the ready state runs, and still runs
disposeAsync ...`. Recipe, matching the reviewer's:

1. Mount `_ReadyRaceScope` via `BuildOwner.buildScope` directly (as in the
   first test) — no frame drawn yet.
2. `await binding.idle();` — lets `initAsync()` (`Stream.value
   (AsyncScopeReady())`) deliver its value and the `AsyncScopeReady` branch
   run, scheduling the post-frame callback + `scheduleFrame()`, without
   drawing a frame (so the callback stays pending).
3. Remove the scope the same way (`attachRootWidget` + `buildScope` +
   `finalizeTree`, no frame drawn) — starts `_performAsyncDispose()`, which
   suspends at its first `await`.
4. `await tester.runAsync(() => Future<void>.delayed(const Duration
   (milliseconds: 20)));` — escapes `FakeAsync`, lets the real disposal
   chain (and `_model.dispose()`) actually finish.
5. `await tester.pump();` — draws the first real frame, draining the stale
   callback.
6. `expect(tester.takeException(), isNull);`

**Failing run (guard 2 removed by hand, no `git stash`):**

```
$ flutter test test/async_scope_test.dart
...
══╡ EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK ╞════════════════════════════
The following TestFailure was thrown running a test:
Expected: null
  Actual: FlutterError:<A _AsyncScopeNotifier was used after being disposed.
          Once you have called dispose() on a _AsyncScopeNotifier, it can no longer be used.>
...
    file:///.../test/async_scope_test.dart line 143   (expect(tester.takeException(), isNull))
════════════════════════════════════════════════════════════════════════════
00:00 +1 -1: ... [E]
Some tests failed.
```

Matches the reviewer's report verbatim (`A _AsyncScopeNotifier was used
after being disposed.`). Guard 2 was then restored by hand (`Edit`, no
`git stash`) and the run repeated:

```
$ flutter test test/async_scope_test.dart
00:00 +0: ... does not assert when the element is removed from the tree before the post-frame callback that registers it with the parent scope has a chance to run
00:00 +1: ... does not throw when the element is removed before the post-frame callback that applies the ready state runs, and still runs disposeAsync for the resources initAsync acquired
00:00 +2: All tests passed!
```

### Finding 2 — guard 2 suppresses `disposeAsync()` in a real leak window

Confirmed by construction: `_performAsyncDispose`'s
`if (model.state case AsyncScopeReady())` check (~line 324 before this fix)
reads `model.state`, which is only ever updated by the very callback guard 2
may skip. So: element removed in the frame that would drain the
init-completion callback → `_model.update(state)` never runs → `model.state`
stays at whatever it was before (e.g. `AsyncScopeWaiting`) → `_performAsyncDispose`
takes the "do not dispose of" branch → `disposeAsync()` (and whatever
resources a successful `initAsync()` acquired) leaks. This is a real
regression introduced by guard 2 in commit `550a338`, not a pre-existing bug
(before guard 2, `_model.update(state)` always ran and always set `_state`
to `AsyncScopeReady` *before* any crash from a dead listener, since
`ScopeStateNotifier.update` assigns `_state = value` before calling
`notifyListeners()`).

**Fix**, per the approved direction — track success independently of
`model.state`:

```diff
   final _initCompleter = Completer<void>();

+  /// Whether [initAsync] has definitively completed successfully (reached
+  /// [AsyncScopeReady]). Tracked separately from `model.state` because the
+  /// `_model.update(state)` call that applies it is behind a `mounted`
+  /// guard and may never run.
+  bool _initSucceeded = false;
+
   AsyncScopeCoordinatorEntry? _asyncScopeEntry;
...
           }
+          _initSucceeded = true;
           _log.i('initialized');
           _initCompleter.complete();
...
     try {
-      if (model.state case AsyncScopeReady()) {
+      if (_initSucceeded) {
         _log.i('dispose…');
```

`_initSucceeded = true` is set unconditionally in the `AsyncScopeReady`
case, after the `pauseAfterInitialization`/immediate-callback branching but
before `_initCompleter.complete()` — i.e. synchronously, regardless of
`mounted`, so it always reflects whether `initAsync()` itself succeeded,
independent of whether the (possibly guarded) UI-state update ever landed.
Since it's set at the exact point that *would* lead to `model.state`
becoming `AsyncScopeReady`, every case where the old check was `true` still
has `_initSucceeded == true` — this only *adds* correct `disposeAsync()`
calls, it never removes one that used to happen (also verified this
incidentally covers the pre-existing analogous risk in the
`pauseAfterInitialization` delayed branch, which has its own `mounted`
guard on the same `_model.update(state)` call).

**Error path checked** (asyncMap's `onError` branch, `AsyncScopeError`):
does not set `_initSucceeded`, so a failed `initAsync()` still correctly
skips `disposeAsync()`. Verified with a probe (`initAsync` that throws):
`disposeCount` stayed `0` and no exception leaked, both before and after
this fix — unchanged behavior.

**Leak made observable** — extended the same test
(`does not throw when the element is removed before the post-frame
callback that applies the ready state runs, and still runs disposeAsync
...`) with a `_ReadyRaceScopeElement.disposeCount` counter and a final
assertion: `expect(element.disposeCount, 1);`.

**Failing run (only the flag fix reverted by hand, guard 2 left in place, no
`git stash`)** — i.e. `_performAsyncDispose` restored to
`if (model.state case AsyncScopeReady())`:

```
$ flutter test test/async_scope_test.dart
...
══╡ EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK ╞════════════════════════════
The following TestFailure was thrown running a test:
Expected: <1>
  Actual: <0>
...
    file:///.../test/async_scope_test.dart line 155   (expect(element.disposeCount, 1))
════════════════════════════════════════════════════════════════════════════
00:00 +1 -1: ... [E]
Some tests failed.
```

Confirms the leak is real and observable (`initAsync()` ran, `disposeAsync()`
never did). The flag fix was then restored by hand and the run repeated —
passes (`disposeCount == 1`), shown above.

### Full verification after both fixes

```
$ flutter test
...
00:00 +42: All tests passed!
```
42 tests total = baseline 40 + 2 new tests in `async_scope_test.dart`
(the pre-existing `_registerWithParent` test, unchanged, plus the new
combined ready-state/disposeAsync test). No other test regressed.

```
$ flutter analyze
Analyzing audit-fixes...
warning • invalid_annotation_target • example/.../scope_notifier_example2.dart:91:4
   info • avoid_classes_with_only_static_members • lib/src/environment/scope_config.dart:7:22
   info • unnecessary_this • lib/src/scope/h_scope/scope_auto_dependency/scope_auto_dependency.dart:25:36
3 issues found.
```
Same 3 pre-existing issues as baseline, unchanged.

```
$ dart format --set-exit-if-changed lib/src/scope/e_async_scope/async_scope_core.dart test/async_scope_test.dart
Formatted 2 files (0 changed) in 0.01 seconds.
```
(One run reformatted a line that was too long; re-run after confirmed clean,
and tests were re-verified to still pass post-format.)

### Self-review (follow-up)

- No `git stash` used anywhere in this follow-up: both guard 2 and the
  `_initSucceeded`-based condition were reverted/restored with plain `Edit`
  calls, one at a time, to capture each failing run in isolation before
  restoring and moving to the next.
- `docs/` remains untracked/untouched, unrelated to this task.
- New commit only (`6eb72a0`), nothing amended.

### Commit

```
6eb72a0 fix disposeAsync suppression and add path-2 regression test
```
Files: `lib/src/scope/e_async_scope/async_scope_core.dart`,
`test/async_scope_test.dart`.


---

## Файл: task-8-brief.md

### Task 8: LiteScope.close() виснет вне состояния Ready + ScreenshotReplacer

- `lib/src/scope/g_lite_scope/lite_scope_core.dart:216-244`: `close()` ждёт `_screenshotCompleter`, который комплитится только из `ScreenshotReplacer` внутри `buildOnReady()`. Если scope в `Waiting`/`Progress`/`Error` — `close()` виснет навсегда.
- `lib/src/utils/screenshot_replacer.dart:51-71`: `finally { widget.onCompleted(); }` срабатывает и на retry-путях (`boundary == null`, `debugNeedsPaint`) — барьер скриншота не работает; `_image` никогда не `dispose()`-ится — утечка `ui.Image` на каждое закрытие.

**Files:**
- Modify: `lib/src/scope/g_lite_scope/lite_scope_core.dart:216-244`
- Modify: `lib/src/utils/screenshot_replacer.dart`
- Test: Create `test/lite_scope_test.dart`

- [ ] **Step 1: падающий тест** — `LiteScope` в состоянии `Waiting` (инициализация не стартовала/не завершена), вызвать `close()`, прокрутить кадры, ожидать завершения future от `close()` (сейчас — timeout).
- [ ] **Step 2: фикс `close()`** — ждать `_screenshotCompleter` только если он реально будет закомплекчен: создавать/ждать его только когда текущее состояние — Ready (т.е. `buildOnReady` активен); иначе пропускать барьер.
- [ ] **Step 3: фикс `ScreenshotReplacer._capture()`** — убрать `onCompleted()` из `finally`; вызывать его явно в конце успешной ветки и в терминальных ошибочных ветках, но **не** на retry-путях (`return` до вызова). В `State.dispose()` добавить `_image?.dispose();`.
- [ ] **Step 4:** PASS + весь сьют. Коммит: `fix LiteScope.close hang and ScreenshotReplacer lifecycle`.



---

## Файл: task-8-report.md

# Task 8 report: `LiteScope.close()` hang + `ScreenshotReplacer` lifecycle

Branch: `worktree-audit-fixes` (worktree `.claude/worktrees/audit-fixes`).

## Files touched

- `lib/src/scope/g_lite_scope/lite_scope_core.dart` (Bug A)
- `lib/src/utils/screenshot_replacer.dart` (Bug B)
- `test/lite_scope_test.dart` (new, 6 tests)

## The exact "will `buildOnReady()` render" condition

Derived from the state machine, not guessed:

1. `ScopeWidgetElementBase.build() => buildChild()` (`b_scope_widget/scope_widget_core.dart:247`).
2. `AsyncScopeElementBase.buildChild() => buildOnState(model.state)`
   (`e_async_scope/async_scope_core.dart:370`).
3. `LiteScopeElementBase.buildOnState()` is an exhaustive switch over the sealed
   `AsyncScopeState`, and **only** `AsyncScopeReady()` maps to `buildOnReady()`
   (`g_lite_scope/lite_scope_core.dart:186-192`). `AsyncScopeWaiting` →
   `buildOnWaiting()`/`buildOnInitializing(null)`, `AsyncScopeProgress` →
   `buildOnInitializing(progress)`, `AsyncScopeError` → `buildOnError(...)`.
4. `buildOnReady()` is the only place that mounts a `ScreenshotReplacer`, and the
   replacer's `onCompleted` is the only thing that releases
   `_screenshotCompleter`.

So the barrier can only ever be released if **both** hold:

- `state is AsyncScopeReady` (`state` ⇒ `model.state`, a plain field read — safe
  even after `_model.dispose()`), **and**
- the element is still in the tree, i.e. the `markNeedsBuild()` that
  `_performAsyncDispose` issues actually results in another `buildChild()` call.

The second half is not a hypothetical: `markNeedsBuild()` only queues the
element; if the parent removes the subtree in the same frame, `buildScope`
skips the (now inactive) element and the `ScreenshotReplacer` is never mounted
at all. That case is covered by the third test and by the `dispose()` guard
below (before the fix it hung exactly like the non-ready states).

## Fix A — `lite_scope_core.dart`

- `close()` now installs the barrier only when it can be released:
  `if (mounted && state is AsyncScopeReady) { _screenshotCompleter = Completer(); }`.
  In every other state `close()` goes straight to `_performAsyncDispose()`,
  which still calls `markNeedsBuild()` (so `buildOnClosing()`-less non-ready
  builders keep rebuilding as before) but no longer awaits anything.
- Extracted `_completeScreenshot()` (idempotent) out of the inline closure in
  `buildOnReady()`, and call it from a new `dispose()` override, so an element
  that leaves the tree mid-close releases the barrier instead of deadlocking
  the in-flight `close()` (and, with it, `disposeAsync()` of the scope state).
  `dispose()` runs from `ScopeWidgetElementBase.unmount()` **before**
  `AsyncScopeElementBase.dispose()` re-enters `_performAsyncDispose()`, so the
  barrier is already released when that chain resumes.
- `markNeedsBuild()` from the unmount path stays a no-op (Flutter returns early
  for non-`active` elements), unchanged behaviour.

## Fix B — `screenshot_replacer.dart`

- `onCompleted` is reported through `_reportCompleted()`, guarded by
  `_isCompletionReported`, so it fires **exactly once** for the lifetime of the
  state (previously: once from `finally` + once from `dispose()` = twice, and
  also once per retry attempt).
- The retry paths (`boundary == null`, `boundary.debugNeedsPaint`) now `return`
  **without** reporting completion, so the barrier is not released before the
  screenshot exists. `boundary == null` used to be a terminal path; since it is
  now a retry path, the reschedule also calls `scheduleFrame()` (same idiom as
  `async_scope_core.dart`) — an `addPostFrameCallback` alone only runs if
  something else happens to schedule a frame.
- Terminal paths still report: the success path (after `setState`) and any
  throw from the capture (`on Object { _reportCompleted(); rethrow; }`).
  **The whole boundary lookup + `toImage()` is inside that `try` on purpose:**
  `RenderObject.debugNeedsPaint` reads a `late` local that is only assigned
  inside an `assert`, so it throws `LateInitializationError` when asserts are
  disabled. Keeping it inside the `try` preserves today's release-mode
  behaviour (barrier released, no screenshot) instead of turning it into a hang.
- Post-dispose safety: `_capture()` returns early when `!mounted`; if the state
  is disposed of while `toImage()` is in flight, the resulting image is disposed
  of on the spot (nobody will show it) and completion is not reported again
  (`dispose()` already did).
- Leak fix: `dispose()` now calls `_image?.dispose()`. Verified that this is not
  a double dispose: `RawImage.createRenderObject`/`updateRenderObject` pass
  `image?.clone()` to `RenderImage`, so `RenderImage.dispose()` releases *its
  own* handle and the state owns the original (`RawImage`'s own doc comment says
  the creator must dispose of it).

## Evidence

Baseline before the task: `flutter test` 42 passing, `flutter analyze` exactly
3 known issues.

### Failing (final test file, `lib/` reverted to HEAD via `git checkout --`, no stash)

```
00:00 +1 -5: Some tests failed.

Failing tests:
  test/lite_scope_test.dart: LiteScope.close() completes while the scope is in the waiting state
  test/lite_scope_test.dart: LiteScope.close() completes while the scope is in the initializing state
  test/lite_scope_test.dart: LiteScope.close() completes while the scope is in the error state
  test/lite_scope_test.dart: LiteScope.close() completes when the element leaves the tree before the closing frame is built
  test/lite_scope_test.dart: ScreenshotReplacer reports completion exactly once and releases the captured image
```

with, respectively:

```
Expected: true
  Actual: <false>
close() must not wait for a screenshot that buildOnReady() never takes in the waiting state
...initializing state
...error state
a scope removed from the tree while closing must not keep close() waiting for a screenshot that can no longer be taken

Expected: <1>
  Actual: <2>
disposal must not report completion again
```

The 6th test (`completes in the ready state once the screenshot has been
captured`) passes before the fix too — it is the regression guard proving the
barrier is still installed and still released on the happy path.

### Passing (after the fix)

```
flutter test test/lite_scope_test.dart   ->  00:00 +6: All tests passed!   (x3 runs, no flakiness)
flutter test                             ->  00:00 +48: All tests passed!  (42 baseline + 6 new)
flutter analyze                          ->  3 issues found.               (the same 3 pre-existing)
```

## Test-authoring notes (things that cost time)

- **`close()` is never awaited directly** in the tests; it is fired with
  `unawaited(... .whenComplete(() => isClosed = true))` and asserted through the
  flag, so the pre-fix behaviour is a *failing* test, not a hung test run.
- The test scope is a `LiteScopeCore` with a test-visible element type
  (`_CloseScopeElement extends LiteScopeElementBase`), because
  `LiteScope`'s element is library-private and `close()` must be reachable in
  states where no `LiteScopeCoreState` exists yet.
- `RenderRepaintBoundary.toImage()` **does** work in widget tests, but only
  inside `tester.runAsync` (`OffsetLayer.toImage` awaits `ui.Scene.toImage`,
  which the engine completes on the real event loop). The same applies to the
  `await subscription.cancel()` chain in
  `AsyncScopeElementBase._performAsyncDispose` — the identical `runAsync`
  workaround is already documented in `async_scope_test.dart`. Hence the
  `_settle(tester, until: ...)` helper (real-time slice + `pump()`, budgeted).
- Init-stream helpers must be *cancellable*: an `async*` generator suspended on
  a never-completing future makes `StreamSubscription.cancel()` itself hang
  (unrelated to this bug, but it masked it). Used `Stream.multi` instead.
- `Stream<T>.error(...)` as the init stream never reached the model in a widget
  test (state stayed `AsyncScopeWaiting`, no exception surfaced) — worked fine
  in a plain `test()`. Sidestepped by using an `async*` that throws, which does
  reach `AsyncScopeError`. Not investigated further; flagged below.

## Concerns / follow-ups (candidates for Task 10 / TODO.md)

1. **`ScreenshotReplacer` cannot capture anything in release/profile builds.**
   `boundary.debugNeedsPaint` throws `LateInitializationError` without asserts,
   so `_capture()` always fails outside debug: the closing overlay is drawn over
   the *live* widget and an unhandled async error is reported. My change
   deliberately preserves that (rather than hanging), but the real fix is to
   read `debugNeedsPaint` only inside an `assert(() {...}())`, or to drop the
   check. Out of this brief's scope — untestable from a debug-mode test suite.
2. **Retry loop has no cap.** If the boundary never becomes paintable, the
   replacer now reschedules (and schedules a frame) forever instead of releasing
   the barrier early. That is the intended barrier semantics, but a bounded
   number of attempts (or a timeout that reports completion) would be safer for
   `close()`.
3. `Stream.error` not being delivered to the async-scope model under
   `AutomatedTestWidgetsFlutterBinding` (see above) may hide a real
   fake-async/scheduling issue in `_performAsyncInit`'s error path. Worth a look
   independently.
4. `_isCaptured` in `_ScreenshotReplacerState` is now fully redundant with
   `_image != null`; left as is to keep the diff focused.

---

# Fix report: three regressions from `6cf403f`

All three review findings reproduced, fixed, and each fix verified to be
load-bearing by hand-reverting *only* that fix and re-running only its test (no
`git stash`). New commit, not an amend.

Files touched by this round:

- `lib/src/scope/g_lite_scope/lite_scope_core.dart` (finding 1)
- `lib/src/utils/screenshot_replacer.dart` (finding 2)
- `lib/src/scope/e_async_scope/async_scope_core.dart` (finding 3, new file for
  this task — the approved fix direction)
- `test/lite_scope_test.dart` (+4 tests: 6 -> 10)

## Finding 1 (CRITICAL) — double `close()` orphaned the barrier

`close()` assigned `_screenshotCompleter` unconditionally, while
`_performAsyncDispose()` captures the completer in a local
(`if (_screenshotCompleter case final screenshotCompleter?) await ...`) and
`_completeScreenshot()` reads the *field*. A second `close()` therefore swapped
in C2, the replacer released C2, and C1 — the one the first `close()` awaits —
stayed pending forever; `_closeCompleter` never completed either, so the second
`close()` (which returns `_closeCompleter.future`) hung too, and `disposeAsync()`
never ran.

Fix: `_screenshotCompleter ??= Completer<void>();` — the barrier is installed at
most once per element, so the field and the captured local are always the same
object. Repeated `close()` calls simply join the in-flight one via
`_closeCompleter`.

Test: `LiteScope.close() completes both futures when close() is called twice`.
Note on the repro — it is *not* enough to `await tester.pump()` before the second
`close()`: in this environment `RenderRepaintBoundary.toImage()` resolves within
that pump, so the barrier is already released and the race closes. The test
builds the closing frame with `buildOwner.buildScope(rootElement)` instead
(mounting the replacer without drawing), so the capture is still pending when
the second `close()` arrives.

Evidence — reverting only `??=` back to `=`:

```
Expected: true
  Actual: <false>
the first close() must not be orphaned by the second one
00:00 +0 -1: Some tests failed.
```

## Finding 2 (IMPORTANT) — unbounded retry loop

The `boundary == null || debugNeedsPaint` retry path had no cap and called
`scheduleFrame()` on every attempt, so a child that is built but never painted
(`Offstage`, unselected `IndexedStack` branch) meant `close()` never completed
*and* frames busy-looped forever. Pre-`6cf403f` these paths released the barrier
and scheduled nothing.

Fix: `ScreenshotReplacer.maxRetries = 5` (public, documented on the widget) plus
a `_retries` counter. On the 6th attempt the capture gives up: it reports
completion once (barrier released, `child` left in place, no screenshot) and
stops rescheduling. `onCompleted`'s doc comment now states the exactly-once
contract and all three ways it can fire.

Tests:
- `ScreenshotReplacer retries without reporting completion, then gives up after
  the retry cap` — asserts `onCompleted` is not fired for the first attempt nor
  for 3 subsequent retries, is fired exactly once after the cap, that no
  `RawImage` appears, and that no further frame reports again.
- `LiteScope.close() completes in the ready state even when the screenshot can
  never be taken` — a Ready scope inside `Offstage`: `close()` completes.

Evidence — reverting only the cap block:

```
Expected: <1>
  Actual: <0>
giving up must report completion exactly once
00:00 +0 -1: Some tests failed.

Expected: true
  Actual: <false>
the capture must give up after a bounded number of retries instead of keeping close() waiting forever
00:00 +0 -1: Some tests failed.
```

## Finding 3 (IMPORTANT) — pending ready callback hit the disposed model

Skipping the barrier made disposal reach `finally { _model.dispose(); }` inside
the one-frame window where `initAsync()` has already produced `AsyncScopeReady`
(post-frame `_model.update(Ready)` scheduled, `model.state` still
`AsyncScopeWaiting`). Task 7's `mounted` guard does not help: an element closed
via `close()` — as opposed to removed from the tree — is still mounted, so the
stale callback ran and threw *"A `_AsyncScopeNotifier` was used after being
disposed."*

Fix (as approved): `AsyncScopeElementBase._isDisposing`, set at the very top of
`_performAsyncDispose()`, and checked *in addition to* `mounted` in both
Ready-path callbacks — the post-frame one and the `pauseAfterInitialization`
delayed one. Documented on the field.

Ordering note: `LiteScopeElementBase._performAsyncDispose` awaits the barrier
before calling `super`, so `_isDisposing` is only set after the capture on the
Ready-state path. That is harmless — the barrier is only ever installed when
`state` is *already* `AsyncScopeReady`, i.e. after the callback in question has
run.

Test: `LiteScope.close() does not touch the disposed model when close() wins the
race with the post-frame callback that applies the ready state`. It mounts via
`attachRootWidget` + `buildScope` + `binding.idle()` (the technique documented in
`async_scope_test.dart`) so the callback stays pending, asserts the window is
real (`element.state is AsyncScopeWaiting`), calls `close()`, then asserts:
`takeException()` is null, `close()` completed, `disposeAsyncCount == 1` (task
7's `_initSucceeded` must still run `disposeAsync()` even though the ready state
was never applied), and `state` remains `AsyncScopeWaiting` (disposal won the
race, so the ready state is correctly never published).

Evidence — reverting only the two `_isDisposing` checks:

```
Expected: null
  Actual: FlutterError:<A _AsyncScopeNotifier was used after being disposed.
          Once you have called dispose() on a _AsyncScopeNotifier, it can no longer be used.>
the pending ready callback must not use the disposed model
00:00 +0 -1: Some tests failed.
```

## Verification

```
flutter test test/lite_scope_test.dart  ->  00:00 +10: All tests passed!   (x3 runs, no flakiness)
flutter test                            ->  00:00 +52: All tests passed!   (42 baseline + 10)
flutter analyze                         ->  3 issues found.                (the same 3 pre-existing)
dart format <4 changed files>           ->  Formatted 4 files (1 changed)
```

All 6 tests from `6cf403f` stayed green throughout; the 4 new tests all fail at
`6cf403f` (captured before the fixes) and pass now.

## Concerns

1. The release-mode `debugNeedsPaint` issue from the first round still stands and
   is now *entangled with the cap*: without asserts, `debugNeedsPaint` throws, so
   the very first attempt goes to the `on Object` branch, reports completion, and
   rethrows — the retry cap is debug-only behaviour in practice. Still a TODO/task-10
   candidate (`assert(() { needsPaint = boundary.debugNeedsPaint; return true; }())`).
2. `maxRetries = 5` is a deterministic frame count, not a deadline. A scope that
   legitimately needs more than 6 frames to paint (very heavy first frame) would
   now close without a screenshot instead of waiting. That is the intended
   trade-off (bounded wait beats an infinite one), but if it ever bites, a
   deadline-based cap would be the fix.
3. `_isDisposing` is set inside `AsyncScopeElementBase._performAsyncDispose`, so
   `LiteScope`'s barrier wait happens before the flag is set. Not exploitable
   today (see the ordering note above), but if a future change installs the
   barrier in a non-Ready state, the flag would want to move earlier.


---

## Файл: task-9-brief.md

### Task 9: проглоченные ошибки disposal + кривой toString

- `lib/src/scope/h_scope/scope_auto_dependency/scope_auto_dependency.dart:65-72`: `onError: (Object e) {}` — ошибки disposal исчезают бесследно. Минимум: логировать.
- `lib/src/scope/e_async_scope/async_scope_state.dart:51-53`: `AsyncScopeError.toString()` при непустом `progress` даёт несбалансированную скобку: `AsyncScopeError(e, st, progress: p))`.

**Files:**
- Modify: оба файла выше
- Test: `test/async_scope_state_test.dart` (create), тест на лог — в `test/scope_auto_dependencies_test.dart`

- [ ] **Step 1: тест toString**

```dart
test('AsyncScopeError.toString balanced parens', () {
  final s = AsyncScopeError(Exception('x'), StackTrace.empty, progress: 1)
      .toString();
  expect('('.allMatches(s).length, ')'.allMatches(s).length);
});
```

(Сигнатуру конструктора сверить по `async_scope_state.dart:43-53`.)

- [ ] **Step 2: фикс toString**

```dart
String toString() => '$AsyncScopeError($error, $stackTrace'
    '${progress == null ? '' : ', progress: $progress'})';
```

- [ ] **Step 3: фикс onError** — `scope_auto_dependency.dart:67`:

```dart
onError: (Object error, StackTrace stackTrace) {
  _log.e('dispose error', error: error, stackTrace: stackTrace);
},
```

(сигнатуру `_log.e` сверить с `ScopeLogFn`: `bool Function(Object? message, {Object? error, StackTrace? stackTrace})`).

- [ ] **Step 4:** PASS. Коммит: `log disposal errors, fix AsyncScopeError.toString`.



---

## Файл: task-9-report.md

# Task 9 Report: swallowed disposal errors + AsyncScopeError.toString parenthesis bug

## Status: PASS

## Changes

### 1. `lib/src/scope/e_async_scope/async_scope_state.dart` (~line 53)

Confirmed constructor signature first: `AsyncScopeError(this.error, this.stackTrace, {this.progress});` — positional `error`, `stackTrace`, named optional `progress`.

Root cause: the old `toString()` had a stray `)` baked into the ternary's non-null branch *and* another `)` outside the interpolation, so the `progress != null` case emitted two closing parens for one opening paren:

```dart
// before
String toString() => '$AsyncScopeError($error, $stackTrace'
    '${progress == null ? '' : ', progress: $progress)'})';
```

Fixed by moving the closing paren out of the ternary's non-null branch (matches the brief exactly):

```dart
// after
String toString() => '$AsyncScopeError($error, $stackTrace'
    '${progress == null ? '' : ', progress: $progress'})';
```

Now both branches (`progress == null` and `progress != null`) produce exactly one `(`/`)` pair.

### 2. `lib/src/scope/h_scope/scope_auto_dependency/scope_auto_dependency.dart` (~line 67)

`dispose()`'s `dependencies.runDispose().listen(...)` had `onError: (Object e) {}` — disposal errors vanished silently. Checked `ScopeLogFn` in `lib/src/environment/scope_logger.dart`: `bool Function(Object? message, {Object? error, StackTrace? stackTrace})`, and the file's existing `_log.d(...)` usage style. Changed to:

```dart
onError: (Object error, StackTrace stackTrace) {
  _log.e('dispose error', error: error, stackTrace: stackTrace);
},
```

Kept the two-argument `(Object error, StackTrace stackTrace)` signature since `StreamSubscription.onError` requires it to match what the stream can throw, and passed both through to `_log.e` per its named-parameter signature.

## Tests

Added `test/async_scope_state_test.dart` (new file) with two cases (brief only asked for the `progress != null` case per its Step 1 snippet; added the `progress == null` case too as a quick regression guard since the old code was accidentally balanced in that branch):

```dart
test('balanced parens without progress', () { ... });
test('balanced parens with progress', () { ... });
```

Both assert `'('.allMatches(s).length == ')'.allMatches(s).length`. Both pass against the fixed code.

For the `onError` logging fix: did **not** add a new log-emission test. Per the brief's "minimum: log" framing and the task instructions calling this optional, I instead verified there is no dispose-path test in `test/scope_auto_dependencies_test.dart` that ever makes `dep.dispose()` throw — grepped `dispose = \|dispose:` and `throw\|Exception` across the file; all throwing scenarios (`dep5`, `dep6`, `dep7`, `depB`, etc.) are **init**-phase failures (`initDep` throws before assigning `dep.dispose`), never disposal-phase failures. So the `onError` callback in `ScopeAutoDependencies.dispose()` is never exercised by the existing suite either before or after the change — confirmed via full `flutter test` run showing identical pass count/behavior, no new failures, no behavior change for any existing scenario. Adding a synthetic dispose-throwing dependency + `ScopeConfig.logger`/`test/utils/logging.dart` capture just to test this one log call was judged not worth the added test-infrastructure churn for this small, narrowly-scoped task; flagging this as the one open item below.

## Verification

- `flutter test test/async_scope_state_test.dart`: 2/2 pass.
- `flutter test` (full suite): **54/54 pass** (52 baseline + 2 new).
- `flutter analyze`: **3 issues**, identical to baseline (unrelated pre-existing items in `example/scopo_demo/...`, `scope_config.dart:7`, `scope_auto_dependency.dart:25` — none touch the lines changed by this task).

## Commit

- Only `lib/src/scope/e_async_scope/async_scope_state.dart`, `lib/src/scope/h_scope/scope_auto_dependency/scope_auto_dependency.dart`, and the new `test/async_scope_state_test.dart` were staged and committed.
- An untracked `docs/superpowers/` directory was present in the worktree before this task started (unrelated artifact) and was deliberately left untouched/unstaged.
- Commit hash: `2120927f3e92117ead41a694cf0cd367cf61f7d9`
- Message: `log disposal errors, fix AsyncScopeError.toString`

## Concerns

- No direct unit test exercises the new `_log.e('dispose error', ...)` call path (no existing fixture makes a dependency's `dispose()` throw). Behavior is correct by inspection and signature-matches `ScopeLogFn`, and the change is behavior-neutral for all currently passing tests, but the log emission itself is unverified by an automated test. Flagging for whoever reviews/closes out this task in case they want a dedicated regression test added later.


---

## Файл: task-10-brief.md

### Task 10: известные проблемы, выносимые за скоуп релиза (зафиксировать в TODO.md)

Три находки требуют дизайна, а не точечного фикса; в этом релизе — только зафиксировать:

- [ ] **Step 1:** добавить в `TODO.md`:

```
- AsyncScopeCoordinator: глобальный static _queues без очистки; _AsyncScopeCoordinatorQueue.close() не вызывается нигде; два координатора с одним scopeKey делят очередь (в т.ч. между widget-тестами).
- AsyncScopeElementBase: окно между enter() и присвоением _subscription — dispose() в этом окне не отменяет инициализацию (см. TODO(nashol) в async_scope_core.dart:279).
- ScopeAutoDependencies: _root не сбрасывается после dispose() — повторный init() падает на assert; при autoDisposeOnError runDispose затирает ScopeDependencyFailed → ошибки группы теряются.
- Покрытие тестами: a_base, b_scope_widget, c_scope_model, d_scope_notifier, e_async_scope (особенно AsyncScopeCoordinator), f_async_data_scope, g_lite_scope — ноль тестов (частично закрывается регрессионными тестами 0.10.0).
- test/utils/logging.dart безусловно включает debug-уровень (шум ~15 строк на тест) — сделать opt-in; в my_fake_async.dart тела printPendingTimers/printFakeAsyncPendingTimers перепутаны местами.
```

- [ ] **Step 2:** Коммит: `record known async lifecycle issues in TODO`.

---

## Фаза 3 — мёртвый код, опечатки, анализатор



---

## Файл: task-10-report.md

# Task 10 Report: Documentation of Known Async Lifecycle Issues

## Summary

Successfully documented all known async lifecycle issues in TODO.md by appending:
1. Five main issues from the brief (AsyncScopeCoordinator queuing, AsyncScopeElementBase dispose window, ScopeAutoDependencies lifecycle, test coverage gaps, test infrastructure issues)
2. Five additional issues discovered during Tasks 5-8 implementation (ScreenshotReplacer LateInitializationError, AsyncScope init-stream StateError, test infrastructure Stream.error behavior, ScopeDependencyGroup.init() empty-set guard, LiteScope render condition)

## Changes

- **File modified:** TODO.md
- **Lines added:** 12
- **Structure preserved:** Added new "Известные проблемы (0.10.x)" section after existing "Тесты:" section
- **Style maintained:** Bullet-point format consistent with file's existing style

## Commit

- **Hash:** 44b9bd5
- **Message:** "record known async lifecycle issues in TODO"
- **Files:** TODO.md only

## Verification

- `git diff --stat` shows only TODO.md modified (+12 insertions, 0 deletions)
- No other files committed
- All items preserved in correct order

## Notes

All documented issues are categorized as requiring design work or deeper architecture fixes beyond the scope of this release. They serve as reference documentation for future maintenance and design decisions.


---

## Файл: task-11-brief.md

### Task 11: обнулить flutter analyze

Ровно 3 замечания:

**Files:**
- Modify: `lib/src/environment/scope_config.dart:5-7`
- Modify: `lib/src/scope/h_scope/scope_auto_dependency/scope_auto_dependency.dart:25`
- Modify: `example/scopo_demo/lib/home/demos/c_scope_notifier/scope_notifier_example2.dart:91`
- Modify: `example/scopo_demo/analysis_options.yaml:31`

- [ ] **Step 1:** `scope_config.dart` — `// ignore: avoid_classes_with_only_static_members` стоит на строке 5, но между ним и классом вклинился dartdoc (строка 6), из-за чего ignore не работает. Переставить комментарий непосредственно над `abstract final class ScopeConfig` (после dartdoc).
- [ ] **Step 2:** `scope_auto_dependency.dart:25` — `this.buildDependencies(context)` → `buildDependencies(context)`.
- [ ] **Step 3:** `scope_notifier_example2.dart:91` — удалить строку `@override` над конструктором `CounterScopeElement(super.widget);`. Заодно удалить окаменелость `# invalid_annotation_target: ignore ???` в `example/scopo_demo/analysis_options.yaml:31`.
- [ ] **Step 4:** `flutter analyze` (корень + оба example) → **0 issues**. Коммит: `fix analyzer issues`.



---

## Файл: task-11-report.md

# Task 11: Fix Analyzer Issues

## Summary
Successfully eliminated all 3 analyzer issues and verified no regressions.

## Changes Made

### 1. lib/src/environment/scope_config.dart
**Issue:** The `// ignore: avoid_classes_with_only_static_members` comment on line 5 was separated from the class declaration by the dartdoc comment on line 6, making the ignore ineffective.

**Fix:** Moved the ignore comment to directly above the class declaration (line 6), after the dartdoc.

```dart
/// {@category debug}
// ignore: avoid_classes_with_only_static_members
abstract final class ScopeConfig {
```

### 2. lib/src/scope/h_scope/scope_auto_dependency/scope_auto_dependency.dart
**Issue:** Line 25 had `this.buildDependencies(context)` which is unnecessary self-reference.

**Fix:** Changed to `buildDependencies(context)`.

### 3. example/scopo_demo/lib/home/demos/c_scope_notifier/scope_notifier_example2.dart
**Issue:** Line 91 had a stray `@override` annotation above the constructor, which is invalid.

**Fix:** Deleted the `@override` line, kept the constructor.

### 4. example/scopo_demo/analysis_options.yaml
**Issue:** Line 40 had a leftover comment: `# invalid_annotation_target: ignore ???`

**Fix:** Deleted the entire comment line.

## Verification Results

### Root Repository
```
flutter analyze
Analyzing audit-fixes...
No issues found! (ran in 1.8s)
```

### example/scopo_demo
```
flutter analyze
Analyzing scopo_demo...
No issues found! (ran in 2.0s)
```

### example/minimal
```
flutter analyze
Analyzing minimal...
No issues found! (ran in 0.6s)
```

### Test Suite
```
flutter test
00:00 +54: All tests passed!
```

## Result
✅ All 3 analyzer issues fixed
✅ 0 issues found in all 3 analyze runs
✅ 54/54 tests passing (no regressions)
✅ Commit: 0f97e03 "fix analyzer issues"


---

## Файл: task-12-brief.md

### Task 12: мёртвый код

Всё ниже не имеет ни одного вызова в lib/test/example (проверено аудитом); удаления экспортируемого — breaking, идут в 0.10.0.

**Files:**
- Delete: `lib/src/utils/type_to_string.dart` (не импортируется никем)
- Delete: `lib/src/scope/g_lite_scope/lite_scope_init_state.dart` (`LiteScopeInitState/Waiting/Progress/Ready` — LiteScope реально использует `AsyncScopeInitState`; **экспортируется** → breaking) — удалить и `part`-директиву из `lib/src/scope/scope.dart`
- Modify: `lib/src/scope/h_scope/scope_auto_dependency/scope_dependency/scope_dependency_state.dart:170` — опечатка `ScopeDependencyNoDisposalRequred` → `ScopeDependencyNoDisposalRequired` (класс нигде не конструируется; переименование — breaking для тех, кто матчит sealed-иерархию)
- Modify: `lib/src/scope/h_scope/scope_auto_dependency/scope_dependency/scope_dependency_impl.dart:23-24` — убрать дублирующее присваивание `_helper = helper;`
- Modify: `lib/src/scope/h_scope/scope_auto_dependency/scope_dependency/scope_dependency.dart:41` — удалить неиспользуемый `ScopeDependencyExtension.isGroup` **или** оставить как публичное API (решение: оставить — безвредный public helper)
- НЕ трогать: `ListenableView` (экспортируется, потенциально полезен пользователям), `Notifier` (оживает в Задаче 3), `_AsyncScopeCoordinatorQueue.close()` (ждёт редизайна из Задачи 10)

- [ ] **Step 1:** удаления и правки по списку; `grep -rn 'LiteScopeInitState\|LiteScopeWaiting\|typeToShortString\|NoDisposalRequred'` по lib/test/example → 0 совпадений.
- [ ] **Step 2:** `flutter analyze` + `flutter test` — чисто/зелёно. Коммит: `remove dead code, fix ScopeDependencyNoDisposalRequired typo`.



---

## Файл: task-12-report.md

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


---

## Файл: task-13-brief.md

### Task 13: «Deffered» → «Deferred» в демо

**Files:**
- Rename: `example/scopo_demo/lib/home/demos/i_deffered_closing/` → `i_deferred_closing/` (и файл `deffered_closing_demo.dart` → `deferred_closing_demo.dart`)
- Modify: класс `DefferedClosingDemo` → `DeferredClosingDemo`, лейбл вкладки в `example/scopo_demo/lib/home/home.dart:29` `'Deffered closing'` → `'Deferred closing'`

- [ ] **Step 1:** `git mv` + переименование класса + правка импортов/лейбла; `grep -rin deffered example/` → 0.
- [ ] **Step 2:** `flutter analyze` в scopo_demo → 0. Коммит: `fix Deferred spelling in demo`.

---

## Фаза 4 — документация и упаковка



---

## Файл: task-13-report.md

# Task 13: Deferred Spelling Fix - Report

## Summary
Successfully fixed "Deffered" → "Deferred" misspelling throughout example/scopo_demo.

## Changes Made

### Directory Renames
- `example/scopo_demo/lib/home/demos/i_deffered_closing` → `i_deferred_closing`
- `deffered_closing_demo.dart` → `deferred_closing_demo.dart` (inside renamed directory)
- All files in the directory automatically renamed via `git mv`

### Code Updates
- **Class name**: `DefferedClosingDemo` → `DeferredClosingDemo`
- **Import statement**: Updated path in `home.dart` to reference `i_deferred_closing/deferred_closing_demo.dart`
- **Tab label**: `'Deffered closing'` → `'Deferred closing'` in `home.dart`

## Verification Results

| Check | Result |
|-------|--------|
| `grep -rin "deffered" example/scopo_demo` | 0 hits ✓ |
| `grep -rin "Deffered" example/scopo_demo` | 0 hits ✓ |
| `cd example/scopo_demo && flutter analyze` | No issues ✓ |
| `flutter analyze` (root) | No issues ✓ |
| `flutter test` (root) | 54/54 passed ✓ |

## Commit
- **Hash**: `c7ef8bc`
- **Message**: `fix Deferred spelling in demo`

## Concerns
None. All verifications passed, no code logic changes (pure rename), tests unaffected.


---

## Файл: task-14-brief.md

### Task 14: pubspec.yaml — метаданные pub.dev

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1:** добавить после `homepage`:

```yaml
repository: https://github.com/vi-k/scopo
issue_tracker: https://github.com/vi-k/scopo/issues
topics:
  - state-management
  - dependency-injection
  - scope
  - widgets
```

- [ ] **Step 2:** `flutter: ">=1.17.0"` — ложь (пакет использует Dart-3 class modifiers). Заменить на `flutter: ">=3.16.0"` (Flutter 3.16 = Dart 3.2, соответствует `sdk: ^3.2.0`).
- [ ] **Step 3:** `flutter_lints: ^5.0.0` объявлен, но `analysis_options.yaml` включает `package:lints/recommended.yaml` — `lints` используется незадекларированно. Решение: в корне и `example/scopo_demo` заменить include на `package:flutter_lints/flutter.yaml` (все ручные правила в `linter.rules` сохраняются, они имеют приоритет), прогнать `flutter analyze` и погасить/осознанно заглушить новые Flutter-специфичные замечания, если появятся.
- [ ] **Step 4:** `flutter pub publish --dry-run` → 0 warnings. Коммит: `add pub.dev metadata, honest flutter constraint`.



---

## Файл: task-14-report.md

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


---

## Файл: task-15-brief.md

### Task 15: README.md — переписать

Сейчас 3 из 5 примеров кода не компилируются, два раздела документируют несуществующие классы. Структура нового README:

**Files:**
- Modify: `README.md`
- Modify: `TODO.md` (снять пункт `Update README!!!`)

- [ ] **Step 1: исправить сломанные примеры:**
  - `:76-78` — `init(BuildContext)` → `initDependencies(BuildContext)` (реальный член: `lib/src/scope/h_scope/scope_base.dart:83`);
  - `:29-48` — в сэмпл `AppDependencies implements ScopeDependencies` добавить `@override void unmount() {}` (обязателен с 0.7.3);
  - `:118-129` — `class MyConfig extends ScopeWidgetBase` → `final class …` (база — `abstract base class`); убрать собственное поле `child` (оно уже есть у `ScopeInheritedWidget`); добавить `super.key`;
  - `:175-201` — **удалить** разделы `ScopeAsyncInitializer` и `ScopeStreamInitializer` — классов не существует с 0.4.x;
  - `:210` — комментарий `// Get State (listen: true by default)` → `// Get State (does not subscribe; use select/of(listen: true) to listen)` — `Scope.of` жёстко `listen: false` (`scope_base.dart:158-163`);
  - `:46,141` — опечатка `Dipose` → `Dispose`.
- [ ] **Step 2: добавить недостающие разделы** (каждый — 5–15 строк + компилируемый сниппет, выверенный по `example/minimal/lib/main.dart` и `example/scopo_demo`):
  - Installation (`flutter pub add scopo`);
  - Logging & configuration: `ScopeConfig.logger.level`, `ScopeConfig.logger[level].publisher = ScopeLogFormatter(...)`, таймауты `defaultScopeKeysTimeout`/`defaultWaitForChildrenTimeout` — сниппет взять из `example/minimal/lib/main.dart:9-33`;
  - обзор семейств `AsyncScope` / `AsyncDataScope` / `LiteScope` (по абзацу + ссылка на демо);
  - ссылки: на `example/` (оба приложения), на API-доки;
  - бейджи вверху: `pub version`, `license` (`https://img.shields.io/pub/v/scopo`, `…/github/license/vi-k/scopo`).
- [ ] **Step 3:** убрать `> [!WARNING] README needs updating!` (строки 3-4); каждый сниппет скопировать в scratch-файл и прогнать через `dart analyze` перед вставкой.
- [ ] **Step 4:** вычеркнуть `Update README!!!` из TODO.md. Коммит: `rewrite README`.



---

## Файл: task-15-report.md

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


---

## Файл: task-16-brief.md

### Task 16: example/README.md — устранить дрейф (это страница Example на pub.dev)

pub.dev не находит ни один из example-app'ов автоматически (они на уровень глубже, чем ищет pana) и рендерит `example/README.md` — рукописную копию minimal, которая разъехалась и не компилируется.

**Files:**
- Modify: `example/README.md`

- [ ] **Step 1:** заменить вложенный код точной копией актуального `example/minimal/lib/main.dart` (целиком, включая блок логирования строк 1-33 — сейчас он отсутствует, и logging невидим на pub.dev; включая `@override void unmount() {}`, `final class`, `covariant String? progress`).
- [ ] **Step 2:** единственный русский dartdoc в minimal (`example/minimal/lib/main.dart:59` `/// Метод инициализации зависимостей.`) перевести на английский в самом `main.dart` — копия в README подтянется.
- [ ] **Step 3:** сохранить ссылки на оба приложения; ссылку на `scopo_demo` поднять выше и подписать («9 interactive demos»). Коммит: `sync example README with minimal app`.



---

## Файл: task-16-report.md

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


---

## Файл: task-17-brief.md

### Task 17: CHANGELOG + dartdoc-страницы категорий

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `doc/h_scope.md`, `doc/i_debug.md` (остальные 7 заглушек — вне скоупа, зафиксировать в TODO.md)
- Modify: `lib/src/environment/scope_logger.dart` (аннотации категорий)
- Modify: `lib/src/scope/a_base/base.dart:7`

- [ ] **Step 1:** CHANGELOG: разбить `## 0.9.3-0.9.5` на три отдельные секции (pub.dev матчит по точной строке версии; страницы 0.9.4/0.9.5 сейчас без changelog); нормализовать пустую строку после каждого заголовка; добавить секцию `## 0.10.0` (заполняется в Задаче 18).
- [ ] **Step 2:** `doc/i_debug.md` — написать реальную страницу: уровни (`ScopeLogLevel`), включение (`ScopeConfig.logger.level = …`), подключение publisher'а (`ScopeConfig.logger[level].publisher = ScopeLogFormatter(format: ScopeLogger.defaultFormat, output: …)`), таймауты и `pauseAfterInitializationEnabled` из `ScopeConfig`. Основа — рабочий код `example/minimal/lib/main.dart:9-33` и `test/utils/logging.dart`.
- [ ] **Step 3:** `doc/h_scope.md` — обзор главной категории: `Scope` → `initDependencies` → `ScopeAutoDependencies`/`ScopeDependencyGroup` (`sequential`/`concurrent`), формат путей (без ведущего `/`), `ScopeDependencyException`, жизненный цикл dispose/unmount.
- [ ] **Step 4:** добавить `{@category debug}` к `ScopeLogger`, `ScopeLog`, `ScopeLogLevel`, `ScopeLevelLogger`, `ScopeLogFn`, `ScopeLogPublisher`, `ScopeLogFormatter` в `scope_logger.dart` (сейчас на странице debug — один `ScopeConfig`); удалить мусорный dartdoc `/// saaa` в `base.dart:7`. Внимание: `dartdoc_options.yaml` эскалирует `unresolved-doc-reference` в ошибку — все `[ссылки]` в новых страницах проверять сборкой `dart doc`.
- [ ] **Step 5:** дописать в TODO.md: `- заполнить оставшиеся 7 заглушек doc/*.md; скриншоты для pub.dev (screenshots: в pubspec); русские dartdoc-комментарии в lib/ (78 строк) перевести.` Коммит: `changelog per-version sections, debug and scope doc pages`.



---

## Файл: task-17-report.md

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


---

## Файл: task-18-brief.md

### Task 18: релиз 0.10.0

**Files:**
- Modify: `pubspec.yaml:4`, `CHANGELOG.md`

- [ ] **Step 1:** `version: 0.10.0`; секция CHANGELOG:

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
* Guard AsyncScope post-frame callbacks with `mounted`.
* Log dependency disposal errors instead of swallowing them.
* Fix unbalanced parenthesis in `AsyncScopeError.toString()`.
* Add `repository`, `issue_tracker` and `topics` to pubspec; honest Flutter
  constraint.
* Rewrite README; sync the pub.dev example; real `debug`/`Scope` doc pages.
```

- [ ] **Step 2: полная верификация** — `flutter analyze` (корень + оба example) → 0; `flutter test` → все зелёные; `flutter pub publish --dry-run` → 0 warnings; запустить `example/scopo_demo` (`flutter run -d macos`) и прокликать вкладки Scope/LiteScope/AsyncScope — прогресс-пути в консоли без ведущего `/`, закрытие вкладок не виснет.
- [ ] **Step 3:** коммит `release 0.10.0`, тег `v0.10.0`, `git push origin main v0.10.0`, `flutter pub publish --force`.

---

## Verification (сквозная)

1. `flutter test` — **0 failed** (было 17/17 failed); в сьюте появились: тест анонимных групп, 19 тестов `Notifier`, регрессионные тесты Задач 4–9.
2. `flutter analyze` в корне, `example/minimal`, `example/scopo_demo` — 0 issues (было 3).
3. `flutter pub publish --dry-run` — 0 warnings.
4. Ручной прогон `scopo_demo` на macOS: все 9 вкладок открываются/закрываются, консольные пути единообразны.
5. После публикации: страница pub.dev показывает Repository-ссылку, топики, changelog на страницах 0.9.4/0.9.5, компилируемый Example-таб.


---

## Файл: task-18-report.md

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

