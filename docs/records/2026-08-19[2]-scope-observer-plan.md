# План: `ScopeConfig.observer` вместо журнала

> **Состояние на 2026-08-19:** выполнен целиком, ветка `observer`. Пять задач
> закрыты коммитами `cc59355`, `348dbc6`, `0e1cada`, `a852b93`,
> `5f1987e` плюс `b6ee0ba`, `843fb8a` и `7d631ee`. Тестов 384 → 392.
> Отступления от плана и найденные по ходу дефекты — в шапке спеки и в
> `docs/handoff.md`.
> **Что это:** пошаговый план реализации по спеке
> `2026-08-19[1]-scope-observer-design.md` — пять задач, TDD, гейт §6 на
> каждой.
> **Связанные записи:** `2026-08-19[1]-scope-observer-design.md` (дизайн и
> решения владельца).

> **Исполнителю:** задачи идут по порядку, каждая заканчивается своим
> коммитом. Шаги помечены `- [ ]`. Дизайн и обоснования — в спеке; здесь
> только работа.

**Цель.** Заменить журнал на `logger_builder` типизированным наблюдателем
`ScopeConfig.observer`, убрав внешнюю зависимость из репозитория целиком.

**Устройство.** Девять пустых хуков на `ScopeObserver`; источник события
приходит первым параметром как `ScopeObservable` с `debugLabel`. Пакет зовёт
хуки через одну обёртку с `try`/`catch` и флагом от рекурсии. Печать — готовый
`ScopePrintObserver`, пишущий через `print`.

**Тулчейн.** Flutter 3.27.0 через `fvm` (`.fvmrc`), Dart 3.6.0.

**Спека.** `docs/records/2026-08-19[1]-scope-observer-design.md`

## Общие требования (действуют в каждой задаче)

- **Сначала тест.** Падающий тест, потом код. Исправил — откати правку и
  убедись, что тест падает; верни правку. Без этого тест не считается
  нагруженным (`AGENTS.md` §8).
- **Ширина 80 колонок** во всех файлах, включая документацию.
- `public_member_api_docs: true` — **у каждого публичного члена дартдок**, и
  он **по-английски** (`AGENTS.md` §7).
- `require_trailing_commas: true` — висячие запятые обязательны.
- **Правки в `lib/` не заканчиваются без строки в `CHANGELOG.md`**, раздел
  0.10.0 (`AGENTS.md` §8).
- **Правка оригинала в `doc/` или `README.md` — только вместе с зеркалом в
  `docs/ru/` в том же коммите**, потом `sh docs/ru/stamp.sh` (`AGENTS.md` §7).
- Коммиты по-английски с префиксом: `feat:`, `fix:`, `refactor:`, `test:`,
  `docs:`, `chore:`.
- **Коммить только свои файлы поимённо.** В дереве лежит правка владельца в
  `docs/backlog.md` — её не трогать и в свой коммит не брать (`AGENTS.md` §5).
- Перед каждым коммитом минимум: `fvm flutter test`, `fvm flutter analyze`,
  `fvm dart format --set-exit-if-changed lib test`. Полный гейт §6 из восьми
  команд — в конце задач 4 и 5.
- Сейчас в сьюте **384 теста**; число растёт, и новое значение идёт в
  `docs/handoff.md`.

## Карта файлов

| файл | что с ним |
| --- | --- |
| `lib/src/environment/scope_observer.dart` | создать: `ScopeObservable`, `ScopePhase`, `ScopeObserver`, `ScopePrintObserver` |
| `lib/src/environment/scope_config.dart` | добавить `observer`, `notifyObserver`, убрать `logger` и `_reportLoggerFailure` (задача 4) |
| `lib/src/environment/scope_logger.dart` | удалить целиком (задача 4) |
| `lib/scopo.dart` | `hide log` → `hide notifyObserver` (задача 4) |
| `lib/src/scope/scope_widget/scope_widget_core.dart` | `debugLabel`, пара `onInit`/`onDisposed` |
| `lib/src/scope/async_scope/async_scope_core.dart` | 26 точек журнала → хуки |
| `lib/src/scope/full_scope/scope_auto_dependency/scope_auto_dependency.dart` | 11 точек + `debugLabel` |
| `lib/.../scope_dependency/scope_dependency_mixin.dart` | 2 точки + `debugLabel` |
| `lib/src/utils/stream/run_stream_guarded.dart` | 7 точек → `onTrace` |
| `test/utils/observer.dart` | создать: накопитель событий для тестов |
| `test/utils/logging.dart` | удалить (задача 4) |
| `test/scope_logger_test.dart` | заменить на `test/scope_observer_test.dart` |
| `pubspec.yaml` | убрать `logger_builder` (задача 4) |
| `example/*/lib/main.dart`, `example/*/pubspec.yaml` | `ScopePrintObserver`, убрать `logger_builder` и `ansi_escape_codes` |
| `doc/debug.md`, `README.md`, `docs/architecture.md`, `CHANGELOG.md` + зеркала | задача 5 |

