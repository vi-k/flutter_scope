# Scope

> Перевод `doc/full_scope.md` (blob `d6787b39ddee89159da8a13eef54e15228f9ce6f`).
> Правится в том же коммите, что и оригинал; проверка — `sh docs/ru/check.sh`.

`Scope` — основной строительный блок пакета: виджет, который владеет контейнером
зависимостей, инициализирует его асинхронно, строит поверх него состояние, даёт
и то и другое своему поддереву и в конце утилизирует всё в обратном порядке —
после того, как исчезнут его собственные дочерние скоупы.

Один скоуп — это три типа:

1. виджет — наследник `Scope`. Параметры его конструктора и есть параметры
   скоупа, а его билдеры покрывают ветки ожидания, инициализации, ошибки и
   закрытия.
2. контейнер зависимостей — реализация `ScopeDependencies`, которую создаёт
   `initDependencies` ещё до того, как появится состояние.
3. состояние — наследник `ScopeState`; то же самое, что `State` у
   `StatefulWidget`, с той разницей, что `dependencies` уже доступны в
   `initState`.

Младшие семейства (`ScopeWidgetBase`, `ScopeModel`, `ScopeNotifier`,
`AsyncScope`, `AsyncDataScope`, `AsyncControllerScope`, `LiteScope`) отбрасывают
ту или иную часть. `Scope` — полный набор.

## Ветка инициализации

`initDependencies` возвращает `Stream<ScopeInitState<P, D>>` с событиями двух
видов: `ScopeProgress(progress)` сколько угодно раз и `ScopeReady(deps)` один
раз. Поток, а не `Future`, по двум причинам: он умеет сообщать о прогрессе и его
можно отменить — если виджет уйдёт с дерева, пока контейнер ещё строится,
подписку отменят, и недостроенный контейнер никогда не попадёт в состояние.

Что скоуп показывает и что зовёт, по порядку:

| Фаза | Билдер |
| --- | --- |
| ожидание `scopeKey` и первого события потока | `buildOnWaiting` — может вернуть `null`, тогда `buildOnInitializing(context, null)` |
| пришёл `ScopeProgress` | `buildOnInitializing(context, progress)` |
| пришёл `ScopeReady` | `wrapState` вокруг `build` состояния из `createState` |
| поток упал | `buildOnError(context, error, stackTrace, progress)` |
| работает `close()` | `buildOnClosing` поверх замороженного снимка готового поддерева, если снимок удалось снять |

`wrapState` оборачивает только готовую ветку, поэтому виджет, нужный всем веткам
сразу (обычно это `MaterialApp`), строят внутри каждого билдера.

`pauseAfterInitialization` придерживает готовую ветку на фиксированное время
после `ScopeReady`, чтобы индикатор загрузки не сменялся в том же кадре, в
котором появился. `ScopeConfig.pauseAfterInitializationEnabled` выключает все
такие паузы разом — см. тему `debug`.

Контейнер, которому нужен один `await`, можно написать руками:

```dart
final class AppDependencies implements ScopeDependencies {
  final SharedPreferences sharedPreferences;

  AppDependencies({required this.sharedPreferences});

  static Stream<ScopeInitState<String, AppDependencies>> init() async* {
    yield ScopeProgress('Initializing storage…');
    final sharedPreferences = await SharedPreferences.getInstance();

    yield ScopeReady(AppDependencies(sharedPreferences: sharedPreferences));
  }

  /// Отпускает то, что не может ждать асинхронного разбора.
  @override
  void onUnmount() {}

  /// Вызывается после того, как состояние утилизировано. Может быть
  /// асинхронным.
  @override
  Future<void> dispose() async {}
}
```

`ScopeDependenciesExtension.asStream` сокращает вырожденный случай — контейнер,
которому асинхронная работа не нужна вовсе:
`AppDependencies().asStream<String>()` выдаёт единственный
`ScopeReady`.

У трёх функциональных типов, из которых собран скоуп, есть имена — на случай,
если их приходится передавать: `ScopeInitFunction`, `ScopeWaitingBuilder`,
`ScopeInitBuilder` и `ScopeErrorBuilder`.

## ScopeAutoDependencies

Писать поток руками перестаёт масштабироваться, как только у зависимостей
появляется порядок, часть из них можно строить параллельно, и у каждой свой
разбор. `ScopeAutoDependencies` — готовая реализация: опишите дерево один раз в
`buildDependencies`, а его `init` обойдёт дерево, отчитается о прогрессе по
каждой зависимости и утилизирует всё уже построенное, если что-то упадёт.

