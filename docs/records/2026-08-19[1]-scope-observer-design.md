# `ScopeConfig.observer`: оповещения вместо журнала

> **Состояние на 2026-08-19:** сделано и смержено, ветка `observer`:
> `cc59355` (каркас и хуки), `348dbc6` (скоуп), `0e1cada` (зависимости и
> потоки), `a852b93` (печать, удаление журнала, `logger_builder` из
> репозитория), `5f1987e` (названия фаз по-английски) и `7d631ee`
> (документация). Дизайн выполнен целиком; разошлось одно место. §4
> обещала, что базовую пару `onInit`/`onDisposed` можно поставить в
> `ScopeWidgetElementBase` так, чтобы событие не задваивалось: это было
> написано без проверки, что `LiteScopeElementBase extends
> AsyncScopeElementBase`, — то есть асинхронные семейства наследуют базовую
> пару и никакая точка постановки от задвоения не спасает. Развёл их
> переключатель `ScopeWidgetElementBase.reportsOwnLifecycle` (`false` в базе,
> `true` на `AsyncScopeElementBase`), которого в дизайне не было.
> **Что это:** дизайн замены `ScopeConfig.logger` на `ScopeConfig.observer` —
> типизированные хуки жизненного цикла вместо строк журнала, с уходом
> `logger_builder` из зависимостей пакета.
> **Связанные записи:** `2026-08-19[2]-scope-observer-plan.md` (план работ).

## 1. Зачем

Три причины, каждая измерена, а не выведена рассуждением.

**Чужой пакет держит публичный контракт scopo.** Девять публичных имён в
`lib/src/environment/scope_logger.dart` построены на типах `logger_builder`:
`ScopeLogger extends CustomLogger`, `ScopeLevelLogger extends
CustomLevelLogger`, `ScopeLog extends CustomLog`, три typedef поверх
`CustomLogPublisher` и `LogTransformer`, `ScopeLogLevel` поверх `Levels`,
`ScopeLogCallback`. Мы
держим свежий пример в руках: `logger_builder` 0.7.0 меняет поведение
`logger[level].publisher` — и это ломающая правка **публичного API scopo**, при
том что scopo не поменяет ни строки кода. Проверено пробой на обеих версиях:
после `logger[debug].publisher = A; logger.publisher = B` на 0.6.1 всё уходит в
`B`, на 0.7.0 `debug` остаётся в `A`.

**Зависимость уже один раз держала пол платформы.** `logger_builder` 0.5.0
требовал `meta ^1.16.0`, Flutter пинит `meta` точной версией — и пол scopo
стоял на 3.29 не по своей нужде. Опускание до 3.27.0 стоило отдельной работы
(`0b39347`, `a70a550`). У пакета без внешних зависимостей такого риска нет.

**Потребителю предлагается парсить прозу.** Чтобы отправить падение
инициализации в Crashlytics или измерить время старта скоупа, сейчас нужно
поставить `publisher` и разбирать `ScopeLog.message` — строку, написанную для
человека.

## 2. Решение

`ScopeConfig.observer` — один необязательный объект с пустыми методами-хуками,
которые пакет зовёт в точках жизненного цикла. Форма — как у `BlocObserver`:
потребитель наследуется и переопределяет только нужное. Печать, которую сейчас
делает журнал, переезжает в готовый наблюдатель из комплекта, пишущий через
`print`.

`logger_builder` уходит **из репозитория целиком** — решение владельца
2026-08-19: и из `pubspec.yaml` пакета, и из трёх примеров, где печать берёт на
себя `ScopePrintObserver`. Этим же снимается с повестки переход на
`logger_builder` 0.7.0: ждать публикации больше незачем.

## 3. Публичный API

### 3.1 `ScopeObservable` — кто породил событие

```dart
abstract interface class ScopeObservable {
  /// How this object names itself in a log line.
  String get debugLabel;
}
```

Реализуют три класса пакета — те, у кого есть собственное имя в журнале:

| класс | сегодняшняя метка |
| --- | --- |
| `ScopeWidgetElementBase` (элемент любого семейства скоупов) | `widget.toStringShort(showHashCode: true)` |
| `ScopeAutoDependencies` (контейнер зависимостей) | `'$T(#${shortHash(this)})'` |
| `ScopeDependencyMixin` (одна зависимость) | своё имя зависимости |

Интерфейс намеренно не добавляется в `ScopeDependencies` и `ScopeDependency`:
их реализуют потребители, и новый обязательный член сломал бы их код. События
порождают только классы пакета, поэтому маркер нужен только им.

Потребитель, которому нужен один вид источника, сужает проверкой:
`if (target case ScopeInheritedElement(:final widget))`.

### 3.2 `ScopeObserver` — сам наблюдатель

