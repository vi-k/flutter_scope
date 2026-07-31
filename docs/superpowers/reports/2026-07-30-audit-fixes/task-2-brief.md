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

