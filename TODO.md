# TODO

- Update README!!!
- ScopeAutoDependenciesProgress - добавить name (а name переименовать в path)
- Описать все примеры.
- Написать нормальную документацию.
- example для `ScopeWidgetCore`.
- `waitForChildren`, `asyncScopeRoot` - переделать. `asyncScopeRoot` перенести
  логику в `AsyncScopeCoordinator`. timeout перенести внутрь `waitForChildren`.

Тесты:
- одновременно `notifyDependents` и перестроение дерева сверху (`setState`).
- проверить ребёнка с глобальным ключом, что он успешно перерегистрируется и
  фризит старого родителя.

Известные проблемы (0.10.x):
- AsyncScopeCoordinator: глобальный static _queues без очистки; _AsyncScopeCoordinatorQueue.close() не вызывается нигде; два координатора с одним scopeKey делят очередь (в т.ч. между widget-тестами).
- AsyncScopeElementBase: окно между enter() и присвоением _subscription — dispose() в этом окне не отменяет инициализацию (см. TODO(nashol) в async_scope_core.dart:279).
- ScopeAutoDependencies: _root не сбрасывается после dispose() — повторный init() падает на assert; при autoDisposeOnError runDispose затирает ScopeDependencyFailed → ошибки группы теряются.
- Покрытие тестами: a_base, b_scope_widget, c_scope_model, d_scope_notifier, e_async_scope (особенно AsyncScopeCoordinator), f_async_data_scope, g_lite_scope — ноль тестов (частично закрывается регрессионными тестами 0.10.0).
- test/utils/logging.dart безусловно включает debug-уровень (шум ~15 строк на тест) — сделать opt-in; в my_fake_async.dart тела printPendingTimers/printFakeAsyncPendingTimers перепутаны местами.
- ScreenshotReplacer: в release/profile (asserts off) чтение debugNeedsPaint кидает LateInitializationError — первый заход уходит в терминальную ветку, кап retry фактически debug-only. Правильный фикс: читать debugNeedsPaint внутри assert.
- AsyncScope: событие init-стрима, пришедшее после Ready, ведёт к StateError → onError → повторному complete() на _initCompleter → 'Bad state: Future already completed' (см. TODO в async_scope_core.dart рядом с subscription.cancel).
- Тест-инфра: Stream.error(...) как init-стрим не доходит до модели под AutomatedTestWidgetsFlutterBinding (state остаётся Waiting), в plain test() работает — возможно, скрывает проблему планирования в _performAsyncInit.
- ScopeDependencyGroup.init(): та же empty-set дыра, что была в dispose (guard добавлен в 0.10.0, отдельного теста нет).
- LiteScope: markNeedsBuild при _shouldOnlyNotify может не перемонтировать ScreenshotReplacer после notifyDependents+close — 'mounted && Ready' необходимое, но не достаточное условие рендера buildOnReady (pre-existing, воспроизведено ревью Task 8).