```dart
final class HomeDependencies
    extends ScopeAutoDependencies<HomeDependencies, void> {
  late final ApiClient apiClient;
  late final Settings settings;
  late final Session session;

  @override
  ScopeDependency buildDependencies(_) => sequential('', [
        dep('apiClient', (dep) async {
          apiClient = ApiClient();
          dep.dispose = apiClient.close;

          await apiClient.init();
        }),
        concurrent('user', [
          dep('settings', (dep) async {
            settings = await Settings.load();
            dep.dispose = settings.save;
          }),
          dep('session', (dep) async {
            session = await Session.restore(apiClient);
            dep.dispose = session.close;
          }),
        ]),
      ]);
}
```

Дерево описывают три билдера, и все они возвращают `ScopeDependency`:

- `dep(name, init)` — одна зависимость. `DepHelper`, который передают в `init`, —
  это место, где регистрируют обратные операции: `dep.unmount` выполняется
  синхронно до того, как что-либо освобождается, `dep.dispose` дожидаются при
  утилизации. Не задать ни того ни другого нормально — зависимости, которая
  ничем не владеет, разбирать нечего. Имя не может быть пустым.
- `sequential(name, [...])` — `ScopeDependencyGroup`, дети которой
  инициализируются один за другим, а утилизируются в обратном порядке.
- `concurrent(name, [...])` — то же самое, но дети инициализируются (и
  утилизируются) параллельно, поэтому прогресс приходит в порядке завершения, а
  не объявления.

Группы вкладываются свободно, а имя группы может быть пустым (см. пути ниже).
Второй параметр типа `ScopeAutoDependencies` — это то, что получает
`buildDependencies`: `void` для контейнера выше, которому снаружи ничего не
нужно; объявляйте `BuildContext`, когда зависимости надо что-то прочитать из
дерева.

Подключение контейнера к скоупу — один вызов, а
`ScopeAutoDependenciesStream` — псевдоним для типа получающегося потока:

```dart
@override
ScopeAutoDependenciesStream<HomeDependencies> initDependencies(
  BuildContext context,
) =>
    HomeDependencies().init(null);
```

Для контейнера с `BuildContext` пробрасывайте `context` из `initDependencies`
вместо `null`.

Каждое событие этого потока несёт `ScopeAutoDependenciesProgress`: `path` — путь
только что инициализированной зависимости, `name` — последний сегмент этого
пути, то есть имя, с которым зависимость объявлена, плюс счётчик шагов
`ProgressIterator` (`number`, `total` и `progress` как доля от 0 до 1). Именно
этот объект получает `buildOnInitializing`, так что прогресс-бару с подписью
больше ничего не нужно:

```dart
@override
Widget buildOnInitializing(
  BuildContext context,
  covariant ScopeAutoDependenciesProgress? progress,
) =>
    Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        LinearProgressIndicator(value: progress?.progress ?? 0),
        Text(progress?.path ?? ''),
      ],
    );
```

`autoDisposeOnError` (по умолчанию `true`) — то, что заставляет провалившуюся
инициализацию убрать за собой: если дерево не дошло до инициализированного
состояния, `dispose` контейнера отрабатывает раньше, чем ошибка доберётся до
`buildOnError`. Переопределите его в `false`, чтобы оставить недостроенное
дерево для разбора.

### Регистрируйте разбор, как только появилось что разбирать

Утилизация освобождает то, что зависимость **зарегистрировала**, а не то, чем
она кончилась: инициализатор, взявший ресурс и задавший `dep.dispose`, держит
этот ресурс, чем бы дело потом ни обернулось — успехом, отказом или отменой.
Значит, всё решает место регистрации.

```dart
// Неправильно: миграция бросает, регистрировать нечего, и база остаётся
// открытой, а закрыть её некому.
dep('database', (dep) async {
  final database = await Database.open();
  await database.migrate();
  dep.dispose = database.close;
}),
```

```dart
// Правильно: зарегистрировано раньше, чем что-либо успеет упасть.
dep('database', (dep) async {
  final database = await Database.open();
  dep.dispose = database.close;

  await database.migrate();
}),
```

Правило укладывается в строку: **взял — зарегистрируй — продолжай.** Между
захватом и регистрацией не должно быть ни `await`, ни броска, ни точки отмены —
а в Dart первое влечёт за собой остальные два.

`dep.dispose` можно переприсваивать по ходу инициализатора — так и поступает
зависимость, которая строит несколько вещей подряд: регистрируют замыкание,
освобождающее всё взятое к этому моменту, и расширяют его после каждого шага. Не
задавать ни `dep.dispose`, ни `dep.unmount` нормально для зависимости, которая
ничем не владеет: после разбора она скажет `no disposal required`, так что по
дампу дерева всё равно видно, что обход до неё дошёл.

### Чего стоит провал, а чего не стоит

Упавшая зависимость останавливает свою группу, а разбор выше освобождает всё уже
построенное — при условии, что каждый лист зарегистрировал взятое. Где именно
обход останавливается, знать стоит:

