# Архитектура scopo

> Обновлено: 2026-08-12, по коду версии 0.10.0 (`main`, `a97bb74`).
> Документ описывает устройство пакета изнутри: слои, жизненный цикл,
> координацию и инварианты. Публичный API и примеры использования — в
> `README.md` и dartdoc; текущее состояние работ — в `docs/handoff.md`.
> Расходится с кодом — верен код, документ надо поправить.

## 1. Что это за пакет

scopo — Flutter-пакет для управления скоупами в дереве виджетов. Скоуп
владеет зависимостями и состоянием, инициализирует их асинхронно, отдаёт
поддереву и утилизирует по порядку — после того как исчезли дочерние скоупы.

Три вещи, вокруг которых построено всё остальное:

1. **Жизненный цикл живёт в элементе**, а не в `State`. Элемент переживает
   перестроения виджета, доступен потомкам напрямую и может держать
   асинхронные операции, которые длиннее одного кадра.
2. **Асинхронность двусторонняя.** Инициализация — это `Stream` с прогрессом,
   который можно отменить; утилизация — `Future`, которого дожидаются родитель
   и следующий владелец `scopeKey`.
3. **Уведомление ≠ перестроение.** Потомок подписывается на одно значение, и
   его уведомляют, не перестраивая поддерево самого скоупа.

## 2. Карта каталогов

```
lib/scopo.dart                 публичный барель: экспорты
lib/src/scope/scope.dart       единая library, все слои — её part-файлы
lib/src/scope/a_base/          базовые интерфейсы поиска в дереве
lib/src/scope/b_scope_widget/  элемент со селективными подписками
lib/src/scope/c_scope_model/   + произвольная модель
lib/src/scope/d_scope_notifier/+ модель-Listenable
lib/src/scope/e_async_scope/   + асинхронный жизненный цикл и координация
lib/src/scope/f_async_data_scope/ + одно значение данных
lib/src/scope/g_lite_scope/    + State, close(), экран закрытия
lib/src/scope/h_scope/         + контейнер зависимостей
lib/src/environment/           ScopeConfig и ScopeObserver
lib/src/utils/                 самостоятельные утилиты, часть публична
```

Слои названы буквами `a`…`h` по возрастанию возможностей: каждый следующий
наследует предыдущий. Все они — `part` одной библиотеки
(`lib/src/scope/scope.dart`), поэтому приватные члены видны между слоями.
Это осознанный выбор (элементы разных слоёв тесно связаны), но у него есть
цена: приватное поле одного слоя — часть контракта для другого, и правка
`_shouldOnlyNotify` в `b_` ломает закрытие скоупа в `g_`. Единственное
исключение — `e_async_scope/scope_coordination.dart`: обычная библиотека без
Flutter, импортируемая, а не `part`.

## 3. Слои

| Слой | Виджет | Элемент | Что добавляет |
| --- | --- | --- | --- |
| `a_base` | `ScopeInheritedWidget` | `ScopeInheritedElement` (интерфейс) | Поиск скоупа в дереве: `ScopeContext.of/maybeOf/select` |
| `b_scope_widget` | `ScopeWidgetCore`, `ScopeWidgetBase` | `ScopeWidgetElementBase` | Селективные подписки, `notifyDependents()` |
| `c_scope_model` | `ScopeModelCore`, `ScopeModelBase`, `ScopeModel` | `ScopeModelElementBase` | Модель `M extends Object` |
| `d_scope_notifier` | `ScopeNotifierCore`, `ScopeNotifierBase`, `ScopeNotifier` | `ScopeNotifierElementBase` | Модель `M extends Listenable`, подписка элемента на неё |
| `e_async_scope` | `AsyncScopeCore`, `AsyncScopeBase`, `AsyncScope`, `AsyncScopeCoordinator` | `AsyncScopeElementBase` | Асинхронные инициализация и утилизация, `scopeKey`, координация |
| `f_async_data_scope` | `AsyncDataScopeCore`, `AsyncDataScopeBase`, `AsyncDataScope` | `AsyncDataScopeElementBase` | Одно значение данных, полученное при инициализации |
| `g_lite_scope` | `LiteScopeCore`, `LiteScope` | `LiteScopeElementBase` + `LiteScopeCoreState` | `State` через `GlobalKey`, `close()`, экран закрытия |
| `h_scope` | `ScopeCore`, `Scope` | `ScopeElementBase` + `ScopeCoreState` | Контейнер зависимостей `ScopeDependencies` |

