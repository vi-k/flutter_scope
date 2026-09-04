# План: инициализация без асинхронных генераторов

> **Состояние на 2026-09-04:** план написан, работа не начата.
> **Что это:** порядок работ по спеке — замена `Stream`-формы инициализации на
> `Future` с контекстом во всех семействах, релиз 0.14.0.
> **Связанные записи:** `2026-09-04[1]-init-context-design.md` — спека, из
> которой этот план следует; читать её обязательно, план на неё опирается и её
> не пересказывает.

> **Исполнителю:** задачи идут по порядку, каждая кончается зелёным гейтом и
> коммитом. Шаги помечены `- [ ]`. Не переходи к следующей задаче, пока
> предыдущая не закоммичена.

**Цель.** Инициализация во всех семействах пишется как обычная `Future`:
прогресс через `ctx.progress(x)`, результат через `return`, отмена
кооперативная через контекст. Асинхронные генераторы уходят из публичной
формы.

**Устройство.** Между телом и движком стоит адаптер `_runScopeInit`, который
собирает из тела тот же `Stream<AsyncScopeInitState>`, что движок ест сегодня.
`AsyncScopeCore` (1391 строка) не меняется ни в одной задаче — если в ходе
работы кажется, что его надо тронуть, это повод остановиться и перечитать
спеку, а не править.

**Тулчейн.** Flutter 3.27.0 через fvm (`.fvmrc`), Dart 3.6.0 — это пол, и
проверки идут на нём.

## Общие ограничения

- Пол SDK: `sdk: ^3.6.0`, Flutter 3.27.0. Два вайлдкарда подряд (`_`, `_`) —
  это 3.7, на полу они не собираются; второй параметр называть `__`.
- Язык: код, дартдоки, `CHANGELOG.md`, `README.md` и сообщения коммитов — по-
  английски; `docs/` — по-русски.
- Правка оригинала публичного документа не заканчивается без правки зеркала в
  `docs/ru/` **в том же коммите**, после чего `sh docs/ru/stamp.sh`.
- Правка в `lib/` не заканчивается без строки в `CHANGELOG.md`.
- Гейт §6 целиком — перед каждым коммитом, который трогает `lib/`:

  ```sh
  fvm flutter test
  fvm flutter analyze
  (cd example/minimal && fvm flutter analyze)
  (cd example/scopo_demo && fvm flutter analyze)
  fvm dart format --set-exit-if-changed lib test
  fvm dart doc --dry-run
  fvm dart pub publish --dry-run
  sh docs/ru/check.sh
  ```

- Дефект — сперва падающий тест, потом исправление. Исправил — откати
  исправление и убедись, что тест падает.

## Карта файлов

**Создаётся:**

- `lib/src/scope/async_scope/scope_init_context.dart` — `ScopeInitContext`,
  `ScopeInitCancelled`, приватная реализация контекста и адаптер
  `_runScopeInit`. Одна ответственность: превратить тело в стрим, который ест
  движок.
- `test/scope_init_context_test.dart` — тесты самого контекста и адаптера
  через ближайшее семейство.

**Меняется:**

- `lib/src/scope/scope.dart` — строка `part`.
- `lib/src/scope/async_scope/async_scope_core.dart:131` — только сигнатура
  `initScope` и её дефолт. Больше в этом файле не трогается ничего.
- `lib/src/scope/async_scope/async_scope_base.dart`,
  `lib/src/scope/async_scope/async_scope.dart` — форма `initScope`.
- `lib/src/scope/async_data_scope/*` — форма `initData`/`initDataAsync`,
  удаление `async_data_scope_init_state.dart`.
- `lib/src/scope/async_controller_scope/async_controller_scope_core.dart` —
  обёртка контроллера, с переносом освобождения (см. задачу 3).
- `lib/src/scope/lite_scope/lite_scope_base.dart:99,294`,
  `lite_scope_core.dart:141` — форма `initScope`.
- `lib/src/scope/full_scope/*` — форма `initDependencies`, удаление
  `scope_init_state.dart` и расширения `asStream`.
