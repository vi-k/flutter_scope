# План: AsyncControllerScope

> **Состояние на 2026-08-16:** выполнен целиком, все семь задач. Отчёт —
> `2026-08-16[11]-async-controller-scope-report.md`, там же расхождения
> плана с тем, что нашлось по ходу.
> **Что это:** пошаговый план реализации семейства `AsyncControllerScope` и
> предшествующего ему снятия буквенных префиксов с имён файлов.
> **Связанные записи:** `2026-08-16[9]-async-controller-scope-design.md` —
> спека, из которой этот план выведен; читать оба.

**Цель.** Семейство скоупов для контроллера с собственным жизненным циклом,
которое берёт на себя разбор контроллера на всех путях — включая те два, где
сегодня контроллер теряется.

**Устройство.** Три слоя поверх машинерии `AsyncDataScope`
(`Core` + элемент, `Base`, конструкторная форма) плюс базовый класс
`ScopeController` с закрытыми обёртками `performInit`/`performUnmount`/
`performDispose` над переопределяемыми `init`/`onUnmount`/`dispose`. Элемент
создаёт контроллер внутри генератора инициализации, кладёт его в поле и
разбирает по критерию `_initSucceeded` — тому же, по которому разбор решает,
звать ли `disposeAsync`.

**Спека:** `docs/records/2026-08-16[9]-async-controller-scope-design.md`.

## Общие ограничения

Действуют в каждой задаче.

- Тулчейн — **Flutter 3.29.0 через fvm**. Все команды с префиксом `fvm`.
- Порядок работы: **сначала падающий тест**, потом исправление, потом проверка
  нагруженности мутацией (`AGENTS.md` §8).
- Публичные артефакты — **по-английски**: dartdoc в `lib/`, `README.md`,
  `CHANGELOG.md`, сообщения коммитов. Документы для владельца — по-русски.
- Правка оригинала в `doc/` не заканчивается без правки зеркала в `docs/ru/` **в
  том же коммите** и без `sh docs/ru/stamp.sh`.
- Правки в `lib/` не заканчиваются без строки в `CHANGELOG.md`.
- Перед каждым коммитом — полный гейт из восьми команд `AGENTS.md` §6.
- Коммитить только свои файлы поимённо, `git add -A` не использовать.
- **Коммитов ровно три**, по одному на группу задач: 1 — переименование, 2–6 —
  семейство, 7 — демо и пример. Внутри группы задачи заканчиваются прогоном
  тестов, а не коммитом: половина семейства — мёртвый код, коммитить его
  отдельно незачем.

---

## Задача 1: снять буквенные префиксы

Механическая работа, поведение не меняется. Делается первой, чтобы ни один файл
не переименовывался дважды.

**Файлы:**

- Переименовать: 8 папок `lib/src/scope/*`, 10 страниц `doc/*.md`, 10 зеркал
  `docs/ru/doc/*.md`, 9 папок `example/scopo_demo/lib/home/demos/*`
- Изменить: `lib/src/scope/scope.dart` (строки `part` и один `import`),
  `dartdoc_options.yaml` (10 путей `markdown:`), 10 шапок зеркал,
  `example/scopo_demo/lib/home/home.dart` (9 импортов)

- [ ] **Шаг 1: зафиксировать зелёный старт**

```sh
fvm flutter test
```

Ожидается: `All tests passed!`. Число тестов записать — после переименования
оно обязано совпасть.

- [ ] **Шаг 2: переименовать папки библиотеки**

```sh
git mv lib/src/scope/a_base            lib/src/scope/base
git mv lib/src/scope/b_scope_widget    lib/src/scope/scope_widget
git mv lib/src/scope/c_scope_model     lib/src/scope/scope_model
git mv lib/src/scope/d_scope_notifier  lib/src/scope/scope_notifier
git mv lib/src/scope/e_async_scope     lib/src/scope/async_scope
git mv lib/src/scope/f_async_data_scope lib/src/scope/async_data_scope
git mv lib/src/scope/g_lite_scope      lib/src/scope/lite_scope
git mv lib/src/scope/h_scope           lib/src/scope/full_scope
```

Последняя строка — единственное место, где имя не буквальное: папка семейства
`Scope` не может называться `scope`, рядом уже лежит `lib/src/scope/scope.dart`
и путь `lib/src/scope/scope/scope_base.dart` читается как ошибка. `full_scope`
отвечает тому, как это семейство описано в README: «`Scope` is the full set».

- [ ] **Шаг 3: починить пути в библиотеке**

В `lib/src/scope/scope.dart` заменить префиксы во всех строках `part` и в
`import 'e_async_scope/scope_coordination.dart';`. Проверка, что ничего не
пропущено:

```sh
grep -n "[a-h]_" lib/src/scope/scope.dart
```

Ожидается: пусто.

- [ ] **Шаг 4: проверить, что библиотека собирается**

