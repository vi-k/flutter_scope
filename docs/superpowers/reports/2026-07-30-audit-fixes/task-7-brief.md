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