- `lib/src/scope/full_scope/scope_auto_dependency/scope_auto_dependency.dart` —
  переход с `async*` на `Future` с подпиской и `ctx.onCancel`.

**Удаляется:**

- `lib/src/scope/async_data_scope/async_data_scope_init_state.dart`
- `lib/src/scope/full_scope/scope_init_state.dart`
- расширение `ScopeDependenciesExtension` в
  `lib/src/scope/full_scope/scope_dependencies.dart`

---

### Задача 1: контекст, адаптер и семейство `AsyncScope`

Адаптер без потребителя не проверить, поэтому первое семейство идёт вместе с
ним. Черновик обоих лежит в ветке `spike/init-without-generators`
(`35c7443`) — его можно взять оттуда, но каждый комментарий перечитать: он
писался для `AsyncDataScope`.

**Файлы:**

- Создать: `lib/src/scope/async_scope/scope_init_context.dart`
- Изменить: `lib/src/scope/scope.dart` (строка `part` после
  `part 'async_scope/async_scope_state.dart';`)
- Изменить: `lib/src/scope/async_scope/async_scope_core.dart:131`,
  `async_scope_base.dart:101`, `async_scope.dart`
- Тест: `test/scope_init_context_test.dart`, `test/async_scope_test.dart`

**Интерфейсы, на которые опираются следующие задачи:**

```dart
abstract interface class ScopeInitContext {
  void progress(Object progress);
  bool get isCancelled;
  void check();
  Future<T> wait<T>(FutureOr<T> Function() action);
  void Function() onCancel(void Function() callback);
}

final class ScopeInitCancelled implements Exception {
  const ScopeInitCancelled();
}

/// Приватный, доступен всем семействам как part одной библиотеки.
Stream<S> _runScopeInit<S extends Object, T>({
  required Future<T> Function(ScopeInitContext ctx) body,
  required S Function(Object progress) progressState,
  required S Function(T value) readyState,
  required FutureOr<void> Function(T value) releaseLateValue,
});
```

- [ ] **Шаг 1. Падающий тест на форму и на отмену**

`test/scope_init_context_test.dart`:

```dart
testWidgets('reports progress from a nested function', (tester) async {
  Future<void> openStorage(ScopeInitContext ctx) async {
    ctx.progress('opening storage');
    await Future<void>.delayed(Duration.zero);
  }

  await tester.pumpWidget(
    _Host(init: (context, ctx) => openStorage(ctx)),
  );
  await tester.pump();
  await tester.pump();

  expect(find.text('initializing: opening storage'), findsOneWidget);
});

testWidgets('a scope that leaves the tree cancels the body where it waits',
    (tester) async {
  final log = <String>[];
  final gate = Completer<void>();

  await tester.pumpWidget(
    _Host(
      init: (context, ctx) async {
        try {
          await ctx.wait(() => gate.future);
          log.add('past the wait');
        } finally {
          log.add('finally');
        }
      },
    ),
  );
  await tester.pump();

  await tester.pumpWidget(const SizedBox.shrink());
  await settle(tester, until: () => log.contains('finally'));

  expect(log, ['finally']);
  expect(gate.isCompleted, isFalse);
});
```

`_Host` — обёртка над `AsyncScope` с новой формой `initScope`.

- [ ] **Шаг 2. Убедиться, что тест падает**

`fvm flutter test test/scope_init_context_test.dart` — ожидается провал
компиляции: `ScopeInitContext` не объявлен.

- [ ] **Шаг 3. Написать контекст и адаптер**

Взять из `35c7443` файл `lib/src/scope/async_scope/scope_init_context.dart`
целиком. Три места в нём — не украшение, менять их нельзя, не прочитав
причину в комментарии:

1. `unawaited(controller.close())` — ждать закрытия нельзя: `onCancel` зовётся
   и при нормальном завершении стрима, и ожидание закрытия образует дедлок с
   самим собой;
2. `onCancel` возвращает `running` — это то, чего ждёт `subscription.cancel()`,
   и через что работает `initCancellationTimeout`;
3. ветка `if (ctx.isCancelled)` после `await body(ctx)` — освобождение
   позднего значения.

