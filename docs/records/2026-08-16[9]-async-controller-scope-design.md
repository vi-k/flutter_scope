# AsyncControllerScope: устройство

> **Состояние на 2026-08-16:** согласовано с владельцем, не реализовано.
> **Что это:** спека нового семейства скоупов для контроллера с собственным
> жизненным циклом, плюс сопутствующее снятие буквенных префиксов с имён
> файлов.
> **Связанные записи:** `2026-08-16[7]-init-cancellation-timeout-report.md` и
> `2026-08-16[8]-dispose-async-timeout-report.md` (лимиты, на которые семейство
> опирается), `2026-08-14[10]-project-review.md`.

## Зачем

Пункт бэклога владельца: нужен шаблон скоупа для асинхронного контроллера,
пример разделения UI и логики. Разбор боевого кода владельца
(`CarsOnMap` + `CarsOnMapController` в приложении такси) показал, что шаблон
уже сложился и что он стоит дорого:

- **обвязка.** Скоуп поверх `AsyncDataScopeBase` — около сорока строк, из шести
  переопределений четыре тривиальны (`onUnmount`, `disposeData` и два билдера,
  возвращающих `SizedBox.shrink()`);
- **дыра, в которую шаблон заводит сам.** Контроллер создаётся внутри
  генератора `initData`, поэтому скоуп узнаёт о нём только из
  `yield AsyncDataScopeReady(controller)`. Если `init()` контроллера упал или
  скоуп ушёл с дерева, пока `init()` ещё шёл, до `yield` дело не доходит:
  `onUnmount(null)` ничего не делает, `disposeData` не зовётся вовсе
  (`_performAsyncDispose` зовёт `disposeAsync` только при `_initSucceeded`), —
  и контроллер с уже поднятыми подписками живёт дальше, продолжая дёргать
  чужие объекты. В боевом коде эта дыра открыта.

Семейство существует ради второго пункта. Обвязка — приятное следствие;
гарантия разбора — причина.

## ScopeController

```dart
/// {@category AsyncControllerScope}
abstract base class ScopeController {
  bool _mounted = false;
  bool _disposed = false;

  /// Whether the controller is between the start of its initialization and
  /// the moment the scope let go of it.
  bool get mounted => _mounted;

  //
  // Called by the scope. Sealed.
  //

  @nonVirtual
  Future<void> performInit() async {
    _mounted = true;
    await init();
  }

  @nonVirtual
  void performUnmount() {
    if (!_mounted) return;
    _mounted = false;
    onUnmount();
  }

  @nonVirtual
  Future<void> performDispose() async {
    if (_disposed) return;
    _disposed = true;
    performUnmount();
    await dispose();
  }

  //
  // Written by the author of the controller. No `super`, no order to remember.
  //

  Future<void> init() async {}
  void onUnmount() {}
  FutureOr<void> dispose() {}
}
```

Решения и их причины:

- **`init`/`onUnmount`/`dispose` наружу, обёртки закрыты.** Автор контроллера
  не обязан помнить «вызвать `super` первым» — это соглашение, которое можно
  забыть, и в боевом коде оно держится на комментарии. `@nonVirtual` делает
  переопределение обёртки предупреждением анализатора, тем же приёмом, что
  волна 4 применила к `State.dispose`.
- **Имена совпадают с `ScopeDependencies`** (`void onUnmount()`,
  `FutureOr<void> dispose()`): контроллер — такой же объект, которым владеет
  скоуп, и читается он так же.
- **Обёртки публичны.** Внутри пакета это безразлично — библиотека одна, — но
  публичные обёртки оставляют контроллер управляемым вручную: в юнит-тесте
  `await controller.performInit(); … await controller.performDispose();` даёт
  настоящий жизненный цикл вместе с `mounted`.
- **`mounted` становится `true` до `init()`**, чтобы проверки после каждого
  `await` внутри `init()` работали.
- **`performUnmount` и `performDispose` идемпотентны.** Скоуп и так зовёт
  каждую ровно один раз, но идемпотентность — проверяемое свойство, а не
  рассуждение о путях.
- **`dispose()` обязан ожидать частично проинициализированный контроллер** —
  тот же контракт, что у зависимостей пакета: `init()` мог упасть на середине,
  успев что-то занять.

## Скоуп: три слоя

Как у `AsyncDataScope`.

| слой | что даёт |
| --- | --- |
| `AsyncControllerScopeCore<W, E, C>` + `AsyncControllerScopeElementBase<W, E, C>` | свой элемент; всё поведение семейства живёт здесь. Элемент объявляет `C createController(BuildContext context)` точкой переопределения; форма `Base` пробрасывает её в `widget.createController(this)`, конструкторная — в `widget.create(this)` |
| `AsyncControllerScopeBase<W, C>` | наследованием: `createController` и переопределяемые билдеры |
| `AsyncControllerScope<C>` | конструктором: `create:` и билдеры параметрами |

