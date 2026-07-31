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

