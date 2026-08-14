# План реализации документации учебного кода `scopo_demo`

> **Состояние на 2026-08-14:** выполнено прямо в `main` коммитами `10916ce`,
> `ef42e86`, `e66b454` и `631d83b`.
> **Что это:** пошаговый план содержательных английских комментариев во всех
> девяти демонстрациях `example/scopo_demo` и последующей полной проверки.
> **Связанные записи:**
> `2026-08-14[5]-example-code-documentation-design.md`.
>
> **Для агентов-исполнителей:** обязательно использовать
> `superpowers:subagent-driven-development` (рекомендуется) или
> `superpowers:executing-plans`; выполнять задачи по порядку и отмечать шаги
> флажками `- [x]` по мере прохождения.

**Цель:** превратить исходники 39 Dart-файлов в `home/demos/` в понятный
учебный материал о механизмах scopo, не документируя служебный UI формально.

**Устройство:** работа делится по четырём смысловым группам: синхронные
семейства, два асинхронных семейства, два семейства с полным жизненным циклом,
навигация и отложенное закрытие. В каждом файле dartdoc объясняет роль
публичного учебного типа, а редкий обычный комментарий — причину неочевидной
строки; исполняемый код не меняется.

**Технологии:** Dart 3.7.0, Flutter 3.29.0 через fvm, dartdoc-комментарии,
Flutter analyzer, существующие shell-гейты проекта.

## Общие ограничения

- Все новые комментарии в Dart-файлах пишутся по-английски.
- Меняются только комментарии; имена, сигнатуры, выражения и поведение
  остаются байт-в-байт прежними.
- `public_member_api_docs` в examples не включается; очевидные конструкторы,
  `build` и `createState` отдельно не описываются.
- `example/minimal`, `app/`, `common/`, `utils/`, README, `lib/` и
  `CHANGELOG.md` не меняются.
- `scope_notifier_example1_special.dart` не прогоняется через formatter:
  старое тело файла уже расходится с Flutter 3.29.0 и не входит в эту работу.
- После каждого смыслового блока обновляется `docs/handoff.md`; пункт бэклога
  удаляется только вместе с последней частью реализации.
- Полный набор из семи проверок `AGENTS.md` §6 проходит перед коммитом,
  закрывающим реализацию.

---

### Задача 1: синхронные семейства

**Файлы:**

- Изменить:
  `example/scopo_demo/lib/home/demos/a_scope_widget/scope_widget_demo.dart`
- Изменить:
  `example/scopo_demo/lib/home/demos/a_scope_widget/scope_widget_example.dart`
- Изменить:
  `example/scopo_demo/lib/home/demos/a_scope_widget/scope_widget_core_example.dart`
- Изменить:
  `example/scopo_demo/lib/home/demos/b_scope_model/scope_model_demo.dart`
- Изменить:
  `example/scopo_demo/lib/home/demos/b_scope_model/scope_model_example1.dart`
- Изменить:
  `example/scopo_demo/lib/home/demos/b_scope_model/scope_model_example2.dart`
- Изменить:
  `example/scopo_demo/lib/home/demos/b_scope_model/scope_model_example3.dart`
- Изменить:
  `example/scopo_demo/lib/home/demos/c_scope_notifier/scope_notifier_demo.dart`
- Изменить:
  `example/scopo_demo/lib/home/demos/c_scope_notifier/scope_notifier_example1.dart`
- Изменить:
  `example/scopo_demo/lib/home/demos/c_scope_notifier/scope_notifier_example1_special.dart`
- Изменить:
  `example/scopo_demo/lib/home/demos/c_scope_notifier/scope_notifier_example2.dart`
- Изменить:
  `example/scopo_demo/lib/home/demos/c_scope_notifier/scope_notifier_example3.dart`
- Изменить: `docs/handoff.md`

**Интерфейсы:**

- Использует: существующие `ScopeWidget*`, `ScopeModel*` и `ScopeNotifier*`
  без изменения их вызовов.
- Создаёт: только английские объяснения трёх способов владения данными и
  точечных перестроений; runtime-интерфейсов не создаёт.

- [x] **Шаг 1: подтвердить чистую исходную точку example**

  Выполнить:

  ```sh
  cd example/scopo_demo
  rtk fvm flutter analyze
  ```

  Ожидание: `No issues found!`.