- **Последовательная группа** останавливается на первом отказе; те, что были до
  него, освобождаются в обратном порядке.
- **Параллельная группа** отменяет ветви, которые ещё шли, когда одна из них
  упала. Отменённая ветвь возобновляется лишь до ближайшей точки приостановки,
  то есть может встать на середине, — и это второй довод за раннюю регистрацию:
  что она успела зарегистрировать, то освободят, что не успела — нет.
- **Сама утилизация на отказе не останавливается.** Каждое освобождение под
  своей защитой, обход доходит до конца, первая ошибка уходит наверх после него.
  Каждый отказ записан на той зависимости, которой принадлежит, и читается через
  `flattenDependenciesWithErrors()`.

А при `autoDisposeOnError` в `false` освобождение недостроенного дерева — ваше
дело.

### Написанный руками контейнер убирает за собой сам

Разбор провалившейся инициализации выполняет `ScopeAutoDependencies`. За
контейнером, написанным руками, ничего такого нет: скоуп запоминает контейнер,
когда поток выдаёт `ScopeReady`, а поток, упавший раньше, ничего ему и не
передал. Ничто из того, что держит скоуп, на контейнер не указывает, и его
`dispose()` никогда не позовут.

Поэтому написанный руками `init` принимает ту же форму, что и в теме
`AsyncScope`: что шаг взял, то и отдаётся, если контейнер не передали дальше.

```dart
static Stream<ScopeInitState<String, AppDependencies>> init() async* {
  final storage = await Storage.open();
  var handedOver = false;

  try {
    yield ScopeProgress('signing in');
    final session = await Session.restore(storage);

    yield ScopeReady(AppDependencies(storage: storage, session: session));
    handedOver = true;
  } finally {
    if (!handedOver) {
      await storage.close();
    }
  }
}
```

`finally`, а не `catch`: второй способ закончить это досрочно — отмена, когда
скоуп убрали из дерева, так и не дав ему стать готовым, — и она не бросает
ничего, поэтому до `catch` дело не доходит. Разбор целиком — в теме
`AsyncScope`. Эту же форму контейнер пишет за вас: то, что зависимость
зарегистрировала через `dep.dispose`, отдаётся и когда обход упал, и когда его
отменили.

## Осмотр дерева

Чем бы дело ни кончилось, контейнер открывает построенное: `root` — верхняя
`ScopeDependency`, `flattenDependencies()` обходит его в глубину, отдавая записи
`ScopeDependencyInfo` (`level`, `path`, `dependency`), а
`flattenDependenciesWithErrors()` сужает обход до записей с настоящей ошибкой, а
не с проброшенным `ScopeDependencyException`. У каждой зависимости есть ещё и
`ScopeDependencyState` — `ScopeDependencyInitial`,
`ScopeDependencyInitialized`, `ScopeDependencyFailed`,
`ScopeDependencyCancelled`, `ScopeDependencyDisposed`,
`ScopeDependencyNoDisposalRequired`, `ScopeDependencyDisposalFailed`,
`ScopeDependencyDisposalCancelled` — и сокращения `isInitialized`, `isFailed`,
`isCancelled`, `isDisposed` из `ScopeDependencyExtension`.

`ScopeDependencyNoDisposalRequired` — состояние зависимости, которая не задала
`dep.dispose` и отдавать ей нечего: разбор проходит мимо неё, и вот что она
говорит после. Это `ScopeDependencyDisposed`, так что `isDisposed` покрывает оба
случая.

## Пути зависимостей

Зависимость опознаётся по пути от корня дерева: имена объемлющих групп и её
собственное имя, склеенные через `/`. Формат канонический — **ведущего слеша
нет**, а безымянная группа (группа с пустым именем) не добавляет ни сегмента, ни
разделителя. Поэтому корневую группу дерева обычно делают безымянной, и пути её
детей читаются так, будто её нет.

Для дерева

```dart
sequential('', [
  dep('dep1', …),
  concurrent('concurrent1', [
    dep('dep2', …),
    sequential('sequential1', [
      dep('dep3', …),
    ]),
  ]),
])
```

пути будут `dep1`, `concurrent1/dep2` и `concurrent1/sequential1/dep3`. Те же
строки встречаются в трёх местах: в `ScopeAutoDependenciesProgress.path`, в
журнале уровня `debug` при инициализации и утилизации и в
`ScopeDependencyException.name`.

`ScopeDependencyInfo.path` — единственное место, где лежит не весь путь, а его
начало. Обход, из которого он берётся, заходит и в группы, и в листья, поэтому
каждая запись несёт путь *вмещающих* её групп — с завершающим `/`, а у корня
пустой, — а собственное имя лежит рядом, в `dependency.name`. Канонический путь
записи, стало быть, — `'${info.path}${info.dependency.name}'`.

## Ошибки

