## Task 4: Публичная поверхность, документация, релизные заметки

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`
- Modify: `TODO.md`
- Modify: `lib/src/scope/e_async_scope/async_scope_coordinator.dart` (dartdoc)

- [ ] **Step 1: Дописать dartdoc координатора**

У `AsyncScopeCoordinator` сейчас только `{@category AsyncScope}`. Добавить описание: что он владеет очередями `scopeKey` в пределах своего поддерева, что ближайший выигрывает, и что он же ждёт скоупы без родителя. Ссылки писать в квадратных скобках только на существующие символы — `dart doc` эскалирует нерезолвящиеся ссылки в ошибку.

- [ ] **Step 2: README**

В разделе про `scopeKey` (около `README.md:408`) добавить абзац: координатор ограничивает область действия ключей своим поддеревом, а `AsyncScopeCoordinator.waitForChildren(context)` позволяет дождаться верхнеуровневых скоупов. Сниппет проверить компиляцией в scratch-пакете вне репозитория.

- [ ] **Step 3: CHANGELOG**

В секцию `## 0.10.0` добавить:

```markdown
* [breaking changes] `AsyncScopeCoordinator` now owns the `scopeKey` queues of
  its own subtree instead of a process-wide map, and is what scopes without a
  parent scope register with. The global `asyncScopeRoot`, `AsyncScopeRoot`,
  `AsyncScopeCoordinatorEntry` and `ScopeChildEntry` are gone, and
  `AsyncScopeParent.waitForChildren` takes `timeout` and `onTimeout`.
```

- [ ] **Step 4: TODO.md**

Удалить пункты, закрытые этой работой: строку про `AsyncScopeCoordinator` в «Известные проблемы» и пункт `waitForChildren, asyncScopeRoot - переделать…` в верхнем списке.

- [ ] **Step 5: Полная верификация**

```bash
flutter analyze                    # 0
(cd example/minimal && flutter analyze)      # 0
(cd example/scopo_demo && flutter analyze)   # 0
flutter test                       # все зелёные
dart doc --output <scratch>/dartdoc-coord    # 0 warnings, 0 errors
flutter pub publish --dry-run      # 0 warnings
(cd example/scopo_demo && flutter build macos --debug)  # собирается
```

- [ ] **Step 6: Коммит**

```bash
git add -A
git commit -m "docs: describe coordinator-owned scopeKey scoping"
```

---

## Verification

1. `flutter test` — 35 прежних тестов плюс 11 юнит-тестов ядра и 5 widget-тестов координатора, все зелёные.
2. `flutter analyze` — 0 в корне и обоих примерах.
3. `grep -rn "asyncScopeRoot\|AsyncScopeRoot\|AsyncScopeCoordinatorEntry\|ScopeChildEntry" lib test example` — пусто.
4. `grep -c "package:flutter" lib/src/scope/e_async_scope/scope_coordination.dart` — `0`.
5. `dart doc` — 0 warnings, 0 errors.
6. `flutter pub publish --dry-run` — 0 warnings.
7. `example/scopo_demo` собирается под macOS (демо использует координатор).
