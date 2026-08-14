# План example для `ScopeWidgetCore`

> **Состояние на 2026-08-14:** план готов, выполнение не начато.
> **Что это:** TDD-план нового блока demo, widget-теста, README-зеркала и
> завершения состояния проекта.
> **Связанные записи:** `2026-08-14[3]-scope-widget-core-example-design.md`.
>
> **Для агентов-исполнителей:** ОБЯЗАТЕЛЬНЫЙ ДОПОЛНИТЕЛЬНЫЙ SKILL — использовать
> `superpowers:subagent-driven-development` или `superpowers:executing-plans`
> для выполнения плана по задачам. Ход отмечать чекбоксами (`- [ ]`).

**Цель:** добавить во вкладку `ScopeWidget` исполнимый пример изменяемого
состояния в собственном элементе `ScopeWidgetCore` с точечным перестроением
зависимого.

**Устройство:** существующий `ScopeWidgetBase`-блок остаётся сверху, новый
`ScopeWidgetCoreExample` добавляется снизу. Счётчик принадлежит
`CounterScopeElement`; команда вызывается через узкий контекст, а чтение идёт
через селектор. README demo описывает оба уровня семейства.

**Технологии:** Flutter 3.29.0, Dart 3.7.0, `flutter_test`, Markdown,
`docs/ru/stamp.sh`, `docs/ru/check.sh`.

## Общие ограничения

- Работа идёт прямо в `main` по регламенту проекта; PR не создаётся.
- Сначала падающий widget-тест, затем минимальная реализация и зелёный прогон.
- Новый код example не меняет `lib/`, публичный API scopo и `CHANGELOG.md`.
- Публичный README пишется по-английски; русское зеркало меняется в том же
  коммите и получает штамп через `sh docs/ru/stamp.sh`.
- Из бэклога удаляется только выполненный `example` для `ScopeWidgetCore`;
  будущая задача документации examples в коде остаётся.
- Шесть известных старых файлов demo не переформатируются.
- В коммиты входят только файлы, перечисленные в соответствующем шаге.

---

### Задача 1: Добавить проверенный `ScopeWidgetCoreExample`

**Файлы:**

- Создать:
  `example/scopo_demo/test/scope_widget_core_example_test.dart` — публичный
  сценарий «0 → нажатие → 1».
- Создать:
  `example/scopo_demo/lib/home/demos/a_scope_widget/scope_widget_core_example.dart`
  — виджет, скоуп, элемент, узкий контекст и два потомка.
- Изменить:
  `example/scopo_demo/lib/home/demos/a_scope_widget/scope_widget_demo.dart` —
  разместить оба примера вертикально.
- Изменить: `example/scopo_demo/README.md` — описание вкладки `ScopeWidget`.
- Изменить: `docs/ru/example/scopo_demo/README.md` — точный русский перевод.
- Изменить: `docs/backlog.md` — удалить выполненный пункт.

**Интерфейсы:**

- Использует:
  `ScopeWidgetCore<W, E>`, `ScopeWidgetElementBase<W, E>`,
  `ScopeWidgetCore.of`, `ScopeWidgetCore.select`, `notifyDependents()` и
  существующий `BlinkingBox`.
- Даёт: `ScopeWidgetCoreExample`, `CounterScope`, `CounterScopeContext`,
  `CounterScopeElement`, `CounterScope.of(BuildContext)` и
  `CounterScope.countOf(BuildContext)`.

- [ ] **Шаг 1: написать падающий widget-тест**

  Создать `example/scopo_demo/test/scope_widget_core_example_test.dart`:

  ```dart
  import 'package:flutter/material.dart';
  import 'package:flutter_test/flutter_test.dart';
  import 'package:scopo_demo/home/demos/a_scope_widget/scope_widget_core_example.dart';

  void main() {
    testWidgets('ScopeWidgetCore example increments its element-owned count', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: ScopeWidgetCoreExample()),
      );

      expect(find.text('0'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.add_circle));
      await tester.pump();

      expect(find.text('1'), findsOneWidget);
    });
  }
  ```

