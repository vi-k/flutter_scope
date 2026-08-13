# scopo — план исправлений по итогам аудита 2026-07-30

> **Состояние на 2026-08-12:** выполнен полностью, смержен в `main` (9ee497d, релиз 0.10.0). Исторический документ, не поддерживается — часть решений позднее пересмотрена.
> **Что это:** план из 18 задач по итогам аудита кода перед выпуском 0.10.0.
> **Связанные записи:** отчёты по задачам — `2026-07-30[2]-audit-fixes-log.md`, итог волны — `2026-07-30[3]-audit-fixes-final-report.md`.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Довести scopo до зелёного тест-сьюта, исправить 9 найденных багов корректности, вычистить мёртвый код и привести README/упаковку в соответствие с реальным API. Релиз 0.10.0.

**Architecture:** Четыре независимые фазы: (1) единый формат путей зависимостей + оживление тестов, (2) баги корректности с регрессионными тестами, (3) мёртвый код и анализатор, (4) документация и метаданные pub.dev. Фазы 1–2 — код, 3–4 — можно выполнять параллельно с ними.

**Tech Stack:** Flutter/Dart 3, `flutter_test` + `fake_async` (через `test/utils/my_fake_async.dart`), pub.dev.

## Global Constraints

- Версия релиза: `0.10.0` (изменение формата путей в `ScopeDependencyException.name` / `flattenDependencies` — breaking; удаление мёртвого экспортируемого API — breaking). В CHANGELOG помечать `[breaking changes]` по образцу секции 0.9.0.
- Канонический формат путей (зафиксирован коммитом `3c46950`, здесь доводится до конца): **без ведущего `/`**; безымянная группа (name == '') не добавляет ни сегмент, ни разделитель — на любом уровне вложенности, не только в корне. `[root]` → `[group]` остаётся как есть.
- После каждой задачи: `flutter analyze` без новых замечаний, `flutter test` — ни одного нового падения; коммит на задачу.
- Стиль коммитов репозитория: короткие lowercase-сообщения («fix …», «update …»).
- `flutter analyze` до начала работ показывает ровно 3 замечания (см. Задачи 10–11); к концу Фазы 3 их 0.

---

## Фаза 1 — единый формат путей и зелёный тест-сьют

Контекст: сейчас **все 17 тестов падают**. 16 — из-за того, что `3c46950` поменял формат путей только в одном из трёх построителей; 17-й — `test/notifier_test.dart` закомментирован целиком и не имеет `main`.

Три построителя путей:

| # | Место | Учитывает пустое имя? |
|---|---|---|
| A | `scope_dependency_group.dart:27` `_path()` (прогресс) | да (починен 3c46950) |
| B | `scope_dependency_mixin.dart:~104` `_handleError` (ошибки) | **нет** — даёт `/dep1` и `concurrent1//dep2` для вложенной безымянной группы |
| C | `scope_auto_dependency.dart:106` `_extract` (flattenDependencies) | **нет** — даёт `/dep1` и `…//…` |

Выбран вариант «фикс в lib + тестах» (а не только в тестах): намерение `3c46950` — безымянные группы на любом уровне (он же удалил asserts на непустые имена), и B/C при вложенной безымянной группе генерируют двойной слэш — это латентный баг, а не стиль.

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

### Task 6: `ScopeNotifierBase.update` не подписывается на новый Listenable

`lib/src/scope/d_scope_notifier/scope_notifier_base.dart:82-89`: при смене `widget.value` старый слушатель снимается, а на новый вызывается `removeListener` вместо `addListener` — все `select`/`of(listen: true)` навсегда перестают обновляться.

**Files:**
- Modify: `lib/src/scope/d_scope_notifier/scope_notifier_base.dart:86`
- Test: Create `test/scope_notifier_test.dart`

- [ ] **Step 1: падающий widget-тест**