Цепочки наследования идут параллельно — по виджетам и по элементам — и в одном
месте расходятся:

```
виджеты:  ScopeInheritedWidget → ScopeWidgetCore → ScopeModelCore → AsyncScopeCore
                                                 ↘ ScopeNotifierCore
элементы: ScopeWidgetElementBase → ScopeModelElementBase → ScopeNotifierElementBase
                                                         → AsyncScopeElementBase
```

`AsyncScopeCore` наследует `ScopeModelCore`, а не `ScopeNotifierCore`, тогда
как элемент наследует именно `ScopeNotifierElementBase`. Причина утилитарная:
модель скоупа (`AsyncScopeModel`, он же `ScopeStateModel<AsyncScopeState>`)
реализует `Listenable`, и элементу нужна подписка на неё из
`ScopeNotifierElementBase.init()` (`model.addListener(notifyDependents)`), а
виджету от `ScopeNotifierCore` не нужно ничего.

Каждый слой даёт три вида классов: `…Core` — минимальная основа для своих
расширений; `…Base` — готовый к наследованию именованный скоуп со своими
статическими аксессорами; и, где это осмысленно, конечный виджет
(`ScopeModel`, `ScopeNotifier`, `AsyncScope`, `AsyncDataScope`) с колбэками
`create`/`init`/`dispose`/`builder`.

## 4. Подписки и уведомления (`b_scope_widget`)

Потомок находит скоуп через `context.getElementForInheritedWidgetOfExactType`,
а подписывается через `dependOnInheritedElement` с `aspect` — парой
`(текущее значение, селектор)`. При уведомлении элемент прогоняет селекторы и
дёргает `didChangeDependencies` только там, где значение изменилось
(`_notifyDependent`). Подписка без селектора (`aspect == null`) означает «на
любое изменение» и вытесняет все точечные.

Три механизма, которые стоит знать до правок:

- **Самоподписка.** `InheritedElement.notifyClients` не разрешает элементу
  зависеть от самого себя (там assert), а скоупу это нужно — например, чтобы
  перестроиться на смену фазы инициализации. Такие подписки лежат отдельно, в
  `_selfDependencies`, и обрабатываются перед вызовом `super.notifyClients`.
- **`notifyDependents()`** ставит `_shouldOnlyNotify` и помечает элемент
  грязным. На перестроении (`performRebuild`) он уведомляет подписчиков, но
  `updateChild` возвращает **старого** ребёнка — поддерево скоупа не
  перестраивается. Уведомление обязано пройти через `didChangeDependencies`, а
  тот работает только внутри кадра, отсюда этот обходной путь.
- **`_forceRebuild`** отменяет предыдущий пункт: поддерево строится в любом
  случае. Взводится, когда родитель обновляет элемент (`update`), когда у
  элемента есть автоматическая самозависимость (`autoSelfDependence`, им
  пользуются фазы инициализации) и вручную — в закрывающем кадре `LiteScope`
  (см. §7). Без этого отложенный `notifyDependents` съедал бы кадр, в котором
  монтируется `ScreenshotReplacer`.

## 5. Асинхронный жизненный цикл (`e_async_scope`)

Состояние скоупа — `AsyncScopeState`: `AsyncScopeWaiting` → `AsyncScopeProgress`
(сколько угодно раз) → `AsyncScopeReady` либо `AsyncScopeError`. Оно живёт в
`_AsyncScopeNotifier` (наружу отдаётся неизменяемое представление
`model.asUnmodifiable()`), и `buildOnState` выбирает по нему ветку сборки.

