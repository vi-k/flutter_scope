# План переименований

> **Состояние на 2026-08-18:** выполнено целиком, пятью волнами —
> `2c16390` (внутренние), `18f3739` (мелкий публичный), `0124289` (билдеры),
> `be530b2` (жизненный цикл), `dca3924` (интерфейс, контекст, хук). Каждая
> волна прошла гейт §6 на 3.27.0. Вердикты по находкам — в аудите.
> **Что это:** спека волны имён — что во что переименовывается, в каком
> порядке и что при этом обязано измениться вместе с кодом.
> **Связанные записи:** `2026-08-18[1]-naming-review.md` (аудит, из которого
> взяты находки и их номера).

Владелец прошёл по всем двадцати находкам аудита и по каждой дал решение. Ниже
— его решения как задание, плюс порядок волн. Номера находок сохранены: N1…N20
из аудита, суффикс «бис» — уточнение, всплывшее по ходу разбора.

## Правило, которое владелец сформулировал по ходу

**Голый глагол — метод делает то, чем назван. `on…` — метод вызывается, когда
это случилось, но сам этого не делает.**

`initScope()` инициализирует, `disposeScope()` освобождает, `onUnmount()` не
размонтирует — он лишь получает управление, когда скоуп уходит. По этому
правилу сняты две находки (N12 целиком и половина N10), и по нему же названы
новые имена. Правилу подчиняются методы и колбэки; билдеры живут по своей
схеме — суффикс `Builder` у параметра, `buildOn…` у метода.

## Что меняется

### Раздел А — публичный API

| # | было | станет |
| --- | --- | --- |
| N1 | `ScopeConfig.defaultScopeKeysTimeout` | `defaultScopeKeyTimeout` |
| N2 | `ScopeDependencySuccessStates` | `ScopeDependencyAnySuccess` |
| N2 | `ScopeDependencyFailedStates` | `ScopeDependencyAnyFailed` |
| N2 | `ScopeDependencyCancelledStates` | `ScopeDependencyAnyCancelled` |
| N3 | параметр `initBuilder` | `progressBuilder` |
| N3-бис | метод `buildOnInitializing` | `buildOnProgress` |
| N4 | `DepHelper` | `ScopeDependencyHandle` |
| N5 | `ScopeLogFn` | `ScopeLogCallback` |
| N5 | `ScopeInitFunction` | `ScopeInitCallback` |
| N5-бис | `ScopeInitBuilder` | `ScopeProgressBuilder` |
| N6 | `ScopeDependency.runInit` / `runDispose` | `init` / `dispose` |
| N6 | прежние `ScopeDependency.init` / `dispose` | приватные `_runInit` / `_runDispose` |
| N7 | — | новый `AsyncControllerScopeContext` |
| N8 | `ScopeStateNotifier.equals` | `shouldNotify`, смысл инвертирован |
| N9 | `paramsOf` / `selectParam` | **не меняется** |

Подробности, которые из таблицы не видны:

- **N1** — вместе с именем правится дартдок: «waiting for `scopeKeys` to be
  released» → `scopeKey`. Три соседние настройки уже повторяют имя своего
  параметра, эта становится четвёртой;
- **N2** — переименование задевает только `switch`-сопоставления внутри
  `lib` и один тест; документов и примеров не касается;
- **N4** — класс переезжает из `scope_dependency_impl.dart` в собственный файл
  `scope_dependency_handle.dart` (это N20, отдельного пункта у неё нет);
- **N6** — в интерфейсе остаются `init()`/`dispose()`, и это те методы, что
  ведут `state`; сырой шаг реализации становится приватным `_runInit()` /
  `_runDispose()`. Все вызовы в `lib` и тестах идут через обёртки, так что
  меняются только их имена;
- **N7** — **добавление, а не переименование**: интерфейс
  `AsyncControllerScopeContext<W, C> implements AsyncDataScopeContext<W, C>`
  с `controller`, `controllerOrNull`, `hasController`. `of`, `maybeOf` и
  `select` семейства контроллера начинают возвращать его. Старое чтение через
  `.data` остаётся рабочим — оно унаследовано;
- **N8** — **смысл инвертируется**: `equals` возвращал `false` по умолчанию
  («не равны — уведомляем»), `shouldNotify` возвращает `true` («уведомляем»).
  Тот, кто переопределял `equals` с `@override`, получит ошибку компиляции —
  это и нужно; но в `CHANGELOG` инверсию надо назвать прямо, потому что
  переопределение без `@override` промолчит;
- **N9** — находка не подтвердилась: `paramsOf` отдаёт все параметры,
  `selectParam` вытаскивает одно значение, и число здесь несёт смысл.

### Раздел Б — жизненный цикл

**N10. Слой скоупа — виджет и элемент:**

| было | станет |
| --- | --- |
| `AsyncScopeBase.initAsync` / `AsyncScopeElementBase.initAsync` | `initScope` |
| `AsyncScopeBase.disposeAsync` / `AsyncScopeElementBase.disposeAsync` | `disposeScope` |
| `LiteScope.init()` | `initScope()` |
| `AsyncDataScopeBase.initData` / `disposeData` | не меняются — объект уже назван |
| `Scope.initDependencies` | не меняется |
| `AsyncControllerScopeBase.createController` | не меняется |

**N10. Слой состояния:**

| было | станет |
| --- | --- |
| `LiteScopeCoreState.initAsync` | `initStateAsync` |
| `LiteScopeCoreState.disposeAsync` | `disposeStateAsync` |
| `onUnmount` | не меняется |