```dart
base class ScopeObserver {
  const ScopeObserver();

  /// An initialization has begun.
  void onInit(ScopeObservable target) {}

  /// One step of an initialization is done.
  void onProgress(ScopeObservable target, Object? progress) {}

  /// An initialization has finished successfully.
  void onReady(ScopeObservable target) {}

  /// An initialization was cancelled before it finished.
  void onCancelled(ScopeObservable target) {}

  /// A teardown has begun.
  void onDispose(ScopeObservable target) {}

  /// A teardown has finished.
  void onDisposed(ScopeObservable target) {}

  /// Something failed. [phase] says what was running.
  void onError(
    ScopeObservable target,
    ScopePhase phase,
    Object error,
    StackTrace? stackTrace,
  ) {}

  /// A bounded wait expired. [what] names what was waited for.
  void onTimeout(ScopeObservable target, String what) {}

  /// A step of the internal machinery, below the lifecycle.
  void onTrace(ScopeObservable target, String message) {}
}
```

`base class`, а не `abstract`: потомок обязан быть `final`/`base`, что отвечает
стилю пакета, а пустые тела позволяют переопределить один метод из девяти.

`Object? progress` — потому что полезная нагрузка у разных источников разная и
уже типизирована по-своему: у скоупа это `state.progress` (что вернул
`initScope`), у контейнера зависимостей — `ScopeAutoDependenciesProgress(path,
step)`. Оборачивать это в общий тип значит выдумать третий.

### 3.3 `ScopePhase` — что именно упало

```dart
enum ScopePhase {
  initialization,
  initializationCancellation,
  preparationForDisposal,
  unmount,
  disposal,
  abandonedWait,
}
```

Шесть значений — ровно те отказы, которые пакет сегодня различает текстом
сообщения (`initialization failed`, `initialization cancellation failed`,
`preparation for disposal failed`, `unmount failed`, `disposal failed`,
`an abandoned wait for … ended in a failure`). Enum расширяется, и потребителю
стоит писать `switch` с `default`; это сказано в дартдоке.

### 3.4 `ScopePrintObserver` — печать из комплекта

```dart
final class ScopePrintObserver extends ScopeObserver {
  const ScopePrintObserver({
    this.output = print,
    this.trace = false,
  });

  final void Function(String line) output;

  /// Whether [ScopeObserver.onTrace] is printed too.
  final bool trace;
}
```

Формат строки повторяет сегодняшний `ScopeLogger.defaultFormat` без уровня и
без пути логгера:

```text
scopo | CounterScope(#4e0b7) | initialized
scopo | CounterScope(#4e0b7) | initialization failed: Exception: no network
scopo | TestDependencies(#25f53) | progress: dep1 (1/10)
```

`trace: false` по умолчанию — это замена порогу: сегодня `level = info`
отсекает ровно то, что теперь уходит в `onTrace`.

### 3.5 `ScopeConfig.observer`

```dart
static ScopeObserver? observer;
```

`null` по умолчанию — пакет молчит, как сегодня молчит журнал на
`ScopeLogLevel.off`. `ScopeConfig.reset()` наблюдателя не трогает, ровно по той
же причине, по которой не трогал журнал: это объект, а не выключатель, и он
обычно и есть смысл прогона, ради которого его поставили.

## 4. Куда переезжают 46 точек журнала

Полный разбор всех сегодняшних вызовов.

### Скоуп — `ScopeWidgetElementBase` и `AsyncScopeElementBase` (26 точек)

| сегодня | станет |
| --- | --- |
| `d 'prepare for initialization'` | `onTrace` |
| `d 'wait for access to [key]'` | `onTrace` |
| `d 'access to [key] obtained'` / `cancelled` | `onTrace` |
| `i 'initialize…'` | `onInit` |
| `i 'progress: …'` | `onProgress` |
| `i 'initialized'` | `onReady` |
| `i 'initialization cancelled'` (2 точки) | `onCancelled` |
| `e 'initialization failed'` (2 точки) | `onError(initialization)` |
| `e 'not initialized'` | `onError(initialization)` |
| `e 'initialization cancellation failed'` | `onError(initializationCancellation)` |
| `e 'preparation for disposal failed'` | `onError(preparationForDisposal)` |
| `e 'unmount failed'` | `onError(unmount)` |
| `i 'dispose…'` | `onDispose` |
| `i 'disposed'` | `onDisposed` |
| `e 'disposal failed'` | `onError(disposal)` |
| `d 'do not dispose of'` | `onTrace` |
| `d 'exit from [key]'` | `onTrace` |
| `d 'prepare for disposal'` | `onTrace` |
| `d 'cancel waiting for access to [key]'` | `onTrace` |
| `d 'wait for initialization'` | `onTrace` |
| `e 'gave up waiting for $what'` | `onTimeout` |
| `e 'an abandoned wait for $what ended in a failure'` | `onError(abandonedWait)` |