### Инициализация — `_performAsyncInit()`, запускается из `mount()`

1. Пост-фрейм-колбэком скоуп регистрируется у родителя — если к тому моменту
   он ещё не начал утилизироваться.
2. **`scopeKey` читается ровно один раз.** Ответ (в том числе `null`) обязателен
   до конца утилизации: очередь, в которую встал скоуп, сменить нельзя.
3. Если ключ есть: ищется ближайший координатор (**до** создания `AccessEntry`
   — это единственный шаг, который может упасть, когда освобождать ещё
   нечего), создаётся запись, и скоуп встаёт в очередь ключа с таймаутом
   `scopeKeyTimeout ?? ScopeConfig.defaultScopeKeysTimeout`.
4. После ожидания проверяются три условия отмены: `entry.isCancelled`,
   `!mounted`, `_isDisposing`. Третье нужно потому, что `close()` оставляет
   элемент смонтированным, а `_subscription` на этой стороне `await` ещё не
   существует — отменять было бы нечего.
5. Подписка на `initAsync()`: `AsyncScopeProgress` сразу идёт в модель,
   `AsyncScopeReady` — через пост-фрейм-колбэк (или через задержку
   `pauseAfterInitialization`), чтобы последний прогресс успел показаться.
   Тогда же взводится `_initSucceeded` и завершается `_initCompleter`.
6. Ошибки: до `Ready` — модель переходит в `AsyncScopeError`; после `Ready` —
   ошибка репортится через `FlutterError.reportError`, а состояние не
   трогается: ресурсы уже захвачены, виджеты готовой ветки уже на экране, и
   подмена их на `buildOnError` была бы хуже.

### Утилизация — `_performAsyncDispose()`, из `dispose()` или из `close()`

1. `_isDisposing = true`.
2. Отменяется ожидание ключа (`entry.cancel()`) и подписка на инициализацию.
3. Ожидается `_initCompleter` — инициализация должна закончиться, чем угодно.
4. `waitForChildren(...)` — дочерние скоупы, с таймаутом
   `waitForChildrenTimeout ?? ScopeConfig.defaultWaitForChildrenTimeout`.
5. `disposeAsync()` — **только если `_initSucceeded`**: нечего освобождать,
   если ничего не захватывали.
6. `finally`: скоуп снимается с учёта у родителя, выходит из очереди ключа
   (`exit()` — по `_acquiredScopeKey`, а не по текущему значению геттера),
   взводится `_scopeKeySettled`, утилизируется модель.

### Флаги элемента и зачем они

| Флаг | Зачем |
| --- | --- |
| `_initSucceeded` | Инициализация дошла до `Ready`. Отдельно от `model.state`, потому что состояние применяется отложенным колбэком: элемент могли убрать из дерева раньше, а освобождать захваченное всё равно надо |
| `_isDisposing` | Утилизация началась. `mounted` этого не покажет: после `close()` элемент остаётся в дереве |
| `_scopeKeyObserved` | `scopeKey` уже прочитан. Отдельно от значения, потому что `null` — полноценный ответ |
| `_scopeKeySettled` | Утилизация освободила всё, что связано с ключом; с этого момента диагностика ключа молчит |
| `_acquiredScopeKey`, `_acquiredCoordinator` | Что и где реально удерживается — против этого сверяется каждый последующий перестрой |

`_debugCheckScopeKeyOwnership()` (вызывается из `assert` в `activate()` и
`performRebuild()`) ловит четыре способа разойтись с однажды прочитанным
ответом: ключ появился, ключ пропал, ключ сменился, координатор сменился.
Ничего не чинится — освобождение ключа асинхронно, а перестроение нет, — но в
debug-сборке об этом сообщают подробно. Правильный способ сменить ключ:
дать виджету другой `Widget.key`, чтобы фреймворк создал новый элемент.

## 6. Координация (`scope_coordination.dart`, `AsyncScopeCoordinator`)

Ядро координации не зависит от Flutter и тестируется отдельно
(`test/scope_coordination_test.dart`):