```dart
testWidgets('swapping ScopeNotifier.value re-subscribes', (tester) async {
  final first = ValueNotifier(0);
  final second = ValueNotifier(100);
  Widget app(ValueNotifier<int> v) => MaterialApp(
        home: ScopeNotifier<ValueNotifier<int>>.value(
          value: v,
          child: Builder(
            builder: (context) => Text(
              '${ScopeNotifier.of<ValueNotifier<int>>(context).value}',
            ),
          ),
        ),
      );
  await tester.pumpWidget(app(first));
  await tester.pumpWidget(app(second));
  second.value = 101;
  await tester.pump();
  expect(find.text('101'), findsOneWidget); // сейчас: '100', обновления не приходят
});
```

(Точную сигнатуру конструктора/`of` сверить с `scope_notifier.dart` — примеры использования: `example/scopo_demo/lib/home/demos/c_scope_notifier/`.)

- [ ] **Step 2: фикс** — строка 86: `newWidget.value?.removeListener(...)` → `newWidget.value?.addListener(notifyDependents);`
- [ ] **Step 3:** PASS. Коммит: `fix listener re-subscription on ScopeNotifier.value swap`.

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

### Task 8: LiteScope.close() виснет вне состояния Ready + ScreenshotReplacer

- `lib/src/scope/g_lite_scope/lite_scope_core.dart:216-244`: `close()` ждёт `_screenshotCompleter`, который комплитится только из `ScreenshotReplacer` внутри `buildOnReady()`. Если scope в `Waiting`/`Progress`/`Error` — `close()` виснет навсегда.
- `lib/src/utils/screenshot_replacer.dart:51-71`: `finally { widget.onCompleted(); }` срабатывает и на retry-путях (`boundary == null`, `debugNeedsPaint`) — барьер скриншота не работает; `_image` никогда не `dispose()`-ится — утечка `ui.Image` на каждое закрытие.

**Files:**
- Modify: `lib/src/scope/g_lite_scope/lite_scope_core.dart:216-244`
- Modify: `lib/src/utils/screenshot_replacer.dart`
- Test: Create `test/lite_scope_test.dart`

- [ ] **Step 1: падающий тест** — `LiteScope` в состоянии `Waiting` (инициализация не стартовала/не завершена), вызвать `close()`, прокрутить кадры, ожидать завершения future от `close()` (сейчас — timeout).
- [ ] **Step 2: фикс `close()`** — ждать `_screenshotCompleter` только если он реально будет закомплекчен: создавать/ждать его только когда текущее состояние — Ready (т.е. `buildOnReady` активен); иначе пропускать барьер.
- [ ] **Step 3: фикс `ScreenshotReplacer._capture()`** — убрать `onCompleted()` из `finally`; вызывать его явно в конце успешной ветки и в терминальных ошибочных ветках, но **не** на retry-путях (`return` до вызова). В `State.dispose()` добавить `_image?.dispose();`.
- [ ] **Step 4:** PASS + весь сьют. Коммит: `fix LiteScope.close hang and ScreenshotReplacer lifecycle`.

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

### Task 10: известные проблемы, выносимые за скоуп релиза (зафиксировать в TODO.md)

Три находки требуют дизайна, а не точечного фикса; в этом релизе — только зафиксировать:

- [ ] **Step 1:** добавить в `TODO.md`:

```
- AsyncScopeCoordinator: глобальный static _queues без очистки; _AsyncScopeCoordinatorQueue.close() не вызывается нигде; два координатора с одним scopeKey делят очередь (в т.ч. между widget-тестами).
- AsyncScopeElementBase: окно между enter() и присвоением _subscription — dispose() в этом окне не отменяет инициализацию (см. TODO(nashol) в async_scope_core.dart:279).
- ScopeAutoDependencies: _root не сбрасывается после dispose() — повторный init() падает на assert; при autoDisposeOnError runDispose затирает ScopeDependencyFailed → ошибки группы теряются.
- Покрытие тестами: a_base, b_scope_widget, c_scope_model, d_scope_notifier, e_async_scope (особенно AsyncScopeCoordinator), f_async_data_scope, g_lite_scope — ноль тестов (частично закрывается регрессионными тестами 0.10.0).
- test/utils/logging.dart безусловно включает debug-уровень (шум ~15 строк на тест) — сделать opt-in; в my_fake_async.dart тела printPendingTimers/printFakeAsyncPendingTimers перепутаны местами.
```

