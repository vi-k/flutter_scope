# Перенос инициализации элемента после mount — план реализации

> **Состояние на 2026-08-15:** план выполнен и уточнён после финального review;
> волна завершена в единственном amended commit, независимое финальное review
> чистое. Guarded `init()` выполняется из
> `build()` под error boundary `ComponentElement`; normal `dispose()` — только
> после успешного `init()`, а `super.unmount()` освобождает `GlobalKey` до retry.
> Третья финальная TDD-волна устранила запуск async-фазы после failed sync init:
> она начинается в `AsyncScopeElementBase.performRebuild()` ровно один раз после
> успеха. Постоянная async-регрессия и две мутации дали ожидаемые RED и restored
> GREEN. Тело ниже остаётся историческим; актуальный результат определяют шапка
> и код. Полный гейт: 151/151, три чистых analyze, форматтер 76/0, dartdoc 0/0,
> publish dry-run 0 warnings на clean clone точного publishable будущего дерева
> и 13 актуальных зеркал.
> **Пересмотрено позже:** `2026-08-15[8]` заменил retry терминальным
> неуспехом и сделал утилизацию симметричной; тест «retries a synchronous
> create failure» из задачи 1 переписан.
> **Что это:** пошаговый TDD-план исправления P1 №1 полного ревью.
> **Связанные записи:** `2026-08-15[1]-scope-init-after-mount-design.md`,
> `2026-08-14[10]-project-review.md`.

> **Для агента-исполнителя:** обязателен skill
> `superpowers:test-driven-development`; выполнять пункты по checkbox и не
> переходить к production-коду до подтверждённого RED.

**Цель:** вызывать общий `ScopeWidgetElementBase.init()` после подключения
элемента к дереву, но до первого `buildChild`, чтобы `create(context)` и
пользовательский `init()` могли читать предков без подписки.

**Архитектура:** убрать виртуальный вызов из конструктора и один раз выполнить
его в начале первого `ScopeWidgetElementBase.performRebuild()`. Эта точка идёт
после `Element.mount`, где Flutter назначает parent и inherited-map, и до
`ComponentElement.performRebuild`, где строится ребёнок.

**Стек:** Flutter 3.29.0 / Dart 3.7.0 через fvm, `flutter_test`, существующая
иерархия `ScopeWidgetElementBase` → `ScopeModel` → `ScopeNotifier` →
`AsyncScope`.

## Общие ограничения

- Работать прямо в `main`, коммитить только перечисленные файлы; изменения
  владельца в `docs/backlog.md` не трогать и не добавлять в индекс.
- Сначала постоянный падающий тест, затем минимальный production-код.
- После GREEN откатить только production-исправление, убедиться, что новые
  тесты снова падают по исходной причине, вернуть исправление и снова получить
  GREEN.
- Любая правка `lib/` должна попасть в один коммит со строкой в
  `CHANGELOG.md`.
- Английские `doc/*.md` и их русские зеркала править в одном коммите; после
  перевода запустить `sh docs/ru/stamp.sh`, затем `sh docs/ru/check.sh`.
- Не менять публичные сигнатуры и не добавлять зависимостей.
- Завершение — только после полного гейта из `AGENTS.md` на Flutter 3.29.0.

---

### Задача 1: Закрепить безопасный mounted-контекст двумя регрессиями

**Файлы:**

- Изменить: `test/scope_model_test.dart`
- Изменить: `test/scope_widget_test.dart`

**Интерфейсы:**

- Использует: существующие `ScopeModel.of(..., listen: false)`,
  `ScopeWidgetCore.of(..., listen: false)` и `ScopeWidgetElementBase.init()`.
- Производит: два widget-теста, которые падают на вызове `init()` из
  конструктора и проходят только когда элемент уже подключён к предкам до
  первой сборки.

- [x] **Шаг 1. Добавить тест документированного `ScopeModel.create(context)`**

