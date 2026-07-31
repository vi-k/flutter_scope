### Task 9: проглоченные ошибки disposal + кривой toString

- `lib/src/scope/h_scope/scope_auto_dependency/scope_auto_dependency.dart:65-72`: `onError: (Object e) {}` — ошибки disposal исчезают бесследно. Минимум: логировать.
- `lib/src/scope/e_async_scope/async_scope_state.dart:51-53`: `AsyncScopeError.toString()` при непустом `progress` даёт несбалансированную скобку: `AsyncScopeError(e, st, progress: p))`.

**Files:**
- Modify: оба файла выше
- Test: `test/async_scope_state_test.dart` (create), тест на лог — в `test/scope_auto_dependencies_test.dart`

- [ ] **Step 1: тест toString**

```dart
test('AsyncScopeError.toString balanced parens', () {
  final s = AsyncScopeError(Exception('x'), StackTrace.empty, progress: 1)
      .toString();
  expect('('.allMatches(s).length, ')'.allMatches(s).length);
});
```

(Сигнатуру конструктора сверить по `async_scope_state.dart:43-53`.)

- [ ] **Step 2: фикс toString**

```dart
String toString() => '$AsyncScopeError($error, $stackTrace'
    '${progress == null ? '' : ', progress: $progress'})';
```

- [ ] **Step 3: фикс onError** — `scope_auto_dependency.dart:67`:

```dart
onError: (Object error, StackTrace stackTrace) {
  _log.e('dispose error', error: error, stackTrace: stackTrace);
},
```

(сигнатуру `_log.e` сверить с `ScopeLogFn`: `bool Function(Object? message, {Object? error, StackTrace? stackTrace})`).

- [ ] **Step 4:** PASS. Коммит: `log disposal errors, fix AsyncScopeError.toString`.

