### Task 5: вечное зависание dispose/init на пустом наборе стримов concurrent-группы

`scope_dependency_group.dart:129-141`: в `onListen` при пустом iterable цикл не выполняется, `controller.close()` не вызывается — стрим не завершается никогда. Достижимо: `concurrent('g', [...])`, где ни один `dep` не назначил `dep.dispose` → фильтр `.where((dep) => dep.disposalRequired)` пуст → `ScopeAutoDependencies.dispose()` ждёт вечно. Там же вторая гонка: `subscription.onDone(...)` навешивается **до** `subscriptions.add(subscription)` при sync-контроллере — синхронно завершившийся стрим видит пустой список и закрывает контроллер раньше времени.

**Files:**
- Modify: `lib/src/scope/h_scope/scope_auto_dependency/scope_dependency/scope_dependency_group.dart:129-141`
- Test: `test/scope_auto_dependencies_test.dart`

- [ ] **Step 1: падающий тест** (по образцу существующих, через `MyFakeAsync`):

```dart
test('dispose completes when no dependency requires disposal', () {
  // TestDependencies-вариант, где ни один initDep не задаёт dep.dispose
  final dependencies = TestDependenciesNoDispose();
  myFakeAsync((async) {
    // init до Ready, затем:
    var disposed = false;
    unawaited(dependencies.dispose().then((_) => disposed = true));
    async.waitFuture(...); // прокрутить все таймеры
    expect(disposed, isTrue); // сейчас: false — висит вечно
  });
});
```

- [ ] **Step 2: фикс** — в начале `onListen`:

```dart
controller.onListen = () {
  if (isEmpty) {
    controller.close();
    return;
  }
  // …
```

и переставить `subscriptions.add(subscription);` **до** навешивания `onDone` (собрать подписки циклом, обработчики `onDone` навесить после заполнения списка).

- [ ] **Step 3:** тест PASS, весь сьют зелёный. Коммит: `fix hang on empty concurrent stream set`.

