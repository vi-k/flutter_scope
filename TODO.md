# TODO

- ScopeAutoDependenciesProgress - добавить name (а name переименовать в path)
- Описать все примеры.
- Написать нормальную документацию.
- example для `ScopeWidgetCore`.

Тесты:
- одновременно `notifyDependents` и перестроение дерева сверху (`setState`).
- проверить ребёнка с глобальным ключом, что он успешно перерегистрируется и
  фризит старого родителя.

Известные проблемы (0.10.x):
- dart format расходится на 6 файлах example/scopo_demo (версия форматтера новее той, которой их писали); переформатирование конфликтует с require_trailing_commas — чинить вместе с обновлением тулчейна.
- Покрытие тестами: a_base, b_scope_widget, c_scope_model, d_scope_notifier, e_async_scope (особенно AsyncScopeCoordinator), f_async_data_scope, g_lite_scope — ноль тестов (частично закрывается регрессионными тестами 0.10.0).
- test/utils/logging.dart безусловно включает debug-уровень (шум ~15 строк на тест) — сделать opt-in; в my_fake_async.dart тела printPendingTimers/printFakeAsyncPendingTimers перепутаны местами.
- Тест-инфра: Stream.error(...) как init-стрим не доходит до модели под AutomatedTestWidgetsFlutterBinding (state остаётся Waiting), в plain test() работает — возможно, скрывает проблему планирования в _performAsyncInit.
- ScopeDependencyGroup.init(): та же empty-set дыра, что была в dispose (guard добавлен в 0.10.0, отдельного теста нет).

Документация:
- заполнить оставшиеся 7 заглушек doc/*.md: a_base, b_scope_widget, c_scope_model, d_scope_notifier, e_async_scope, f_async_data_scope, g_lite_scope (h_scope и i_debug написаны в 0.10.0).
- скриншоты для pub.dev: секция `screenshots:` в pubspec.yaml отсутствует.
- в категорию Scope не попадают `ScopeState`, `ScopeDependencyException`, `ScopeDependencyInfo`, `DepHelper`, `ScopeDependenciesExtension`, `ScopeDependencyExtension` — у них нет `{@category Scope}` (аналогично проверить остальные 8 категорий).