В группу `ScopeModel` файла `test/scope_model_test.dart` добавить:

```dart
testWidgets('create can read an ancestor scope before the first build', (
  tester,
) async {
  const session = _Session('alice');

  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: ScopeModel<_Session>.value(
        value: session,
        builder: (context) => ScopeModel<_Repository>(
          create: (context) => _Repository(
            ScopeModel.of<_Session>(context, listen: false),
          ),
          dispose: (repository) {},
          builder: (context) {
            final repository =
                ScopeModel.of<_Repository>(context, listen: false);

            return Text('session: ${repository.session.name}');
          },
        ),
      ),
    ),
  );

  expect(find.text('session: alice'), findsOneWidget);
});
```

Внизу того же файла добавить реальные данные без mock:

```dart
final class _Session {
  final String name;

  const _Session(this.name);
}

final class _Repository {
  final _Session session;

  const _Repository(this.session);
}
```

Этот тест ловит возврат `widget.create!(this)` в фазу до mount: родительский
`ScopeModel<_Session>` тогда недоступен и текст первой сборки не появляется.

- [x] **Шаг 2. Добавить тест базового lifecycle hook**

В `test/scope_widget_test.dart` добавить отдельную группу перед
`notifyDependents`:

```dart
group('lifecycle', () {
  testWidgets('init sees ancestors and finishes before the first build', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: _AncestorScope(
          value: 'ready',
          child: _InitReaderScope(),
        ),
      ),
    );

    expect(find.text('init: ready; completed: true'), findsOneWidget);
  });
});
```

После существующих тестовых классов добавить минимальные пользовательские
скоупы:

```dart
final class _AncestorScope
    extends ScopeWidgetCore<_AncestorScope, _AncestorScopeElement> {
  final String value;
  final Widget child;

  const _AncestorScope({required this.value, required this.child});

  static String valueOf(BuildContext context) =>
      ScopeWidgetCore.of<_AncestorScope, _AncestorScopeElement>(
        context,
        listen: false,
      ).widget.value;

  @override
  _AncestorScopeElement createScopeElement() => _AncestorScopeElement(this);
}

final class _AncestorScopeElement
    extends ScopeWidgetElementBase<_AncestorScope, _AncestorScopeElement> {
  _AncestorScopeElement(super.widget);

  @override
  Widget buildChild() => widget.child;
}

final class _InitReaderScope
    extends ScopeWidgetCore<_InitReaderScope, _InitReaderScopeElement> {
  const _InitReaderScope();

  @override
  _InitReaderScopeElement createScopeElement() =>
      _InitReaderScopeElement(this);
}

final class _InitReaderScopeElement
    extends ScopeWidgetElementBase<_InitReaderScope, _InitReaderScopeElement> {
  _InitReaderScopeElement(super.widget);

  String? _ancestorValue;
  bool _initCompleted = false;

  @override
  void init() {
    _ancestorValue = _AncestorScope.valueOf(this);
    _initCompleted = true;
    super.init();
  }

  @override
  Widget buildChild() =>
      Text('init: $_ancestorValue; completed: $_initCompleted');
}
```

Этот тест защищает именно общий hook, поэтому узкий lazy-fix только в
`ScopeModel` его не удовлетворит.

- [x] **Шаг 3. Запустить оба файла и подтвердить RED по исходной причине**

Команда:

```sh
rtk fvm flutter test test/scope_model_test.dart test/scope_widget_test.dart
```

Ожидается ненулевой exit: обе новые проверки не находят родительский скоуп из
контекста элемента, созданного до mount. Существующие тесты в этих файлах не
должны вводить дополнительных причин падения. Если тест не компилируется,
исправить тестовый код и повторять до поведенческого RED; production-код не
трогать.

### Задача 2: Перенести `init()` в первый `performRebuild`

**Файлы:**

- Изменить: `lib/src/scope/b_scope_widget/scope_widget_core.dart`
- Проверить: `test/scope_model_test.dart`
- Проверить: `test/scope_widget_test.dart`