- [ ] **Шаг 4. Перевести `AsyncScope` на новую форму**

Слоёв два, и путать их нельзя. **Элемент** отдаёт движку стрим — это вход
`AsyncScopeCore`, и он остаётся стримом. **Виджет** держит форму, которую
пишет пользователь. Ровно так уже устроен `AsyncDataScope`
(`async_data_scope_core.dart:110` — `@nonVirtual initScope()` поверх
`initDataAsync()`), и новая раскладка это повторяет, а не выдумывает.

`async_scope_core.dart:131`, элемент — старый метод запечатывается и
собирается адаптером, рядом появляется новый:

```dart
  /// Sealed: this is where the body is turned into the stream the engine
  /// consumes. The hook to write is [initScopeAsync].
  @nonVirtual
  Stream<AsyncScopeInitState> initScope() =>
      _runScopeInit<AsyncScopeInitState, void>(
        body: initScopeAsync,
        progressState: AsyncScopeProgress.new,
        readyState: (_) => AsyncScopeReady(),
        releaseLateValue: (_) => disposeScope(),
      );

  /// The initialization; ready at once by default.
  Future<void> initScopeAsync(ScopeInitContext ctx) async {}
```

`async_scope_base.dart:101`, виджет:

```dart
  /// The initialization.
  ///
  /// Reports its steps through [ScopeInitContext.progress] and returns when
  /// the scope is ready.
  Future<void> initScope(BuildContext context, ScopeInitContext ctx);
```

`async_scope_base.dart`, элемент семейства — делегирование, как у соседей
(`lite_scope_base.dart:294` делает то же самое одной строкой):

```dart
  @override
  Future<void> initScopeAsync(ScopeInitContext ctx) =>
      widget.initScope(this, ctx);
```

`releaseLateValue` здесь — `disposeScope()`: у этого семейства значения нет,
но «поздний» конец инициализации всё равно означает, что тело успело взять
ресурсы, и отдать их некому, кроме `disposeScope`.

- [ ] **Шаг 5. Прогон тестов**

`fvm flutter test test/scope_init_context_test.dart test/async_scope_test.dart`
— зелено. `async_scope_test.dart` (52 КБ) правится в этом же шаге: все
`initScope: (context) async* { … yield AsyncScopeReady(); }` становятся
`initScope: (context, ctx) async { … }`.

- [ ] **Шаг 6. Проверить, что тест нагружен**

Закомментировать `ctx._cancel();` в `onCancel` — тест на отмену обязан упасть.
Вернуть.

- [ ] **Шаг 7. Гейт и коммит**

```bash
git add lib/src/scope/async_scope/ lib/src/scope/scope.dart \
        test/scope_init_context_test.dart test/async_scope_test.dart \
        CHANGELOG.md
git commit -m "feat!: an AsyncScope initialization returns instead of yielding"
```

---

### Задача 2: `AsyncDataScope`

**Файлы:**

- Изменить: `async_data_scope_core.dart:110-140` (`initScope` через адаптер),
  `async_data_scope_base.dart`, `async_data_scope.dart`
- Удалить: `async_data_scope_init_state.dart` и его `part`
- Тест: `test/async_data_scope_test.dart`

**Потребляет:** `_runScopeInit`, `ScopeInitContext` из задачи 1.
**Производит:** `Future<T> initData(BuildContext, ScopeInitContext)`.

- [ ] **Шаг 1. Падающий тест на позднее значение**

```dart
testWidgets('a value that arrives after the cancellation is handed to dispose',
    (tester) async {
  final disposed = <_Database>[];
  final database = _Database('main');
  final gate = Completer<void>();

  await tester.pumpWidget(
    _Host(
      init: (context, ctx) async {
        await gate.future; // голый await: тело не спрашивает контекст
        return database;
      },
      dispose: disposed.add,
    ),
  );
  await tester.pump();

  await tester.pumpWidget(const SizedBox.shrink());
  gate.complete();
  await settle(tester, until: () => disposed.isNotEmpty);

  expect(disposed, [same(database)]);
});
```