Ошибку, брошенную инициализатором `dep`, оборачивают в
`ScopeDependencyException`, который несёт `name` (тот самый путь), исходную
`error` и её `stackTrace`. Пока исключение поднимается через объемлющие группы,
каждая именованная группа приписывает спереди свой сегмент, так что до
`buildOnError` доходит точное имя упавшей зависимости:

```text
concurrent1/sequential1/dep3: Exception: no network
```

Пустое `name` означает, что упала сама безымянная корневая зависимость.

Группа, увидевшая провал, перестаёт требовать инициализации и переходит в
`ScopeDependencyFailed`; ошибки её соседей, если `concurrent`-группа выдала
несколько, все сохраняются в состоянии и доступны через
`flattenDependenciesWithErrors()`. `stateToString()` группы подводит этому итог:
упавшие дети по именам и всякая ошибка, которая сама не является
`ScopeDependencyException`, — списком неразрешённых.

## Утилизация, unmount и close

Разбор скоупа идёт в жёстком порядке, и каждого асинхронного шага дожидаются:

1. `onUnmount` — синхронный, всегда первый и до начала любого асинхронного
   шага. Выполняется ровно один раз, каким бы способом скоуп ни уходил: снят с
   дерева виджетов или закрыт через `close()`, оставаясь на экране. Скоуп
   выполняет `ScopeState.onUnmount`, а затем пробрасывает в
   `ScopeDependencies.onUnmount`, который `ScopeAutoDependencies` доводит дальше
   до каждого `dep.unmount`. Здесь место всему, что должно случиться немедленно
   и не может ждать асинхронного разбора: отписаться, например.

   Собственный `State.dispose` у Flutter в этот порядок не входит и войти не
   может: фреймворк зовёт его до всего разбора, когда скоуп снимают с дерева, и
   не зовёт до снятия дерева после `close()`. Поэтому у `ScopeState` он закрыт
   от переопределения.
2. Инициализацию, если она ещё идёт, отменяют — или дожидаются, если отменить
   нельзя. Ожидание отмены ограничено `initCancellationTimeout` (по умолчанию
   `ScopeConfig.defaultInitCancellationTimeout`), чтобы инициализация,
   припаркованная на future, который никогда не завершится, не держала разбор
   за собой.
3. Дожидаются дочерних скоупов, чтобы родитель никогда не утилизировал
   зависимость, которой ребёнок ещё пользуется. Ожидание ограничено
   `waitForChildrenTimeout` (по умолчанию
   `ScopeConfig.defaultWaitForChildrenTimeout`).
4. `ScopeState.disposeAsync` — собственный асинхронный разбор состояния, с
   ограничением `disposeAsyncTimeout` (по умолчанию
   `ScopeConfig.defaultDisposeAsyncTimeout`), чтобы разбор, который никогда не
   завершится, не держал освобождение `scopeKey` на шаге 6.
5. `ScopeDependencies.dispose` — для `ScopeAutoDependencies` это обход дерева в
   обратную сторону: дети `sequential`-группы в обратном порядке объявления,
   дети `concurrent`-группы параллельно, и только те, кто действительно
   зарегистрировал `dep.dispose`.
6. `scopeKey`, если он был, освобождается, и следующий ждущий его скоуп проходит
   дальше.

`close()` запускает тот же самый разбор, пока скоуп ещё на экране: готовое
поддерево замораживается снимком, поверх показывается `buildOnClosing`, а
возвращённый future завершается, когда утилизация закончена. Это способ показать
UI «закрываемся…» для скоупа, чья утилизация занимает заметное время, вместо
замирания на последнем кадре. Снимок снимают по возможности: поддерево, которое
никогда не рисовалось — внутри `Offstage` или в невыбранной ветке
`IndexedStack`, — снять нельзя. Попыток не больше `ScreenshotReplacer.maxRetries`
кадров, после чего `close()` идёт дальше, и `buildOnClosing` рисуется поверх
живого поддерева, а не замороженного.

## Доступ из поддерева

До состояния добираются через статические помощники `Scope`, которые каждый
скоуп обычно переоткрывает своими именованными аксессорами:

- `Scope.of` и `Scope.maybeOf` — состояние, без подписки. Чтобы звать методы.
- `Scope.select` — одно значение, выведенное из состояния; вызывающего
  перестроят, только когда это значение изменится, и только если состояние
  позвало `notifyDependents`.
- `Scope.paramsOf` и `Scope.selectParam` — то же самое для параметров скоупа, то
  есть для полей самого виджета.

`notifyDependents` перестраивает подписанных потомков, не перестраивая
собственное поддерево состояния, — благодаря этому скоуп годится для частых
обновлений. `isInitialized` сообщает, завершилась ли инициализация полностью, а
`onInitialized` — хук, который зовут сразу после этого.