- [ ] **Step 2:** Коммит: `record known async lifecycle issues in TODO`.

---

## Фаза 3 — мёртвый код, опечатки, анализатор

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

### Task 12: мёртвый код

Всё ниже не имеет ни одного вызова в lib/test/example (проверено аудитом); удаления экспортируемого — breaking, идут в 0.10.0.

**Files:**
- Delete: `lib/src/utils/type_to_string.dart` (не импортируется никем)
- Delete: `lib/src/scope/g_lite_scope/lite_scope_init_state.dart` (`LiteScopeInitState/Waiting/Progress/Ready` — LiteScope реально использует `AsyncScopeInitState`; **экспортируется** → breaking) — удалить и `part`-директиву из `lib/src/scope/scope.dart`
- Modify: `lib/src/scope/h_scope/scope_auto_dependency/scope_dependency/scope_dependency_state.dart:170` — опечатка `ScopeDependencyNoDisposalRequred` → `ScopeDependencyNoDisposalRequired` (класс нигде не конструируется; переименование — breaking для тех, кто матчит sealed-иерархию)
- Modify: `lib/src/scope/h_scope/scope_auto_dependency/scope_dependency/scope_dependency_impl.dart:23-24` — убрать дублирующее присваивание `_helper = helper;`
- Modify: `lib/src/scope/h_scope/scope_auto_dependency/scope_dependency/scope_dependency.dart:41` — удалить неиспользуемый `ScopeDependencyExtension.isGroup` **или** оставить как публичное API (решение: оставить — безвредный public helper)
- НЕ трогать: `ListenableView` (экспортируется, потенциально полезен пользователям), `Notifier` (оживает в Задаче 3), `_AsyncScopeCoordinatorQueue.close()` (ждёт редизайна из Задачи 10)

- [ ] **Step 1:** удаления и правки по списку; `grep -rn 'LiteScopeInitState\|LiteScopeWaiting\|typeToShortString\|NoDisposalRequred'` по lib/test/example → 0 совпадений.
- [ ] **Step 2:** `flutter analyze` + `flutter test` — чисто/зелёно. Коммит: `remove dead code, fix ScopeDependencyNoDisposalRequired typo`.

### Task 13: «Deffered» → «Deferred» в демо

**Files:**
- Rename: `example/scopo_demo/lib/home/demos/i_deffered_closing/` → `i_deferred_closing/` (и файл `deffered_closing_demo.dart` → `deferred_closing_demo.dart`)
- Modify: класс `DefferedClosingDemo` → `DeferredClosingDemo`, лейбл вкладки в `example/scopo_demo/lib/home/home.dart:29` `'Deffered closing'` → `'Deferred closing'`

- [ ] **Step 1:** `git mv` + переименование класса + правка импортов/лейбла; `grep -rin deffered example/` → 0.
- [ ] **Step 2:** `flutter analyze` в scopo_demo → 0. Коммит: `fix Deferred spelling in demo`.

---

## Фаза 4 — документация и упаковка

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

### Task 15: README.md — переписать

Сейчас 3 из 5 примеров кода не компилируются, два раздела документируют несуществующие классы. Структура нового README:

**Files:**
- Modify: `README.md`
- Modify: `TODO.md` (снять пункт `Update README!!!`)