---

## Задача 1: каркас и синхронная пара

Каркас без единой точки оповещения нечем проверить, поэтому вместе с ним идёт
пара `onInit`/`onDisposed` в общем предке элементов — та, что делает видимыми
все семейства скоупов.

**Файлы:**
- Создать: `lib/src/environment/scope_observer.dart`
- Изменить: `lib/src/environment/scope_config.dart`
- Изменить: `lib/src/scope/scope_widget/scope_widget_core.dart`
- Создать: `test/utils/observer.dart`
- Создать: `test/scope_observer_test.dart`

**Интерфейсы, которые появятся** (ими пользуются задачи 2–5):
- `abstract interface class ScopeObservable { String get debugLabel; }`
- `enum ScopePhase { initialization, initializationCancellation,
  preparationForDisposal, unmount, disposal, abandonedWait }`
- `base class ScopeObserver` с девятью хуками
- `ScopeConfig.observer` — `static ScopeObserver?`
- `void notifyObserver(void Function(ScopeObserver observer) call)` — не
  экспортируется, зовётся из `lib/src/scope/**`

- [ ] **Шаг 1. Накопитель для тестов**

Создать `test/utils/observer.dart`:

```dart
import 'package:scopo/scopo.dart';

/// Records what the package reports, in order, as plain strings.
///
/// Strings, not objects: a test that compares the whole list at once catches
/// both a missing event and one too many, and the reason a comparison failed
/// is readable without a debugger.
final class RecordingObserver extends ScopeObserver {
  /// Every event so far, oldest first.
  final events = <String>[];

  /// Whether [onTrace] is recorded too.
  final bool trace;

  /// Creates a recorder; pass `trace: true` to record traces as well.
  RecordingObserver({this.trace = false});

  @override
  void onInit(ScopeObservable target) =>
      events.add('init ${target.debugLabel}');

  @override
  void onProgress(ScopeObservable target, Object? progress) =>
      events.add('progress ${target.debugLabel} $progress');

  @override
  void onReady(ScopeObservable target) =>
      events.add('ready ${target.debugLabel}');

  @override
  void onCancelled(ScopeObservable target) =>
      events.add('cancelled ${target.debugLabel}');

  @override
  void onDispose(ScopeObservable target) =>
      events.add('dispose ${target.debugLabel}');

  @override
  void onDisposed(ScopeObservable target) =>
      events.add('disposed ${target.debugLabel}');

  @override
  void onError(
    ScopeObservable target,
    ScopePhase phase,
    Object error,
    StackTrace? stackTrace,
  ) =>
      events.add('error ${target.debugLabel} ${phase.name} $error');

  @override
  void onTimeout(ScopeObservable target, String what) =>
      events.add('timeout ${target.debugLabel} $what');

  @override
  void onTrace(ScopeObservable target, String message) {
    if (trace) {
      events.add('trace ${target.debugLabel} $message');
    }
  }
}
```

- [ ] **Шаг 2. Падающий тест на пару событий**

Создать `test/scope_observer_test.dart`. Скоуп берётся самый простой из
семейств — `LiteScope`; сегодня он не пишет в журнал ничего, и именно это
меняется.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scopo/scopo.dart';

import 'utils/observer.dart';

void main() {
  late RecordingObserver observer;

  setUp(() {
    observer = RecordingObserver();
    ScopeConfig.observer = observer;
  });

  tearDown(() {
    ScopeConfig.observer = null;
  });

  testWidgets('a scope reports that it was initialized and disposed of',
      (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: _CounterScope(child: SizedBox()),
      ),
    );

    expect(observer.events, ['init _CounterScope']);

    await tester.pumpWidget(const SizedBox());

    expect(observer.events, ['init _CounterScope', 'disposed _CounterScope']);
  });
}
```

Заглушка скоупа для этого файла — `LiteScope` с пустым состоянием; за образцом
идти в `test/lite_scope_test.dart`, где такой уже написан, и повторить его
здесь под именем `_CounterScope`.

**Метка в ожиданиях — без `#hash`:** `debugLabel` строится как
`widget.toStringShort(showHashCode: true)` и хеш в нём меняется от прогона к
прогону. Поэтому сравнивать нужно с меткой без хеша: в накопителе метка
обрезается по `(`, либо тест сверяет через `startsWith`. Выбрать первое —
обрезать в `RecordingObserver`, дописав в шаге 1
`String _label(ScopeObservable t) => t.debugLabel.split('(').first;` и звать
его вместо `target.debugLabel`.