- **`KeyedAccessQueues`** — FIFO-мьютекс по произвольному ключу. Вошедший в
  свободный ключ проходит сразу; очередь ключа исчезает, когда её покинул
  последний участник, поэтому неудерживаемый ключ ничего не стоит. По таймауту
  участника **впускают всё равно**: держать его вечно значило бы заморозить
  дерево, а невозвращённый ключ — ошибка удерживающего, не его преемника.
- **`AccessEntry`** — место в очереди: `exit()` освобождает ключ, `cancel()`
  отказывается от ожидания (запись остаётся в очереди до `exit()`).
- **`ChildRegistry` / `ChildEntry`** — дети, которых родитель ждёт перед
  собственной утилизацией. `waitForChildren` снимает **снимок** детей на
  момент вызова: зарегистрировавшийся позже к этому ожиданию не относится. По
  таймауту незавершённые дети выбрасываются из реестра (иначе следующее
  ожидание повисло бы на них навсегда), а `Future` завершается нормально.
  `unregister()` идемпотентен.

Над ядром — миксин **`AsyncScopeParent`** (на элементе координатора и на каждом
`AsyncScopeElementBase`) и виджет **`AsyncScopeCoordinator`**, который владеет
очередями `scopeKey` своего поддерева.

Два правила, которые легко перепутать:

1. **Очередь ключа** — у ближайшего координатора сверху. Два скоупа с
   одинаковым ключом под разными координаторами друг друга не ждут. Очереди
   принадлежат элементу координатора: заменили сам координатор — очереди
   исчезли вместе с ним, поэтому его место выше всего, что может замениться.
2. **Ожидающий родитель** — ближайший `AsyncScopeParent` сверху, но
   родительский скоуп всегда важнее координатора
   (`_registerWithParent` обходит предков и не останавливается на
   координаторе). Иначе `AsyncScopeCoordinator(child: MaterialApp(…))` внутри
   корневого скоупа перехватил бы ожидание и корень перестал бы ждать своих
   детей.

Ожидания везде ограничены таймаутом и не фатальны: истечение репортится через
`FlutterError.reportError` (либо отдаётся в `onTimeout`), а работа
продолжается. `null` в `ScopeConfig` снимает ограничение, `Duration.zero`
означает мгновенное истечение — не отсутствие лимита.

## 7. `LiteScope`: состояние, `close()` и барьер скриншота

`LiteScopeElementBase` добавляет к асинхронному скоупу `State`: элемент строит
`_LiteScopeCoreWidget` с `GlobalKey`, а `LiteScopeCoreState` получает ссылку на
элемент (`params`, `notifyDependents()`, `close()`). У состояния свой мини-цикл
`initAsync`/`disposeAsync` со своим `_initCompleter`, который элемент
дожидается в собственной утилизации.

`close()` — утилизация без удаления из дерева:

- барьер `_screenshotCompleter` ставится, только если элемент смонтирован и
  находится в `Ready`; в любом другом состоянии освобождать барьер было бы
  некому и `close()` не завершился бы никогда;
- барьер ставится не более одного раза на элемент — повторный `close()` не
  должен подменить тот, которого ждёт уже идущая утилизация;
- один прогон утилизации на элемент (`_closeCompleter`), и все вызывающие —
  явный `close()`, второй `close()`, неявная утилизация при размонтировании —
  получают один и тот же результат, включая ошибку;
- закрывающий кадр строится принудительно (`_forceRebuild = true` +
  `markNeedsBuild`), иначе отложенный `notifyDependents` заставил бы
  `updateChild` вернуть старого ребёнка и `ScreenshotReplacer` не смонтировался
  бы вовсе;
- `buildOnReady` в этом кадре отдаёт `Stack` из `ScreenshotReplacer` (снимок
  живого поддерева) и `buildOnClosing()` поверх него;