Суффикс `Async` уходит со слоя скоупа (там возвращается `Stream`, синхронного
близнеца нет) и остаётся на слое состояния: там есть синхронный `initState`
самого Flutter, и `Async` отличает от него асинхронную половину.

**N10-бис. Таймаут, названный по методу, идёт за методом:**

| было | станет |
| --- | --- |
| `disposeAsyncTimeout` | `disposeScopeTimeout` |
| `onDisposeAsyncTimeout` | `onDisposeScopeTimeout` |
| `ScopeConfig.defaultDisposeAsyncTimeout` | `defaultDisposeScopeTimeout` |

`initCancellationTimeout` и `onInitCancellationTimeout` не трогаем: они
названы по событию, а не по методу.

**N11. Параметр удобного виджета зовётся ровно как метод, который он
замещает:**

| виджет | было | станет |
| --- | --- | --- |
| `AsyncScope` | `mount` / `init` / `unmount` / `dispose` | `onMount` / `initScope` / `onUnmount` / `disposeScope` |
| `AsyncDataScope` | `mount` / `init` / `unmount` / `dispose` | `onMount` / `initData` / `onUnmount` / `disposeData` |
| `AsyncControllerScope` | `create` | `createController` |

Билдеры под это правило не попадают: у параметра суффикс `Builder`
(`waitingBuilder`, `progressBuilder`, `errorBuilder`, `builder`), у метода —
`buildOn…`.

**N12 — не подтвердилась.** Тройка `ScopeController.init` / `onUnmount` /
`dispose` названа точно по правилу выше. Публичные `performInit`,
`performUnmount`, `performDispose` остаются: `perform…` — флаттеровская идиома
для точки входа, которую зовёт фреймворк (`performRebuild`, `performLayout`),
дартдок каждой говорит «Called by the scope», и ими законно пользуется
юнит-тест, гоняющий контроллер без дерева виджетов.

**N13 — только дартдок.** У `AsyncControllerScopeBase` билдеры без `progress`,
и это намеренно: инициализация контроллера не рапортует шагов, стрим отдаёт
сразу `Ready`. Сейчас это сказано комментарием в реализации; надо сказать в
дартдоке `buildOnProgress` и `buildOnError` этого семейства.

### Раздел В — внутренние имена

| # | было | станет |
| --- | --- | --- |
| N14 | `_disposalIsOver` | `_disposalFinished` |
| N15 | `_isNotifyOnlyRebuild` | `_rebuildIsNotifyOnly` |
| N16 | `throwWhenDisposed` | `throwIfDisposed` |
| N16 | параметр `method` у `debugAssertNotDisposed` | `disposeMethod` |
| N17 | `_debugName` у `AccessEntry` и `ChildEntry` | `_reportName` |
| N18 | `Progress.progress` | `Progress.value` |
| N18 | `ScopeAutoDependenciesProgress.progress` | `value` |
| N19 | `ProgressIterator.add(int n)` | `addSteps(int n)` |

Остальные булевы поля (`_didUnmount`, `_isDisposing`, `_notifyPending` и
прочие) остаются: три схемы различают «случилось однажды», «длится сейчас» и
«факт», и это различие осмысленное. `debugAssertNotDisposed` не трогаем — имя
буквально повторяет `ChangeNotifier.debugAssertNotDisposed` из Flutter.

**N17 тянет за собой правку не имени, а кода:** в `async_scope_core.dart:516`
и `:566` выписано выражение `widget.toStringShort(showHashCode: true)` —
ровно то, что возвращает `reportName` того же класса. Оба места зовут геттер.

## Порядок волн

Каждая волна — отдельный коммит, и каждая заканчивается зелёным гейтом §6
целиком, включая сьюты примеров. Публичное имя, изменившись, тянет за собой
строку в `CHANGELOG.md`, правку `doc/*.md` и **зеркала `docs/ru/` в том же
коммите** (§7 регламента), плюс `sh docs/ru/stamp.sh`.

1. **Волна 1 — внутренние (N14, N15, N16, N17).** Ничего публичного,
   `CHANGELOG` не трогается, документов нет. Самая безопасная, идёт первой,
   чтобы дальше диффы были только про API.
2. **Волна 2 — мелкий публичный (N1, N2, N4+N20, N5, N5-бис, N18, N19).**
   Независимые друг от друга переименования, каждое узкое.
3. **Волна 3 — билдеры (N3, N3-бис).** `progressBuilder` и `buildOnProgress`
   вместе: параметр и метод — одна пара, порознь их разводить нельзя.
4. **Волна 4 — жизненный цикл (N10, N10-бис, N11).** Самая большая: ~500
   вхождений по коду, тестам, документам, зеркалам и примерам. Делается одним
   куском, потому что имена связаны: параметр повторяет метод, таймаут
   повторяет метод.
5. **Волна 5 — интерфейс и контекст (N6, N7, N8, N13).** N6 меняет форму
   интерфейса, N7 добавляет тип, N8 инвертирует смысл хука, N13 — дартдок.
   Каждая из трёх первых требует своего абзаца в `CHANGELOG`.

## Чего в волнах нет

- N9 и N12 — вердикт «не подтвердилось», кода не касаются;
- переименования, которых владелец не выбирал (`selectParams`, `widgetOf`,
  сведение булевых полей к одной схеме, `initializingBuilder`, `AnyFailed`
  вместо единственного числа и прочие варианты из аудита) — они остались в
  аудите как отвергнутые и повторно не предлагаются.