- [ ] **Шаг 3. Убедиться, что тест падает**

```sh
fvm flutter test test/scope_observer_test.dart
```

Ожидается: не компилируется — `ScopeObserver`, `ScopeObservable`,
`ScopeConfig.observer` не существуют.

- [ ] **Шаг 4. Написать каркас**

Создать `lib/src/environment/scope_observer.dart`:

```dart
part of 'scope_config.dart';

/// An object whose lifecycle [ScopeConfig.observer] is told about.
///
/// Implemented by the scope elements of every family, by the container of
/// automatic dependencies and by a single dependency. It is deliberately not
/// implemented by `ScopeDependencies` or `ScopeDependency`: those are yours to
/// implement, and a new member on them would break the code that already does.
///
/// {@category debug}
abstract interface class ScopeObservable {
  /// How this object names itself in a report.
  String get debugLabel;
}

/// What was running when a failure reached [ScopeObserver.onError].
///
/// More values may be added later, so a `switch` over this enum wants a
/// `default` branch.
///
/// {@category debug}
enum ScopePhase {
  /// An initialization, synchronous or asynchronous.
  initialization,

  /// The cancellation of an initialization that was still running.
  initializationCancellation,

  /// The synchronous half of a teardown, before the asynchronous one.
  preparationForDisposal,

  /// The `onUnmount` hook.
  unmount,

  /// A teardown.
  disposal,

  /// A wait nobody was left to hear the end of.
  abandonedWait,
}

/// Hooks called as scopes and their dependencies live and die.
///
/// Assign one to [ScopeConfig.observer]. Every hook is empty, so a subclass
/// overrides only what it needs. Hooks are called synchronously, from the
/// build, the initialization or the teardown they belong to; a hook that
/// throws is reported through [FlutterError.reportError] and does not reach
/// the scope.
///
/// {@category debug}
base class ScopeObserver {
  /// Creates an observer that does nothing.
  const ScopeObserver();

  /// An initialization has begun.
  void onInit(ScopeObservable target) {}

  /// One step of an initialization is done.
  ///
  /// [progress] is what that source reports: the value an `initScope` yielded
  /// for a scope, a `ScopeAutoDependenciesProgress` for a container.
  void onProgress(ScopeObservable target, Object? progress) {}

  /// An initialization has finished successfully.
  void onReady(ScopeObservable target) {}

  /// An initialization was cancelled before it finished.
  void onCancelled(ScopeObservable target) {}

  /// A teardown has begun.
  void onDispose(ScopeObservable target) {}

  /// A teardown has finished.
  void onDisposed(ScopeObservable target) {}

  /// Something failed; [phase] says what was running.
  void onError(
    ScopeObservable target,
    ScopePhase phase,
    Object error,
    StackTrace? stackTrace,
  ) {}

  /// A bounded wait expired; [what] names what was waited for.
  void onTimeout(ScopeObservable target, String what) {}

  /// A step of the machinery below the lifecycle.
  ///
  /// Off by default in [ScopePrintObserver]: this is where the coordination
  /// of `scopeKey`s and the guarded streams report themselves, and a scope
  /// produces a dozen such lines where it produces one of the rest.
  void onTrace(ScopeObservable target, String message) {}
}
```

В `lib/src/environment/scope_config.dart` — рядом с `part
'scope_logger.dart';` добавить `part 'scope_observer.dart';`, а в тело
`ScopeConfig`:

```dart
  /// Where the package reports its lifecycle.
  ///
  /// `null` by default: the package says nothing until an observer is
  /// assigned. [reset] leaves it alone, as it leaves the logger alone: it is
  /// an object rather than a switch, and it is usually the whole point of the
  /// run it was assigned for.
  static ScopeObserver? observer;

  /// Whether a notification is already running.
  static bool _notifying = false;
```

И, вне класса, в том же файле:

```dart
/// Calls [call] on [ScopeConfig.observer], guarded.
///
/// Not exported: the package notifies, an application observes.
///
/// The observer is consumer code called from a build, an initialization or a
/// teardown — the same three places a throwing logger used to take a scope
/// down from. A failure is reported through [FlutterError.reportError] and the
/// caller goes on. An observer that produces an event of its own — one that
/// builds a scope from a hook — would otherwise recurse without end, so the
/// second entry is refused and reported once.
void notifyObserver(void Function(ScopeObserver observer) call) {
  final observer = ScopeConfig.observer;
  if (observer == null) {
    return;
  }

  if (ScopeConfig._notifying) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: StateError(
          'A scope observer produced a scope event while it was being '
          'notified. The second notification is refused: it would not end.',
        ),
        library: 'scopo',
        context: ErrorDescription('while notifying a scope observer'),
      ),
    );

    return;
  }

  ScopeConfig._notifying = true;
  try {
    call(observer);
    // ignore: avoid_catching_errors
  } on Object catch (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'scopo',
        context: ErrorDescription('while notifying a scope observer'),
      ),
    );
  } finally {
    ScopeConfig._notifying = false;
  }
}
```

