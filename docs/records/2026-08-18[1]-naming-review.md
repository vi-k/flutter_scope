# Ревью имён

> **Состояние на 2026-08-18:** закрыт целиком. Владелец прошёл по всем двадцати
> находкам, задание собрано в `2026-08-18[2]-naming-plan.md` и выполнено пятью
> волнами (`2c16390`, `18f3739`, `0124289`, `be530b2`, `dca3924`). У каждой
> находки внизу вердикт; две — N9 и N12 — не подтвердились. Раздел «Что я
> предлагаю взять» в конце отменён решениями владельца и оставлен как есть.
> **Что это:** сплошной проход по именам пакета — публичный API и
> внутренности: ошибки, несогласованность, двусмысленность.
> **Связанные записи:** `2026-08-17[3]-project-review.md` (третье полное
> ревью), `2026-08-18[2]-naming-plan.md` (решения владельца и порядок волн).

Взято из бэклога владельца: «время, когда можно переименовать переменные,
колбэки и т.п. Посмотри, стоит ли что-то переименовать? Может есть ошибки в
названиях, несогласованность, неопределённость, двойственность?»

Окно открыто, пока 0.10.0 не опубликована: в релизе уже есть ломающие правки,
так что ещё одна волна имён не добавляет потребителю ни одного лишнего
перехода. После публикации то же самое стоит мажорной версии.

Смотрел всё, что объявлено в `lib/` — типы, члены, параметры конструкторов,
колбэки, приватные поля, — плюс как эти имена звучат в `doc/`, `README.md` и
примерах. Находки разложены по тому, чего они стоят: сначала те, где имя прямо
врёт или спорит с соседним, потом семейные несогласованности, потом
внутренние, которых потребитель не видит.

Цена в каждой находке — число вхождений: `lib` / `test` / публичные документы
(`doc/*.md`, `README.md`, `CHANGELOG.md`) / зеркала `docs/ru` / примеры.
Переименование публичного имени — это ещё и строка в `CHANGELOG.md`, и правка
зеркала в том же коммите.

## А. Имя врёт или спорит с соседним

**N1. `ScopeConfig.defaultScopeKeysTimeout` — множественное число там, где
везде единственное.** `scope_config.dart:33`. Параметр виджета —
`scopeKey` и `scopeKeyTimeout` (единственное), у всех пяти семейств; настройка
по умолчанию для того же таймаута названа `defaultScopeKeysTimeout`. Дартдок
строкой выше повторяет ошибку: «waiting for `scopeKeys` to be released». Три
соседние настройки — `defaultWaitForChildrenTimeout`,
`defaultDisposeAsyncTimeout`, `defaultInitCancellationTimeout` — повторяют имя
своего параметра ровно. Предлагаю `defaultScopeKeyTimeout`.
Цена: 6 / 3 / 3 / 2 / 1.

**Вердикт: исправлено.** Волна 2, `18f3739`. `defaultScopeKeyTimeout`, вместе
с дартдоком, где «scopeKeys» стало «a `scopeKey`».

**N2. `ScopeDependencySuccessStates`, `ScopeDependencyFailedStates`,
`ScopeDependencyCancelledStates` — множественное число у типа, экземпляр
которого всегда одно состояние.** `scope_dependency_state.dart:18, 57, 64`.
Множественное здесь означает «группа состояний» — то есть свойство иерархии, а
не объекта; но пишется-то оно на объекте: `state is ScopeDependencyFailedStates`
читается как «состояние есть состояния». Конкретные наследники при этом
единственного числа: `ScopeDependencyFailed`, `ScopeDependencyDisposalFailed`.
Предлагаю единственное: `ScopeDependencySuccessState` и т.д. — тогда `sealed`
база и её листья различаются суффиксом `State`, а не числом.
Цена: 11 / 1 / 0 / 0 / 0 — самая дешёвая находка списка.

**Вердикт: исправлено, с уточнением к находке.** Волна 2, `18f3739`. Владелец
выбрал не единственное число, а префикс `Any`: `ScopeDependencyAnySuccess`,
`ScopeDependencyAnyFailed`, `ScopeDependencyAnyCancelled`. На месте вызова это
читается как «любое из провалившихся», и база не выглядит листом — чего
единственное число не давало.

