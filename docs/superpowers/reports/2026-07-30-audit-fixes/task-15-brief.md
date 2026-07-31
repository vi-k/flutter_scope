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