**Интерфейсы:**

- Использует: виртуальный `init()` и существующий override
  `performRebuild()`.
- Производит: неизменённую публичную сигнатуру `void init()`, вызываемую один
  раз после mount и до первого `buildChild()`.

- [x] **Шаг 1. Сделать минимальную production-правку**

Заменить конструктор с виртуальным вызовом:

```dart
/// Creates the element.
ScopeWidgetElementBase(W super.widget);
```

Рядом с флагами rebuild добавить:

```dart
/// Whether [init] has completed successfully.
bool _didInit = false;
```

В самое начало существующего `performRebuild()` добавить:

```dart
if (!_didInit) {
  init();
  _didInit = true;
}
```

Не переносить логику в `mount()`: `super.mount()` у `ComponentElement` уже
выполняет первую сборку. Не добавлять lazy-инициализацию в `model` и не менять
сигнатуры hook.

- [x] **Шаг 2. Подтвердить GREEN на двух затронутых семействах**

```sh
rtk fvm flutter test test/scope_model_test.dart test/scope_widget_test.dart
```

Ожидается exit 0. Новые тесты подтверждают mounted-контекст, существующий тест
`creates the model once and provides it to the subtree` подтверждает, что
`create` не повторяется при обновлении виджета.

- [x] **Шаг 3. Проверить старшие семейства**

```sh
rtk fvm flutter test test/scope_notifier_test.dart test/async_scope_test.dart test/async_data_scope_test.dart
```

Ожидается exit 0: notifier успевает подписаться до первого ребёнка, а
`AsyncScopeElementBase.mount()` запускает `_performAsyncInit()` после возврата
`super.mount()`, когда синхронный `init()` уже завершён.

- [x] **Шаг 4. Выполнить mutation-check**

Временно вернуть `init();` в тело конструктора и удалить его guarded-вызов из
`performRebuild`, не трогая тесты. Повторить:

```sh
rtk fvm flutter test test/scope_model_test.dart test/scope_widget_test.dart
```

Ожидается исходный RED обеих новых проверок. Затем вернуть `_didInit` и вызов в
`performRebuild`, снова запустить ту же команду и получить exit 0. Временную
мутацию не оставлять в diff.

### Задача 3: Обновить публичный контракт и русские зеркала

**Файлы:**

- Изменить: `lib/src/scope/a_base/base.dart`
- Изменить: `lib/src/scope/b_scope_widget/scope_widget_core.dart`
- Изменить: `CHANGELOG.md`
- Изменить: `doc/a_base.md`
- Изменить: `doc/b_scope_widget.md`
- Изменить: `doc/c_scope_model.md`
- Изменить: `docs/ru/doc/a_base.md`
- Изменить: `docs/ru/doc/b_scope_widget.md`
- Изменить: `docs/ru/doc/c_scope_model.md`

**Интерфейсы:**

- Использует: новый момент вызова `init()` из задачи 2.
- Производит: единый английский и русский контракт — после mount, до первой
  сборки, поиск предков только без подписки.

- [x] **Шаг 1. Обновить dartdoc базового hook и конструктора элемента**

Для `ScopeInheritedElement.init()` использовать смысл:

```dart
/// Called once after the element is mounted and before its first [buildChild].
///
/// The element is already connected to its ancestors, so implementations may
/// look a scope up from this context with `listen: false`.
@mustCallSuper
void init();
```

Для конструктора `ScopeWidgetElementBase` оставить формулировку `Creates the
element`; возле `_didInit` и guarded-вызова сохранить комментарии из задачи 2.

- [x] **Шаг 2. Добавить строку текущей версии в CHANGELOG**

В `## 0.10.0` добавить английский пункт:

```markdown
* Fix `ScopeModel.create(context)` running before the element was mounted: the
  context can now read ancestor scopes with `listen: false`, while the model
  and notifier subscriptions are still ready before the first subtree build.
  The same mounted-before-build timing now applies to custom
  `ScopeWidgetElementBase.init()` overrides.
```