- [ ] **Шаг 2: подтвердить красный прогон**

  Выполнить из `example/scopo_demo`:

  ```sh
  fvm flutter test test/scope_widget_core_example_test.dart
  ```

  Ожидание: FAIL компиляции, потому что
  `scope_widget_core_example.dart` и `ScopeWidgetCoreExample` ещё не
  существуют.

- [ ] **Шаг 3: реализовать минимальный example**

  Создать
  `example/scopo_demo/lib/home/demos/a_scope_widget/scope_widget_core_example.dart`:

  ```dart
  import 'package:flutter/material.dart';
  import 'package:scopo/scopo.dart';
  import 'package:scopo_demo/common/presentation/blinking_box.dart';

  class ScopeWidgetCoreExample extends StatelessWidget {
    const ScopeWidgetCoreExample({super.key});

    @override
    Widget build(BuildContext context) => const CounterScope();
  }

  final class CounterScope
      extends ScopeWidgetCore<CounterScope, CounterScopeElement> {
    const CounterScope({super.key});

    static CounterScopeContext of(BuildContext context) =>
        ScopeWidgetCore.of<CounterScope, CounterScopeElement>(
          context,
          listen: false,
        );

    static int countOf(BuildContext context) =>
        ScopeWidgetCore.select<CounterScope, CounterScopeElement, int>(
          context,
          (element) => element.count,
        );

    Widget build(BuildContext context) => Center(
          child: BlinkingBox(
            blinkingColor:
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$ScopeWidgetCoreExample'),
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [_CounterView(), _IncrementAction()],
                ),
              ],
            ),
          ),
        );

    @override
    CounterScopeElement createScopeElement() => CounterScopeElement(this);
  }

  abstract interface class CounterScopeContext {
    int get count;
    void increment();
  }

  final class CounterScopeElement
      extends ScopeWidgetElementBase<CounterScope, CounterScopeElement>
      implements CounterScopeContext {
    CounterScopeElement(super.widget);

    int _count = 0;

    @override
    int get count => _count;

    @override
    Widget buildChild() => widget.build(this);

    @override
    void increment() {
      _count++;
      notifyDependents();
    }
  }

  class _CounterView extends StatelessWidget {
    const _CounterView();

    @override
    Widget build(BuildContext context) {
      final count = CounterScope.countOf(context);
      return Center(
        child: BlinkingBox(
          blinkingColor:
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
          child: Text('$count'),
        ),
      );
    }
  }

  class _IncrementAction extends StatelessWidget {
    const _IncrementAction();

    @override
    Widget build(BuildContext context) => IconButton(
          color: Theme.of(context).colorScheme.primary,
          onPressed: CounterScope.of(context).increment,
          icon: const Icon(Icons.add_circle),
        );
  }
  ```

- [ ] **Шаг 4: подтвердить зелёный прогон example**

  Выполнить из `example/scopo_demo`:

  ```sh
  fvm flutter test test/scope_widget_core_example_test.dart
  ```

  Ожидание: 1 тест зелёный.

- [ ] **Шаг 5: встроить второй блок во вкладку**

  Добавить импорт `scope_widget_core_example.dart` и заменить тело
  `ScopeWidgetDemo.build` на:

  ```dart
  return const Column(
    children: [
      Expanded(child: ScopeWidgetExample()),
      Divider(),
      Expanded(child: ScopeWidgetCoreExample()),
    ],
  );
  ```

- [ ] **Шаг 6: обновить README и зеркало**

  В `example/scopo_demo/README.md` заменить строку таблицы на:

  ```markdown
  | ScopeWidget | widget parameters through `ScopeWidgetBase`, plus element-owned mutable state and selective rebuilds through `ScopeWidgetCore` |
  ```

  В `docs/ru/example/scopo_demo/README.md` дать точный перевод:

  ```markdown
  | ScopeWidget | параметры виджета через `ScopeWidgetBase` плюс изменяемое состояние элемента и точечные перестроения через `ScopeWidgetCore` |
  ```

  Затем выполнить из корня:

  ```sh
  sh docs/ru/stamp.sh
  sh docs/ru/check.sh
  ```

  Ожидание: все 13 переводов актуальны.

