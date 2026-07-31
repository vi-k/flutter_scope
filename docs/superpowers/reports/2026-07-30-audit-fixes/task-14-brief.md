### Task 14: pubspec.yaml — метаданные pub.dev

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1:** добавить после `homepage`:

```yaml
repository: https://github.com/vi-k/scopo
issue_tracker: https://github.com/vi-k/scopo/issues
topics:
  - state-management
  - dependency-injection
  - scope
  - widgets
```

- [ ] **Step 2:** `flutter: ">=1.17.0"` — ложь (пакет использует Dart-3 class modifiers). Заменить на `flutter: ">=3.16.0"` (Flutter 3.16 = Dart 3.2, соответствует `sdk: ^3.2.0`).
- [ ] **Step 3:** `flutter_lints: ^5.0.0` объявлен, но `analysis_options.yaml` включает `package:lints/recommended.yaml` — `lints` используется незадекларированно. Решение: в корне и `example/scopo_demo` заменить include на `package:flutter_lints/flutter.yaml` (все ручные правила в `linter.rules` сохраняются, они имеют приоритет), прогнать `flutter analyze` и погасить/осознанно заглушить новые Flutter-специфичные замечания, если появятся.
- [ ] **Step 4:** `flutter pub publish --dry-run` → 0 warnings. Коммит: `add pub.dev metadata, honest flutter constraint`.