- [x] **Шаг 3. Синхронно поправить три тематические страницы**

В `doc/a_base.md` заменить «when the element is created» на точный порядок
«once after mount and before the first `buildChild`» и добавить, что предков
можно читать с `listen: false`, а подписка из hook не поддерживается.

В `doc/b_scope_widget.md` после примера lifecycle явно записать: `init()`
выполняется после подключения элемента к предкам, но до первого `buildChild`;
ресурсы и notifier-listener готовы к первой сборке.

В `doc/c_scope_model.md` в разделах `ScopeModel` и `Lifetime` заменить
«element is created» на «element is mounted, before its first subtree build».
Сохранить пример чтения `Session` и ограничение `listen: false`.

В `docs/ru/doc/a_base.md`, `b_scope_widget.md`, `c_scope_model.md` внести те же
смысловые изменения по-русски, не ограничиваясь заменой stamp-хеша.

- [x] **Шаг 4. Обновить stamp-хеши и проверить зеркала**

```sh
rtk sh docs/ru/stamp.sh
rtk sh docs/ru/check.sh
```

Ожидается `переводы актуальны: 13`.

### Задача 4: Зафиксировать состояние, проверить и закоммитить волну

**Файлы:**

- Изменить: `docs/handoff.md`
- Изменить шапку: `docs/records/2026-08-14[10]-project-review.md`
- Изменить шапку и checkbox: `docs/records/2026-08-15[2]-scope-init-after-mount-plan.md`
- Изменить шапку: `docs/records/2026-08-15[1]-scope-init-after-mount-design.md`

**Интерфейсы:**

- Использует: подтверждённые RED → GREEN → mutation RED → restored GREEN из
  задач 1–2 и синхронизированные документы из задачи 3.
- Производит: один проверенный коммит P1 №1 и handoff, указывающий на P1 №2 как
  следующую волну.

- [x] **Шаг 1. Обновить исторические шапки и handoff**

В design-документе отметить: «реализовано и проверено в коммите этой волны» —
без заранее неизвестного хеша. В этом плане отметить выполненные checkbox и
состояние проверки. В шапке полного ревью заменить «находки не исправлены» на
точный счётчик: P1 №1 исправлен, остаются 17 находок (2 P1, 12 P2, 3 P3).

В `docs/handoff.md` убрать P1 №1 из открытых проблем, записать результаты
mutation-check и полного гейта и назвать P1 №2 (`NavigationNode` и системный
back) следующей волной. Публикация остаётся заблокированной до закрытия всех
18 исходных находок и финального ревью.

- [x] **Шаг 2. Запустить полный обязательный гейт**

Последовательно выполнить:

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

Ожидается: 148 тестов зелёные, три analyze без замечаний, 0 изменённых файлов
форматтером, dartdoc 0 warnings/0 errors, publish dry-run 0 warnings, 13
актуальных переводов. Если число тестов отличается только из-за фактического
разбиения/объединения новых сценариев, записать реальное число в handoff и
план; любой failed тест блокирует коммит.

- [x] **Шаг 3. Проверить точный diff и индекс**

```sh
rtk git diff --check
rtk git status --short
rtk git diff --stat
```

Убедиться, что production-изменение ограничено переносом `init`, тесты ловят
оба контракта, английские и русские документы согласованы, а
`docs/backlog.md` остаётся unstaged пользовательской правкой. Добавить в индекс
только перечисленные файлы поимённо и выполнить `git diff --cached --check`.

- [x] **Шаг 4. Создать один коммит исправления**

```sh
rtk git commit -m "fix: initialize scope elements after mount"
```

После коммита проверить `git show --stat --oneline HEAD` и `git status
--short`; единственной оставшейся локальной правкой должен быть пользовательский
`docs/backlog.md`.
