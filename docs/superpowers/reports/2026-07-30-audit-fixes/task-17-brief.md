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