- [ ] **Шаг 5. Пара событий в общем предке элементов**

`lib/src/scope/scope_widget/scope_widget_core.dart`:

1. объявить реализацию — `implements ScopeInheritedElement<W>, ScopeObservable`
   в `ScopeWidgetElementBase`;
2. добавить метку:

```dart
  @override
  String get debugLabel => widget.toStringShort(showHashCode: true);
```

3. в `build()`, сразу после `_initPhase = _InitPhase.done;` (строка ~527):

```dart
      notifyObserver((observer) => observer.onInit(this));
```

4. в `unmount()`, в `finally` после `dispose()` (строки ~205–213) — так, чтобы
   событие ушло и после `init`, который бросил:

```dart
    } finally {
      notifyObserver((observer) => observer.onDisposed(this));
      super.unmount();
    }
```

- [ ] **Шаг 6. Тест зелёный**

```sh
fvm flutter test test/scope_observer_test.dart
```

- [ ] **Шаг 7. Проверить нагруженность**

Убрать вызов `onInit` из `build()`, прогнать — тест должен упасть на первом
`expect`. Вернуть. То же для `onDisposed`.

- [ ] **Шаг 8. Тесты на устойчивость**

Дописать в `test/scope_observer_test.dart` три теста: наблюдатель, бросающий из
`onInit`; наблюдатель, строящий скоуп из `onInit`; `ScopeConfig.reset()`.

```dart
  testWidgets('a throwing observer does not reach the scope', (tester) async {
    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = previous);

    ScopeConfig.observer = _ThrowingObserver();

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: _CounterScope(child: Text('built')),
      ),
    );

    expect(find.text('built'), findsOneWidget,
        reason: 'the scope builds its subtree even though the observer threw');
    expect(errors, hasLength(1));
    expect(errors.single.library, 'scopo');
  });
```

`_ThrowingObserver` — `final class _ThrowingObserver extends ScopeObserver`,
переопределяющий `onInit` броском `StateError('observer failed')`.

Тест на рекурсию: наблюдатель, чей `onInit` зовёт
`notifyObserver`-порождающий код, — проще всего накопитель, который в `onInit`
строит второй скоуп через `tester.pumpWidget`; достаточно проверить, что
`FlutterError.onError` получил ровно один отчёт и прогон завершился.

Тест на `reset()`: поставить наблюдателя, вызвать `ScopeConfig.reset()`,
убедиться, что `ScopeConfig.observer` тот же.

- [ ] **Шаг 9. Проверки и коммит**

```sh
fvm flutter test
fvm flutter analyze
fvm dart format --set-exit-if-changed lib test
```

`CHANGELOG.md`, раздел 0.10.0 — строка про появление `ScopeConfig.observer` и
про то, что теперь о жизненном цикле сообщают все семейства скоупов, а не
только асинхронные.

```sh
git add lib/src/environment/scope_observer.dart \
        lib/src/environment/scope_config.dart \
        lib/src/scope/scope_widget/scope_widget_core.dart \
        test/utils/observer.dart test/scope_observer_test.dart CHANGELOG.md
git commit -m "feat: a scope observer, and every family reports its lifecycle"
```

---

## Задача 2: 26 точек асинхронного скоупа

**Файлы:**
- Изменить: `lib/src/scope/async_scope/async_scope_core.dart`
- Изменить: `test/scope_observer_test.dart`

**Потребляет:** `notifyObserver`, `ScopeObserver`, `ScopePhase`,
`ScopeObservable` из задачи 1. `AsyncScopeElementBase` наследует `debugLabel`
от `ScopeWidgetElementBase`, объявлять заново не нужно.

- [ ] **Шаг 1. Тесты на путь успеха**

Дописать в `test/scope_observer_test.dart` тест на `AsyncScope`, который
проходит инициализацию с прогрессом и утилизируется. Ожидаемая
последовательность целиком:

```dart
    expect(observer.events, [
      'init _AsyncScope',
      'progress _AsyncScope 1/2',
      'progress _AsyncScope 2/2',
      'ready _AsyncScope',
      'dispose _AsyncScope',
      'disposed _AsyncScope',
    ]);
```

Образец асинхронного скоупа с прогрессом — в `test/async_scope_test.dart`;
повторить его здесь.

- [ ] **Шаг 2. Убедиться, что тест падает**

```sh
fvm flutter test test/scope_observer_test.dart
```

Ожидается: список пуст, кроме `init`/`disposed` из задачи 1.