```sh
fvm flutter analyze
```

Ожидается: `No issues found!`.

- [ ] **Шаг 5: переименовать страницы документации и зеркала**

```sh
for pair in "a_base:base" "b_scope_widget:scope_widget" \
            "c_scope_model:scope_model" "d_scope_notifier:scope_notifier" \
            "e_async_scope:async_scope" "f_async_data_scope:async_data_scope" \
            "g_lite_scope:lite_scope" "h_scope:scope" "i_debug:debug" \
            "j_utils:utils"; do
  old="${pair%%:*}"; new="${pair##*:}"
  git mv "doc/$old.md" "doc/$new.md"
  git mv "docs/ru/doc/$old.md" "docs/ru/doc/$new.md"
done
```

Здесь `h_scope.md` → `scope.md` без оговорок: в `doc/` коллизии нет.

- [ ] **Шаг 6: починить шапки зеркал и `dartdoc_options.yaml`**

В каждом `docs/ru/doc/*.md` первая строка-цитата вида
`> Перевод \`doc/h_scope.md\` (blob \`…\`)` должна указывать на новое имя
оригинала. Хеш **не меняется**: переименование не меняет содержимое, а
`check.sh` считает `git hash-object` от файла. В `dartdoc_options.yaml` — те же
10 путей в `markdown:`.

- [ ] **Шаг 7: проверить документацию**

```sh
sh docs/ru/check.sh
fvm dart doc --dry-run
```

Ожидается: `переводы актуальны: 14` и `Found 0 warnings and 0 errors.`

- [ ] **Шаг 8: переименовать папки демо**

```sh
cd example/scopo_demo/lib/home/demos
git mv a_scope_widget scope_widget
git mv b_scope_model scope_model
git mv c_scope_notifier scope_notifier
git mv d_async_scope async_scope
git mv e_async_data_scope async_data_scope
git mv f_lite_scope lite_scope
git mv g_scope full_scope
git mv h_navigation_node navigation_node
git mv i_deferred_closing deferred_closing
cd -
```

Затем поправить 9 импортов в `example/scopo_demo/lib/home/home.dart` и любые
межпапочные импорты:

```sh
grep -rn "demos/[a-i]_" example/scopo_demo/lib/
```

Ожидается после правки: пусто.

- [ ] **Шаг 9: полный гейт**

```sh
fvm flutter test
fvm flutter analyze
(cd example/minimal && fvm flutter analyze)
(cd example/scopo_demo && fvm flutter analyze)
(cd example/navigation_node && fvm flutter analyze)
fvm dart format --set-exit-if-changed lib test
fvm dart doc --dry-run
fvm dart pub publish --dry-run
sh docs/ru/check.sh
```

Число тестов обязано совпасть с шагом 1. `pub publish --dry-run` до коммита
покажет предупреждение о незакоммиченных файлах — это нормально, повторить
после коммита и убедиться в `0 warnings`.

- [ ] **Шаг 10: коммит 1**

```sh
git add -u
git add lib/src/scope doc docs/ru/doc example/scopo_demo/lib dartdoc_options.yaml
git commit
```

Сообщение (английский, префикс `refactor:`) — о том, что порядок страниц задан
`categoryOrder`, а не именами файлов, поэтому буквы ничего не держали.

---

## Задача 2: ScopeController

**Файлы:**

- Создать: `lib/src/scope/async_controller_scope/scope_controller.dart`
- Создать: `test/async_controller_scope_test.dart`
- Изменить: `lib/src/scope/scope.dart` (одна строка `part`)

**Интерфейсы:**

- Отдаёт: `abstract base class ScopeController` с `bool get mounted`,
  `Future<void> performInit()`, `void performUnmount()`,
  `Future<void> performDispose()`, `Future<void> init()`, `void onUnmount()`,
  `FutureOr<void> dispose()`.

- [ ] **Шаг 1: написать падающий тест**

Создать `test/async_controller_scope_test.dart`:

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scopo/scopo.dart';

void main() {
  group('ScopeController', () {
    test('runs the hooks in order, each exactly once', () async {
      final controller = _TestController();

      expect(controller.mounted, isFalse);

      await controller.performInit();
      expect(controller.mounted, isTrue);
      expect(controller.calls, ['init']);

      await controller.performDispose();
      expect(controller.mounted, isFalse);
      expect(
        controller.calls,
        ['init', 'onUnmount', 'dispose'],
        reason: 'the wrapper unmounts before it disposes',
      );
    });

    test('the wrappers are idempotent', () async {
      final controller = _TestController();

      await controller.performInit();
      controller
        ..performUnmount()
        ..performUnmount();
      await controller.performDispose();
      await controller.performDispose();

      expect(controller.calls, ['init', 'onUnmount', 'dispose']);
    });

    test('a controller that never initialized has nothing to unmount',
        () async {
      final controller = _TestController();

      await controller.performDispose();

      expect(
        controller.calls,
        ['dispose'],
        reason: '`onUnmount` belongs to a controller that was mounted',
      );
    });
  });
}

