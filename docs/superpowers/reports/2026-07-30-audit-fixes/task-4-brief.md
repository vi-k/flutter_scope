### Task 4: `CompareUtils.identical` — бесконечная рекурсия (StackOverflow в публичном API)

`lib/src/utils/compare_utils.dart:7`: неквалифицированный вызов `identical` резолвится в сам статический метод, а не в `dart:core.identical`. Любой вызов → `StackOverflowError`. Экспортируется из `lib/scopo.dart:7`.

**Files:**
- Modify: `lib/src/utils/compare_utils.dart`
- Test: Create `test/compare_utils_test.dart`

- [ ] **Step 1: падающий тест**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:scopo/scopo.dart';

void main() {
  test('CompareUtils.identical does not recurse', () {
    final a = Object();
    expect(CompareUtils.identical(a, a), isTrue);
    expect(CompareUtils.identical(a, Object()), isFalse);
    expect(CompareUtils.notIdentical(a, Object()), isTrue);
  });
}
```

Ожидаемое падение: `StackOverflowError`.

- [ ] **Step 2: фикс** — квалифицировать ядро:

```dart
import 'dart:core' as core;
// …
static bool identical(Object? a, Object? b) => core.identical(a, b);
static bool notIdentical(Object? a, Object? b) => !core.identical(a, b);
```

- [ ] **Step 3:** тест PASS. Коммит: `fix infinite recursion in CompareUtils.identical`.