- [ ] **Шаг 3. Заменить 26 точек**

В каждой строке `_log.X(...)` заменяется на `notifyObserver(...)` по таблице.
Номера строк — по состоянию на `b033844`, они поедут по ходу правки; искать по
тексту сообщения.

| строка | сегодня | станет |
| --- | --- | --- |
| 523 | `d 'prepare for initialization'` | `onTrace(this, 'prepare for initialization')` |
| 570 | `d 'wait for access to [$scopeKey]'` | `onTrace` с тем же текстом |
| 587 | `d 'access to [$scopeKey] cancelled'` | `onTrace` |
| 589 | `d 'access to [$scopeKey] obtained'` | `onTrace` |
| 602 | `i 'initialization cancelled'` | `onCancelled(this)` |
| 621 | `i 'initialize…'` | `onInit(this)` |
| 638 | `i 'progress: ${state.progress}'` | `onProgress(this, state.progress)` |
| 668 | `i 'initialized'` | `onReady(this)` |
| 676 | `e 'initialization failed'` | `onError(this, ScopePhase.initialization, error, stackTrace)` |
| 734 | `e 'not initialized'` | `onError(this, ScopePhase.initialization, error, null)` |
| 760 | `e 'initialization failed'` | `onError(..., ScopePhase.initialization, ...)` |
| 853 | `e 'unmount failed'` | `onError(..., ScopePhase.unmount, ...)` |
| 861 | `e 'preparation for disposal failed'` | `onError(..., ScopePhase.preparationForDisposal, ...)` |
| 871 | `i 'dispose…'` | `onDispose(this)` |
| 893 | `d 'do not dispose of'` | `onTrace(this, 'do not dispose of')` |
| 896 | `i 'disposed'` | `onDisposed(this)` |
| 899 | `e 'disposal failed'` | `onError(..., ScopePhase.disposal, ...)` |
| 915 | `d 'exit from [$_acquiredScopeKey]'` | `onTrace` |
| 990 | `e 'an abandoned wait for $what ended in a failure'` | `onError(..., ScopePhase.abandonedWait, ...)` |
| 1005 | `e 'gave up waiting for $what'` | `onTimeout(this, what)` |
| 1025 | `d 'prepare for disposal'` | `onTrace` |
| 1033 | `d 'cancel waiting for access to […]'` | `onTrace` |
| 1075 | `e 'initialization cancellation failed'` | `onError(..., ScopePhase.initializationCancellation, ...)` |
| 1089 | `i 'initialization cancelled'` | `onCancelled(this)` |
| 1103 | `d 'wait for initialization'` | `onTrace` |

Образец одной замены — успех:

```dart
// было
_log.i('initialized');
// стало
notifyObserver((observer) => observer.onReady(this));
```

Образец замены с отказом:

```dart
// было
_log.e('initialization failed', error: error, stackTrace: stackTrace);
// стало
notifyObserver(
  (observer) => observer.onError(
    this,
    ScopePhase.initialization,
    error,
    stackTrace,
  ),
);
```

Образец трассировки — здесь исчезает ленивость `() => '…'`, потому что строка
строится только когда наблюдатель есть, а `notifyObserver` выходит раньше,
если его нет:

```dart
// было
_log.d(() => 'wait for access to [$scopeKey]');
// стало
notifyObserver(
  (observer) => observer.onTrace(this, 'wait for access to [$scopeKey]'),
);
```

- [ ] **Шаг 4. Тесты зелёные**

```sh
fvm flutter test
```

Тесты, гонявшие журнал (`test/async_scope_coordinator_test.dart` вокруг строки
107, `test/run_stream_guarded_test.dart`), на этом шаге ещё работают: журнал не
удалён. Если какой-то упал — разобраться, а не подгонять ожидания.

- [ ] **Шаг 5. Тесты на отказы и таймаут**

Дописать в `test/scope_observer_test.dart`: инициализация, которая бросает
(`error … initialization`); утилизация, которая бросает (`error … disposal`);
истёкший таймаут (`timeout …`). Образцы сценариев — в
`test/async_scope_test.dart` и `test/async_scope_parameters_test.dart`.

- [ ] **Шаг 6. Нагруженность**

Для каждого нового теста: убрать соответствующий `notifyObserver`, убедиться,
что тест падает, вернуть.

- [ ] **Шаг 7. Проверки и коммит**

```sh
fvm flutter test
fvm flutter analyze
fvm dart format --set-exit-if-changed lib test
git add lib/src/scope/async_scope/async_scope_core.dart \
        test/scope_observer_test.dart
git commit -m "refactor: the asynchronous scope reports through the observer"
```

---

## Задача 3: зависимости и трассировка потоков