- страховка: `dispose()` элемента освобождает барьер сам, а
  `ScreenshotReplacer` ограничен `maxRetries` — поддерево, которое никогда не
  рисуется, снять нельзя, и после исчерпания попыток закрывающий экран рисуется
  поверх живого поддерева.

После `close()` элемент остаётся смонтированным и его можно двигать с
`GlobalKey` — именно поэтому по всему `e_async_scope` проверяется
`_isDisposing`, а не только `mounted`.

## 8. Зависимости (`h_scope`)

`Scope` = скоуп + контейнер зависимостей + состояние.

- **`ScopeDependencies`** — интерфейс контейнера: `unmount()` (синхронно, при
  размонтировании) и `dispose()` (можно асинхронно, после утилизации
  состояния).
- **`ScopeElementBase.initAsync()`** переводит поток `initDependencies()`
  (`ScopeInitState`: `ScopeProgress` | `ScopeReady`) в `AsyncScopeInitState`
  и по дороге запоминает готовый контейнер в `_dependencies`.
- **`ScopeAutoDependencies`** — необязательная надстройка: дерево зависимостей
  из `dep` / `sequential` / `concurrent`, автоматический прогресс
  (`ScopeAutoDependenciesProgress` + `ProgressIterator`) и автоматическая
  утилизация при ошибке (`autoDisposeOnError`).

Состояния узла дерева (`ScopeDependencyState`) делятся на успешные
(`Initial`, `Initialized`, `Disposed`, `NoDisposalRequired`), провальные
(`Failed`, `DisposalFailed`) и отменённые (`Cancelled`, `DisposalCancelled`).
Два правила, которые стоили отдельных дефектов:

- **Ошибки переживают утилизацию.** Группу утилизируют именно потому, что под
  ней что-то упало, и затирание её состояния на `Disposed` уничтожало
  единственную запись о причине. Поэтому «утилизация завершена» отслеживается
  отдельным флагом `_isDisposalDone`, а не состоянием.
- **Дерево живёт один цикл.** Каждый узел инициализируется из `Initial`, так
  что повторный `init()` на уже отработавшем дереве невозможен;
  `_prepareDependencies()` строит новое дерево, когда предыдущее полностью
  утилизировано, и явно ругается, если предыдущее ещё живо (иначе всё, что оно
  держит, утекло бы).

Ошибка узла оборачивается в `ScopeDependencyException`, которая по дороге
наверх собирает путь (`group/subgroup/dep`); анонимная группа (`name == ''`) в
путь не добавляется.

## 9. Конфигурация и оповещения

`ScopeConfig` (в `lib/src/environment/`) — статические настройки:

| Поле | Смысл |
| --- | --- |
| `observer` | `ScopeObserver?`, по умолчанию `null` — пакет молчит |
| `pauseAfterInitializationEnabled` | Глобальный выключатель искусственных пауз `pauseAfterInitialization` (нужен в тестах) |
| `defaultScopeKeysTimeout` | Ожидание освобождения `scopeKey`, по умолчанию 3 с |
| `defaultWaitForChildrenTimeout` | Ожидание утилизации дочерних скоупов, по умолчанию 3 с |

У обоих таймаутов `null` — ожидание без ограничения, `Duration.zero` —
истечение немедленно.

`ScopeObserver` (`lib/src/environment/scope_observer.dart`) — девять пустых
хуков: `onInit`, `onProgress`, `onReady`, `onCancelled`, `onDispose`,
`onDisposed`, `onError` (с `ScopePhase` из шести значений), `onTimeout`,
`onTrace`. Первый аргумент каждого — `ScopeObservable`, маркер с `debugLabel`;
его реализуют элементы скоупов всех семейств, контейнер автоматических
зависимостей и одна зависимость. Внешних зависимостей у пакета нет: до 0.10.0
на этом месте стоял `ScopeLogger` поверх `logger_builder`, и он убран целиком.