- [ ] **Шаг 2. Убедиться, что падает.** `fvm flutter test test/async_data_scope_test.dart`

- [ ] **Шаг 3. Перевести семейство**

`initDataAsync()` становится `Future<T> initDataAsync(ScopeInitContext ctx)`,
`initScope` собирается адаптером; `releaseLateValue` — `disposeData`. Проверку
«второй `Ready`» (`if (_hasData) throw StateError('$W already initialized')`)
сохранить: она стоит в `map` не случайно, причина — в комментарии над ней.

- [ ] **Шаг 4. Удалить `AsyncDataScopeInitState` и его наследников**, снять
  `part` из `scope.dart`, вычистить упоминания в дартдоках этого семейства.

- [ ] **Шаг 5. Прогон.** `fvm flutter test` целиком: упадут тесты других
  семейств, которых задача ещё не касалась, — это ожидаемо; в этой задаче
  зелёными должны быть `async_data_scope_test.dart`,
  `async_scope_test.dart`, `scope_init_context_test.dart`.

- [ ] **Шаг 6. Гейт и коммит.**
  `git commit -m "feat!: an AsyncDataScope initialization returns its value"`

---

### Задача 3: `AsyncControllerScope` — перевёрнутый порядок

Единственная задача, где правка не механическая. Прочитать в спеке раздел
«Второй узел: контроллерное семейство» до первой строки кода.

Сегодня (`async_controller_scope_core.dart:98-143`):

```dart
try {
  await controller.performInit();
  yield AsyncDataScopeReady(controller);
} finally {
  if (!_initSucceeded) {
    await _releaseController(controller);
  }
}
```

`finally` выполняется, когда у стрима просят следующее событие, — то есть
**после** того, как движок принял `Ready` и поставил `_initSucceeded`. С
`return` он выполнится **до** этого, увидит `false` и разрушит контроллер,
уехавший в готовую ветку.

**Файлы:** `async_controller_scope_core.dart`, тест
`test/scope_removed_while_initializing_test.dart`,
`test/async_controller_scope_test.dart`

- [ ] **Шаг 1. Тест, который ловит именно этот зазор**

```dart
testWidgets('a controller that initialized is not released behind the '
    'ready branch', (tester) async {
  final released = <String>[];

  await tester.pumpWidget(
    _Host(
      createController: () => _Controller(onDispose: () => released.add('x')),
      pauseAfterInitialization: const Duration(milliseconds: 50),
    ),
  );
  await tester.pumpAndSettle();

  expect(
    released,
    isEmpty,
    reason: 'the controller is running behind the ready branch',
  );
});
```

`pauseAfterInitialization` здесь не украшение: он растягивает окно между
приёмом значения и показом готовой ветки — то самое, в котором старый и новый
порядок расходятся.

- [ ] **Шаг 2. Убедиться, что тест падает** после механического перевода
  `yield` → `return` (сделать перевод, увидеть падение, и только потом чинить).

- [ ] **Шаг 3. Переписать обёртку**

```dart
  @nonVirtual
  @override
  Future<C> initDataAsync(ScopeInitContext ctx) async {
    final controller = _controller = createController(this);

    assert(
      !controller._initStarted && controller._disposeCompleter == null,
      '…', // сообщение оставить как есть
    );

    try {
      await controller.performInit();
      // ignore: avoid_catching_errors
    } on Object {
      // Освобождение переехало сюда из `finally`: с `return` тот выполнялся
      // раньше, чем движок принимал значение, и разрушал контроллер, который
      // уехал в готовую ветку. Отказ и отмена — единственные пути, на которых
      // контроллер остаётся на руках у этого тела.
      await _releaseController(controller);
      rethrow;
    }

    return controller;
  }
```

Контроллер, произведённый после отмены, освобождает адаптер общим правилом
позднего значения (`releaseLateValue` → `disposeData` → `performDispose`).
`_releaseController` не меняется.

- [ ] **Шаг 4. Прогон.** `fvm flutter test test/async_controller_scope_test.dart
  test/scope_removed_while_initializing_test.dart` — зелено.