**N3. `initBuilder` рядом с `init` — двусмысленность в одном конструкторе.**
`async_scope.dart:31`, `async_data_scope.dart:42`,
`async_controller_scope.dart:15`. `init` — это работа (стрим инициализации),
`initBuilder` — экран, который показывают, **пока** она идёт. Из имени
`initBuilder` первое читается раньше второго: «билдер для init». Соседи не
двусмысленны, потому что называют состояние: `waitingBuilder` ↔ `buildOnWaiting`,
`errorBuilder` ↔ `buildOnError`. У этого же билдера метод-переопределение зовётся
`buildOnInitializing` — то есть правильное слово в пакете уже есть, просто до
параметра оно не дошло. Предлагаю `initializingBuilder`.
Цена: 12 / 26 / 10 / 9 / 4.

**Вердикт: исправлено, с уточнением к находке.** Волна 3, `0124289`. Выбрано
`progressBuilder`, а не предложенное `initializingBuilder`: билдер назван по
состоянию `AsyncScopeProgress`, которое он и обслуживает. Из этого выбора
вышло то, чего находка не предлагала: метод `buildOnInitializing` стал
`buildOnProgress` во всех семействах, и тогда все четыре метода семейства зовут
свои состояния по именам.

**N4. `DepHelper` — сокращение и «Helper» в публичном типе.**
`scope_dependency_impl.dart:82`, отдаётся наружу в `ScopeDependency(...)` и в
`ScopeAutoDependencies.dep(...)`. Всё семейство пишет слово целиком:
`ScopeDependency`, `ScopeDependencies`, `ScopeDependencyInfo`,
`ScopeDependencyState`, `ScopeDependencyException`. Сокращение оправдано в
`dep('httpClient', (dep) async {...})` — это DSL, там короткое имя работает; но
тип, который человек пишет в сигнатуре своего колбэка, сокращать незачем. И
«Helper» не говорит, что это: а это ручка одной зависимости, на которую вешают
`dispose` и `unmount`. Предлагаю `ScopeDependencyHandle` (или
`DependencyHandle`, если длина смущает). Заодно стоит перенести его из
`scope_dependency_impl.dart` — публичный тип в файле с «Impl» в имени.
Цена: 8 / 11 / 3 / 1 / 0.

**Вердикт: исправлено.** Волна 2, `18f3739`. `ScopeDependencyHandle`, и вместе
с ним переезд в собственный файл — то есть заодно закрыт N20.

**N5. `ScopeLogFn` против `ScopeInitFunction` — два стиля для одного понятия.**
`scope_logger.dart:57` и `scope_base.dart:7`. Один тип-функция сокращает слово
до `Fn`, другой пишет `Function` целиком; в Dart для такого принят суффикс
`Callback` (`VoidCallback`, `ValueChanged`). Предлагаю привести к одному —
`ScopeLogCallback` и `ScopeInitCallback`, — или, если менять только
несогласованность, к `Function` в обоих.
Цена: 8 / 0 / 1 / 1 / 0 и 1 / 0 / 1 / 1 / 2.

**Вердикт: исправлено.** Волна 2, `18f3739`. Оба к `Callback`:
`ScopeLogCallback` и `ScopeInitCallback`. Тем же коммитом `ScopeInitBuilder`
стал `ScopeProgressBuilder` — хвост от N3, замеченный по ходу.

**N6. `ScopeDependency` даёт наружу и `init()`, и `runInit()` — из имён не
видно, что вызывать.** `scope_dependency.dart:39, 42, 51, 54`. `runInit()`
оборачивает `init()` учётом состояния и ошибок; голый `init()` в интерфейсе
нужен реализациям, а не тем, кто зависимостью пользуется. Имена же
симметричные, и `init()` короче — то есть выглядит основным. Предлагаю назвать
внутреннюю пару так, как она работает: `init()`/`dispose()` остаются шагом
реализации, а обёртки становятся `runInit()`→`initialize()` и
`runDispose()`→`release()`; либо, наоборот, увести голые из интерфейса.
Это единственная находка раздела, где решение стоит принимать по устройству, а
не по вкусу.
Цена: 5 / 11 / 0 / 0 / 0 (`runInit`), 6 / 1 / 1 / 1 / 0 (`runDispose`).