- [ ] **Шаг 7: закрыть только выполненный пункт бэклога**

  Удалить из `docs/backlog.md`:

  ```markdown
  - `example` для `ScopeWidgetCore`.
  ```

  Оставить строку:

  ```markdown
  - Задокументировать examples в коде.
  ```

- [ ] **Шаг 8: отформатировать только новые и изменённые Dart-файлы**

  Выполнить из корня:

  ```sh
  fvm dart format \
    example/scopo_demo/lib/home/demos/a_scope_widget/scope_widget_core_example.dart \
    example/scopo_demo/lib/home/demos/a_scope_widget/scope_widget_demo.dart \
    example/scopo_demo/test/scope_widget_core_example_test.dart
  ```

  Не запускать formatter на всём `example/scopo_demo`: шесть старых файлов
  намеренно остаются вне этой работы.

- [ ] **Шаг 9: прогнать проверки до коммита результата**

  Выполнить тест нового example, затем все проверки из `AGENTS.md` §6, кроме
  publish dry-run:

  ```sh
  (cd example/scopo_demo && fvm flutter test test/scope_widget_core_example_test.dart)
  fvm flutter test
  fvm flutter analyze
  (cd example/minimal && fvm flutter analyze)
  (cd example/scopo_demo && fvm flutter analyze)
  fvm dart format --set-exit-if-changed lib test
  fvm dart doc --dry-run
  sh docs/ru/check.sh
  ```

  Ожидание: новый тест и 146 корневых тестов зелёные; три анализа чистые; 76
  корневых файлов не меняются; dartdoc — 0 предупреждений и 0 ошибок; все 13
  переводов актуальны.

- [ ] **Шаг 10: проверить и закоммитить результат**

  Выполнить `git diff --check`, просмотреть `git diff` и добавить поимённо:

  ```sh
  git add \
    example/scopo_demo/lib/home/demos/a_scope_widget/scope_widget_core_example.dart \
    example/scopo_demo/lib/home/demos/a_scope_widget/scope_widget_demo.dart \
    example/scopo_demo/test/scope_widget_core_example_test.dart \
    example/scopo_demo/README.md \
    docs/ru/example/scopo_demo/README.md \
    docs/backlog.md
  git commit -m "feat: add a ScopeWidgetCore example"
  ```

- [ ] **Шаг 11: проверить публикуемый архив после коммита**

  Выполнить из корня:

  ```sh
  fvm dart pub publish --dry-run
  ```

  Ожидание: 0 предупреждений. Проверка идёт после коммита, потому что README и
  Dart-файлы example входят в публикуемый архив, а валидатор предупреждает о
  незакоммиченных публикуемых файлах.

### Задача 2: Зафиксировать завершённое состояние

**Файлы:**

- Изменить: `docs/records/2026-08-14[3]-scope-widget-core-example-design.md`.
- Изменить: `docs/records/2026-08-14[4]-scope-widget-core-example-plan.md`.
- Изменить: `docs/handoff.md`.

**Интерфейсы:**

- Использует: хеш коммита результата и фактический вывод проверок задачи 1.
- Даёт: актуальные исторические шапки и снимок проекта без незавершённой
  работы.

- [ ] **Шаг 1: обновить шапки design и plan**

  Указать хеш коммита результата, конечное состояние и фактические итоги
  проверок. Отметить выполненные чекбоксы плана.

- [ ] **Шаг 2: обновить `docs/handoff.md`**

  Записать готовый example, новый тест, результаты полного гейта и чистое
  дерево. В «Что дальше» оставить скриншоты, документацию examples в коде и
  публикацию 0.10.0.

- [ ] **Шаг 3: проверить и закоммитить состояние**

  Выполнить `git diff --check`, `sh docs/ru/check.sh`, просмотреть `git diff` и
  добавить поимённо:

  ```sh
  git add docs/handoff.md \
    'docs/records/2026-08-14[3]-scope-widget-core-example-design.md' \
    'docs/records/2026-08-14[4]-scope-widget-core-example-plan.md'
  git commit -m "docs: record the ScopeWidgetCore example"
  ```
