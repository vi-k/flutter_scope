# Системный back во вложенном NavigationNode — план реализации

> **Состояние на 2026-08-15:** выполнен и полностью проверен в единственном
> amended commit. Первый independent review нашёл обход inner `PopScope` прямым
> `pop`; отдельный TDD-цикл заменил его на `maybePop`, а повторный review чистый.
> **Что это:** пошаговый TDD-план исправления P1 №2 полного review.
> **Связанные записи:** `2026-08-15[4]-navigation-system-back-design.md`,
> `2026-08-14[10]-project-review.md`,
> `2026-08-15[6]-navigation-system-back-report.md`.

> **Для агента-исполнителя:** обязателен skill
> `superpowers:test-driven-development`; выполнять пункты по checkbox и не
> переходить к production-коду до подтверждённого RED.

**Цель:** системный back сначала закрывает pushed route или dialog вложенного
`NavigationNode`, не затрагивая внешний route.

**Архитектура:** оставить текущие `PopScope`, local-history hook, `onPop` и
`isRoot` для случая пустого внутреннего стека. Обернуть `_NodeNavigator` в
штатный `NavigatorPopHandler<Object?>`, который через
`onPopWithResult` вызывает `_navigator.pop(result)` только когда Flutter
сообщает, что дочерний navigator способен обработать pop.

**Стек:** Flutter 3.29.0 / Dart 3.7.0 через fvm, `flutter_test`, Material
`NavigatorPopHandler`, без новых зависимостей и без public API.

## Общие ограничения

- Работать прямо в `main`; в ветку и worktree не уходить — это правило проекта.
- Сначала постоянные RED-тесты, затем единственная минимальная production-правка.
- После GREEN временно убрать только `NavigatorPopHandler`, подтвердить RED всех
  трёх новых сценариев, вернуть обёртку и снова получить GREEN.
- P2 №14 (повторный и поздний async `onPop`) и P2 №17 (смена `navigatorKey`)
  не менять.
- Правка `lib/` требует строку в `CHANGELOG.md`, правку английской страницы,
  русского зеркала и `sh docs/ru/stamp.sh` после осмысленного перевода.
- `docs/backlog.md` — запись владельца; не менять и не добавлять в индекс.
- Завершать только после полного гейта `AGENTS.md` на Flutter 3.29.0 и
  документирования фактических результатов в report-record.

---

### Задача 1: Зафиксировать системный back тремя падающими widget-тестами

**Файлы:**

- Изменить: `test/navigation_node_test.dart:8-160`

**Интерфейсы:**

- Использует: публичные `NavigationNode`, `NodeNavigatorState`,
  `tester.binding.handlePopRoute()` и `showDialog<void>(useRootNavigator: false)`.
- Производит: три постоянные регрессии, которые на текущем коде оставляют
  вложенный route или dialog открытым после системного back.

- [ ] **Шаг 1. Расширить только тестовую fixture**

Добавить в `_Host` необязательный `bool isRoot = false` и пробросить его в
`NavigationNode(isRoot: isRoot, ...)`. В `_NodeContent` заменить единственную
кнопку на `Column` с прежней кнопкой `open` и второй кнопкой `open dialog`:

```dart
TextButton(
  onPressed: () => unawaited(
    showDialog<void>(
      context: context,
      useRootNavigator: false,
      builder: (context) => const AlertDialog(
        content: Text('dialog'),
      ),
    ),
  ),
  child: const Text('open dialog'),
),
```

`useRootNavigator: false` обязателен: тест проверяет dialog именно внутреннего
navigator, а не root navigator приложения.

- [ ] **Шаг 2. Добавить RED для pushed route**

В группу `NavigationNode` добавить:

```dart
testWidgets('system back pops a pushed route inside the node', (tester) async {
  await tester.pumpWidget(const _Host(useNode: true));

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  expect(find.text('pushed: secret'), findsOneWidget);

  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();

  expect(find.text('pushed: secret'), findsNothing);
  expect(find.text('open'), findsOneWidget);
});
```