**Вердикт: исправлено, но не переименованием.** Волна 5, `dca3924`. Владелец
выбрал сокращение интерфейса: обёртки взяли имена `init()`/`dispose()`, а сырой
шаг стал приватным `_runInit()`/`_runDispose()` — позвать не то теперь
невозможно. Находка называла это одним из вариантов и не решала за владельца;
решение принято по устройству, как она и предлагала.

**N7. У `AsyncControllerScope` контроллер читается как `data`, а контекст
называется `AsyncDataScopeContext`.** `async_controller_scope_base.dart:124,
137, 151`, `async_controller_scope.dart:70, 84`; документация показывает это
прямо: `doc/async_controller_scope.md:139` — `).data;`, и `:153` —
`(scope) => scope.data.position`. Семейство контроллера переиспользует контекст
семейства данных, подставив контроллер в слот `T`. Тип в публичной сигнатуре
называет чужое семейство, а член называет контроллер данными. Предлагаю
добавить `AsyncControllerScopeContext<W, C> implements AsyncDataScopeContext<W,
C>` с геттером `controller` (и `controllerOrNull`/`hasController`, если нужна
симметрия) — это добавление, а не переименование, старое чтение остаётся
рабочим.
Цена: 7 / 2 / 2 / 2 / 1 плюс новый тип.

**Вердикт: исправлено добавлением.** Волна 5, `dca3924`. Появился
`AsyncControllerScopeContext` с полной тройкой — `controller`,
`controllerOrNull`, `hasController`, — и `of`/`maybeOf`/`select` семейства
возвращают его. Старое чтение через `.data` осталось рабочим: новый интерфейс
наследует прежний. Покрыто тестом, который падает на геттере, возвращающем не
тот объект.

**N8. Два разных `equals` в одном пакете.** `compare_utils.dart:13` —
`CompareUtils.equals(a, b)`, честное сравнение. `scope_state_model.dart:35` —
`ScopeStateNotifier.equals(previous, current)`, по умолчанию `false`, и это не
сравнение, а ответ на вопрос «считать ли новое состояние тем же, чтобы не
дёргать слушателей». Значение по умолчанию выдаёт подмену: «равенство»,
которое всегда ложно. Предлагаю `isSameState` (или `shouldSkipNotification` с
инверсией смысла) — тогда `CompareUtils.equals` остаётся единственным
`equals` в пакете.
Цена: 4 / 2 / 1 / 1 / 0.

**Вердикт: исправлено с инверсией смысла.** Волна 5, `dca3924`. Владелец
выбрал не `isSameState`, а `shouldNotify` — то есть поменял и имя, и знак: по
умолчанию `true`, и `update` уведомляет, когда хук говорит «да». Переопределение
с `@override` перестаёт компилироваться, без `@override` — молчит, и об этом
прямо сказано в `CHANGELOG`.

**N9. `paramsOf` и `selectParam` — число расходится внутри одной пары.**
`scope_base.dart:135, 152`, `scope_core.dart:22, 42`, и то же в
`lite_scope_*`. Один и тот же объект (виджет-параметры скоупа) в одном имени
множественный, в другом единственный. Соседняя пара ровная: `of`/`select`.
Предлагаю `selectParams` — выбирают-то из параметров, а не из параметра.
Цена: 4 / 11 / 8 / 15 / 25 — почти вся цена в примерах и зеркалах.

**Вердикт: не подтвердилось.** Владелец: `paramsOf` отдаёт все параметры, а
`selectParam` вытаскивает одно значение — число здесь несёт смысл, а не
разнобой. Вариант `widgetOf`/`selectWidget` отвергнут отдельно, и по причине,
которой в находке не было: слово «widget» уже занято семейством
`ScopeWidgetBase`, где `of` возвращает именно виджет, так что правка развела бы
одну и ту же вещь по двум именам в зависимости от семейства.