Зовут хуки через `notifyObserver` из `scope_config.dart` — единственную точку,
не экспортируемую из `scopo.dart`. Она держит `try`/`catch` (упавший хук уходит
в `FlutterError.reportError` с `library: 'scopo'`, вызывающий продолжается) и
флаг `_notifying`, отбивающий рекурсию, когда наблюдатель сам порождает событие
из хука. `ScopePrintObserver` — готовый наблюдатель из комплекта, печатает
`scopo | <метка> | <что случилось>`; `trace: false` по умолчанию.

Семейство без своей фазы инициализации (`ScopeWidget`, `ScopeModel`,
`ScopeNotifier`, `AsyncScopeCoordinator`) шлёт голую пару `onInit`/`onDisposed`
из `ScopeWidgetElementBase`; семейство со своей фазой (всё на
`AsyncScopeElementBase`) шлёт эту фазу вместо пары. Разводит их переключатель
`ScopeWidgetElementBase.reportsOwnLifecycle`.

## 10. Утилиты (`lib/src/utils/`)

Публичные (экспортируются из `scopo.dart`):

- `NavigationNode` — вложенный `Navigator`, удерживающий диалоги, шторки и
  пуш-экраны внутри текущего скоупа;
- `ProgressIterator` / `Progress` — счётчик шагов `1/3`, `2/3` для прогресса;
- `ScreenshotReplacer` — рисует поддерево один раз, снимает его и заменяет
  снимком; ограничен `maxRetries`;
- `CompareUtils` — набор компараторов для селекторов;
- расширения `Listenable`: `listen`, `select`, `ListenableSelector`,
  `ListenableView`, `StateAsNotifier`;
- `IsBuildingExtension` — `isBuilding` и `runOutsideFrame` для
  `SchedulerBinding`.

Внутренние: `run_stream_guarded` (поток, который глушится после первой ошибки,
а всё пришедшее после — отдаёт отдельному обработчику) и `check_disposed`
(`throwWhenDisposed`).

## 11. Тесты

| Файл | О чём |
| --- | --- |
| `test/scope_coordination_test.dart` | Ядро координации: `KeyedAccessQueues`, `ChildRegistry` — без Flutter |
| `test/async_scope_coordinator_test.dart` | Диагностика `scopeKey` у живого скоупа, ожидание детей координатором |
| `test/async_scope_test.dart` | Пост-фрейм-колбэки, провал инициализации, ошибка после `Ready` |
| `test/lite_scope_test.dart` | `close()` во всех вариантах, гонка инициализации с утилизацией, `ScreenshotReplacer` |
| `test/scope_auto_dependencies_test.dart` | Дерево зависимостей: пути, группы, повторная инициализация, сохранение ошибок |
| `test/async_scope_state_test.dart`, `test/scope_observer_test.dart`, `test/compare_utils_test.dart` | Точечные проверки |
| `test/utils/` | Накопитель событий наблюдателя и обёртка `fake_async` |

Слои `a_base`…`g_lite_scope` собственных наборов тестов не имеют — покрыты
только регрессионными сценариями 0.10.0. Актуальные пробелы перечислены в
`docs/handoff.md`.

## 12. Инварианты, которые легко нарушить

1. `scopeKey` читается один раз за жизнь элемента; сменить ключ или
   координатор можно только через новый `Widget.key`.
2. Ожидания (`scopeKey`, `waitForChildren`) ограничены по времени и никогда не
   фатальны: истечение — это отчёт и продолжение работы, а не исключение
   вызывающему.
3. `disposeAsync()` вызывается только после успешной инициализации; проверять
   надо `_initSucceeded`, а не `model.state`.
4. После `close()` элемент жив и смонтирован — проверка `mounted` о начавшейся
   утилизации не говорит ничего, нужен `_isDisposing`.
5. Запись в очереди освобождается по `_acquiredScopeKey`, а не по текущему
   значению `scopeKey`.
6. `notifyDependents()` не перестраивает поддерево; если кадр обязан быть
   построен, нужен `_forceRebuild`.
7. Слои — `part` одной библиотеки: приватные поля межслойны, и правка одного
   слоя может молча сломать другой. Тесты `lite_scope_test.dart` держат
   большую часть этих стыков.