/// Records what the scope called, in order.
final class _TestController extends ScopeController {
  final calls = <String>[];

  /// Holds [init] until it is completed.
  final Completer<void>? initGate;

  /// Makes [init] fail, the way user code does.
  final bool failOnInit;

  _TestController({this.initGate, this.failOnInit = false});

  @override
  Future<void> init() async {
    calls.add('init');
    if (initGate case final gate?) {
      await gate.future;
    }
    if (failOnInit) {
      throw StateError('init failed');
    }
  }

  @override
  void onUnmount() => calls.add('onUnmount');

  @override
  Future<void> dispose() async => calls.add('dispose');
}
```

- [ ] **Шаг 2: убедиться, что тест падает**

```sh
fvm flutter test test/async_controller_scope_test.dart
```

Ожидается: ошибка компиляции `Undefined name 'ScopeController'` — падает ровно
на отсутствующей возможности.

- [ ] **Шаг 3: написать минимальную реализацию**

Создать `lib/src/scope/async_controller_scope/scope_controller.dart`:

```dart
part of '../scope.dart';

/// An object with a lifecycle of its own, owned by an
/// [AsyncControllerScopeBase].
///
/// The three methods the scope calls are sealed, so a controller never has to
/// remember to chain to `super`: [performInit] runs [init], [performUnmount]
/// runs [onUnmount] once, and [performDispose] runs both what is left of the
/// teardown and [dispose]. Everything a controller has to write is in the
/// three below them.
///
/// A controller can also be driven by hand — in a test, say — by calling the
/// same three methods in that order.
///
/// {@category AsyncControllerScope}
abstract base class ScopeController {
  bool _mounted = false;
  bool _disposed = false;

  /// Whether the controller is between the start of its initialization and
  /// the moment it was let go of.
  ///
  /// What to check after every `await` inside [init]: the scope may have gone
  /// while the initialization was suspended.
  bool get mounted => _mounted;

  /// Runs [init]. Called by the scope.
  @nonVirtual
  Future<void> performInit() async {
    _mounted = true;
    await init();
  }

  /// Runs [onUnmount], once. Called by the scope.
  @nonVirtual
  void performUnmount() {
    if (!_mounted) {
      return;
    }
    _mounted = false;
    onUnmount();
  }

  /// Runs what is left of the teardown and then [dispose], once.
  ///
  /// Called by the scope. [onUnmount] runs first when it has not run yet, so
  /// the two always arrive in that order.
  @nonVirtual
  Future<void> performDispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    performUnmount();
    await dispose();
  }

  /// Acquires whatever the controller needs; awaited.
  ///
  /// A failure here is terminal: the scope shows its error branch, and the
  /// controller is unmounted and disposed of anyway.
  Future<void> init() async {}

  /// Lets go of whatever cannot wait for [dispose].
  ///
  /// Synchronous, and always before [dispose]. Cancel subscriptions and
  /// detach listeners here.
  void onUnmount() {}

  /// Releases what [init] acquired; awaited.
  ///
  /// Runs on every path, including the one where [init] failed halfway, so it
  /// has to expect a partially initialized controller.
  FutureOr<void> dispose() {}
}
```

Добавить в `lib/src/scope/scope.dart` после строк `part` семейства
`async_data_scope`:

```dart
part 'async_controller_scope/scope_controller.dart';
```

- [ ] **Шаг 4: убедиться, что тесты проходят**

```sh
fvm flutter test test/async_controller_scope_test.dart
```

Ожидается: `+3: All tests passed!`

- [ ] **Шаг 5: проверить нагруженность мутациями**

Каждая мутация должна ронять тест; после проверки — вернуть:

| мутация | какой тест падает |
| --- | --- |
| убрать `performUnmount()` из `performDispose` | первый: порядок вызовов |
| снять проверку `if (_disposed) return;` | второй: идемпотентность |
| снять проверку `if (!_mounted) return;` в `performUnmount` | третий: `onUnmount` у неинициализированного |

---

## Задача 3: элемент и слой Core

**Файлы:**

- Создать: `lib/src/scope/async_controller_scope/async_controller_scope_core.dart`
- Изменить: `lib/src/scope/scope.dart` (одна строка `part`)

**Интерфейсы:**

- Берёт: `ScopeController` из задачи 2.
- Отдаёт: `AsyncControllerScopeCore<W, E, C>` и
  `AsyncControllerScopeElementBase<W, E, C>` с точкой переопределения
  `C createController(BuildContext context)`.

Тестов на этом шаге нет: слой абстрактный и без задачи 4 непроверяем. Его
поведение покрывается тестами задачи 4 — там же и мутации.

- [ ] **Шаг 1: написать слой**

Создать `lib/src/scope/async_controller_scope/async_controller_scope_core.dart`:

```dart
part of '../scope.dart';