## Б. Несогласованность семейств

Эти находки нельзя брать по одной: правка одного семейства без остальных
делает разнобой больше, а не меньше.

**N10. Шаг инициализации называется по-разному в каждом семействе.**
`AsyncScopeBase.initAsync()`, `AsyncDataScopeBase.initData()`,
`ScopeAutoDependencies.init()`, `Scope.initDependencies()`, `LiteScope.init()`,
`LiteScopeState.initAsync()`, `AsyncControllerScopeElementBase.initDataAsync()`.
Семь имён одного места в жизненном цикле. Часть различий содержательна
(`initDependencies` действительно возвращает зависимости), часть — нет:
`initAsync` и `initData` отличаются только тем, что второй несёт значение.
Хуже другое: в `LiteScope` **оба** имени заняты разными вещами — `init()` на
виджете возвращает `Stream<AsyncScopeInitState>`, а `initAsync()` на состоянии
возвращает `FutureOr<void>`. То же с освобождением: `disposeAsync`,
`disposeData`, `dispose`.
Предлагаю не унифицировать всё, а закрыть коллизию в `LiteScope` и объяснить
остальное дартдоком: переименовать `LiteScopeState.initAsync/disposeAsync` в
`onInitAsync/onDisposeAsync` или в `stateInit/stateDispose`.
Цена: `initAsync` 27 / 48 / 16 / 10 / 3, `disposeAsync` 61 / 114 / 44 / 27 / 4
— по всему пакету это самая дорогая правка списка, поэтому и предлагается
только её узкая часть.

**Вердикт: исправлено шире, чем предлагала находка.** Волна 4, `be530b2`.
Находка предлагала тронуть только слой состояния и дать его хукам префикс `on`.
Владелец отверг префикс — по правилу, которое сам и сформулировал: голый глагол
значит, что метод делает названное, а `on…` — что он лишь вызывается при
событии; `initAsync` делает инициализацию, так что `on` был бы ложью. Вместо
этого объект назван с обеих сторон: `initScope`/`disposeScope` на слое скоупа
(туда же ушёл `LiteScope.init()`) и `initStateAsync`/`disposeStateAsync` на слое
состояния. Хвостом пошли таймауты, названные по методу:
`disposeScopeTimeout`, `onDisposeScopeTimeout`, `defaultDisposeScopeTimeout`.

**N11. Параметры удобных виджетов и переопределяемые методы говорят на разных
языках, и `AsyncControllerScope` выпадает из обоих.** У `AsyncScope`:
`mount`/`init`/`unmount`/`dispose` — против `onMount`/`initAsync`/`onUnmount`/
`disposeAsync` у базового класса. Схема понятна: параметр — существительное-
колбэк, метод — глагол. Но у `AsyncControllerScope` параметр зовётся `create`,
а метод — `createController`, то есть ни `mount`-подобной пары, ни `init`.
Предлагаю `createController` в параметре тоже — либо `create` и в методе.
Цена: 7 / 2 / 2 / 2 / 1.

**Вердикт: исправлено, ценой, которой находка не знала.** Волна 4,
`be530b2`. Параметр зовётся как метод — но поле не может носить имя метода,
который оно реализует (`conflicting_field_and_method`), и это выяснилось только
на анализаторе. Поэтому четыре колбэка каждого удобного виджета стали
приватными полями и остались только параметрами конструктора. Владелец
подтвердил цену отдельным решением.

**N12. `ScopeController` — три хука, из них один с `on`.**
`scope_controller.dart`: `init()`, `onUnmount()`, `dispose()`. Соседний
`ScopeDependencies` — то же самое: `onUnmount()` и `dispose()`. Либо все три с
`on` (и тогда `onInit`/`onUnmount`/`onDispose`), либо все без.
Здесь же: публичные `performInit()`/`performUnmount()`/`performDispose()` —
это вызовы фреймворка, а не пользователя, и имя «perform» их не отделяет;
пометить их `@internal` дешевле, чем переименовать.
Цена: 3 / 8 / 5 / 3 / 0 (`performInit`).