- [x] **Шаг 2: объяснить `ScopeWidgetBase` и `ScopeWidgetCore`**

  Использовать следующие ведущие формулировки над указанными типами; второе
  предложение раскрывает ровно перечисленное следствие:

  | тип | точный смысл комментария |
  | --- | --- |
  | `ScopeWidgetDemo` | “Compares immutable widget parameters with mutable state owned by a custom scope element.” |
  | `ScopeWidgetExample` | “Demonstrates `ScopeWidgetBase` exposing a value owned and updated by the parent widget.” |
  | `CounterScope` в base-файле | “Exposes the current widget parameter and lets only dependents whose selected value changed rebuild.” |
  | `ScopeWidgetCoreExample` | “Demonstrates `ScopeWidgetCore` with mutable state stored in its custom element.” |
  | `CounterScope` в core-файле | “Publishes a narrow command context through `of` and a selectively watched count through `countOf`.” |
  | `CounterScopeContext` | “The command-facing interface exposed to descendants without revealing the element implementation.” |
  | `CounterScopeElement` | “Owns the count for the lifetime of the mounted scope and notifies selector dependents after each increment.” |

  Над `notifyDependents()` добавить причину, не описание вызова:

  ```dart
  // Re-evaluate selectors after the element-owned value changes.
  notifyDependents();
  ```

- [x] **Шаг 3: объяснить три варианта `ScopeModel`**

  Добавить dartdoc с такими ведущими предложениями:

  | тип | точный смысл комментария |
  | --- | --- |
  | `ScopeModelDemo` | “Compares an externally owned model, an element-owned model, and a `State` exposed as a model.” |
  | `ScopeModelExample1` | “Passes a parent-owned `CounterModel` through `ScopeModelBase.value`.” |
  | `CounterModel` в example 1 | “A plain mutable value whose owner is responsible for rebuilding the scope widget.” |
  | `CounterScope` в example 1 | “Selects the count from the externally owned model without taking over its lifecycle.” |
  | `ScopeModelExample2` | “Lets a `ScopeModelCore` element create, own, and expose a plain model.” |
  | `CounterModel` в example 2 | “The plain model kept inside `CounterScopeElement` for the element lifetime.” |
  | `CounterScope` в example 2 | “Separates commands through `of` from selective reads through `countOf`.” |
  | `CounterScopeContext` | “The public model-and-command surface implemented by the custom element.” |
  | `CounterScopeElement` | “Owns the model and explicitly notifies dependents after mutating it.” |
  | `ScopeModelExample3` | “Exposes a regular Flutter `State` through `ScopeModel.value`.” |
  | `CounterScope` в example 3 | “Provides typed `of` and `select` accessors for `CounterScopeState`.” |
  | `CounterScopeState` | “Owns the count as normal Flutter state and publishes itself as the scoped model.” |

  У `CounterScopeElement.increment()` добавить:

  ```dart
  // A plain model cannot notify the scope, so the owning element does it.
  notifyDependents();
  ```

- [x] **Шаг 4: объяснить три варианта `ScopeNotifier` и special-сценарий**

  Добавить dartdoc с такими ведущими предложениями:

  | тип | точный смысл комментария |
  | --- | --- |
  | `ScopeNotifierDemo` | “Compares base, core, and `StateAsNotifier` ways to expose a `Listenable`.” |
  | `ScopeNotifierExample1` | “Lets `ScopeNotifierBase` create, listen to, and dispose a `ChangeNotifier`.” |
  | `CounterModel` в example 1 | “Notifies the scope whenever its selected count changes.” |
  | `CounterScope` в example 1 | “Owns the notifier through `create` and `dispose` and exposes command and selector accessors.” |
  | `ScopeNotifierExample1Special` | “Exercises a parent rebuild and a notifier update in the same callback.” |
  | `ScopeNotifierExample2` | “Uses `ScopeNotifierCore` to keep the concrete notifier private behind a narrow interface.” |
  | `CounterModel` в example 2 | “The public `Listenable` contract exposed without the concrete notifier type.” |
  | `CounterScope` в example 2 | “Returns the interface from `of` while its custom element retains the implementation.” |
  | `CounterScopeElement` в example 2 | “Owns the notifier and detaches scope dependents before disposing it.” |
  | `ScopeNotifierExample3` | “Exposes a Flutter `State` as a notifier through `ScopeNotifier.value`.” |
  | `CounterScope` в example 3 | “Provides typed access to the `StateAsNotifier` below it.” |
  | `CounterScopeState` | “Uses `notifyListeners` instead of `setState` so selectors decide what rebuilds.” |

  Заменить два существующих русских комментария точными английскими
  формулировками:

  ```dart
  /// Exercises a parent rebuild and a notifier update in the same callback.
  /// The widget parameter and notifier value update their own dependents.
  class ScopeNotifierExample1Special extends StatefulWidget {
  ```

  ```dart
  // Detach scope dependents before disposing the notifier they reference.
  super.dispose();
  _model.dispose();
  ```