- [ ] **Шаг 5. Нагруженность.** Вернуть освобождение в `finally` с проверкой
  `_initSucceeded` — тест шага 1 обязан упасть. Вернуть исправление.

- [ ] **Шаг 6. Гейт и коммит.**
  `git commit -m "fix!: a controller is released on the two paths that keep it"`

---

### Задача 4: `LiteScope`

**Файлы:** `lite_scope_core.dart:141`, `lite_scope_base.dart:99,294`,
тест `test/lite_scope_test.dart` (78 КБ — самый большой в сьюте)

- [ ] **Шаг 1.** Перевести `initScope` в обе точки: абстрактную в `core` и
  дефолтную в `base`. Дефолт становится пустым телом:

```dart
  /// The initialization; ready at once by default.
  Future<void> initScope(BuildContext context, ScopeInitContext ctx) async {}
```

- [ ] **Шаг 2.** Диагностики на `buildOnProgress` и `buildOnError`
  (`lite_scope_base.dart:130,154`) говорят «overrides `initScope()`» — текст
  оставить, он по-прежнему верен, но перечитать: там сказано «the default one
  is ready at once and never reports progress», и это остаётся правдой.

- [ ] **Шаг 3.** Прогон `fvm flutter test test/lite_scope_test.dart`, правка
  вхождений.

- [ ] **Шаг 4. Гейт и коммит.**
  `git commit -m "feat!: a LiteScope initialization returns instead of yielding"`

---

### Задача 5: `Scope` и `ScopeDependencies`

**Файлы:** `scope_core.dart:140,175`, `scope_base.dart:134,280`,
`scope_dependencies.dart`; удалить `scope_init_state.dart`;
тесты `test/scope_*` (см. список в задаче 7)

- [ ] **Шаг 1.** `initDependencies` во всех трёх точках:

```dart
  /// Initializes the dependencies and returns them.
  Future<D> initDependencies(BuildContext context, ScopeInitContext ctx);
```

- [ ] **Шаг 2.** `initScope` элемента собирается адаптером; проверку
  «второй `Ready`» (`if (_dependencies != null) throw StateError(…)`)
  сохранить — причина в комментарии над ней.

- [ ] **Шаг 3.** Удалить `ScopeInitState`, `ScopeProgress`, `ScopeReady` и
  расширение `ScopeDependenciesExtension.asStream`. Контейнер, готовый сразу,
  теперь возвращается из тела обычным `return`, и короткий путь не нужен.

- [ ] **Шаг 4. Гейт и коммит.**
  `git commit -m "feat!: a Scope initialization returns its dependencies"`

---

### Задача 6: `ScopeAutoDependencies` — узел риска

Здесь новая форма встречается со старой: снаружи `Future`, внутри дерево
по-прежнему отдаёт `Stream<String>`. Отмена перестаёт быть автоматической.

**Файлы:** `scope_auto_dependency.dart:179-300`,
тесты `test/scope_auto_dependencies_test.dart` (110 КБ),
`test/scope_dependency_partial_test.dart`

- [ ] **Шаг 1. Падающий тест: отмена посреди дерева**

```dart
testWidgets('a container cancelled mid-tree releases what it had taken',
    (tester) async {
  final log = <String>[];
  final gate = Completer<void>();

  await tester.pumpWidget(
    _Host(
      dependencies: () => _Deps(
        first: () {
          log.add('first init');

          return () => log.add('first dispose');
        },
        second: () async {
          log.add('second init');
          await gate.future; // сюда придёт отмена
        },
      ),
    ),
  );
  await tester.pump();

  expect(log, ['first init', 'second init']);

  await tester.pumpWidget(const SizedBox.shrink());
  await settle(tester, until: () => log.contains('first dispose'));

  expect(
    log,
    ['first init', 'second init', 'first dispose'],
    reason: 'the walk stops where it stands and gives back the branch that '
        'had already been built',
  );
  expect(gate.isCompleted, isFalse);
});
```

