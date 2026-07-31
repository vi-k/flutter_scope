### Task 11: обнулить flutter analyze

Ровно 3 замечания:

**Files:**
- Modify: `lib/src/environment/scope_config.dart:5-7`
- Modify: `lib/src/scope/h_scope/scope_auto_dependency/scope_auto_dependency.dart:25`
- Modify: `example/scopo_demo/lib/home/demos/c_scope_notifier/scope_notifier_example2.dart:91`
- Modify: `example/scopo_demo/analysis_options.yaml:31`

- [ ] **Step 1:** `scope_config.dart` — `// ignore: avoid_classes_with_only_static_members` стоит на строке 5, но между ним и классом вклинился dartdoc (строка 6), из-за чего ignore не работает. Переставить комментарий непосредственно над `abstract final class ScopeConfig` (после dartdoc).
- [ ] **Step 2:** `scope_auto_dependency.dart:25` — `this.buildDependencies(context)` → `buildDependencies(context)`.
- [ ] **Step 3:** `scope_notifier_example2.dart:91` — удалить строку `@override` над конструктором `CounterScopeElement(super.widget);`. Заодно удалить окаменелость `# invalid_annotation_target: ignore ???` в `example/scopo_demo/analysis_options.yaml:31`.
- [ ] **Step 4:** `flutter analyze` (корень + оба example) → **0 issues**. Коммит: `fix analyzer issues`.