- [x] **Шаг 5: отформатировать синхронные файлы без известного исключения**

  Запустить formatter для одиннадцати изменённых файлов, не передавая
  `scope_notifier_example1_special.dart`:

  ```sh
  rtk fvm dart format --set-exit-if-changed \
    example/scopo_demo/lib/home/demos/a_scope_widget/*.dart \
    example/scopo_demo/lib/home/demos/b_scope_model/*.dart \
    example/scopo_demo/lib/home/demos/c_scope_notifier/scope_notifier_demo.dart \
    example/scopo_demo/lib/home/demos/c_scope_notifier/scope_notifier_example1.dart \
    example/scopo_demo/lib/home/demos/c_scope_notifier/scope_notifier_example2.dart \
    example/scopo_demo/lib/home/demos/c_scope_notifier/scope_notifier_example3.dart
  ```

  Ожидание: `0 changed` и код выхода `0`. Для special-файла проверить, что
  новые строки не длиннее 80 символов и diff не содержит изменений старого
  тела.

- [x] **Шаг 6: проверить блок и только комментарийный diff**

  Выполнить analyzer `example/scopo_demo`, затем:

  ```sh
  rtk rg -n '[А-Яа-яЁё]' example/scopo_demo/lib/home/demos
  rtk git diff -- example/scopo_demo/lib/home/demos/a_scope_widget example/scopo_demo/lib/home/demos/b_scope_model example/scopo_demo/lib/home/demos/c_scope_notifier
  ```

  Ожидание: поиск кириллицы пуст; diff содержит только строки `///`, `//` и
  удаление двух старых русских строк.

- [x] **Шаг 7: записать частичный результат и закоммитить блок**

  В `docs/handoff.md` указать, что синхронные семейства готовы и проверены, а
  асинхронные семейства ещё не начаты. Добавить поимённо 12 Dart-файлов и
  `docs/handoff.md`, проверить staged diff и создать коммит:

  ```sh
  rtk git commit -m "docs: explain synchronous scope examples"
  ```

---

### Задача 2: `AsyncScope` и `AsyncDataScope`

**Файлы:**

- Изменить: все пять Dart-файлов в
  `example/scopo_demo/lib/home/demos/d_async_scope/`
- Изменить: все пять Dart-файлов в
  `example/scopo_demo/lib/home/demos/e_async_data_scope/`
- Изменить: `docs/handoff.md`

**Интерфейсы:**

- Использует: существующие три сценария пересоздания и общий `CounterScope`
  каждого семейства.
- Создаёт: объяснение различия “без ключа / с ключом / родитель и ребёнок” и
  различия между element-owned моделью и готовым async-значением.

- [x] **Шаг 1: объяснить общую матрицу пересоздания**

  Над `AsyncScopeDemo` и `AsyncDataScopeDemo` использовать один и тот же
  каркас, меняя имя семейства:

  ```dart
  /// Rebuilds three asynchronous scope variants together so the console makes
  /// their initialization and disposal ordering visible.
  ///
  /// The variants compare no `scopeKey`, a shared `scopeKey`, and a keyed
  /// parent with a child scope.
  ```

  В каждом семействе над классами 1–3 добавить соответственно:

  ```dart
  /// Recreates the scope without a `scopeKey`, allowing the new instance to
  /// initialize while the previous one is still disposing.
  ```

  ```dart
  /// Reuses a `scopeKey` so initialization waits for the previous instance to
  /// finish disposing.
  ```

  ```dart
  /// Demonstrates a keyed parent waiting for its child scope during disposal.
  /// The console shows child-first teardown before the next parent starts.
  ```

- [x] **Шаг 2: объяснить element-owned жизненный цикл `AsyncScopeCore`**

  В `d_async_scope/counter_scope.dart` добавить:

  ```dart
  /// A notifier initialized and disposed explicitly by `CounterScopeElement`.
  /// Its nullable count makes accidental reads before readiness fail loudly.
  final class CounterModel with ChangeNotifier {
  ```

  ```dart
  /// An `AsyncScopeCore` whose custom element owns the asynchronous model.
  /// The widget carries configuration while the element implements lifecycle.
  final class CounterScope
  ```

  ```dart
  /// Maps model initialization and disposal onto the `AsyncScope` state
  /// machine and publishes the ready model to descendants.
  final class CounterScopeElement
  ```

  Над `scopeKey` getter добавить:

  ```dart
  // The coordinator serializes instances only when the widget supplies a key.
  ```