/// {@category AsyncControllerScope}
abstract base class AsyncControllerScopeCore<
        W extends AsyncControllerScopeCore<W, E, C>,
        E extends AsyncControllerScopeElementBase<W, E, C>,
        C extends ScopeController> extends AsyncDataScopeCore<W, E, C> {
  /// Creates the widget half of a scope owning a controller.
  const AsyncControllerScopeCore({
    super.key,
    super.tag,
    super.child, // Not used by default. You can use it at your own discretion.
  });
}

/// {@category AsyncControllerScope}
abstract base class AsyncControllerScopeElementBase<
        W extends AsyncControllerScopeCore<W, E, C>,
        E extends AsyncControllerScopeElementBase<W, E, C>,
        C extends ScopeController> extends AsyncDataScopeElementBase<W, E, C> {
  /// Creates the element of a scope owning a controller.
  AsyncControllerScopeElementBase(super.widget);

  /// Kept from the moment it is created, so the synchronous half of the
  /// teardown can reach it even when the initialization never finished.
  C? _controller;

  //
  // Overriding block
  //

  /// Creates the controller this scope owns.
  ///
  /// Called once, at the start of the asynchronous phase. The context is the
  /// scope's own element: reading other scopes with `listen: false` is fine,
  /// subscribing to them is not.
  C createController(BuildContext context);

  //
  // End of overriding block
  //

  @override
  Stream<AsyncDataScopeInitState<Object, C>> initDataAsync() async* {
    final controller = _controller = createController(this);

    try {
      await controller.performInit();

      yield AsyncDataScopeReady(controller);
    } finally {
      // The criterion is the one `_performAsyncDispose` uses to decide whether
      // to call `disposeAsync`, and it has to be: a flag set beside the `yield`
      // would lie. The event travels from here through `.map`, which stores the
      // value, to the `asyncMap` callback, which sets `_initSucceeded` -- and a
      // cancellation landing in between drops it, because nothing is delivered
      // after `cancel()`. The scope would then never call `disposeAsync`, and a
      // local flag would have said the controller was handed over.
      if (!_initSucceeded) {
        await controller.performDispose();
      }
    }
  }

  @override
  void onUnmount() {
    super.onUnmount();
    _controller?.performUnmount();
  }

  @override
  FutureOr<void> disposeAsync() => _controller?.performDispose();
}
```

Добавить в `lib/src/scope/scope.dart`:

```dart
part 'async_controller_scope/async_controller_scope_core.dart';
```

- [ ] **Шаг 2: проверить, что собирается**

```sh
fvm flutter analyze
```

Ожидается: `No issues found!`

---

## Задача 4: слой Base и тесты на все пути

**Файлы:**

- Создать: `lib/src/scope/async_controller_scope/async_controller_scope_base.dart`
- Изменить: `lib/src/scope/scope.dart` (одна строка `part`)
- Изменить: `test/async_controller_scope_test.dart`

**Интерфейсы:**

- Берёт: `AsyncControllerScopeCore`, `AsyncControllerScopeElementBase` из
  задачи 3.
- Отдаёт: `AsyncControllerScopeBase<W, C>` с `createController`,
  `buildOnWaiting`, `buildOnInitializing`, `buildOnError`, `buildOnReady` и
  полным набором параметров скоупа (`scopeKey`, четыре таймаута с их
  колбэками, `pauseAfterInitialization`).

- [ ] **Шаг 1: написать падающие тесты**

Сначала дописать в шапку файла два импорта, которые понадобятся здесь и не были
нужны в задаче 2 (неиспользуемый импорт — замечание анализатора, поэтому они
появляются ровно там, где начинают работать):

```dart
import 'package:flutter/material.dart';

import 'utils/settle.dart';
```

Затем дописать в `test/async_controller_scope_test.dart` внутри `void main()`:

```dart
  group('AsyncControllerScope', () {
    testWidgets('builds the ready branch and tears the controller down once',
        (tester) async {
      final controller = _TestController();

      await tester.pumpWidget(_Host(controller: controller));
      await tester.pumpAndSettle();

      expect(find.text('ready'), findsOneWidget);
      expect(controller.calls, ['init']);

      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester, until: () => controller.calls.contains('dispose'));

      expect(
        controller.calls,
        ['init', 'onUnmount', 'dispose'],
        reason: 'the scope unmounts the controller before it disposes of it',
      );
    });

    // The hole this family exists to close: a controller whose `init` threw is
    // holding whatever it took before the failure, and the scope never saw it.
    testWidgets('disposes of a controller whose init failed', (tester) async {
      final controller = _TestController(failOnInit: true);

      await tester.pumpWidget(_Host(controller: controller));
      await settle(tester, until: () => controller.calls.contains('dispose'));

      expect(find.text('error'), findsOneWidget);
      expect(controller.calls, ['init', 'onUnmount', 'dispose']);
      expect(tester.takeException(), isNull);
    });

    // The same hole, reached the other way: nothing threw, the scope simply
    // left before the initialization finished.
    testWidgets('disposes of a controller left behind by a scope that went',
        (tester) async {
      final gate = Completer<void>();
      final controller = _TestController(initGate: gate);

      await tester.pumpWidget(_Host(controller: controller));
      await tester.pump();

      expect(find.text('initializing'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      gate.complete();
      await settle(tester, until: () => controller.calls.contains('dispose'));

      expect(controller.calls, ['init', 'onUnmount', 'dispose']);
    });
  });
```

И фикстуру ниже, рядом с `_TestController`:

```dart
final class _Host extends StatelessWidget {
  final _TestController controller;

  const _Host({required this.controller});

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: _TestScope(controller: controller),
      );
}