Ещё два теста той же формы: отмена, пришедшая между двумя шагами (гейт
закрывается после `first`, до `second`), и отказ ветки при уже отменённом
обходе (`second` бросает после отмены — ошибка не должна ни потеряться, ни
заменить собой отмену). Фикстуры `_Host` и `_Deps` брать из
`scope_auto_dependencies_test.dart`, там они уже есть.

- [ ] **Шаг 2.** Перевести `init` на `Future`:

```dart
  Future<T> init(C context, ScopeInitContext ctx) async {
    // Обе проверки — `this is! T` и `_initializing` — переносятся дословно и
    // остаются первыми: причина у каждой в её собственном сообщении.
    if (this is! T) {
      throw StateError('…'); // текст как есть
    }
    if (_initializing) {
      throw StateError('…'); // текст как есть
    }

    final dependencies = _prepareDependencies(context);
    final progressIterator = ProgressIterator(dependencies.count);
    final done = Completer<void>();

    _initializing = true;
    try {
      notifyObserver((observer) => observer.onInit(this));

      final subscription = dependencies.init().listen(
        (path) {
          final step = progressIterator.nextStep();
          final progress = ScopeAutoDependenciesProgress(path, step);
          notifyObserver((observer) => observer.onProgress(this, progress));
          ctx.progress(progress);
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!done.isCompleted) {
            done.completeError(_explainRerunFailure(error), stackTrace);
          }
        },
        onDone: () {
          if (!done.isCompleted) {
            done.complete();
          }
        },
        cancelOnError: true,
      );

      final unregister = ctx.onCancel(() {
        // Снимаем подписку и не ждём её здесь: `onCancel` синхронный, а
        // ожидание — дело тела, которое стоит на `done` ниже.
        unawaited(subscription.cancel());
        if (!done.isCompleted) {
          done.completeError(const ScopeInitCancelled(), StackTrace.current);
        }
      });

      try {
        await done.future;
      } finally {
        unregister();
      }

      if (!dependencies.isInitialized) {
        throw StateError('…'); // ветка, где обход кончился, ничего не собрав
      }
      notifyObserver((observer) => observer.onReady(this));

      return this as T;
    } finally {
      // Порядок как был: флаг снимается ДО разбора начатого, иначе контейнер
      // отказывает собственной уборке через guard, который защищает от
      // чужого `dispose` посреди работы.
      _initializing = false;

      if (!dependencies.isInitialized) {
        // Разбор начатого — целиком переносится из нынешнего `finally`,
        // включая `onUnmount` и обе ветки отчёта об ошибках.
      }
    }
  }
```

Ошибка дерева приходит в `onError` подписки, а не в `catch` вокруг
делегирования — это правило скилла `dart` и находка R3; `handleError`,
стоявший в старой версии, здесь заменяется на `onError` подписки, и это тот
же канал.

Ошибку дерева по-прежнему нельзя ловить `try`-ом вокруг делегирования: она
идёт через обработчик, а не через `catch` (правило скилла `dart`, находка R3).

- [ ] **Шаг 3.** `finally` с `_initializing = false` и разбором начатого —
  перенести дословно, включая порядок: флаг снимается **до** разбора.

- [ ] **Шаг 4. Нагруженность.** Убрать `ctx.onCancel(...)` — тест на отмену
  посреди дерева обязан упасть.

- [ ] **Шаг 5. Гейт и коммит.**
  `git commit -m "feat!: a dependency container initializes without a generator"`

---

### Задача 7: остаток сьюты

24 файла тестов содержат 69 вхождений `Ready(`. Большая часть правится в
задачах 1–6; эта задача добирает остальное.

**Файлы:** `test/cleanup_after_user_error_test.dart` (53 КБ),
`test/scope_observer_test.dart` (51 КБ),
`test/async_scope_coordinator_test.dart` (51 КБ),
`test/scope_step_entry_test.dart`, `test/public_facades_test.dart`,
`test/ide_snippets_test.dart`, `test/published_docs_test.dart`,
`test/scope_parameters_matrix_test.dart`, `test/scope_timeout_test.dart`,
`test/scope_lifecycle_order_test.dart`, `test/base_test.dart`

