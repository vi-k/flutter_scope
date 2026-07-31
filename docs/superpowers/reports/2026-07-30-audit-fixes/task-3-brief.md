### Task 3: оживить test/notifier_test.dart

Файл (201 строка) полностью закомментирован и валит сьют ошибкой «Missing definition of `main`». Он тестирует упаковку массива слушателей в `Notifier` (`lib/src/utils/listenable/notifier.dart`) — 19 тестов на хитрую логику `_packListeners()`; `TestNotifier` существует в lib **только** ради этого файла. Все символы на месте.

**Files:**
- Modify: `test/notifier_test.dart`

- [ ] **Step 1: раскомментировать весь файл.**
- [ ] **Step 2: исправить импорт** — `package:scopo/scopo.dart` не экспортирует `Notifier`; заменить на прямой путь (такой стиль уже используется в `scope_auto_dependencies_test.dart:6`):

```dart
import 'package:scopo/src/utils/listenable/notifier.dart';
```

- [ ] **Step 3:** `flutter test test/notifier_test.dart`. Если какие-то из 19 захардкоженных раскладок массива (`[f1,f2,f3,null]` и т.п.) не совпадают с текущим `_packListeners()` — сверить с реализацией и обновить ожидания (реализация первична: тест описывает internal layout).
- [ ] **Step 4:** Полный `flutter test` → все зелёные. Коммит: `revive notifier_test`.

---

## Фаза 2 — баги корректности (каждый с регрессионным тестом)