- [x] **Шаг 3: объяснить готовое значение и прогресс `AsyncDataScopeBase`**

  В `e_async_data_scope/counter_scope.dart` добавить:

  ```dart
  /// Produces progress events followed by the notifier consumed as scope data.
  /// Cancellation before readiness is visible in the demo console.
  final class CounterModel with ChangeNotifier {
  ```

  Перед `finally`-веткой оставить причину:

  ```dart
  // An interrupted initialization never yielded a ready model to dispose.
  ```

  Над скоупом добавить:

  ```dart
  /// An `AsyncDataScopeBase` that turns the initialization stream into a
  /// ready `CounterModel` and owns its later disposal.
  final class CounterScope
  ```

- [x] **Шаг 4: форматирование, локальная проверка и коммит**

  Выполнить:

  ```sh
  rtk fvm dart format --set-exit-if-changed \
    example/scopo_demo/lib/home/demos/d_async_scope/*.dart \
    example/scopo_demo/lib/home/demos/e_async_data_scope/*.dart
  cd example/scopo_demo
  rtk fvm flutter analyze
  ```

  Ожидание formatter — `0 changed`, analyzer — `No issues found!`. Проверить
  diff двух каталогов на отсутствие изменений исполняемых строк.

  Обновить `docs/handoff.md`: задачи 1–2 готовы, следующая — `LiteScope` и
  полный `Scope`. Закоммитить десять файлов и handoff:

  ```sh
  rtk git commit -m "docs: explain asynchronous scope examples"
  ```

---

### Задача 3: `LiteScope` и полный `Scope`

**Файлы:**

- Изменить: все пять Dart-файлов в
  `example/scopo_demo/lib/home/demos/f_lite_scope/`
- Изменить: все пять Dart-файлов в
  `example/scopo_demo/lib/home/demos/g_scope/`
- Изменить: `docs/handoff.md`

**Интерфейсы:**

- Использует: ту же матрицу `scopeKey`, что и задача 2.
- Создаёт: объяснение state-owned жизненного цикла `LiteScope` и разделения
  параметров, зависимостей и состояния в полном `Scope`.

- [x] **Шаг 1: объяснить матрицу трёх сценариев в обоих семействах**

  Над `LiteScopeDemo` и `ScopeDemo` добавить:

  ```dart
  /// Rebuilds three asynchronous scope variants together so the console makes
  /// their initialization and disposal ordering visible.
  ///
  /// The variants compare no `scopeKey`, a shared `scopeKey`, and a keyed
  /// parent with a child scope.
  ```

  Над классами 1–3 обоих семейств добавить соответственно:

  ```dart
  /// Recreates the scope without a `scopeKey`, allowing the new instance to
  /// initialize while the previous one is still disposing.
  ```

  ```dart
  /// Reuses a `scopeKey` so initialization waits for the previous instance to
  /// finish disposing.
  ```

  ```dart
  /// Demonstrates a keyed parent waiting for its child scope during disposal.
  /// The console shows child-first teardown before the next parent starts.
  ```

  В третьем полном `Scope` добавить к dartdoc отдельную фразу:

  ```dart
  /// The child is mounted only after the parent state reports initialization.
  ```

- [x] **Шаг 2: объяснить жизненный цикл `LiteScopeState`**

  В `f_lite_scope/counter_scope.dart` добавить:

  ```dart
  /// A notifier owned by `CounterState` after its asynchronous initialization.
  final class CounterController with ChangeNotifier {
  ```

  ```dart
  /// A `LiteScope` that exposes immutable widget parameters separately from
  /// its lifecycle-aware `CounterState`.
  final class CounterScope extends LiteScope<CounterScope, CounterState> {
  ```

  ```dart
  /// Owns asynchronous initialization, disposal, and the ready subtree for the
  /// lightweight scope.
  final class CounterState extends LiteScopeState<CounterScope, CounterState> {
  ```

  Перед ранним возвратом из `build` добавить:

  ```dart
  // The state object exists before its asynchronous fields are ready.
  ```

