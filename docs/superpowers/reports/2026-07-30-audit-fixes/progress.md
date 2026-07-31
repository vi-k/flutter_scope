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