- [ ] **Step 1: исправить сломанные примеры:**
  - `:76-78` — `init(BuildContext)` → `initDependencies(BuildContext)` (реальный член: `lib/src/scope/h_scope/scope_base.dart:83`);
  - `:29-48` — в сэмпл `AppDependencies implements ScopeDependencies` добавить `@override void unmount() {}` (обязателен с 0.7.3);
  - `:118-129` — `class MyConfig extends ScopeWidgetBase` → `final class …` (база — `abstract base class`); убрать собственное поле `child` (оно уже есть у `ScopeInheritedWidget`); добавить `super.key`;
  - `:175-201` — **удалить** разделы `ScopeAsyncInitializer` и `ScopeStreamInitializer` — классов не существует с 0.4.x;
  - `:210` — комментарий `// Get State (listen: true by default)` → `// Get State (does not subscribe; use select/of(listen: true) to listen)` — `Scope.of` жёстко `listen: false` (`scope_base.dart:158-163`);
  - `:46,141` — опечатка `Dipose` → `Dispose`.
- [ ] **Step 2: добавить недостающие разделы** (каждый — 5–15 строк + компилируемый сниппет, выверенный по `example/minimal/lib/main.dart` и `example/scopo_demo`):
  - Installation (`flutter pub add scopo`);
  - Logging & configuration: `ScopeConfig.logger.level`, `ScopeConfig.logger[level].publisher = ScopeLogFormatter(...)`, таймауты `defaultScopeKeysTimeout`/`defaultWaitForChildrenTimeout` — сниппет взять из `example/minimal/lib/main.dart:9-33`;
  - обзор семейств `AsyncScope` / `AsyncDataScope` / `LiteScope` (по абзацу + ссылка на демо);
  - ссылки: на `example/` (оба приложения), на API-доки;
  - бейджи вверху: `pub version`, `license` (`https://img.shields.io/pub/v/scopo`, `…/github/license/vi-k/scopo`).
- [ ] **Step 3:** убрать `> [!WARNING] README needs updating!` (строки 3-4); каждый сниппет скопировать в scratch-файл и прогнать через `dart analyze` перед вставкой.
- [ ] **Step 4:** вычеркнуть `Update README!!!` из TODO.md. Коммит: `rewrite README`.

### Task 16: example/README.md — устранить дрейф (это страница Example на pub.dev)

pub.dev не находит ни один из example-app'ов автоматически (они на уровень глубже, чем ищет pana) и рендерит `example/README.md` — рукописную копию minimal, которая разъехалась и не компилируется.

**Files:**
- Modify: `example/README.md`

- [ ] **Step 1:** заменить вложенный код точной копией актуального `example/minimal/lib/main.dart` (целиком, включая блок логирования строк 1-33 — сейчас он отсутствует, и logging невидим на pub.dev; включая `@override void unmount() {}`, `final class`, `covariant String? progress`).
- [ ] **Step 2:** единственный русский dartdoc в minimal (`example/minimal/lib/main.dart:59` `/// Метод инициализации зависимостей.`) перевести на английский в самом `main.dart` — копия в README подтянется.
- [ ] **Step 3:** сохранить ссылки на оба приложения; ссылку на `scopo_demo` поднять выше и подписать («9 interactive demos»). Коммит: `sync example README with minimal app`.

### Task 17: CHANGELOG + dartdoc-страницы категорий

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `doc/h_scope.md`, `doc/i_debug.md` (остальные 7 заглушек — вне скоупа, зафиксировать в TODO.md)
- Modify: `lib/src/environment/scope_logger.dart` (аннотации категорий)
- Modify: `lib/src/scope/a_base/base.dart:7`