### Контейнер зависимостей — `ScopeAutoDependencies` (11 точек)

| сегодня | станет |
| --- | --- |
| `d 'initialize…'` | `onInit` |
| `d 'progress: $path ($step)'` | `onProgress` |
| `d 'initialized'` | `onReady` |
| `d 'not initialized'` | `onCancelled` |
| `e 'unmount error'` | `onError(unmount)` |
| `e 'an abandoned wait for the disposal ended in a failure'` | `onError(abandonedWait)` |
| `e 'gave up waiting for the disposal'` | `onTimeout` |
| `d 'dispose…'` | `onDispose` |
| `d '$path'` (шаг утилизации) | `onProgress` |
| `e 'dispose error'` | `onError(disposal)` |
| `d 'disposed'` | `onDisposed` |

### Синхронные семейства — событий не было, появятся

Решение владельца 2026-08-19: наблюдатель оповещает о **любом** скоупе, а не
только об асинхронном. Сегодня `Scope`, `LiteScope`, `ScopeModel` и
`ScopeNotifier` не пишут в журнал ни строки — их жизненный цикл виден только
отладчику.

Стоит это одной пары вызовов: `onInit` и `onDisposed` в `init()` и `dispose()`
общего предка `ScopeWidgetElementBase`, откуда наследуются элементы всех
семейств. Асинхронные семейства зовут те же хуки в своих местах, поэтому пара в
базовом классе ставится так, чтобы событие не задваивалось: базовый `onInit`
отмечает синхронную фазу, а `AsyncScopeElementBase` — свою, асинхронную.

Это единственное место дизайна, где появляется поведение, которого раньше не
было; в `CHANGELOG.md` оно идёт отдельной строкой.

### Одна зависимость — `ScopeDependencyMixin` (2 точки)

`d '[handleError] …'` и `d '[handlePostCancelError] …'` → `onTrace`.

### `runStreamGuarded` (7 точек verbose)

Все семь → `onTrace`. Источником для них служит скоуп или зависимость, внутри
которых крутится поток; сама функция `ScopeObservable` не реализует, потому что
она не объект, а вызов.

Это же закрывает попутную находку: дартдок `ScopeLogLevel.verbose` обещает
«Registered, but unused by the package», а `runStreamGuarded` пишет на нём семь
раз. С уходом уровней обещание исчезает вместе с классом.

## 5. Устойчивость: наблюдатель — код потребителя

Ровно та проблема, которую закрыл `c3abfdc` для журнала, возвращается в новом
месте: наблюдатель может бросить, а зовут его из билда, из инициализации и из
разбора. Значит с самого начала:

- каждый вызов хука идёт через одну внутреннюю обёртку с `try`/`catch`;
  пойманное уходит в `FlutterError.reportError` с `library: 'scopo'` и
  `ErrorDescription('while notifying a scope observer')` — красный экран в
  debug, `FlutterError.onError` в release, и вызывающий продолжается;
- обёртка держит флаг «уже оповещаю»: наблюдатель, который сам порождает
  событие (создаёт скоуп из хука), иначе уходит в бесконечную рекурсию. Второй
  вход отбивается и репортится один раз, как у журнала отбивалась публикация в
  тот же уровень.

## 6. Тесты

По регламенту §8 каждый пункт — сперва падающий тест.

1. По одному тесту на хук на каждый источник: скоуп (`onInit`, `onProgress`,
   `onReady`, `onCancelled`, `onDispose`, `onDisposed`, `onError` каждой из
   шести фаз, `onTimeout`), контейнер зависимостей, одна зависимость.
   Наблюдатель-накопитель в `test/utils/`, сравнение списка событий целиком —
   так ловится и лишнее событие, и пропущенное.
2. Синхронные семейства: `Scope`, `LiteScope`, `ScopeModel`, `ScopeNotifier` —
   каждое даёт `onInit` и `onDisposed` ровно по разу, и ни одно не задваивает
   события с асинхронной половиной.
3. Наблюдатель бросает из каждого хука — скоуп доходит до готового состояния,
   разбор доходит до конца, отказ виден в `FlutterError.onError`.
4. Наблюдатель порождает событие из хука — рекурсия обрывается, репорт один.
5. `ScopePrintObserver`: формат строки, `trace: false` молчит на `onTrace`,
   `trace: true` печатает, `output` перенаправляется.
6. `ScopeConfig.observer = null` — ни одного вызова, ноль накладных расходов на
   пути (проверяется тем, что накопитель пуст, а не замером).
7. `ScopeConfig.reset()` наблюдателя не трогает.

Нагруженность каждого теста проверяется откатом правки, как заведено.

## 7. Документация