Наследуется от машинерии `AsyncDataScope`, поэтому контроллер бесплатно
достаётся поддереву (`of`, `maybeOf`, `select`, `data`) и попадает в
`debugFillProperties`. `scopeKey`, `tag`, `child`, все четыре таймаута и
`pauseAfterInitialization` — как у всех.

Наследование: `AsyncControllerScopeCore<W, E, C> extends AsyncDataScopeCore<W, E, C>`,
`AsyncControllerScopeElementBase<W, E, C> extends AsyncDataScopeElementBase<W, E, C>`,
`C extends ScopeController`.

## Жизненный цикл и гарантия

Элемент семейства реализует `initDataAsync()` сам — это и есть вся суть:

```dart
C? _controller;

@override
Stream<AsyncDataScopeInitState<Object, C>> initDataAsync() async* {
  final controller = _controller = createController(this);

  try {
    await controller.performInit();

    yield AsyncDataScopeReady(controller);
  } on Object catch (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(exception: error, stack: stackTrace, library: 'scopo'),
    );
    rethrow;
  } finally {
    // Критерий — тот же признак, по которому `_performAsyncDispose` решает,
    // звать ли `disposeAsync`. Свой флаг здесь врёт: событие могли выбросить
    // уже после `yield`.
    if (!_initSucceeded) await controller.performDispose();
  }
}

@override
void onUnmount() {
  super.onUnmount();
  _controller?.performUnmount();
}

@override
FutureOr<void> disposeAsync() => _controller?.performDispose();
```

**Почему критерий именно `_initSucceeded`, а не локальный флаг.** После `yield`
событие идёт вниз по цепочке: `.map` в `AsyncDataScopeElementBase` кладёт
значение в `_data`, и только потом колбэк `asyncMap` в `_performAsyncInit`
ставит `_initSucceeded`. `asyncMap` на время своего колбэка приостанавливает
источник, так что окно между «сгенерировали» и «скоуп принял» существует, а
отмена в этом окне событие выбрасывает — после `cancel()` доставки нет. Флаг,
поставленный рядом с `yield`, в этом случае соврёт: скажет «отдал», хотя
`disposeAsync` не будет вызван никогда. Поле `_initSucceeded` — приватное поле
той же библиотеки, и разъехаться два решения не могут по построению.

Что получается на каждом пути:

| путь | `performUnmount` | `performDispose` |
| --- | --- | --- |
| элемент снят до начала асинхронной фазы | контроллера нет | контроллера нет |
| `init()` контроллера бросил | из `onUnmount` скоупа | из `finally` |
| скоуп ушёл, пока шёл `init()` | из `onUnmount` скоупа | из `finally` при отмене |
| событие готовности выброшено отменой | из `onUnmount` скоупа | из `finally` |
| обычный: готов, потом ушёл | из `onUnmount` скоупа | из `disposeAsync` |

Порядок «сначала `onUnmount`, потом `dispose`» держится сам собой:
`_performAsyncDispose` зовёт `unmountScope()` синхронно и первым, отмену
подписки — вторым шагом, `disposeAsync()` — третьим.

Зависший контроллер запереть `scopeKey` не может: ожидание `finally` при отмене
ограничено `initCancellationTimeout` (волна 7), ожидание `disposeAsync` —
`disposeAsyncTimeout` (волна 8).

## Билдеры и ошибка инициализации

Прогресса у семейства нет по построению: `init()` — это `Future<void>`, поток
никаких `AsyncDataScopeProgress` не выдаёт. Поэтому параметра `progress` в
билдерах нет:

```dart
Widget? buildOnWaiting(BuildContext context);
Widget buildOnInitializing(BuildContext context);
Widget buildOnError(BuildContext context, Object error, StackTrace stackTrace);
Widget buildOnReady(BuildContext context, C controller);
```

Значения по умолчанию: готово — `child` (он обязателен в `Base` и в
конструкторной форме, семейство существует ради обёртывания поддерева),
остальные ветки — `const SizedBox.shrink()`.

**Провал `init()` репортится через `FlutterError.reportError` один раз, в
момент падения.** Это сознательное отличие от `AsyncScope` и `AsyncDataScope`,
где ошибка приезжает только в `buildOnError`. Причина в типичной форме этого
семейства: его билдеры обычно ничего не рисуют (скоуп владеет побочными
эффектами, а не экраном), и молча съеденный провал инициализации — не
гипотетическая, а уже случившаяся в боевом коде ошибка. `buildOnError` при этом
получает ошибку как обычно, так что показать что-то на экране никто не мешает.