/// Hands out a controller made outside, so the test can inspect it.
final class _TestScope
    extends AsyncControllerScopeBase<_TestScope, _TestController> {
  final _TestController controller;

  const _TestScope({required this.controller});

  @override
  _TestController createController(BuildContext context) => controller;

  @override
  Widget buildOnInitializing(BuildContext context) => const Text('initializing');

  @override
  Widget buildOnError(
    BuildContext context,
    Object error,
    StackTrace stackTrace,
  ) =>
      const Text('error');

  @override
  Widget buildOnReady(BuildContext context, _TestController controller) =>
      const Text('ready');
}
```

- [ ] **Шаг 2: убедиться, что тесты падают**

```sh
fvm flutter test test/async_controller_scope_test.dart
```

Ожидается: ошибка компиляции `Undefined name 'AsyncControllerScopeBase'`.

- [ ] **Шаг 3: написать слой**

Создать `lib/src/scope/async_controller_scope/async_controller_scope_base.dart`:

```dart
part of '../scope.dart';

/// {@category AsyncControllerScope}
abstract base class AsyncControllerScopeBase<
        W extends AsyncControllerScopeBase<W, C>, C extends ScopeController>
    extends AsyncControllerScopeCore<W, _AsyncControllerScopeElement<W, C>, C> {
  /// Serializes this scope with the others that share the key.
  final Object? scopeKey;

  /// How long to wait for [scopeKey]; `null` waits indefinitely.
  final Duration? scopeKeyTimeout;

  /// Called when the wait for [scopeKey] expires.
  final void Function()? onScopeKeyTimeout;

  /// How long the teardown waits for the initialization to be cancelled;
  /// `null` waits indefinitely.
  final Duration? initCancellationTimeout;

  /// Called when the wait for the cancellation expires.
  final void Function()? onInitCancellationTimeout;

  /// How long to wait for the asynchronous teardown; `null` waits
  /// indefinitely.
  final Duration? disposeAsyncTimeout;

  /// Called when the wait for the asynchronous teardown expires.
  final void Function()? onDisposeAsyncTimeout;

  /// How long to wait for the child scopes; `null` waits indefinitely.
  final Duration? waitForChildrenTimeout;

  /// Called when the wait for the child scopes expires.
  final void Function()? onWaitForChildrenTimeout;

  /// Holds the ready branch back for this long after the initialization.
  final Duration? pauseAfterInitialization;

  /// Creates a scope owning a controller.
  const AsyncControllerScopeBase({
    super.key,
    super.tag,
    this.scopeKey,
    this.scopeKeyTimeout,
    this.onScopeKeyTimeout,
    this.initCancellationTimeout,
    this.onInitCancellationTimeout,
    this.disposeAsyncTimeout,
    this.onDisposeAsyncTimeout,
    this.waitForChildrenTimeout,
    this.onWaitForChildrenTimeout,
    this.pauseAfterInitialization,
    super.child, // Not used by default. You can use it at your own discretion.
  });

  //
  // Overriding block
  //

  /// Creates the controller this scope owns.
  C createController(BuildContext context);

  /// Built while waiting for a `scopeKey` and for the controller.
  ///
  /// Returning `null` falls back to [buildOnInitializing].
  Widget? buildOnWaiting(BuildContext context) => null;

  /// Built while the controller is initializing.
  Widget buildOnInitializing(BuildContext context);

  /// Built when the initialization of the controller failed.
  Widget buildOnError(
    BuildContext context,
    Object error,
    StackTrace stackTrace,
  );

  /// Built once the controller is ready, and receives it.
  Widget buildOnReady(BuildContext context, C controller);

  //
  // End of overriding block
  //

  @override
  // ignore: library_private_types_in_public_api
  _AsyncControllerScopeElement<W, C> createScopeElement() =>
      _AsyncControllerScopeElement<W, C>(this as W);
}