**Файлы:**
- Изменить: `lib/src/scope/full_scope/scope_auto_dependency/`
  `scope_auto_dependency.dart`
- Изменить: `lib/src/scope/full_scope/scope_auto_dependency/scope_dependency/`
  `scope_dependency_mixin.dart`
- Изменить: `lib/src/utils/stream/run_stream_guarded.dart`
- Изменить: `test/scope_observer_test.dart`

**Потребляет:** то же, что задача 2.

- [ ] **Шаг 1. Тест на контейнер зависимостей**

Тест строит скоуп с `ScopeAutoDependencies` из двух зависимостей и сверяет
список целиком:

```dart
    expect(observer.events, [
      'init _TestDependencies',
      'progress _TestDependencies dep1 (1/2)',
      'progress _TestDependencies dep2 (2/2)',
      'ready _TestDependencies',
      'dispose _TestDependencies',
      'disposed _TestDependencies',
    ]);
```

Образец контейнера — в `test/scope_auto_dependencies_test.dart`.

- [ ] **Шаг 2. Убедиться, что падает**

```sh
fvm flutter test test/scope_observer_test.dart
```

- [ ] **Шаг 3. Метка и 11 точек контейнера**

В `ScopeAutoDependencies` объявить `implements ScopeDependencies,
ScopeObservable` и метку, повторяющую сегодняшнее имя логгера:

```dart
  @override
  String get debugLabel => '$T(#${shortHash(this)})';
```

Замены:

| строка | сегодня | станет |
| --- | --- | --- |
| 98 | `d 'initialize…'` | `onInit(this)` |
| 101 | `d 'progress: $path ($step)'` | `onProgress(this, ScopeAutoDependenciesProgress(path, step))` |
| 107 | `d 'initialized'` | `onReady(this)` |
| 111 | `d 'not initialized'` | `onCancelled(this)` |
| 134 | `e 'unmount error'` | `onError(this, ScopePhase.unmount, error, stackTrace)` |
| 206 | `e 'an abandoned wait for the disposal ended in a failure'` | `onError(this, ScopePhase.abandonedWait, error, stackTrace)` |
| 222 | `e 'gave up waiting for the disposal'` | `onTimeout(this, 'the disposal')` |
| 250 | `d 'dispose…'` | `onDispose(this)` |
| 253 | `d path` | `onProgress(this, path)` |
| 256 | `e 'dispose error'` | `onError(this, ScopePhase.disposal, error, stackTrace)` |
| 276 | `d 'disposed'` | `onDisposed(this)` |

- [ ] **Шаг 4. Метка и 2 точки одной зависимости**

В `ScopeDependencyMixin` — `implements ScopeDependency, ScopeObservable`, метка
из имени зависимости (`name`), и обе точки в `onTrace`:

```dart
  @override
  String get debugLabel => name;
```

| строка | сегодня | станет |
| --- | --- | --- |
| 148 | `d '[handleError] $wrappedName'` | `onTrace(this, '[handleError] $wrappedName: $error')` |
| 196 | `d '[handlePostCancelError] $wrappedName'` | `onTrace(this, '[handlePostCancelError] $wrappedName: $error')` |

Ошибка уезжает внутрь строки: `onTrace` несёт только текст, а эти две точки
писали `error:` отдельным полем.

- [ ] **Шаг 5. Семь точек `runStreamGuarded`**

Функции нужен источник: сейчас она пишет в собственный логгер, у неё своего
`ScopeObservable` нет и не будет. Добавить необязательный параметр:

```dart
Stream<T> runStreamGuarded<T>(
  Stream<T> Function() streamFactory,
  void Function(Object, StackTrace) onPostCancelError, {
  String? debugName,
  ScopeObservable? observable,
})
```

Каждая из семи точек становится:

```dart
if (observable case final observable?) {
  notifyObserver((observer) => observer.onTrace(observable, '${label}cancel'));
}
```

Все вызовы `runStreamGuarded` в `lib/` передают `observable: this`. Найти их:

```sh
grep -rn "runStreamGuarded(" lib --include="*.dart"
```

- [ ] **Шаг 6. Тест на трассировку**

Тест с `RecordingObserver(trace: true)`, который проверяет, что трассировка
приходит и что с `trace: false` её в списке нет.

- [ ] **Шаг 7. Нагруженность, проверки и коммит**

```sh
fvm flutter test
fvm flutter analyze
fvm dart format --set-exit-if-changed lib test
git add lib/src/scope/full_scope/scope_auto_dependency/ \
        lib/src/utils/stream/run_stream_guarded.dart \
        test/scope_observer_test.dart
git commit -m "refactor: dependencies and streams report through the observer"
```

---

## Задача 4: печать, удаление журнала, зависимость

Ломающая задача: отсюда `logger_builder` исчезает из репозитория.

