### Task 1: выровнять построители B и C по пустому имени

**Files:**
- Modify: `lib/src/scope/h_scope/scope_auto_dependency/scope_dependency/scope_dependency_mixin.dart:100-116`
- Modify: `lib/src/scope/h_scope/scope_auto_dependency/scope_auto_dependency.dart:106`
- Test: `test/scope_auto_dependencies_test.dart` (новый тест в конце `main`)

**Interfaces:**
- Produces: `ScopeDependencyException.name` и `ScopeDependencyInfo.path` больше не содержат ведущий `/` и двойные `//`. Задача 2 опирается на этот формат.

- [ ] **Step 1: падающий тест на безымянную вложенную группу**

```dart
group('anonymous nested group paths', () {
  test('no leading or double slashes', () {
    final dependencies = TestDependenciesAnonNested(failed: {'depB'});
    myFakeAsync((async) {
      final progress = handleInitFor(dependencies, async);
      expect(progress, ['depA (1/2)', 'depB: Exception: depB failed']);
      expect(
        dependencies
            .flattenDependencies()
            .map((info) => '${info.path}${info.dependency.name}')
            .toList(),
        ['', 'depA', 'depB'], // корень + два ребёнка, без '/' и '//'
      );
    });
  });
});
```

где `TestDependenciesAnonNested` строит `sequential('', [dep('depA', …), concurrent('', [dep('depB', …)])])` — по образцу существующего `TestDependencies` (строки 14–83). Вспомогательный `handleInitFor` — копия логики `handleInit()` (строки 89–127), параметризованная экземпляром.

- [ ] **Step 2: убедиться, что тест падает** — `flutter test test/scope_auto_dependencies_test.dart --name 'anonymous'`; ожидаемое падение: `'/depB: …'` или `'//depB…'` вместо `'depB: …'`.

- [ ] **Step 3: фикс построителя B** — `scope_dependency_mixin.dart`, ветка `error is ScopeDependencyException`:

```dart
ScopeDependencyException(
  name.isEmpty ? error.name : '$name/${error.name}',
  error.error,
  error.stackTrace,
),
```

(Ветку `else` с голым `name` не менять: для безымянной группы её собственная ошибка даёт `name == ''` — допустимо, `toString()` выведет `': <error>'`; поведение зафиксировать dartdoc-комментарием у `ScopeDependencyException.name`: «путь без ведущего слэша; пустая строка — ошибка безымянного корня».)

- [ ] **Step 4: фикс построителя C** — `scope_auto_dependency.dart:106`:

```dart
yield* _extract(
  child,
  level + 1,
  dependency.name.isEmpty ? path : '$path${dependency.name}/',
);
```

- [ ] **Step 5:** `flutter test … --name 'anonymous'` → PASS. Остальные 16 тестов всё ещё красные (чинятся Задачей 2). Коммит: `fix path building for anonymous dependency groups`.