final class _AsyncControllerScopeElement<
        W extends AsyncControllerScopeBase<W, C>, C extends ScopeController>
    extends AsyncControllerScopeElementBase<W,
        _AsyncControllerScopeElement<W, C>, C> {
  _AsyncControllerScopeElement(super.widget);

  @override
  Object? get scopeKey => widget.scopeKey;

  @override
  Duration? get scopeKeyTimeout => widget.scopeKeyTimeout;

  @override
  void onScopeKeyTimeout() => widget.onScopeKeyTimeout?.call();

  @override
  Duration? get initCancellationTimeout => widget.initCancellationTimeout;

  @override
  void onInitCancellationTimeout() => widget.onInitCancellationTimeout?.call();

  @override
  Duration? get disposeAsyncTimeout => widget.disposeAsyncTimeout;

  @override
  void onDisposeAsyncTimeout() => widget.onDisposeAsyncTimeout?.call();

  @override
  Duration? get waitForChildrenTimeout => widget.waitForChildrenTimeout;

  @override
  void onWaitForChildrenTimeout() => widget.onWaitForChildrenTimeout?.call();

  @override
  Duration? get pauseAfterInitialization => widget.pauseAfterInitialization;

  @override
  C createController(BuildContext context) => widget.createController(context);

  @override
  Widget buildOnState(AsyncScopeState state) => switch (state) {
        AsyncScopeWaiting() =>
          widget.buildOnWaiting(this) ?? widget.buildOnInitializing(this),
        // A controller reports no progress: `initDataAsync` above yields the
        // ready state and nothing else.
        AsyncScopeProgress() => widget.buildOnInitializing(this),
        AsyncScopeReady() => widget.buildOnReady(this, data),
        AsyncScopeError(:final error, :final stackTrace) =>
          widget.buildOnError(this, error, stackTrace),
      };
}
```

Добавить в `lib/src/scope/scope.dart`:

```dart
part 'async_controller_scope/async_controller_scope_base.dart';
```

- [ ] **Шаг 4: убедиться, что тесты проходят**

```sh
fvm flutter test test/async_controller_scope_test.dart
```

Ожидается: `+6: All tests passed!`

- [ ] **Шаг 5: проверить нагруженность мутациями**

| мутация | какой тест падает |
| --- | --- |
| убрать `await controller.performDispose()` из `finally` | второй и третий тесты группы |
| заменить `if (!_initSucceeded)` локальным флагом, взводимым перед `yield` | ни один — см. шаг 6 |
| убрать `_controller?.performUnmount()` из `onUnmount` | все три теста группы (нет `onUnmount` в списке) |
| `disposeAsync` → `null` вместо `_controller?.performDispose()` | первый тест группы |

- [ ] **Шаг 6: закрыть пятый путь или честно записать, что он не покрыт**

Пятый путь — событие готовности, выброшенное отменой между `yield` и колбэком
`asyncMap`. Попытка воспроизвести детерминированно: смонтировать скоуп ручным
управлением биндингом и снять его между микрозадачами, как это сделано в
`test/async_scope_test.dart` (группа `AsyncScope post-frame callbacks`, там
`binding.attachRootWidget` + `buildOwner!.buildScope` + `finalizeTree` без
кадра). Если детерминированного теста не выходит — не изображать покрытие:
записать в отчёт волны, что путь проверен только рассуждением и мутацией
(вторая строка таблицы выше), и оставить в коде комментарий, который уже
объясняет критерий.

---

## Задача 5: конструкторная форма

**Файлы:**

- Создать: `lib/src/scope/async_controller_scope/async_controller_scope.dart`
- Изменить: `lib/src/scope/scope.dart` (одна строка `part`)
- Изменить: `test/async_controller_scope_test.dart`

**Интерфейсы:**

- Берёт: `AsyncControllerScopeBase` из задачи 4.
- Отдаёт: `AsyncControllerScope<C>` с `create`, `waitingBuilder`,
  `initBuilder`, `errorBuilder`, `builder` и статическими `maybeOf`, `of`,
  `select`.

- [ ] **Шаг 1: написать падающий тест**

Дописать в группу `AsyncControllerScope` в `test/async_controller_scope_test.dart`:

```dart
    testWidgets('the constructor form creates the controller once and hands '
        'it to the subtree', (tester) async {
      var created = 0;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: AsyncControllerScope<_TestController>(
            create: (context) {
              created++;

              return _TestController();
            },
            initBuilder: (context) => const Text('initializing'),
            errorBuilder: (context, error, stackTrace) => const Text('error'),
            builder: (context, controller) => const _Reader(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(created, 1);
      expect(find.text('reader: init'), findsOneWidget);
    });
```

И фикстуру-читателя рядом с `_Host`:

```dart
/// Reads the controller from the context, the way a descendant does.
final class _Reader extends StatelessWidget {
  const _Reader();

  @override
  Widget build(BuildContext context) {
    final calls = AsyncControllerScope.select<_TestController, String>(
      context,
      (scope) => scope.data.calls.join(','),
    );

    return Text('reader: $calls');
  }
}
```

- [ ] **Шаг 2: убедиться, что тест падает**

```sh
fvm flutter test test/async_controller_scope_test.dart
```

Ожидается: ошибка компиляции `Undefined name 'AsyncControllerScope'`.

- [ ] **Шаг 3: написать форму**

Создать `lib/src/scope/async_controller_scope/async_controller_scope.dart`:

```dart
part of '../scope.dart';

/// {@category AsyncControllerScope}
final class AsyncControllerScope<C extends ScopeController>
    extends AsyncControllerScopeBase<AsyncControllerScope<C>, C> {
  /// Creates the controller this scope owns.
  final C Function(BuildContext context) create;

  /// Built while waiting for a `scopeKey` and for the controller.
  ///
  /// Falls back to [initBuilder] when omitted.
  final Widget Function(BuildContext context)? waitingBuilder;

  /// Built while the controller is initializing.
  final Widget Function(BuildContext context) initBuilder;

  /// Built when the initialization of the controller failed.
  final Widget Function(
    BuildContext context,
    Object error,
    StackTrace stackTrace,
  ) errorBuilder;

  /// Built once the controller is ready, and receives it.
  final Widget Function(BuildContext context, C controller) builder;

  /// Creates a scope owning a controller.
  const AsyncControllerScope({
    super.key,
    super.tag,
    super.scopeKey,
    super.scopeKeyTimeout,
    super.onScopeKeyTimeout,
    super.initCancellationTimeout,
    super.onInitCancellationTimeout,
    super.disposeAsyncTimeout,
    super.onDisposeAsyncTimeout,
    super.waitForChildrenTimeout,
    super.onWaitForChildrenTimeout,
    super.pauseAfterInitialization,
    required this.create,
    this.waitingBuilder,
    required this.initBuilder,
    required this.builder,
    required this.errorBuilder,
  });

  @override
  C createController(BuildContext context) => create(context);

  @override
  Widget? buildOnWaiting(BuildContext context) => waitingBuilder?.call(context);

  @override
  Widget buildOnInitializing(BuildContext context) => initBuilder(context);

  @override
  Widget buildOnError(
    BuildContext context,
    Object error,
    StackTrace stackTrace,
  ) =>
      errorBuilder(context, error, stackTrace);

  @override
  Widget buildOnReady(BuildContext context, C controller) =>
      builder(context, controller);

  /// The nearest `AsyncControllerScope<C>` above [context], or `null`.
  static AsyncDataScopeContext<AsyncControllerScope<C>, C>?
      maybeOf<C extends ScopeController>(
    BuildContext context, {
    required bool listen,
  }) =>
          ScopeContext.maybeOf<AsyncControllerScope<C>,
              AsyncDataScopeContext<AsyncControllerScope<C>, C>>(
            context,
            listen: listen,
          );

  /// The nearest `AsyncControllerScope<C>` above [context].
  ///
  /// Throws when there is none.
  static AsyncDataScopeContext<AsyncControllerScope<C>, C>
      of<C extends ScopeController>(
    BuildContext context, {
    required bool listen,
  }) =>
          ScopeContext.of<AsyncControllerScope<C>,
              AsyncDataScopeContext<AsyncControllerScope<C>, C>>(
            context,
            listen: listen,
          );

  /// Subscribes to one value of the scope and returns it.
  ///
  /// The controller's type comes first and the selected type second, as
  /// everywhere else in the package.
  static V select<C extends ScopeController, V extends Object?>(
    BuildContext context,
    V Function(AsyncDataScopeContext<AsyncControllerScope<C>, C> context)
        selector,
  ) =>
      ScopeContext.select<AsyncControllerScope<C>,
          AsyncDataScopeContext<AsyncControllerScope<C>, C>, V>(
        context,
        selector,
      );
}
```

Добавить в `lib/src/scope/scope.dart`:

```dart
part 'async_controller_scope/async_controller_scope.dart';
```

- [ ] **Шаг 4: убедиться, что тесты проходят**

```sh
fvm flutter test test/async_controller_scope_test.dart
fvm flutter analyze
```

Ожидается: `+7: All tests passed!` и `No issues found!`

- [ ] **Шаг 5: проверить нагруженность мутациями**

| мутация | какой тест падает |
| --- | --- |
| `createController` зовёт `create(context)` дважды | проверка `created == 1` |
| `buildOnReady` возвращает `initBuilder(context)` | `reader: init` не находится |

Прогнать каждую, убедиться в падении, вернуть.

---

## Задача 6: документация и коммит 2

**Файлы:**

- Создать: `doc/async_controller_scope.md`, `docs/ru/doc/async_controller_scope.md`
- Изменить: `dartdoc_options.yaml`, `README.md`, `docs/ru/README.md`,
  `CHANGELOG.md`

- [ ] **Шаг 1: страница документации**

`doc/async_controller_scope.md` по образцу `doc/async_data_scope.md`. Разделы:
зачем семейство (контроллер как владелец побочных эффектов, а не источник
значений); `ScopeController` и его шесть методов; таблица путей разбора из
спеки — она и есть главное содержание страницы; чего семейство не делает
(наблюдаемость — `ScopeNotifier` под ним; прогресс — `AsyncDataScope`); строка
о том, куда девать провал `init()` (`buildOnError` или `ScopeConfig.logger`);
раздел «куда дальше».

- [ ] **Шаг 2: зеркало и регистрация темы**

`docs/ru/doc/async_controller_scope.md` с шапкой
`> Перевод \`doc/async_controller_scope.md\` (blob \`…\`)`. В
`dartdoc_options.yaml` — категория `AsyncControllerScope` с путём к странице и
строка в `categoryOrder` **сразу после `AsyncDataScope`**.

```sh
sh docs/ru/stamp.sh
sh docs/ru/check.sh
```

Ожидается: `переводы актуальны: 15`.

- [ ] **Шаг 3: README и CHANGELOG**

Раздел `### AsyncControllerScope` в `README.md` сразу после `### AsyncDataScope`
и то же в `docs/ru/README.md`; пример — 15–20 строк на конструкторной форме.
Строка в `CHANGELOG.md` в раздел `0.10.0`.

```sh
sh docs/ru/stamp.sh
sh docs/ru/check.sh
```

- [ ] **Шаг 4: полный гейт**

Все восемь команд из задачи 1, шаг 9.

- [ ] **Шаг 5: коммит 2**

```sh
git add lib/src/scope/async_controller_scope lib/src/scope/scope.dart \
        test/async_controller_scope_test.dart \
        doc/async_controller_scope.md docs/ru/doc/async_controller_scope.md \
        dartdoc_options.yaml README.md docs/ru/README.md CHANGELOG.md
git commit
```

Сообщение (`feat:`) — о гарантии разбора, а не об экономии строк: она причина.

---

## Задача 7: демо и пример

**Файлы:**

- Создать: `example/scopo_demo/lib/home/demos/async_controller/` —
  `async_controller_demo.dart`, `profile_controller.dart`, `profile_view.dart`
- Изменить: `example/scopo_demo/lib/home/home.dart` (импорт и строка в `_tabs`
  сразу после `AsyncDataScope`), `example/scopo_demo/README.md` и его зеркало
  (строка в таблице вкладок, «Nine tabs» → «Ten tabs»)

- [ ] **Шаг 1: контроллер и скоуп демо**

`profile_controller.dart`: `ProfileController extends ScopeController` на
нейтральном домене — «профиль»: `init()` с задержкой и логированием в консоль
демо, `onUnmount()` со снятием подписки, `dispose()` с освобождением. Скоуп —
`ProfileScope extends AsyncControllerScopeBase<ProfileScope, ProfileController>`.

- [ ] **Шаг 2: панель демо**

`async_controller_demo.dart` по образцу `async_data_scope_demo.dart`: два-три
варианта рядом (обычный; падающий `init()`; уход с дерева во время `init()`) с
`ConsoleView` под каждым и кнопкой пересборки. Именно эти три варианта делают
видимой таблицу путей.

- [ ] **Шаг 3: регистрация вкладки**

Импорт и строка `('AsyncControllerScope', AsyncControllerDemo()),` в `_tabs`
сразу после `('AsyncDataScope', AsyncDataScopeDemo()),`.

- [ ] **Шаг 4: README демо и зеркало**

Строка в таблицу вкладок, счётчик вкладок с девяти на десять — в оригинале и в
зеркале, затем `sh docs/ru/stamp.sh`.

- [ ] **Шаг 5: проверки и коммит 3**

```sh
(cd example/scopo_demo && fvm flutter analyze)
sh docs/ru/check.sh
```

Плюс полный гейт пакета. Тестов у `scopo_demo` нет вообще — в отчёте волны
сказать это прямо, а не изображать покрытие.

---

## Самопроверка плана

- **Покрытие спеки.** `ScopeController` — задача 2; три слоя — задачи 3–5;
  таблица путей — тесты задачи 4 (четыре из пяти строк) и шаг 6 той же задачи
  (пятая строка, честно помеченная как непокрываемая детерминированно);
  билдеры и их обязательность — задачи 4 и 5; отсутствие прогресса — в
  `buildOnState` комментарием и в документации; снятие букв — задача 1;
  порядок «сразу после `AsyncDataScope`» — задачи 6 и 7; три коммита — шаги
  1.10, 6.5, 7.5.
- **Заглушек нет.** Каждый шаг содержит либо код, либо команду с ожидаемым
  выводом.
- **Согласованность имён.** `performInit`/`performUnmount`/`performDispose`,
  `init`/`onUnmount`/`dispose`, `createController`, `_controller`,
  `_initSucceeded` — одинаково во всех задачах.