- [x] **Шаг 3: объяснить три части полного `Scope`**

  В `g_scope/counter_scope.dart` добавить:

  ```dart
  /// The notifier created and released by `CounterDependencies`.
  final class CounterController with ChangeNotifier {
  ```

  ```dart
  /// Builds the scope dependency tree and records each disposer with the node
  /// that initialized the resource.
  final class CounterDependencies
  ```

  Над `concurrent` добавить:

  ```dart
  // Independent nodes initialize together while still reporting progress.
  ```

  Над скоупом и состоянием добавить:

  ```dart
  /// Combines widget parameters, asynchronously initialized dependencies, and
  /// a lifecycle-aware state in one full `Scope`.
  final class CounterScope
  ```

  ```dart
  /// Initializes after dependencies are ready and builds the scope's ready
  /// subtree with direct access to those dependencies.
  final class CounterState
  ```

- [x] **Шаг 4: форматирование, локальная проверка и коммит**

  Выполнить:

  ```sh
  rtk fvm dart format --set-exit-if-changed \
    example/scopo_demo/lib/home/demos/f_lite_scope/*.dart \
    example/scopo_demo/lib/home/demos/g_scope/*.dart
  cd example/scopo_demo
  rtk fvm flutter analyze
  ```

  Ожидание formatter — `0 changed`, analyzer — `No issues found!`. Проверить
  diff двух каталогов на отсутствие изменений исполняемых строк.

  Обновить `docs/handoff.md`: семь семейств готовы, остаются навигация и
  отложенное закрытие. Закоммитить десять файлов и handoff:

  ```sh
  rtk git commit -m "docs: explain lifecycle scope examples"
  ```

---

### Задача 4: `NavigationNode`, отложенное закрытие и полный гейт

**Файлы:**

- Изменить: все четыре Dart-файла в
  `example/scopo_demo/lib/home/demos/h_navigation_node/`
- Изменить: все три Dart-файла в
  `example/scopo_demo/lib/home/demos/i_deferred_closing/`
- Изменить: `docs/backlog.md`
- Изменить: `docs/handoff.md`

**Интерфейсы:**

- Использует: существующие локальные навигаторы, `close()` и
  `buildOnClosing`.
- Создаёт: объяснение границы контекста маршрутов и гарантии завершения
  утилизации до pop; закрывает весь пункт бэклога.

- [x] **Шаг 1: объяснить границу `NavigationNode`**

  Добавить следующие dartdoc-блоки:

  ```dart
  /// Places identical route use cases beside each other with and without a
  /// local `NavigationNode` under the counter scope.
  class NavigationNodeDemo extends StatelessWidget {
  ```

  ```dart
  /// Supplies a tagged local counter so routes can reveal which inherited
  /// scope remains visible from their navigator.
  final class CounterScope extends ScopeNotifierBase<CounterScope, CounterModel> {
  ```

  ```dart
  /// Reads and updates the nearest tagged counter from both the original
  /// subtree and routes pushed by the local navigator.
  class CounterView extends StatelessWidget {
  ```

  ```dart
  /// A lifecycle-aware route used to show whether a pushed screen can still
  /// reach the counter scope beneath the selected navigator.
  final class ChildScreen extends LiteScope<ChildScreen, ChildScreenState> {
  ```

  ```dart
  /// Delays disposal so `NavigationNode.onPop` visibly waits for `close()`
  /// before allowing the route to pop.
  final class ChildScreenState
  ```

  Перед `useRootNavigator: false` добавить:

  ```dart
  // Keep the dialog inside the nearest navigation node and scope subtree.
  ```

  Перед `await ChildScreen.of(context).close()` добавить:

  ```dart
  // Finish the scope lifecycle before the local navigator removes the route.
  ```

- [x] **Шаг 2: объяснить отложенное закрытие и screenshot-replacement**

  Добавить:

  ```dart
  /// Opens a scope-backed screen whose route waits for asynchronous disposal.
  /// The console shows the close request and completion around that wait.
  class DeferredClosingDemo extends StatelessWidget {
  ```

  ```dart
  /// The route body that installs `ScreenScope` as the screen itself.
  class ChildScreen extends StatelessWidget {
  ```

  ```dart
  /// Initializes four dependencies sequentially and gives each one a delayed
  /// disposer so closing remains visible.
  final class ScreenDependencies
  ```

  ```dart
  /// A full screen scope whose navigation pop awaits `close()` and whose
  /// closing branch overlays a frozen image of the removed ready subtree.
  final class ScreenScope
  ```

  ```dart
  /// Builds moving ready-state content so the frozen closing image is easy to
  /// distinguish from the removed live widgets.
  final class ScreenState
  ```

  Перед `await ScreenScope.of(context).close()` добавить:

  ```dart
  // Keep the route mounted until dependencies and state finish disposing.
  ```

