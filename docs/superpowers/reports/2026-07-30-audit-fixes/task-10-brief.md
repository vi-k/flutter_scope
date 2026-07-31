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