**Файлы:**
- Изменить: `lib/src/environment/scope_observer.dart` (добавить
  `ScopePrintObserver`)
- Удалить: `lib/src/environment/scope_logger.dart`
- Изменить: `lib/src/environment/scope_config.dart`, `lib/scopo.dart`,
  `pubspec.yaml`
- Удалить: `test/utils/logging.dart`, `test/scope_logger_test.dart`
- Изменить: `test/scope_auto_dependencies_test.dart` (звал `logInit()`),
  `test/async_scope_coordinator_test.dart`, `test/run_stream_guarded_test.dart`
- Изменить: `example/{minimal,scopo_demo,navigation_node}/lib/main.dart` и их
  `pubspec.yaml`

- [ ] **Шаг 1. Тест на печатающий наблюдатель**

```dart
  test('the print observer writes one line per event', () {
    final lines = <String>[];
    const scope = _FakeObservable('CounterScope(#4e0b7)');
    final observer = ScopePrintObserver(output: lines.add);

    observer
      ..onInit(scope)
      ..onReady(scope)
      ..onTrace(scope, 'wait for access to [key]');

    expect(lines, [
      'scopo | CounterScope(#4e0b7) | initialize…',
      'scopo | CounterScope(#4e0b7) | initialized',
    ], reason: 'a trace is silent unless trace: true');
  });
```

`_FakeObservable` — `final class _FakeObservable implements ScopeObservable`
с полем `debugLabel`, объявленный в том же тестовом файле.

- [ ] **Шаг 2. Убедиться, что падает**

```sh
fvm flutter test test/scope_observer_test.dart
```

- [ ] **Шаг 3. Написать `ScopePrintObserver`**

В `lib/src/environment/scope_observer.dart`:

```dart
/// A [ScopeObserver] that writes a line per event.
///
/// The line is `scopo | <label> | <what happened>`, and a failure adds
/// `: <error>` and the stack trace on a line of its own.
///
/// {@category debug}
final class ScopePrintObserver extends ScopeObserver {
  /// Creates an observer printing through [output].
  const ScopePrintObserver({
    this.output = print,
    this.trace = false,
  });

  /// Where a line goes; `print` by default.
  final void Function(String line) output;

  /// Whether [onTrace] is printed too.
  final bool trace;

  void _write(ScopeObservable target, String message) =>
      output('scopo | ${target.debugLabel} | $message');

  @override
  void onInit(ScopeObservable target) => _write(target, 'initialize…');

  @override
  void onProgress(ScopeObservable target, Object? progress) =>
      _write(target, 'progress: $progress');

  @override
  void onReady(ScopeObservable target) => _write(target, 'initialized');

  @override
  void onCancelled(ScopeObservable target) =>
      _write(target, 'initialization cancelled');

  @override
  void onDispose(ScopeObservable target) => _write(target, 'dispose…');

  @override
  void onDisposed(ScopeObservable target) => _write(target, 'disposed');

  @override
  void onError(
    ScopeObservable target,
    ScopePhase phase,
    Object error,
    StackTrace? stackTrace,
  ) =>
      _write(
        target,
        '${phase.name} failed: $error'
        '${stackTrace == null || stackTrace == StackTrace.empty
            ? '' : '\n$stackTrace'}',
      );

  @override
  void onTimeout(ScopeObservable target, String what) =>
      _write(target, 'gave up waiting for $what');

  @override
  void onTrace(ScopeObservable target, String message) {
    if (trace) {
      _write(target, message);
    }
  }
}
```

- [ ] **Шаг 4. Удалить журнал**

1. `rm lib/src/environment/scope_logger.dart`;
2. в `scope_config.dart` убрать `part 'scope_logger.dart';`, поле `logger`,
   метод `_reportLoggerFailure` и импорт `package:logger_builder/…`;
3. в `lib/scopo.dart`: `export 'src/environment/scope_config.dart' hide log;`
   → `hide notifyObserver`;
4. `pubspec.yaml`: убрать `logger_builder: ^0.6.1`;
5. в `lib/` убрать оставшиеся `log.withAddedName(...)` и поля `_log` — искать
   `grep -rn "_log\b\|withAddedName" lib`.

- [ ] **Шаг 5. Тесты, которые держались за журнал**

- `test/utils/logging.dart` и `test/scope_logger_test.dart` — удалить;
- `test/scope_auto_dependencies_test.dart:302` — убрать вызов `logInit()` и
  импорт;
- `test/async_scope_coordinator_test.dart` (около 107) и
  `test/run_stream_guarded_test.dart` — переписать на `RecordingObserver`;
  то, что они проверяли через публикатор, проверяется теперь событиями.

- [ ] **Шаг 6. Примеры**