## Чего семейство не делает

- **Наблюдаемости не даёт.** Контроллер — владелец побочных эффектов, а не
  источник значений для виджетов; нужен `Listenable` — ставьте под скоупом
  `ScopeNotifier.value`.
- **Прогресса инициализации не даёт.** Нужен — берите `AsyncDataScope`
  напрямую.

Обе границы держат семейство отличимым от `AsyncDataScope`; без них оно
расплывётся в его дубликат.

## Размещение и порядок

`AsyncControllerScope` встаёт **сразу после `AsyncDataScope`**: в
`categoryOrder` в `dartdoc_options.yaml`, в списке семейств `README.md`,
вкладкой в `scopo_demo`.

Код — `lib/src/scope/async_controller_scope/`: `scope_controller.dart`,
`async_controller_scope_core.dart`, `async_controller_scope_base.dart`,
`async_controller_scope.dart`. Документация — `doc/async_controller_scope.md` и
зеркало `docs/ru/doc/async_controller_scope.md`.

## Снятие буквенных префиксов

Отдельная работа, делается **первой**, чтобы ни один файл не переименовывался
дважды. Поведение не меняется.

| что | сколько |
| --- | --- |
| папки `lib/src/scope/*` | 8 (`a_base` → `base`, …) |
| строки `part` и один `import` в `lib/src/scope/scope.dart` | ~40 |
| страницы `doc/*.md` | 10 |
| зеркала `docs/ru/doc/*.md` | 10 |
| шапки зеркал (`> Перевод \`doc/…\``) | 10 |
| пути в `dartdoc_options.yaml` | 10 |
| папки демо в `example/scopo_demo/lib/home/demos/*` и импорты | 9 папок |

Ссылок на буквенные имена в прозе документации нет — проверено: единственные
упоминания это шапки зеркал. Порядок страниц задан `categoryOrder`, а не
именами файлов, поэтому от снятия букв ничего не сдвигается. Записи в
`docs/records/` — исторические, их не правим.

После переименования — `sh docs/ru/stamp.sh` (хеши оригиналов не меняются, но
пути в шапках да) и полный гейт.

## Тесты

Отдельный файл `test/async_controller_scope_test.dart`.

Обязательные сценарии — по строке на каждый путь из таблицы выше:

1. обычный путь: `init` → готово → построен `child`; при уходе с дерева
   `onUnmount` и затем `dispose`, каждый ровно один раз, в этом порядке;
2. `init()` бросил: построена ветка ошибки, `onUnmount` и `dispose` всё равно
   выполнены, провал отрепорчен;
3. скоуп ушёл, пока шёл `init()`: готовности не было, `onUnmount` и `dispose`
   выполнены;
4. идемпотентность: повторные `performUnmount` и `performDispose` ничего не
   делают; `mounted` меняется в заявленных точках;
5. конструкторная форма: `create` вызван один раз, контроллер достаётся
   поддереву через `of`.

Пятый путь — **событие готовности выброшено отменой** — детерминированно
воспроизводится тяжело: окно между `yield` и колбэком `asyncMap` измеряется
микрозадачами. План: попытаться собрать его ручным управлением биндингом, как
это сделано в `test/async_scope_test.dart` для гонок с post-frame-колбэками.
Если детерминированно не выйдет — покрыть критерий мутацией (заменить
`_initSucceeded` локальным флагом и показать, какой тест падает) и честно
записать в отчёте, что отдельного теста на этот путь нет.

Мутации для проверки нагруженности: убрать `performDispose` из `finally`;
заменить критерий локальным флагом; убрать `_controller?.performUnmount()` из
`onUnmount`; снять идемпотентность.

## План работ

Три коммита:

1. `refactor:` снять буквенные префиксы (механика, поведение не меняется);
2. `feat:` семейство: `ScopeController`, три слоя, тесты, страница
   документации с зеркалом, раздел README;
3. `feat:` демо в `scopo_demo` сразу после вкладки `AsyncDataScope` и короткий
   пример в README.

## Риски

- **Новая публичная поверхность перед выпуском.** 0.10.0 ещё не опубликована;
  семейство войдёт в неё и попадёт под повторное полное ревью — это скорее
  плюс, но выпуск отодвигается.
- **Опора на приватное поле чужого слоя.** Элемент семейства читает
  `_initSucceeded` из `AsyncScopeElementBase`. Внутри одной библиотеки это
  законно, но связь неявная; в коде она закрыта комментарием, а в тестах —
  мутацией.
- **Отличие в репорте ошибки** от двух соседних семейств придётся объяснять в
  документации каждый раз, когда кто-то сравнит.