- [ ] **Step 1:** CHANGELOG: разбить `## 0.9.3-0.9.5` на три отдельные секции (pub.dev матчит по точной строке версии; страницы 0.9.4/0.9.5 сейчас без changelog); нормализовать пустую строку после каждого заголовка; добавить секцию `## 0.10.0` (заполняется в Задаче 18).
- [ ] **Step 2:** `doc/i_debug.md` — написать реальную страницу: уровни (`ScopeLogLevel`), включение (`ScopeConfig.logger.level = …`), подключение publisher'а (`ScopeConfig.logger[level].publisher = ScopeLogFormatter(format: ScopeLogger.defaultFormat, output: …)`), таймауты и `pauseAfterInitializationEnabled` из `ScopeConfig`. Основа — рабочий код `example/minimal/lib/main.dart:9-33` и `test/utils/logging.dart`.
- [ ] **Step 3:** `doc/h_scope.md` — обзор главной категории: `Scope` → `initDependencies` → `ScopeAutoDependencies`/`ScopeDependencyGroup` (`sequential`/`concurrent`), формат путей (без ведущего `/`), `ScopeDependencyException`, жизненный цикл dispose/unmount.
- [ ] **Step 4:** добавить `{@category debug}` к `ScopeLogger`, `ScopeLog`, `ScopeLogLevel`, `ScopeLevelLogger`, `ScopeLogFn`, `ScopeLogPublisher`, `ScopeLogFormatter` в `scope_logger.dart` (сейчас на странице debug — один `ScopeConfig`); удалить мусорный dartdoc `/// saaa` в `base.dart:7`. Внимание: `dartdoc_options.yaml` эскалирует `unresolved-doc-reference` в ошибку — все `[ссылки]` в новых страницах проверять сборкой `dart doc`.
- [ ] **Step 5:** дописать в TODO.md: `- заполнить оставшиеся 7 заглушек doc/*.md; скриншоты для pub.dev (screenshots: в pubspec); русские dartdoc-комментарии в lib/ (78 строк) перевести.` Коммит: `changelog per-version sections, debug and scope doc pages`.

### Task 18: релиз 0.10.0

**Files:**
- Modify: `pubspec.yaml:4`, `CHANGELOG.md`

- [ ] **Step 1:** `version: 0.10.0`; секция CHANGELOG:

```markdown
## 0.10.0

* [breaking changes] Unify dependency path format: no leading `/` in
  `ScopeDependencyException.name`, `ScopeDependencyInfo.path` and progress
  paths; anonymous groups add no separator.
* [breaking changes] Remove dead API: `LiteScopeInitState`/`Waiting`/
  `Progress`/`Ready`, `typeToShortString`; rename
  `ScopeDependencyNoDisposalRequred` to `ScopeDependencyNoDisposalRequired`.
* Fix infinite recursion in `CompareUtils.identical`.
* Fix hang in `ScopeAutoDependencies.dispose()` when no dependency requires
  disposal.
* Fix `ScopeNotifier.value` not subscribing to a new listenable on update.
* Fix `LiteScope.close()` hang outside the Ready state; fix
  `ScreenshotReplacer` completing early and leaking `ui.Image`.
* Guard AsyncScope post-frame callbacks with `mounted`.
* Log dependency disposal errors instead of swallowing them.
* Fix unbalanced parenthesis in `AsyncScopeError.toString()`.
* Add `repository`, `issue_tracker` and `topics` to pubspec; honest Flutter
  constraint.
* Rewrite README; sync the pub.dev example; real `debug`/`Scope` doc pages.
```

- [ ] **Step 2: полная верификация** — `flutter analyze` (корень + оба example) → 0; `flutter test` → все зелёные; `flutter pub publish --dry-run` → 0 warnings; запустить `example/scopo_demo` (`flutter run -d macos`) и прокликать вкладки Scope/LiteScope/AsyncScope — прогресс-пути в консоли без ведущего `/`, закрытие вкладок не виснет.
- [ ] **Step 3:** коммит `release 0.10.0`, тег `v0.10.0`, `git push origin main v0.10.0`, `flutter pub publish --force`.

---

## Verification (сквозная)

1. `flutter test` — **0 failed** (было 17/17 failed); в сьюте появились: тест анонимных групп, 19 тестов `Notifier`, регрессионные тесты Задач 4–9.
2. `flutter analyze` в корне, `example/minimal`, `example/scopo_demo` — 0 issues (было 3).
3. `flutter pub publish --dry-run` — 0 warnings.
4. Ручной прогон `scopo_demo` на macOS: все 9 вкладок открываются/закрываются, консольные пути единообразны.
5. После публикации: страница pub.dev показывает Repository-ссылку, топики, changelog на страницах 0.9.4/0.9.5, компилируемый Example-таб.