В каждом из трёх `main.dart` — вместо настройки уровней и публикаторов:

```dart
  ScopeConfig.observer = const ScopePrintObserver();
```

Из `example/minimal/pubspec.yaml` и `example/scopo_demo/pubspec.yaml` убрать
`ansi_escape_codes` (он был нужен только для раскраски по уровням), из всех
трёх — транзитивный `logger_builder` уйдёт сам. Пересоздать локи:

```sh
(cd example/minimal && fvm flutter pub get)
(cd example/scopo_demo && fvm flutter pub get)
(cd example/navigation_node && fvm flutter pub get)
```

- [ ] **Шаг 7. Полный гейт §6**

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

Последняя команда упадёт: зеркала ещё не правлены. Это задача 5 — здесь
допустимо, но коммит задачи 4 и задачи 5 идут подряд, без прогона CI между
ними.

- [ ] **Шаг 8. Коммит**

`CHANGELOG.md` — строка про удаление девяти публичных имён и зависимости.

```bash
git add -u lib test example pubspec.yaml CHANGELOG.md
git add lib/src/environment/scope_observer.dart
git commit -m "feat!: the logger is gone, the observer prints in its place"
```

---

## Задача 5: документация

**Файлы:**
- Изменить: `doc/debug.md` и `docs/ru/doc/debug.md`
- Изменить: `README.md` и `docs/ru/README.md`
- Изменить: `docs/architecture.md`
- Изменить: `CHANGELOG.md`
- Изменить: `docs/backlog.md` — вычеркнуть запись владельца
- Изменить: `docs/handoff.md`

- [ ] **Шаг 1. `doc/debug.md`**

Переписать целиком: вместо уровней, публикаторов и трансформера — таблица
девяти хуков, `ScopePrintObserver`, раздел «когда падает сам наблюдатель»
(guard и защита от рекурсии), раздел «в тестах» с накопителем. 39 упоминаний
журнала не должно остаться ни одного:

```sh
grep -n "logger\|publisher\|Levels\|ScopeLog" doc/debug.md
```

- [ ] **Шаг 2. Зеркало и штамп**

```sh
grep -n "logger\|publisher" docs/ru/doc/debug.md   # должно быть пусто
sh docs/ru/stamp.sh
sh docs/ru/check.sh
```

Комментарии внутри примеров кода в зеркале тоже переводятся (`AGENTS.md` §7).

- [ ] **Шаг 3. `README.md` и его зеркало**

Раздел «Logging and configuration» — на наблюдателя; `docs/ru/README.md`
следом, затем снова `sh docs/ru/stamp.sh`.

- [ ] **Шаг 4. `docs/architecture.md`**

Абзац про `ScopeLogger` (строки ~297–300) — про `ScopeObserver`. Файл русский,
зеркала у него нет.

- [ ] **Шаг 5. Бэклог и handoff**

Из `docs/backlog.md` удалить запись владельца про `logger_builder` — работа
сделана (`AGENTS.md` §3). В `docs/handoff.md` пункт 8 «Что дальше» закрыть:
что сделано, каким коммитом, сколько тестов стало.

- [ ] **Шаг 6. Полный гейт §6 и коммит**

Все восемь команд из шага 7 задачи 4, теперь включая `sh docs/ru/check.sh`
зелёным.

```bash
git add doc/ docs/ru/ docs/architecture.md docs/handoff.md docs/backlog.md \
        CHANGELOG.md README.md
git commit -m "docs: the debug topic is about the observer now"
```

- [ ] **Шаг 7. Пуш и CI**

```sh
git push
gh run watch
```

CI — тот же гейт на 3.27.0 плюс сьюты примеров и шаг `Nothing drifted`,
который сверяет локи примеров. Если он упал — локи пересозданы не закреплённым
тулчейном; повторить `pub get` под `fvm` и закоммитить снова.

---

## Самопроверка плана

- **Покрытие спеки.** §3 (API) → задачи 1 и 4; §4 (46 точек + синхронные
  семейства) → задачи 1, 2, 3; §5 (устойчивость) → задача 1, шаг 8; §6 (тесты)
  → тесты в каждой задаче; §7 (документация) → задача 5; §8 (порядок) → пять
  задач один в один.
- **Имена сверены между задачами:** `notifyObserver`, `ScopeObservable`,
  `debugLabel`, `ScopePhase`, `RecordingObserver`, `ScopePrintObserver`
  употребляются одинаково в задачах 1–5.
- **Известное расхождение со спекой:** спека не говорит, что делать с
  синхронным отказом `init()` у несинхронных семейств. План его и не трогает —
  отказ по-прежнему уходит в границу ошибок Flutter, события для него нет.
  Если владелец захочет `onError(initialization)` и там — это отдельная правка
  после задачи 1.