Этот сценарий задаёт наблюдаемый контракт P1: внутренняя страница закрыта,
исходное содержимое узла осталось в том же внешнем route.

- [ ] **Шаг 3. Добавить RED для dialog**

Рядом добавить:

```dart
testWidgets('system back closes a dialog inside the node', (tester) async {
  await tester.pumpWidget(const _Host(useNode: true));

  await tester.tap(find.text('open dialog'));
  await tester.pumpAndSettle();
  expect(find.text('dialog'), findsOneWidget);

  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();

  expect(find.text('dialog'), findsNothing);
  expect(find.text('open dialog'), findsOneWidget);
});
```

Он не сводит исправление к `MaterialPageRoute`: dialog тоже является route
вложенного navigator и обязан закрываться тем же системным событием.

- [ ] **Шаг 4. Добавить RED для root node с вложенным route**

Добавить:

```dart
testWidgets('system back stays in a root node while it has an inner route', (
  tester,
) async {
  await tester.pumpWidget(const _Host(useNode: true, isRoot: true));

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  expect(find.text('pushed: secret'), findsOneWidget);

  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();

  expect(find.text('pushed: secret'), findsNothing);
  expect(find.text('open'), findsOneWidget);
});
```

`isRoot` не должен обойти inner-first обработку: пока внутренний стек содержит
route, событие не передаётся за пределы root node.

- [ ] **Шаг 5. Запустить файл и подтвердить поведенческий RED**

```sh
rtk fvm flutter test test/navigation_node_test.dart
```

Ожидается ненулевой exit только у трёх добавленных тестов: после
`handlePopRoute()` по-прежнему находится `pushed: secret` или `dialog`.
Если тест падает из-за ошибки fixture, исправлять только тестовый код и
повторять команду до RED исходного поведения; production-код пока не менять.

### Задача 2: Направить системный back вложенному navigator

**Файлы:**

- Изменить: `lib/src/utils/navigation_node/navigation_node.dart:53-89`
- Проверить: `test/navigation_node_test.dart`

**Интерфейсы:**

- Использует: существующий `_navigator` типа `NodeNavigatorState` и Flutter
  `NavigatorPopHandler<Object?>.onPopWithResult`.
- Производит: прежний `NavigationNode` API, в котором системный back снимает
  верхний route внутреннего navigator до участия внешнего `PopScope`.

- [ ] **Шаг 1. Обернуть только `_NodeNavigator`**

Внутри существующего `PopScope` заменить его `child` на следующую обёртку;
остальные поля `PopScope`, `_NodeNavigator`, `_NodeNavigatorObserver` и
`PreviousNavigatorExtension` не менять:

```dart
child: NavigatorPopHandler<Object?>(
  onPopWithResult: (result) => _navigator.pop(result),
  child: _NodeNavigator(
    key: _navigatorKey,
    node: this,
    pages: [MaterialPage<void>(child: widget.child)],
    onDidRemovePage: (_) {},
  ),
),
```

Это один уровень dispatch перед текущим navigator: `NavigatorPopHandler`
получает `NavigationNotification` от `_NodeNavigator` и не даёт внешнему route
сняться, пока внутренний стек способен обработать pop.

- [ ] **Шаг 2. Подтвердить GREEN целевого файла**

```sh
rtk fvm flutter test test/navigation_node_test.dart
```

Ожидается exit 0: пять прежних и три новых теста проходят. В частности,
`handlePopRoute()` снимает `MaterialPageRoute` и `DialogRoute` внутреннего
navigator, а `isRoot: true` не меняет этот приоритет.

- [ ] **Шаг 3. Выполнить mutation-check нагрузки тестов**

Временно удалить только `NavigatorPopHandler<Object?>`, оставив `_NodeNavigator`
непосредственным `child` внешнего `PopScope`. Повторить:

```sh
rtk fvm flutter test test/navigation_node_test.dart
```

Ожидается исходный RED всех трёх новых сценариев: `pushed: secret` или `dialog`
остаются после системного back. Вернуть обёртку ровно из шага 1 и повторить
команду с ожидаемым exit 0. Временную мутацию не оставлять в diff.