- [ ] **Шаг 1.** `fvm flutter test` целиком, собрать список падений.
- [ ] **Шаг 2.** `public_facades_test.dart` и `published_docs_test.dart` — не
  механика: первый сторожит публичную поверхность, второй сверяет примеры из
  опубликованных документов. Оба обязаны узнать про семь ушедших имён и про
  `ScopeInitContext`.
- [ ] **Шаг 3.** `ide_snippets_test.dart` — сниппеты в `test/ide/` тоже
  пишутся в новой форме.
- [ ] **Шаг 4. Гейт и коммит.** `git commit -m "test: the suite speaks the new form"`

---

### Задача 8: документация и зеркала

**Файлы:** `README.md`, `doc/async_scope.md`, `doc/async_data_scope.md`,
`doc/full_scope.md`, `doc/lite_scope.md`, `doc/scope_notifier.md`,
`example/minimal/lib/main.dart`, `example/README.md`,
`example/scopo_demo/lib/app/app_dependencies.dart`,
`example/scopo_demo/lib/home/demos/async_scope/counter_scope.dart`,
`example/scopo_demo/lib/home/demos/async_data_scope/counter_scope.dart`,
и шесть зеркал в `docs/ru/`

- [ ] **Шаг 1.** README: раздел «Why another one» открывается словами
  «initialization is a `Stream`» — переписать. Это обещание пакета, и оно
  меняется: инициализация становится обычной `Future` с отменой.
- [ ] **Шаг 2.** Пять топиков: заменить примеры, добавить раздел про
  кооперативную отмену (`check`, `wait`, `onCancel`) — сегодня об этом нет
  ничего, потому что отмену делал генератор.
- [ ] **Шаг 3.** Оба примера, включая `app_dependencies.dart` демо.
- [ ] **Шаг 4.** Зеркала — тем же коммитом, комментарии внутри примеров кода
  тоже переводятся (`AGENTS.md` §7). Затем `sh docs/ru/stamp.sh`, и до штампа
  посмотреть `git status`.
- [ ] **Шаг 5.** `sh docs/ru/check.sh` — 0 расхождений.
- [ ] **Шаг 6. Коммит.** `git commit -m "docs: the initialization returns, and the docs say so"`

---

### Задача 9: релиз 0.14.0

- [ ] **Шаг 1.** `CHANGELOG.md` — раздел 0.14.0. Ломающими помечаются: форма
  инициализации во всех семействах; удаление семи имён
  (`AsyncDataScopeInitState`, `AsyncDataScopeProgress`, `AsyncDataScopeReady`,
  `ScopeInitState`, `ScopeProgress`, `ScopeReady`,
  `ScopeDependenciesExtension.asStream`); перенос освобождения контроллера с
  `finally` на ветку отказа.
- [ ] **Шаг 2.** Отдельным пунктом — то, что появилось: значение,
  произведённое после отмены, теперь освобождается, а не теряется.
- [ ] **Шаг 3.** `pubspec.yaml` → 0.14.0; локи примеров пересоздать
  закреплённым тулчейном.
- [ ] **Шаг 4.** Гейт §6 целиком, все восемь команд, вывод — в
  `docs/handoff.md`.
- [ ] **Шаг 5.** Удалить ветку `spike/init-without-generators`: её содержимое
  переехало, и держать черновик рядом с реализацией незачем.
- [ ] **Шаг 6.** Обновить шапки обеих записей (`[1]`-design и `[2]`-plan):
  состояние «сделано и смержено», с коммитами.
- [ ] **Шаг 7.** Публикация — **только по явной просьбе владельца**
  (`AGENTS.md` §5).

---

## Чего в плане нет намеренно

Половина B — внутренности слоя зависимостей (`Stream<String>`,
`_mergeStreams`, `runStreamGuarded`, конкурентные группы). Отдельная работа
после релиза, спека её границу называет.

Движок `AsyncScopeCore`. Ветка `onDone`-без-`Ready` в нём после замены
недостижима из публичного API; удалять её не надо, но тест, который её держит,
перечитать в задаче 7 — если он строил такой стрим через публичный вход, ему
нужен другой способ кормить движок.