**Вердикт: не подтвердилось, обе половины.** Тройка `init`/`onUnmount`/
`dispose` у `ScopeController` названа точно по правилу владельца, а не
вразнобой. Публичные `performInit`/`performUnmount`/`performDispose` оставлены:
`perform…` — флаттеровская идиома для точки входа фреймворка
(`performRebuild`, `performLayout`), дартдок каждой говорит «Called by the
scope», и ими законно пользуется юнит-тест, гоняющий контроллер без дерева.

**N13. `AsyncControllerScopeBase` строит без `progress`, три других семейства —
с ним.** `async_controller_scope_base.dart`: `buildOnInitializing(context)` и
`buildOnError(context, error, stackTrace)` против
`buildOnInitializing(context, progress)` и `buildOnError(context, error,
stackTrace, progress)` у `AsyncScope`, `AsyncDataScope` и `Scope`. Это
асимметрия сигнатур, а не имён, и она может быть намеренной: контроллер
создаётся одним вызовом, прогрессу неоткуда взяться. Но тогда это стоит сказать
в дартдоке — сейчас там ни слова, и человек, переходящий с `AsyncDataScope`,
читает пропажу аргумента как ошибку.
Цена: правка дартдока, кода не касается.

**Вердикт: исправлено дартдоком, как находка и предлагала.** Волна 5,
`dca3924`. Сигнатуры не тронуты; `buildOnProgress` и `buildOnError` семейства
контроллера теперь сами говорят, почему у них нет `progress`.

## В. Внутренние имена

Потребитель их не видит, ломающими они не являются, гейт после них тот же.

**N14. Булевы поля живут по четырём схемам сразу.** `_didInit`, `_didUnmount`,
`_didListen`, `_didStartAsyncInit` — «did»; `_isDisposing`, `_isRebuilding`,
`_isDisposed`, `_isCaptured` — «is»; `_notifyPending`, `_forceRebuild`,
`_initStarted`, `_initSucceeded`, `_scopeKeyObserved`, `_scopeKeySettled` — без
префикса; `_disposalIsOver` (`async_scope_core.dart:197`) — вообще фраза, и
плохая: «disposal is over» о состоянии «разбор закончился» звучит как «пора
заканчивать». Предлагаю `_disposalFinished` и, если браться шире, свести
остальные к «did» для случившегося и «is» для длящегося.

**Вердикт: исправлено частично, по решению владельца.** Волна 1, `2c16390`.
Правлено одно поле — `_disposalIsOver` стало `_disposalFinished`. Остальные три
схемы оставлены: «случилось однажды», «длится сейчас» и «факт» — это различие
осмысленное, и сведение к одной схеме было бы шумом.

**N15. `_isNotifyOnlyRebuild` не читается.** `scope_widget_core.dart:169`.
Речь о перестроении, вызванном только уведомлением зависимых, — то есть
`_isNotifyingOnlyRebuild` или `_rebuildIsNotifyOnly`.

**Вердикт: исправлено.** Волна 1, `2c16390`. `_rebuildIsNotifyOnly` —
подлежащее то же, что в его собственном дартдоке.

**N16. Одна и та же проверка названа двумя способами, и параметр у неё разный.**
`check_disposed.dart`: `throwWhenDisposed(object, isDisposed, disposeMethod)` и
`debugAssertNotDisposed(object, isDisposed, method)`. «When disposed» против
«not disposed» — противоположные формулировки одного условия, а третий параметр
у них называется по-разному, хотя это одно и то же имя метода.

**Вердикт: исправлено.** Волна 1, `2c16390`. `throwIfDisposed`, и третий
параметр зовётся `disposeMethod` в обеих. `debugAssertNotDisposed` не тронут: он
буквально повторяет имя из Flutter.