### Задача 3: Описать публичное исправление и пройти проверки

**Файлы:**

- Изменить: `CHANGELOG.md`
- Изменить: `doc/j_utils.md:73-91`
- Изменить: `docs/ru/doc/j_utils.md`
- Изменить: `docs/handoff.md`
- Изменить: `docs/records/2026-08-15[4]-navigation-system-back-design.md`
- Создать: `docs/records/2026-08-15[6]-navigation-system-back-report.md`

**Интерфейсы:**

- Использует: поведение, доказанное задачами 1–2.
- Производит: английское и русское описание inner-first system back, changelog
текущей версии и проверяемый снимок фактического состояния волны.

- [ ] **Шаг 1. Обновить английские публичные документы**

В `CHANGELOG.md` добавить в `0.10.0` пункт:

```markdown
* Fix `NavigationNode` system back handling: a pushed route or dialog in its
  nested navigator now closes before the enclosing route can pop.
```

В `doc/j_utils.md` после описания `isRoot` и `onPop` добавить:

```markdown
System back first asks the node's nested navigator to close its top route. Only
when that navigator has nothing left to pop do `onPop` and `isRoot` decide what
happens outside the node.
```

- [ ] **Шаг 2. Перевести тот же контракт и обновить stamp**

В `docs/ru/doc/j_utils.md` добавить смысловой перевод после абзаца про
`isRoot` и `onPop`:

```markdown
Системный back сначала просит вложенный navigator узла закрыть верхний маршрут.
Лишь когда во вложенном navigator больше нечего закрывать, `onPop` и `isRoot`
решают, что произойдёт за пределами узла.
```

После перевода выполнить:

```sh
rtk sh docs/ru/stamp.sh
rtk sh docs/ru/check.sh
```

Ожидается актуальное зеркало `doc/j_utils.md` и успешная проверка всех
переводов; stamp запускается только после текста перевода из этого шага.

- [ ] **Шаг 3. Пройти полный гейт на закреплённом тулчейне**

Выполнить последовательно:

```sh
rtk fvm flutter test
rtk fvm flutter analyze
cd example/minimal && rtk fvm flutter analyze
cd example/scopo_demo && rtk fvm flutter analyze
rtk fvm dart format --set-exit-if-changed lib test
rtk fvm dart doc --dry-run
rtk sh docs/ru/check.sh
```

Все команды должны завершиться с exit 0. `example/*` запускать в отдельных
подоболочках из корня, чтобы текущий каталог основного процесса не изменился.

- [ ] **Шаг 4. Создать report-record и подготовить чистую публикационную проверку**

В report-record описать подтверждённую причину, RED, GREEN, mutation-check,
точные результаты полного гейта и исключённые P2 №14/№17. В шапке design-record
заменить состояние на «реализовано и проверено» только после успешных шагов
гейта. В `handoff.md` указать commit, количество тестов, результаты семи
проверок и следующую волну P1 №3.

Явно добавить только свои файлы и создать коммит:

```sh
rtk git add CHANGELOG.md doc/j_utils.md docs/ru/doc/j_utils.md \
  lib/src/utils/navigation_node/navigation_node.dart \
  test/navigation_node_test.dart docs/handoff.md \
  docs/records/2026-08-15[4]-navigation-system-back-design.md \
  docs/records/2026-08-15[6]-navigation-system-back-report.md
rtk git commit -m "fix: handle system back in nested navigation"
```

Не добавлять `docs/backlog.md` и не использовать `git add -A`.

- [ ] **Шаг 5. Подтвердить publish dry-run на чистом HEAD**

После коммита, когда `rtk git status --short` не печатает строк, выполнить:

```sh
rtk fvm dart pub publish --dry-run
```

Ожидаются 0 warnings. Если после занесения результата в handoff или report
нужен `git commit --amend --no-edit`, изменяются только исключённые из архива
`docs/`-файлы; затем status снова должен быть чистым. Live publish не выполнять.