- `doc/debug.md` — переписывается целиком (39 упоминаний журнала): вместо
  уровней, публикаторов и трансформера — наблюдатель, таблица хуков, готовый
  `ScopePrintObserver`, раздел про отказ наблюдателя;
- `docs/ru/doc/debug.md` — зеркало в том же коммите, `sh docs/ru/stamp.sh`,
  затем `sh docs/ru/check.sh`;
- `README.md` — раздел «Logging and configuration» (5 упоминаний) переписать на
  наблюдателя, `docs/ru/README.md` следом;
- `docs/architecture.md` — абзац про `ScopeLogger` (6 упоминаний);
- `CHANGELOG.md`, раздел 0.10.0 — ломающая правка: девять имён удалены,
  `logger_builder` больше не зависимость, взамен `ScopeConfig.observer`;
- `example/minimal`, `example/scopo_demo` и `example/navigation_node` —
  `ScopePrintObserver` вместо настройки публикаторов, `logger_builder` и
  `ansi_escape_codes` уходят из их `pubspec.yaml` вместе с раскраской по
  уровням; локи трёх примеров пересоздаются закреплённым тулчейном.

## 8. Порядок работ

Пять шагов, каждый заканчивается зелёным гейтом §6.

1. **Каркас.** `ScopeObservable`, `ScopeObserver`, `ScopePhase`,
   `ScopeConfig.observer`, обёртка с `try`/`catch` и флагом рекурсии, тесты 2 и
   3 из раздела 6. Журнал ещё на месте, ничего не удалено.
2. **Скоуп.** 26 точек `AsyncScopeElementBase` переезжают на хуки, и там же
   появляется пара `onInit`/`onDisposed` в `ScopeWidgetElementBase` — та самая,
   что делает видимыми синхронные семейства. С тестами на обе половины и на
   отсутствие задвоения.
3. **Зависимости.** 11 + 2 + 7 точек: контейнер, одна зависимость,
   `runStreamGuarded`.
4. **Печать и удаление журнала.** `ScopePrintObserver`, удаление
   `scope_logger.dart` и девяти имён, `logger_builder` из `pubspec.yaml`,
   примеры на наблюдателя.
5. **Документация.** `doc/debug.md` с зеркалом, `README.md` с зеркалом,
   `docs/architecture.md`, `CHANGELOG.md`.

Шаги 1–3 не ломают ничего: журнал и наблюдатель какое-то время работают рядом.
Ломающий — четвёртый, и он же снимает зависимость.

## 9. Что решено по ходу и почему

- **Хуки, а не sealed-события.** Новый хук с пустым телом не ломает чужой код,
  а новый потомок `sealed class` ломает исчерпывающий `switch` у каждого
  потребителя. Аллокации объекта события на каждый шаг тоже нет.
- **Девять хуков, а не двадцать.** Один хук на лог-строку дал бы API размером с
  сегодняшний журнал. Отладочная мелочь собрана в `onTrace`, отказы — в один
  `onError` с `ScopePhase`.
- **`onTrace` вместо удаления трассировки.** Семь точек `runStreamGuarded` и
  две в миксине зависимостей писались не зря; выбросить их значит потерять то,
  чем отлаживали, ничего не выиграв. Пустой хук по умолчанию стоит ноль.
- **Метка (`debugLabel`) в интерфейсе источника, а не параметром хука.** Иначе
  каждый потребитель, пишущий свой наблюдатель, повторял бы `switch` по типам,
  который пакет и так умеет.
- **Порога уровней нет.** Его роль делят `null`-наблюдатель (всё выключено),
  пустые тела хуков (интересует только часть) и флаг `trace`.

## 10. Решения владельца

Приняты 2026-08-19, в разговоре, и дизайн выше уже им отвечает.

1. **Форма API — хуки, как у `BlocObserver`**, а не sealed-события; в комплекте
   готовый наблюдатель, печатающий через `print`.
2. **`logger_builder` уходит из репозитория полностью**, включая примеры.
   Переход на 0.7.0 отменён вместе с зависимостью.
3. **Наблюдатель оповещает обо всех семействах скоупов**, а не только об
   асинхронных, как это делал журнал.
4. **Отладочная трассировка сохраняется** — 16 точек уходят в `onTrace`, по
   умолчанию молчащий.
5. **Имена пар — `onInit`/`onReady` и `onDispose`/`onDisposed`**: `Ready` уже
   устоялось в API пакета (`buildOnReady`, `buildOnProgress`, `buildOnError`),
   и наблюдатель говорит на том же языке.
6. **Момент — сейчас**, пока 0.10.0 не опубликована (на pub.dev последняя
   0.9.6). Работа ломающая; сделанная сейчас, она не стоит потребителю ни
   одного лишнего перехода.

Открытых вопросов не осталось.