- [x] **Шаг 3: локально проверить последние семь файлов**

  Выполнить:

  ```sh
  rtk fvm dart format --set-exit-if-changed \
    example/scopo_demo/lib/home/demos/h_navigation_node/*.dart \
    example/scopo_demo/lib/home/demos/i_deferred_closing/*.dart
  cd example/scopo_demo
  rtk fvm flutter analyze
  ```

  Ожидание formatter — `0 changed`, analyzer — `No issues found!`. Проверить
  diff двух каталогов: исполняемые строки не должны меняться.

- [x] **Шаг 4: закрыть бэклог и подготовить handoff перед длинной проверкой**

  Удалить из `docs/backlog.md` ровно строку:

  ```markdown
  - Задокументировать examples в коде.
  ```

  В `docs/handoff.md` записать: комментарии готовы во всех девяти
  демонстрациях, полный гейт запущен, окончательные результаты ещё не
  подтверждены. Не менять пункт о скриншотах и две добавленные владельцем
  записи про warning `xcodebuild` и зависание приложения после закрытия.

- [x] **Шаг 5: прогнать все семь обязательных проверок**

  Из корня выполнить по порядку:

  ```sh
  rtk fvm flutter test
  rtk fvm flutter analyze
  (cd example/minimal && rtk fvm flutter analyze)
  (cd example/scopo_demo && rtk fvm flutter analyze)
  rtk fvm dart format --set-exit-if-changed lib test
  rtk fvm dart doc --dry-run
  rtk fvm dart pub publish --dry-run
  rtk sh docs/ru/check.sh
  ```

  Ожидания: 146 тестов зелёные; три analyzer-запуска чистые; formatter не
  меняет файлы; dartdoc — 0 warnings и 0 errors;
  publish dry-run — 0 warnings; актуальны 13 переводов.

- [x] **Шаг 6: зафиксировать результаты и закоммитить завершение реализации**

  Заменить в `docs/handoff.md` формулировку «гейт запущен» точными результатами
  шага 5. Проверить `git diff --check`, поиск кириллицы в `home/demos/` и весь
  diff от коммита плана: Dart-часть содержит только комментарии.

  Добавить поимённо семь Dart-файлов, `docs/backlog.md` и `docs/handoff.md`,
  проверить staged diff и создать коммит:

  ```sh
  rtk git commit -m "docs: explain navigation and closing examples"
  ```

---

### Задача 5: закрыть исторические записи

**Файлы:**

- Изменить:
  `docs/records/2026-08-14[5]-example-code-documentation-design.md`
- Изменить:
  `docs/records/2026-08-14[6]-example-code-documentation-plan.md`
- Изменить: `docs/handoff.md`

**Интерфейсы:**

- Использует: фактические хеши четырёх реализационных коммитов и вывод полного
  гейта.
- Создаёт: окончательный исторический статус и чистую точку восстановления.

- [x] **Шаг 1: обновить шапки и отметить выполненные шаги**

  В шапке дизайна заменить состояние на «реализовано прямо в `main`» и
  перечислить фактические хеши четырёх коммитов из задач 1–4. Добавить план в
  связанные записи.

  В этом плане отметить все пройденные шаги `- [x]`, заменить состояние шапки
  на «выполнено» и добавить те же фактические хеши. Не переписывать
  исторический текст плана.

- [x] **Шаг 2: сделать `handoff` снимком завершённой работы**

  Удалить формулировки о незавершённой документации examples. Указать, что
  все девять демонстраций получили содержательные английские комментарии,
  исполняемый код не менялся, полный гейт прошёл, а в бэклоге остались только
  невыполненные записи владельца. В «Что дальше» перечислить warning
  `xcodebuild`, зависание приложения после закрытия, скриншоты и публикацию
  0.10.0, не выдавая первые два наблюдения за уже диагностированные дефекты.

- [x] **Шаг 3: проверить и закоммитить исторический итог**

  Выполнить:

  ```sh
  rtk git diff --check
  rtk git status --short
  ```

  Добавить поимённо дизайн, план и handoff, просмотреть staged diff и создать
  коммит:

  ```sh
  rtk git commit -m "docs: record example code documentation"
  ```

  После коммита `rtk git status --short --branch` должен показывать чистое
  дерево.