**N17. Вокруг «как эта штука называется в журнале» пять слов.** `name`
(`ScopeDependency`), `wrappedName` (`scope_dependency.dart:57`), `reportName`
(`async_scope_core.dart:51`, `async_scope_parent.dart:38`,
`async_scope_coordinator.dart:111`), `_debugName` (`scope_coordination.dart`),
`path` (`ScopeLogger`, `ScopeAutoDependenciesProgress`). Каждое своё дело
делает, но человеку, который ищет «где формируется имя в логе», приходится
знать все пять.

**Вердикт: исправлено, и не только в именах.** Волна 1, `2c16390`.
`_debugName` записей очереди стал `_reportName`, а два места, где было выписано
`widget.toStringShort(showHashCode: true)`, зовут соседний `reportName`.
Остальные три слова оставлены: они называют разное.

**N18. `Progress.progress`.** `progress_iterator.dart`: у класса `Progress`
поле `number`, `total` и геттер `progress` — доля. `progress.progress`
объясняет себя хуже, чем `progress.fraction` или `progress.ratio`. То же
наружу вылезает в `ScopeAutoDependenciesProgress.progress`, а этот тип уже
публичный.

**Вердикт: исправлено, с уточнением к находке.** Волна 2, `18f3739`.
Выбрано `value`, а не предложенное `fraction`: это имя совпадает с параметром
`LinearProgressIndicator`, куда число чаще всего и едет.
`ScopeAutoDependenciesProgress.progress` переименован следом.

**N19. `ProgressIterator` мешает «шаг» и «прогресс».** `currentStep` — это
`Progress`, `nextStep()` — сдвиг на единицу, `add(int n)` — на `n`. Либо всё в
шагах (`step`, `nextStep`, `addSteps`), либо всё в прогрессе.

**Вердикт: исправлено.** Волна 2, `18f3739`. `add(int n)` стал
`addSteps(int n)` — слово, которое `nextStep` и `currentStep` уже использовали.

**N20. Публичный `DepHelper` живёт в `scope_dependency_impl.dart`.** «Impl» в
имени файла обещает внутренности; см. N4 — переезд напрашивается вместе с
переименованием.

**Вердикт: исправлено вместе с N4.** Волна 2, `18f3739`.

## Г. Проверено и менять не за что

- `buildOnWaiting` / `buildOnInitializing` / `buildOnReady` / `buildOnError` /
  `buildOnClosing` / `buildOnState` — ровное семейство во всех пяти скоупах;
- четыре таймаута и четыре колбэка к ним (`scopeKeyTimeout` ↔
  `onScopeKeyTimeout` и далее) — ровно, включая порядок в конструкторе;
- `of` / `maybeOf` / `select` — ровно везде, включая статические варианты на
  `*Core`;
- `ScopeStateModel` / `ScopeStateNotifier` / `ScopeStateModelView` и та же
  тройка с `WithError` — ровно;
- `v` / `d` / `i` / `e` у логгера — идиома логирования, разворачивать незачем;
- `AsyncScopeWaiting` / `AsyncScopeProgress` / `AsyncScopeReady` и их аналоги в
  `ScopeInitState` и `AsyncDataScopeInitState` — ровно;
- `isRoot`, `onPop`, `navigatorKey` у `NavigationNode` — повторяют словарь
  `Navigator`, и это правильно.

## Что я предлагаю взять

Одной волной, от дешёвого к дорогому, и только раздел А:

1. **N2** (11 вхождений, никаких документов) — чистая правка.
2. **N1** (`defaultScopeKeyTimeout`) — ошибка в публичном имени, дешёвая.
3. **N8** (`isSameState`) — снимает двойное `equals`.
4. **N4** (`ScopeDependencyHandle` + переезд из `_impl`).
5. **N5** (`ScopeLogCallback` / `ScopeInitCallback`).
6. **N3** (`initializingBuilder`) — дороже из-за тестов и зеркал.
7. **N9** (`selectParams`) — дороже всех из-за примеров.
8. **N7** (`AsyncControllerScopeContext`) — добавление, не переименование.

Раздел Б я бы взял только в части N11 и N13 (дёшево и точно), а N10 и N12
оставил бы владельцу: там цена измеряется сотнями вхождений, а выигрыш —
вкусовой. Раздел В можно делать когда угодно и хоть по одной находке: он
никого не ломает.
