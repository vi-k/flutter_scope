# Повторное полное независимое ревью проекта перед 0.10.0

> **Состояние на 2026-08-16:** ревью завершено, код при ревью не менялся.
> Подтверждено 43 находки: 0 P0, 6 P1, 17 P2, 20 P3. Закрыты 40: все P1
> (волна 10), все P2 (волна 11) и 17 P3 (волна 12, идёт). Осталось три P3 —
> №3, №11, №19. **У каждой закрытой находки в конце стоит подраздел
> «Вердикт»**; текст самой находки исторический и не правится, даже там, где
> проверка показала, что находка была неточна.
> **Что это:** второе полное независимое ревью всей кодовой базы, публичных
> контрактов, документации и тестов scopo — после того как первое
> (`2026-08-14[10]`) было закрыто целиком и сверх него добавлено новое
> семейство `AsyncControllerScope`.
> **Связанные записи:** `2026-08-14[10]-project-review.md` (первое ревью),
> `2026-08-16[11]-async-controller-scope-report.md`,
> `2026-08-15[9]-navigation-system-back-audit-report.md`.

## Executive summary

Пакет в хорошем состоянии по всем формальным признакам: гейт из восьми команд
`AGENTS.md` §6 проходит целиком на `9296648` (222 теста зелёные, `analyze`
чист в корне и во всех трёх примерах, `dart doc` и `pub publish --dry-run` без
единого предупреждения, переводы актуальны). Код написан аккуратно и, что
редкость, **обоснован**: почти каждое неочевидное решение снабжено
комментарием, объясняющим не «что», а «почему», и эти объяснения при проверке
оказываются верными. Тестовая сьюта написана от дефектов, а не для отчёта.

Тем не менее ревью нашло **шесть находок уровня P1**, и характер у них общий:
**всё, что закрывали в первом ревью, закрыли по одному месту, а не по классу.**
Три из шести — это тот же дефект, что уже исправляли в 0.10.0, но в соседней
ветке кода:

- падение диспозера прекращает разбор соседей — починено для последовательной
  группы, оставлено в параллельной;
- падение пользовательского хука обрывает обязательную уборку — закрыто в
  `disposeAsync`, оставлено в `onUnmount` десятью строками выше;
- девять параметров жизненного цикла проброшены в новом семействе и не
  проброшены в двух старых.

Ещё две P1 — расхождение видимого поведения с документированным: синхронный
провал инициализации никогда не показывает ветку ошибки (вечный спиннер), а
первый же пример README не компилируется, потому что переименование
`unmount` → `onUnmount` доехало до кода и до `example/minimal`, но не до
README, `example/README.md` и русского зеркала. Шестая — конструктивная:
исключение из пользовательского селектора навсегда «замораживает» элемент
скоупа, и в release это тихая необратимая потеря реактивности поддерева.

Ни одна находка не является P0: нет пути, на котором пакет портит данные,
падает на штатном сценарии или течёт при обычной работе. Но три P1 — это
утечки ресурсов на путях отказа, ради которых пакет и существует, а две —
первое, что увидит человек, открывший пакет на pub.dev.

**Рекомендация: не публиковать 0.10.0 до закрытия шести P1.** Четыре из них —
правки на несколько строк.

Отдельно стоит сказать о процессе. Первое ревью закрыли добросовестно: все 18
находок исправлены, каждая с тестом и проверкой нагруженности. Но ни разу не
был задан вопрос «где ещё в кодовой базе живёт этот же дефект». Три P1 из
шести стоили бы одного grep'а по соседнему классу.

## Project overview

**Назначение.** `scopo` — инфраструктурный Flutter-пакет: скоупы в дереве
виджетов, внедрение зависимостей, асинхронная инициализация и разбор с
контролируемым порядком. 8 114 строк в `lib/` (60 файлов), 11 060 строк тестов
(23 файла), три примера, 11 страниц dartdoc-тем.

**Устройство.** Одна библиотека `lib/src/scope/scope.dart`, собранная из 46
`part`-файлов, плюс утилиты. Всё стоит на паре
`ScopeInheritedWidget` / `ScopeWidgetElementBase` (`base/base.dart`,
`scope_widget/scope_widget_core.dart`): `InheritedWidget`, чей элемент сам
решает, что показывать (`buildChild()`), и сам ведёт учёт подписок.

Поверх пары — линейная цепочка из шести семейств, каждое в трёх слоях
(`Core` → `Base` → готовый виджет с колбэками):

```
ScopeWidgetCore → ScopeModelCore → ScopeNotifierCore → AsyncScopeCore
                                                        ├→ AsyncDataScopeCore → AsyncControllerScopeCore
                                                        └→ LiteScopeCore → ScopeCore
```

То есть `Scope` — это `LiteScope` плюс дерево зависимостей, `LiteScope` — это
`AsyncScope` плюс класс состояния, а `AsyncControllerScope` — `AsyncDataScope`,
чьё значение имеет собственный жизненный цикл.

**Потоки данных.** Три независимых механизма:

1. **Инициализация** — `Stream`. `initAsync()` отдаёт `AsyncScopeProgress`
   любое число раз и `AsyncScopeReady` один; поток проходит через `map`
   (семейство сохраняет значение) и `asyncMap` (ядро ставит `_initSucceeded`
   и обновляет модель).
2. **Оповещение** — `ChangeNotifier` внутри элемента (`_AsyncScopeNotifier`)
   плюс собственный учёт селекторов поверх `InheritedElement`. Зависимый
   регистрирует пары `(значение, селектор)`; при уведомлении скоуп прогоняет
   селекторы и будит только тех, у кого результат изменился.
3. **Разбор** — четыре стадии в `_performAsyncDispose`, каждая под своей
   защитой, плюс координация через `KeyedAccessQueues` (FIFO-мьютекс по
   `scopeKey`) и `ChildRegistry` (родитель ждёт детей).

**Границы модулей.** `scope_coordination.dart` (очереди и реестр) — чистые
структуры без Flutter, импортируются, наружу не экспортируются;
`run_stream_guarded.dart` и `check_disposed.dart` — тоже внутренние.
Публичная поверхность — около 80 типов из `lib/scopo.dart`.

## Critical and high-severity findings

P0 не найдено.

### P1-1. Первый пример README не компилируется

**severity:** High · **confidence:** high
**файлы:** `README.md:71-73`, `example/README.md:183-185`,
`docs/ru/README.md:75-77`; эталон — `lib/src/scope/full_scope/scope_dependencies.dart:13`

`ScopeDependencies` объявляет `void onUnmount();`. README, вкладка Example и
русское зеркало показывают:

```dart
/// Called synchronously when the scope is unmounted.
@override
void unmount() {}
```

0.10.0 переименовал `unmount` → `onUnmount` (`CHANGELOG.md`, помечено
`[breaking changes]`). Код, `doc/full_scope.md:65-67` и
`example/minimal/lib/main.dart:168-169` обновлены; три перечисленных файла —
нет.

**Сценарий.** Пользователь открывает pub.dev, копирует раздел
«### 1. Dependencies» — самый первый блок кода про `Scope` — и получает две
ошибки анализатора: `non_abstract_class_inherits_abstract_member` (не
реализован `onUnmount`) и `override_on_non_overriding_member` (`unmount`
ничего не переопределяет). Ни одна не подсказывает нового имени.

**Последствия.** Первое впечатление от пакета — «примеры не работают». Это
две главные вкладки страницы пакета.

**Исправление.** Заменить `unmount()` на `onUnmount()` в трёх файлах.

**Смежное.** Дефект дожил до релиза потому, что гейт его не видит: второй
цикл `docs/ru/check.sh` перебирает `README.md doc/*.md example/*/README.md`,
и шаблон не покрывает `example/README.md` — у этого файла зеркала нет вовсе, а
проверка молчит и печатает «переводы актуальны: 15». Врезки с кодом ни один
гейт не сверяет с `.dart`-файлами, из которых они взяты.

#### Вердикт

**Исправлено.** Волна 10, `71b3824`.

Пример приведён к компилируемому виду вместе с русским зеркалом.

### P1-2. `AsyncScope` и `AsyncDataScope` не принимают ни одного из девяти унаследованных параметров

**severity:** High · **confidence:** high
**файлы:** `lib/src/scope/async_scope/async_scope.dart:47-59`,
`lib/src/scope/async_data_scope/async_data_scope.dart:45-57`;
для сравнения — `lib/src/scope/async_controller_scope/async_controller_scope.dart:28-46`;
объявление полей — `async_scope_base.dart:10-76`

`AsyncScopeBase` объявляет девять полей настройки жизненного цикла:
`scopeKeyTimeout`, `onScopeKeyTimeout`, `initCancellationTimeout`,
`onInitCancellationTimeout`, `disposeAsyncTimeout`, `onDisposeAsyncTimeout`,
`waitForChildrenTimeout`, `onWaitForChildrenTimeout`,
`pauseAfterInitialization`. `_AsyncScopeElement:167-195` читает все девять из
виджета. А конструктор `AsyncScope` пробрасывает только `key`, `tag`,
`scopeKey` — остальные девять для пользователя навсегда `null`. То же у
`AsyncDataScope`. `AsyncControllerScope` пробрасывает все девять.

**Сценарий.** У скоупа штатно долгий `disposeAsync` — закрытие базы, флаш
кеша, пять секунд. Поднять для него лимит нельзя: параметра нет. Остаётся
либо глобальный `ScopeConfig.defaultDisposeAsyncTimeout`, меняющий поведение
всего приложения, либо отказ от замыкательной формы в пользу подкласса
`AsyncScopeBase`.

**Последствия.** Две формы, которые README рекламирует как «lightweight
alternatives», лишены персональной настройки жизненного цикла, а
`doc/debug.md:177-181` при этом прямо утверждает обратное: «Every scope can
override all four defaults for itself with the `scopeKeyTimeout`,
`initCancellationTimeout`, `disposeAsyncTimeout` and
`waitForChildrenTimeout` parameters». Публикация закрепит расхождение в API.

**Исправление.** Добавить девять `super.`-параметров в оба конструктора —
изменение аддитивное, ничего не ломает.

*Найдено тремя агентами независимо.*

#### Вердикт

**Исправлено.** Волна 10, `77ac51e`.

Все девять параметров проброшены в обоих семействах. Поверхность со стороны
конструктора закрыта новым `test/async_scope_parameters_test.dart` — до этого
вся сьюта ходила к этим настройкам через рукописные подклассы.

### P1-3. Синхронный провал инициализации не показывает ветку ошибки

**severity:** High · **confidence:** high
**файл:** `lib/src/scope/async_scope/async_scope_core.dart:636-644`;
точки броска — `:499` (поиск координатора) и `:544` (`initAsync()`)

Единственное место, где модель становится `AsyncScopeError`, — обработчик
`onError` подписки (`:613`). Синхронный бросок ловится внешним `catch`,
который модель не трогает:

```dart
} on Object catch (error, stackTrace) {
  _log.e('initialization failed', error: error, stackTrace: stackTrace);
  if (!_initCompleter.isCompleted) {
    _initCompleter.complete();
  }
  rethrow;
}
```

`rethrow` уходит в отброшенный future (`:318`), то есть в необработанную
ошибку зоны. Модель остаётся `AsyncScopeWaiting`, `buildOnState` строит
`buildOnWaiting() ?? buildOnInitializing(null)`, `hasError` — `false`.

**Сценарий.** Самый частый: у скоупа есть `scopeKey`, а `AsyncScopeCoordinator`
выше забыт. `AsyncScopeCoordinator._elementOf` бросает `FlutterError` с
подробным текстом — и на экране навсегда остаётся спиннер. Тот же путь у
любого `initAsync`, который бросает синхронно (не `async*`-функция), и у
пользовательского `onScopeKeyTimeout()`, бросившего из колбэка.

**Последствия.** `doc/async_scope.md:174` обещает, что этот случай «fails
loudly», а таблица состояний (`:42`) — что `AsyncScopeError` строит
`buildOnError`, когда «`init` failed before it was ready». В консоли
действительно громко; в интерфейсе — тихо и навсегда. Существующие тесты
(`test/async_scope_test.dart:447`, `:527`) проверяют только, что разбор
доведён до конца и ошибка дошла до зоны; состояние модели не проверяет ни
один.

**Исправление.** В `catch` до `rethrow` перевести модель в `AsyncScopeError`,
если разбор ещё не начался. В пакете уже есть готовый инструмент —
`runStreamGuarded`, который превращает бросок фабрики в `Stream.error`; ядро
им не пользуется, хотя `ScopeDependencyMixin` пользуется.

#### Вердикт

**Исправлено.** Волна 10, `f952d5e`.

Синхронный провал переводит модель в `AsyncScopeError`. Состояние применяется
через `runOutsideFrame`: такая ошибка возникает до первого `await`, то есть
внутри сборки элемента, и прямой `_model.update` дёргал бы `markNeedsBuild`
посреди неё.

### P1-4. Падение одного диспозера в `concurrent`-группе обрывает разбор соседей

**severity:** High · **confidence:** high
**файл:** `lib/src/scope/full_scope/scope_auto_dependency/scope_dependency/scope_dependency_group.dart:153-160`;
для сравнения — последовательная группа, `:111-137`

Последовательная группа обходит детей поимённо, каждого в своём `try`,
собирает ошибки и перебрасывает первую после обхода — с комментарием: «One
dependency that cannot let go is no reason to walk away from the ones below
it». Параллельная группа не делает ничего из этого:

```dart
@override
Stream<String> dispose() async* {
  yield* _dependencies.reversed
      .where((dep) => dep.disposalRequired)
      .map((dep) => dep.runDispose())
      ._mergeStreams()
      .map(_path);
}
```

Ошибка ребёнка идёт `_mergeStreams` → `yield*` → `runStreamGuarded.onError` →
`close()` + `cancel()` → отмена подписок на **всех остальных** детей. Ни
одного `catch` на пути нет.

**Сценарий.** `concurrent('c', [sequential('s', [dep('a'), dep('b')]), dep('x')])`,
у всех трёх листьев назначен `dispose`. Скоуп уходит с дерева, разбор идёт
параллельно по `x` и `s`, диспозер `x` бросает, отмена долетает до генератора
`s.dispose()` — и `a` не освобождается вообще. Хуже: `finally` в `runDispose`
ставит `_isDisposalDone = true`, после чего `disposalRequired == false` и
повторный разбор эту ветку пропустит навсегда.

**Последствия.** Утечка ресурсов без возможности ретрая, и состояние дерева
при этом врёт: соседи показывают `disposal cancelled`, хотя их диспозеры
отработали, а `a` остаётся `initialized`.

**Ключевое.** `CHANGELOG.md` 0.10.0 содержит пункт «Fix one failing disposer
taking the rest of a sequential group with it». Починили ровно ту ветку, на
которую пришла находка первого ревью (P2 №5), и не посмотрели в соседний
класс того же файла.

**Исправление.** Гасить ошибку до слияния — оборачивать каждый детский
`runDispose()` в `handleError`, собирать ошибки, бросать первую после
закрытия слитого потока. Заодно не ставить `_isDisposalDone` при отмене
разбора, чтобы повтор мог дойти.

**Не покрыто тестами:** падающий диспозер проверяется только в
последовательной группе (`test/scope_dependency_partial_test.dart:107-165`).

#### Вердикт

**Исправлено.** Волна 10, `f2c07ed`.

Каждая ветвь параллельной группы держит свой отказ при себе, слияние доходит до
конца, первая ошибка уходит наверх после него. Инициализация той же группы
оставлена как есть: там отмена проигравших ветвей задумана, а взятое ими
подхватывает последующий разбор.

### P1-5. Упавший `ScopeState.onUnmount` пропускает весь синхронный unmount зависимостей

**severity:** High · **confidence:** high
**файл:** `lib/src/scope/full_scope/scope_core.dart:173-179`;
для сравнения — `disposeAsync` там же, `:181-204`

```dart
@override
void onUnmount() {
  // The state lets go of its own first, the dependencies after it, in the
  // same order as the asynchronous half below.
  super.onUnmount();
  _dependencies?.onUnmount();
}
```

Комментарий обещает «тот же порядок, что и у асинхронной половины ниже».
Асинхронная половина двадцатью строками ниже специально защищена — с
объяснением: «A state that failed to let go of its own is still a state whose
dependencies are holding theirs». Здесь защиты нет. Группа зависимостей ниже
тоже защищена (`scope_dependency_group.dart:44-59`). Не защищён ровно стык.

**Сценарий.** Пользователь переопределяет `ScopeState.onUnmount` —
документированный хук, — и там что-то бросает. `_dependencies?.onUnmount()`
не выполняется: **ни один `dep.unmount` не вызывается**. Исключение ловит
`_performAsyncDispose`, разбор идёт дальше, асинхронные `dep.dispose`
отрабатывают, синхронные — нет.

**Последствия.** Подписки и слушатели, которые обязаны отвалиться немедленно
(это и есть назначение `unmount`), живут до конца асинхронного разбора или
навсегда, если снимал их только `unmount`. Тихо: ошибка уходит в общий
репорт, связь «поэтому подписки живы» ниоткуда не видна.

**Ключевое.** Это тот же класс, что находка P2 №4 первого ревью («Ошибка
пользовательского cleanup обрывает обязательную очистку»), исправленная в
`a3e278c`. Исправили `disposeAsync`, соседний `onUnmount` остался.

**Не покрыто тестами:** в `cleanup_after_user_error_test.dart` для семейства
`Scope` проверены падающий `dep.unmount` и падающий `ScopeState.disposeAsync`;
падающего `ScopeState.onUnmount` нет.

#### Вердикт

**Исправлено.** Волна 10, `5c245dc`.

Падение пользовательского `onUnmount` больше не пропускает синхронный unmount
зависимостей. По правилу «ищи в соседней реализации» прочитаны все восемь
`onUnmount` в `lib/`: форма «пользовательский код внутри `super`, обязательная
работа после него» встречается ровно один раз — та, что чинили.

### P1-6. Исключение из селектора навсегда «замораживает» элемент скоупа

**severity:** High · **confidence:** high
**файл:** `lib/src/scope/scope_widget/scope_widget_core.dart:357-366`,
селекторы — `:266-295`

```dart
@override
void performRebuild() {
  if (_shouldOnlyNotify) {
    notifyClients(widget);          // <- selector(this as E): код пользователя, без try
    _shouldOnlyNotify = !autoSelfDependence && !_forceRebuild;
  }
  super.performRebuild();           // только здесь ComponentElement снимает _dirty
  ...
}
```

Проверено по исходникам Flutter 3.29.0: `ComponentElement.performRebuild`
снимает `_dirty` в `finally` вокруг `build()`, то есть внутри
`super.performRebuild()`; `ProxyElement` его не переопределяет.
`BuildScope._flushDirtyElements` ловит исключение, репортит его и в своём
`finally` сбрасывает `_inDirtyList = false` и чистит `_dirtyElements`.
`Element.markNeedsBuild` начинается с `if (dirty) { return; }`.

Итог: если `selector` бросает, `_dirty` остаётся `true`, а из списка грязных
элемент удалён — **он больше никогда не попадёт в сборку**.

**Сценарий (составной, обе половины подтверждены).** Виджет под
`buildOnInitializing` вызывает `LiteScope.select(context, (s) => s.value)`.
Селектор внутри делает `element._globalStateKey.currentState!`
(`lite_scope_core.dart:99`), а состояние монтируется только в ветке
`AsyncScopeReady` — до неё `currentState` равен `null`. Первое же
`notifyDependents()` прогоняет селектор, тот бросает `Null check operator`,
и скоуп замирает.

**Последствия.** В release — тихая необратимая потеря реактивности целого
поддерева: `notifyDependents()` больше ни на что не влияет, экран замер. В
debug — падение с сообщением про «while rebuilding dirty elements», не
указывающим на настоящую причину.

**Тот же дефект по второму адресу:** `async_scope_core.dart:304-320` —
`assert(_debugCheckScopeKeyOwnership())` стоит до `super.performRebuild()`, а
проверка не возвращает `false`, а бросает `FlutterError` (`:404-420`). То
есть диагностика про сменившийся `scopeKey` сама приводит к заморозке
элемента. `docs/handoff.md` уже фиксирует родственную ловушку («ассерт в
`didUpdateWidget` рвёт кадр… ставить такие проверки в `build`, где их ловит
build error boundary») — здесь ровно она, этажом выше.

**Исправление.** Обернуть `notifyClients(widget)` в `try`/`catch` с
`FlutterError.reportError` — оповещение одного зависимого не должно ронять
скоуп; и перенести диагностические ассерты `performRebuild` после
`super.performRebuild()`.

#### Вердикт

**Исправлено частично, и находка права не в том, что заявляет.** Волна 10,
`295d790`.

**Заморозки элемента нет.** Проба `Element.dirty` сразу после упавшего
уведомления даёт `false`: фреймворк восстанавливается, скоуп продолжает
перестраиваться. Первая редакция теста это и показала — она проходила и с
исправлением, и без него.

Настоящий вред другой, и он исправлен: бросок обрывает **обход зависимых**, а
кто именно не услышал уведомление, решает порядок обхода хеш-таблицы
`_dependents`. Самоподписка скоупа обходится первой, поэтому отказ в ней съедает
уведомление целиком — на этом и построен окончательный тест.

**Вторая половина находки откачена.** Перенос
`assert(_debugCheckScopeKeyOwnership())` за `super.performRebuild()` ничего не
меняет: все четыре теста диагностик `scopeKey` ведут себя одинаково до и после,
падающего теста написать не удалось. Разбор — `2026-08-16[13]`.

## Medium and low-severity findings

### P2 — существенные дефекты

**P2-1. `AsyncScopeParent.waitForChildren()` без аргументов ждёт бесконечно.**
`async_scope_parent.dart:45` передаёт `timeout` в `ChildRegistry` как есть, а
тот при `null` вообще не ставит предела. Одноимённый
`AsyncScopeCoordinator.waitForChildren` дефолт применяет
(`async_scope_coordinator.dart:86`), и внутренний вызов из
`_prepareForDisposal` тоже (`async_scope_core.dart:921`). Публичный вызов
`scope.waitForChildren()` по образцу `doc/async_scope.md:139` зависает
навсегда, если ребёнок не завершится, — при том что `:147` обещает «Nothing
here deadlocks; it degrades into a delay and a report». Исправление —
`timeout ?? ScopeConfig.defaultWaitForChildrenTimeout`. *confidence: high*

#### Вердикт

**Исправлено.** Волна 11, `0f04cb9`.

Миксин берёт дефолт из `ScopeConfig.defaultWaitForChildrenTimeout`, как это давно
делал координатор. У `waitForChildren` два публичных входа, и дефолт был только
у второго.

**P2-2. `_performAsyncDispose` затирает первую ошибку вопреки своему
комментарию.** `async_scope_core.dart:670` и `:682` пишут `failure =`, `:716`
— `failure ??=`, а комментарий над блоком (`:658`) заявляет «The first failure
is passed on once all four are over». Каскад «упал `onUnmount`, затем упал
`onWaitForChildrenTimeout`» отдаёт наружу вторую ошибку; первая остаётся
только в логе, выключенном по умолчанию. Для `LiteScope.close()` это ошибка,
которую ждёт вызывающий. *confidence: high*

#### Вердикт

**Исправлено, но каскад из находки недостижим.** Волна 11, `75dda4b`.

На пути удаления с дерева `unmountScope()` вызывает `unmount()` **до** начала
разбора, поэтому к первой стадии `_performAsyncDispose` флаг `_didUnmount` уже
взведён, стадия вырождается в no-op и упасть не может. Из трёх пар сломана была
только (1, 2), и увидеть её можно лишь через `close()` — туда и переехал тест
(`lite_scope_test.dart`).

**P2-3. Провал `init()` контроллера теряется, если его `dispose()` бросает.**
`async_controller_scope_core.dart:54-63`: `finally` без защиты, а исключение
из `finally` по семантике Dart вытесняет исходное. При этом документация
самого `ScopeController` требует, чтобы `dispose()` умел работать с
полуинициализированным объектом, — то есть именно в этом состоянии он и
наиболее склонен упасть. Пользователь увидит в `buildOnError` вторичный сбой
уборки вместо `SocketException`. *confidence: high*

#### Вердикт

**Исправлено.** Волна 11, `459e058`.

Провал `init()` переживает падение `dispose()` и доезжает до `buildOnError`;
вторичный отказ сообщается отдельно, а не вытесняет исходный.

**P2-4. Разбор контроллера на пути «`init()` бросил» не ограничен ничем.**
Там же. `disposeAsyncTimeout` применяется только в `_performAsyncDispose`, то
есть только при `_initSucceeded`; на этом пути разбор идёт из `finally`
живого генератора, вне всяких границ. Если `dispose()` контроллера зависнет,
генератор не завершится, ошибка не дойдёт до `onError`, модель останется
`AsyncScopeWaiting` — скоуп бесконечно показывает `buildOnInitializing` без
единого отчёта. `doc/async_controller_scope.md` утверждает: «the wait for
`dispose()` by `disposeAsyncTimeout`». *confidence: high*

#### Вердикт

**Исправлено.** Волна 11, `459e058`.

Разбор на пути «`init()` бросил» ограничен: зависший `dispose()` больше не
оставляет скоуп на ветке загрузки навсегда.

**P2-5. «Notify-only» пересборка всё равно строит и выбрасывает поддерево.**
`scope_widget_core.dart:349-370`. Комментарий обещает «Skips rebuilding the
whole subtree (skips [build])», но переопределён только `updateChild`;
`ComponentElement.performRebuild` (проверено по SDK) вызывает `build()`
всегда. То есть на каждое `notifyDependents()` выполняется `buildChild()` →
пользовательский `builder` строит всё дерево виджетов, а `updateChild`
возвращает старого ребёнка и построенное уходит в мусор. Тест
`scope_widget_test.dart:116-143` этого не ловит: он считает сборки **детей**,
а не вызовы `buildChild()` самого скоупа. *confidence: high*

#### Вердикт

**Исправлено.** Волна 11, `c488f35`.

Построенное поддерево кешируется, и `buildChild()` на уведомление не выполняется.

**P2-6. `CompositeListenableSubscription.cancel()` обрывается на уже
отменённой подписке.** `listen.dart:148-157` вызывает `cancel()` на членах без
защиты, а `ListenableSubscription.cancel` (`:85-92`) начинается с
`assert(debugAssertNotDisposed(...))`, который бросает `StateError`. Если одну
подписку отменили отдельно, композит падает на ней, `_subscriptions` не
очищается, и **все подписки после сбойной остаются висеть** — утечка
слушателей. Повтор не поможет: `_isDisposed` уже `true`. В release assert'а
нет, и тот же код работает — то есть debug падает там, где release проходит.
*confidence: high*

#### Вердикт

**Исправлено.** Волна 11, `f97d880`.

Композит пропускает уже отменённых членов и доводит отмену до конца.

**P2-7. Ошибка зависимости приезжает в `buildOnError` с пустым стектрейсом.**
`scope_dependency_mixin.dart:135-141` заворачивает ошибку листа в
`ScopeDependencyException` и бросает с `StackTrace.empty`; выше по дереву
перебрасывается тот же пустой. Типовая интеграция
`Crashlytics.recordError(error, stackTrace)` из `buildOnError` отправит запись
без стека. Оригинал не потерян — он внутри
`ScopeDependencyException.stackTrace`, — но `toString()` его не печатает и
документация о нём не говорит. *confidence: high*

#### Вердикт

**Исправлено.** Волна 11, `41de8ee`.

Ошибка листа перебрасывается с трассой самого отказа, а не с пустой.

**P2-8. Ошибки разбора зависимостей не доходят никуда, кроме выключенного
логгера.** `scope_auto_dependency.dart:105-114`: `onError` только пишет в
`_log.e`, а `ScopeAutoDependencies.dispose()` никогда не бросает. Из-за этого
аккуратная передача ошибки в `ScopeElementBase.disposeAsync()`
(`scope_core.dart:196-203`) для этого семейства мертва. `ScopeConfig.logger`
по умолчанию `off` — значит, при `httpClient.close()`, бросившем на выходе из
скоупа, не происходит **ничего**. Во всём остальном пакете такие сбои идут
через `FlutterError.reportError`. *confidence: high*

#### Вердикт

**Исправлено.** Волна 11, `41de8ee`.

Ошибки разбора зависимостей идут через `FlutterError.reportError`, а не только в
логгер, выключенный по умолчанию.

**P2-9. `.value`-конструкторы принимают `value: null`.**
`scope_model_base.dart:30-36`, `scope_notifier_base.dart:31-37`: поле
объявлено `M?` (нужно для владеющего конструктора), поэтому `required` от
`null` не защищает, а `model => _model ?? widget.value!`
(`scope_model/base.dart:57`) падает голым null-check без имени скоупа и
параметра. Хуже вариант с `update`: при `newWidget.value == null`
`_ScopeNotifierElement.update` снимет слушателя со старой модели и не
поставит на новую, а `dispose()` затем бросит уже во время `unmount`, вне
границы билда. *confidence: high*

#### Вердикт

**Исправлено сильнее, чем предлагалось.** Волна 11, `f97d880`.

Ассерт был написан, и анализатор подсказал лучшее:
`tighten_type_of_initializing_formals`. `required M this.value` при поле `M?`
делает `value: null` **ошибкой компиляции**, а не рантайма. Ассерт снят, тесты на
него удалены: гарантия стала статической и тестами не проверяется.

**P2-10. `LiteScope.of`/`select`/`Scope.of` падают null-check до готовности
скоупа.** `lite_scope_core.dart:81`, `:99`, `scope_base.dart:166-194`:
состояние живёт в `_LiteScopeCoreWidget`, который монтируется только в
`buildOnReady()`; до этого `_globalStateKey.currentState` — `null`, а `of` и
`select` пишут `!`. `maybeOf` возвращает тот же `null`, что и при отсутствии
скоупа, так что различить случаи нельзя. `doc/base.md:180-200` перечисляет два
вида отказа поиска и обещает, что оба — «plain exceptions carrying the type
that was asked for»; третий таким не является. Вместе с P1-6 даёт заморозку
элемента. *confidence: high*

#### Вердикт

**Исправлено.** Волна 11, `3127305`.

Поиск в соседних реализациях нашёл `!` не в двух местах, а в шести — по паре
`of`/`select` в четырёх файлах (`lite_scope_core`, `lite_scope_base`,
`scope_core`, `scope_base`).

**P2-11. `LiteScopeCoreState.close()` ищет свой скоуп по дереву.**
`lite_scope_core.dart:474`: `ScopeContext.of<W, E>(context, listen: false).close()`
— при том что элемент лежит в поле `_scopeElement` и соседний
`notifyDependents()` (`:470`) сделан через него. Отложенный вызов `close()`
после демонтажа падает на `State.context` вместо no-op; а если пользовательский
`wrapState` обернёт состояние ещё в один скоуп того же типа `W`, закрыт будет
внутренний, а не свой. Исправление в одну строку:
`close() => _scopeElement.close()`. *confidence: high*

#### Вердикт

**Исправлено.** Волна 11, `41de8ee`.

`close() => _scopeElement.close()`, как и предлагалось.

**P2-12. Инварианты производных семейств не запечатаны.**
`AsyncControllerScopeElementBase.initDataAsync()` (`:44`) и `disposeAsync()`
(`:73`) не помечены ни `@nonVirtual`, ни `@mustCallSuper`, при том что
соседний `onUnmount()` защищён — он наследует `@mustCallSuper` от
`ScopeWidgetElementBase`. Классы объявлены `abstract base class` в
экспортируемой библиотеке, то есть потребитель имеет право их наследовать
(это и есть заявленный третий слой). Переопределение `disposeAsync()` без
`super` выключает освобождение контроллера целиком — ту самую утечку, ради
закрытия которой семейство появилось, — и ни компилятор, ни анализатор не
возражают. То же у `AsyncDataScopeElementBase.initAsync()` (`:103`).
*confidence: high*

#### Вердикт

**Исправлено.** Волна 11, `34afb82`.

`@nonVirtual` на `initAsync` data-слоя и `initDataAsync` контроллерного,
`@mustCallSuper` на его `disposeAsync`. Гарантия анализаторная и тестами не
покрывается — это отмечено в `docs/handoff.md`.

**P2-13. `doc/scope_notifier.md` приписывает `AsyncScope` чужую модель
состояния.** `:96-98`, `:130-132`, `:141` утверждают, что «`AsyncScope` is
built on them» (включая `ScopeStateWithErrorNotifier`), что чтение `state` у
неудавшегося скоупа «rethrows», и что «the asynchronous families check
`hasError` before touching `state`». В коде
`_AsyncScopeNotifier extends ScopeStateNotifier<AsyncScopeState>`
(`async_scope_model.dart:7`); отказ моделируется значением `AsyncScopeError`
внутри `state`, `state` — обычный геттер, `hasError` сам вычисляется из
`state`. Триада `ScopeStateWithError*` не используется в `lib/` нигде.
*confidence: high*

#### Вердикт

**Исправлено.** Волна 11, `e1eb533`.

Текст `doc/scope_notifier.md` приведён к коду.

**P2-14. `ScopeDependenciesExtension.asStream` содержит непроверяемое
приведение.** `scope_dependencies.dart:22-27`: `this as T`, где `T` никак не
связан с типом получателя. Форма из `doc/full_scope.md:75-78` требует писать
тип руками, поэтому после переименования контейнера вызов продолжит
компилироваться и упадёт на первом кадре. Лечится дженериком по получателю —
изменение ломающее, нужна строка в CHANGELOG. *confidence: high*

#### Вердикт

**Исправлено.** Волна 11, `0af44f7`.

`asStream` стал дженериком по получателю, приведение `this as T` исчезло.
Изменение ломающее, строка в `CHANGELOG.md` есть.

**P2-15. Подписки, сделанные из `didChangeDependencies`, теряются на следующем
кадре.** `scope_widget_core.dart:222-253`: граница «одна регистрация = один
кадр» приравнивает кадр к билду, но у `StatefulElement` в одном
`performRebuild` подряд идут `didChangeDependencies()` и `build()` — один
кадр, один `pass`, регистрации складываются. На следующем кадре, когда
родитель просто пересобирает виджет, `didChangeDependencies` не вызывается,
`pass` другой, `reset()` стирает пару, зарегистрированную из
`didChangeDependencies`, и восстановить её неоткуда. `doc/base.md:166` пишет
«re-established while the dependent builds», то есть контракт по факту —
«подписывайся только из `build`», но он ни сказан явно, ни проверен ассертом,
а Flutter такую подписку разрешает. Закрывается ассертом
`context.debugDoingBuild` в `ScopeContext._find`. *confidence: high*

#### Вердикт

**Исправлено ассертом, а не переделкой границы.** Волна 11, `cb35b9a`.

У находки было два пути. Граница пересборки по кадру — решение вынужденное (у
Flutter нет хука «зависимый начинает сборку»), она задокументирована вместе со
своей ценой, и переделка задела бы всё семейство; поэтому взят второй путь —
сузить контракт и ловить нарушение. Поставлен `context.debugDoingBuild` в
`ScopeContext._find` плюс явное правило в `doc/base.md`.

Ложных срабатываний нет: зелены сьюта пакета, тесты `scopo_demo` и семнадцать
тестов `navigation_node`. Один тест пакета поправлен — `base_test.dart` брал
подписку на себя прямо из тела теста, то есть делал ровно то, что ассерт
запрещает.

**P2-16. Флагманский пример 0.10.0 использует API чужого пакета.**
`README.md:379` и `doc/async_controller_scope.md:12`, `:28` создают контроллер
как `PlayerController(api: context.read<Api>())`. В `lib/` нет ни одного
расширения на `BuildContext`; `read<T>()` принадлежит `provider`, и ни один
пример пакета его не подключает. При этом
`async_controller_scope_core.dart:34-36` прямо говорит, что здесь нужно
«reading another scope with `listen: false`». Единственная настоящая новинка
релиза учит идиоме конкурента и не компилируется. *confidence: high*

#### Вердикт

**Исправлено.** Волна 11, `e1eb533`.

`context.read<Api>()` нашёлся не в двух местах, а в шести — три оригинала и три
русских зеркала.

**P2-17. `AsyncControllerScope` отсутствует в навигации.** Категория объявлена
в `dartdoc_options.yaml`, страница `doc/async_controller_scope.md` написана,
зеркало есть — но таблица тем `README.md:556-567` перечисляет 10 тем из 11, а
`doc/base.md:3-4` и `:204-211` дважды перечисляют семейства пакета и оба раза
новое пропускают; то же в `doc/full_scope.md:19-20`. Главная новинка релиза
наполовину невидима. *confidence: high*

#### Вердикт

**Исправлено.** Волна 11, `e1eb533`.

Тема добавлена в таблицу `README.md` и в оба перечисления семейств.

### P3 — локальные несогласованности

**P3-1.** Пример в dartdoc `ProgressIterator` не компилируется:
`progress_iterator.dart:5` показывает `ProgressIterator(count: 3)`, а
конструктор позиционный (`:29`); там же ссылка на несуществующий тип
`ProgressValue`. `doc/utils.md:121` показывает правильную форму — при
переименовании поправили тему и пропустили dartdoc. Это опубликованный
справочник API. *high*

#### Вердикт

**Исправлено.** Волна 12, `495629b`.

В примере `ProgressIterator(3)` и `Progress` вместо несуществующего
`ProgressValue`.

**P3-2.** `Progress.progress => number / total` (`:61`) не проверяет ничего:
`ProgressIterator(0)` даёт `NaN`, `add(-1)` — отрицательное значение, а в
release, где assert выключен, `nextStep()` сверх `total` даёт `4/3`. Внутри
пакета путь безопасен (при `count == 0` поток не отдаёт ни одного элемента),
но тип публичный, а `doc/utils.md:129` обещает «a fraction between 0 and 1».
*high*

#### Вердикт

**Исправлено.** Волна 12, `495629b`.

`progress` держит долю между 0 и 1 при любой паре: `0/0` читается как 1, перелёт
клампится. Конструктор `Progress` отвергает отрицательные `number` и `total`
ассертом, а сообщение ассерта в `add` говорит `total`, а не `count`.

**P3-3.** `ScopeDependencyNoDisposalRequired`
(`scope_dependency_state.dart:179-185`) не создаётся нигде — публичный мёртвый
класс из sealed-иерархии, перечисленный в `doc/full_scope.md:188`. Причина:
лист без `dispose` не проходит фильтр `disposalRequired`, его `runDispose()`
не запускается, состояние остаётся `initialized` — то есть после полного
разбора дамп дерева читается как «половина скоупа ещё жива». *high*

**P3-4.** `AsyncScopeModel get model => _model.asUnmodifiable()`
(`async_scope_core.dart:138`) аллоцирует новую обёртку на каждое чтение, а
через `model` идут `state`, `isInitialized`, `hasError`, `error`,
`stackTrace`, `buildChild()` и `debugFillProperties`. Функционально безвредно
(обёртка делегирует в тот же нотифаер), но это мусор на каждый билд и на
каждый прогон селектора. Лечится `late final` полем. *high*

#### Вердикт

**Исправлено.** Волна 12, `f4a1535`.

`late final` поле вместо обёртки на каждое чтение.

**P3-5.** `ScopeController.performInit` (`scope_controller.dart:27-31`) не
идемпотентен и не проверяет `_disposed`, при том что
`doc/async_controller_scope.md:87-89` и `CHANGELOG.md` утверждают «they make
each hook run at most once», а дартдок прямо приглашает водить контроллер
руками. После `performDispose()` вызов `performInit()` снова ставит
`_mounted = true` и выполняет `init()` на разобранном объекте. *high*

#### Вердикт

**Исправлено.** Волна 12, `b377aa0`.

`performInit` выполняет `init()` не больше одного раза и ничего не делает после
`performDispose`: три метода стали односторонней последовательностью, как
документация и обещала.

**P3-6.** `performDispose` ставит `_disposed = true` до `await dispose()`,
поэтому параллельный второй вызов возвращается немедленно и врёт, что разбор
окончен (`scope_controller.dart:49-57`). Внутри пакета недостижимо, но это
часть публичного контракта. Образец решения рядом — `_closeCompleter` в
`lite_scope_core.dart:250-258`. *high*

#### Вердикт

**Исправлено.** Волна 12, `b377aa0`.

По образцу `_closeCompleter`, на который находка и указывала: completer ставится
до старта разбора, и все вызвавшие получают его исход — включая ошибку.

**P3-7.** `data` отдаёт значение раньше, чем скоуп становится ready:
`_hasData` ставится в `.map` при доставке события
(`async_data_scope_core.dart:109-110`), а `_model.update(AsyncScopeReady())`
откладывается на post-frame или на всю длительность `pauseAfterInitialization`
(`async_scope_core.dart:563-578`). В этом окне `isInitialized == false`,
строится `initBuilder`, а `data` уже возвращает значение вместо обещанного
`doc/async_data_scope.md:82` `StateError`. *high*

#### Вердикт

**Исправлено правкой обещания, а не кода.** Волна 12, `f4a1535`.

Окно между появлением значения и готовностью модели закрывать нельзя.
`disposeAsync` читает `data` именно в нём: `_performAsyncDispose` пускает его по
`_initSucceeded`, а тот взводится там же, где `_hasData`. Обещание «`dispose`
всегда получает значение» держится ровно на этом окне, и заставить `data` молчать
до готовности модели значило бы сломать разбор скоупа, ушедшего раньше времени.

Поэтому исправлена та сторона, которая была неверна: дартдок `data` и
`doc/async_data_scope.md` теперь говорят, с какого момента геттер отвечает и
почему это раньше `isInitialized`.

**P3-8.** `dataOrNull` и `onUnmount(T? data)` неразличимы для nullable `T`.
Признак `_hasData` заведён ровно для этого («for a nullable `T` the value
cannot answer for itself», `:88-94`), но применён только к `data`; `dataOrNull`
и `widget.onUnmount(_data)` отдают поле напрямую, а дартдок утверждает «The
value is `null` when the initialization never finished». Наружу `_hasData` не
выведен, так что различить состояния потребитель не может. *high*

#### Вердикт

**Исправлено.** Волна 12, `f4a1535`.

`hasData` выведен в `AsyncDataScopeContext`. Дартдоки `dataOrNull` и
`unmount`/`onUnmount` называют двусмысленность и говорят, куда смотреть;
сигнатуру колбэка не трогали — для этого пришлось бы ломать публичный API ради
случая, у которого теперь есть ответ рядом.

**P3-9.** Второй `AsyncDataScopeReady` подменяет `data` за спиной у модели:
`.map` (`async_data_scope_core.dart:103-114`) сохраняет `_data`/`_hasData`
раньше, чем `asyncMap` (`async_scope_core.dart:551-556`) успевает бросить
диагностику «already initialized». Модель остаётся ready со старым состоянием,
зависимые не оповещаются, `data` возвращает новое значение, а первое уже
никем не освобождается. Тест на двойной ready есть, но только для
`AsyncScope` (`test/async_scope_test.dart:895`), где `_data` нет. *high*

#### Вердикт

**Исправлено.** Волна 12, `f4a1535`.

Второй `ready` отвергается в том же `map`, где значение перехватывают, то есть до
подмены. Тест проверяет главное следствие: освобождают то значение, которое
скоупу передали.

**P3-10.** `@nodoc` на типах, без которых не набрать публичное API:
`NodeNavigatorState` (`navigation_node.dart:209`) обязателен, чтобы написать
`GlobalKey<NodeNavigatorState>()` для `NavigationNode.navigatorKey`, и
`doc/utils.md:86` на него ссылается; `AsyncScopeModel`
(`async_scope_model.dart:3`) стоит третьим типовым аргументом
`AsyncScopeCore` и возвращается из `model`. В справочнике их не будет.
*high*

#### Вердикт

**Исправлено.** Волна 12, `495629b` и `f4a1535`.

Оба типа документированы: `NodeNavigatorState` в первом коммите, `AsyncScopeModel`
во втором.

**P3-11.** `LiteScopeCoreState.widget` — `Never get widget => throw
UnimplementedError()` с аннотацией `@visibleForTesting` и без единой строки
dartdoc (`lite_scope_core.dart:400-402`). Аннотация означает
«пользоваться только из тестов», а смысл противоположный — «не пользоваться
никогда, читайте `params`». Сам фреймворк безопасен (работает с приватным
`_widget`), но любой сторонний миксин на `State`, читающий `widget`, упадёт.
Рядом есть образец правильного оформления — запечатанный `dispose` с
объяснением (`:365-377`). *high*

**P3-12.** `ScopeConfig` — шесть глобальных изменяемых полей без `reset()` и
без снимка умолчаний (`scope_config.dart:18-59`); собственные тесты пакета
вынуждены сохранять и возвращать состояние вручную
(`test/scope_logger_test.dart:5-19`, `test/async_scope_paths_test.dart:13-17`),
и тест, забывший это сделать, отравит соседей. Там же неверный дартдок:
«Forces pause to be disabled during testing and debugging» описывает, что даёт
значение `false`, а документируется поле со значением `true`. *high*

#### Вердикт

**Исправлено.** Волна 12, `b377aa0`.

`ScopeConfig.reset()`, умолчания вынесены в константы, дартдок
`pauseAfterInitializationEnabled` переписан. Три сьюты пакета перешли на
`reset()`. Логгер намеренно не сбрасывается: это объект со своими издателями и
трансформером, а не переключатель, — сказано в дартдоке `reset()`.

**P3-13.** `StateAsNotifier` не обнуляет `_notifier` в `dispose()`
(`state_as_notifier.dart:29-32`). В debug `notifyListeners()` из позднего
колбэка даёт «A ChangeNotifier was used after being disposed» со стеком внутрь
scopo; в release `addListener` после `dispose` молча запоминает слушателя
навсегда — тихая утечка замыкания. Лечится одной строкой `_notifier = null`.
*high*

#### Вердикт

**Исправлено.** Волна 12, `495629b`.

`_notifier` обнуляется в `dispose()`. Одной этой строки мало: без второй половины
поздний `addListener` заводил бы новый нотифаер, который никто не утилизирует,
поэтому размонтированное состояние слушателей больше не берёт.

**P3-14.** Асинхронный `NavigationNode.onPop`, завершившийся ошибкой, даёт
необработанную ошибку зоны: у цепочки
`future.whenComplete(...).then(...)` (`navigation_node.dart:90-102`) нет ни
`onError`, ни `catchError`. Типовой сценарий — упавший диалог подтверждения.
Флаг `_deciding` при этом сбрасывается корректно, зависания нет. *high*

#### Вердикт

**Исправлено.** Волна 12, `495629b`.

Отказ уходит в `FlutterError.reportError`. Нажатие просто не отрабатывается, а
следующее спрашивают как обычно — `_deciding` и до этого сбрасывался верно.

**P3-15.** `runStreamGuarded` строит суб-логгер на каждый вызов
(`run_stream_guarded.dart:34-36`) — единственное из четырёх мест в `lib/`, где
`withAddedName` вызывается не лениво, при том что вызывается он дважды на
каждую зависимость. Каждое создание суб-логгера в `logger_builder` обходит
список живых суб-логгеров корневого логгера более десяти раз. Поведение
квадратичное по числу живых скоупов и зависимостей и происходит целиком
впустую при `level = off`. *high, оценка аналитическая*

#### Вердикт

**Исправлено.** Волна 12, `495629b`.

Один суб-логгер на библиотеку вместо одного на вызов; вызывающий назван в
сообщении, а не в пути. Проверяется счётчиком `subLoggersCount` в
`test/run_stream_guarded_test.dart`.

**P3-16.** Документация `runStreamGuarded` обещает больше, чем делает код
(`:11-16` против `:48-74`): `onPostCancelError` получает только ошибки самой
отмены источника, а не «every error received after that». Функция внутренняя,
цена правки — только текст. *high*

#### Вердикт

**Исправлено.** Волна 12, `495629b`.

Дартдок описывает то, что делает код.

**P3-17.** `doc/full_scope.md:215-218` обещает, что канонические пути
(`concurrent1/dep2`) «appear in `ScopeDependencyInfo.path`», тогда как
`_extract` (`scope_auto_dependency.dart:152-170`) кладёт туда путь вмещающих
групп с завершающим `/` и без имени самой зависимости. Дартдок у поля
описывает это правильно и противоречит теме. *high*

#### Вердикт

**Исправлено.** Волна 12, `495629b`.

`doc/full_scope.md` больше не относит `ScopeDependencyInfo.path` к каноническим
путям и объясняет, чем он от них отличается.

**P3-18.** Мелочи публикуемых сигнатур: осиротевшая заготовка комментария
внутри типа поля `AsyncDataScope.init` (`async_data_scope.dart:10-15`);
ссылка на несуществующую тему `h_scope` в
`scope_auto_dependencies_progress.dart:8` (префиксы файлов сняты в `68be486`);
ссылка на `doc/j_utils.md` в `CHANGELOG.md:157`; сдвоенный дартдок у
`_HookEntry` (`navigation_node.dart:296-308`);
`void onUnmount() => _subscription?.cancel()` в двух примерах контроллера
молча выбрасывает `Future` при включённом у самого пакета
`discarded_futures`. *high*

#### Вердикт

**Исправлено.** Волна 12, `495629b`.

Все пять мелочей.

**P3-19.** `ScopeContext._find` (`base/base.dart:91-98`) использует
`getElementForInheritedWidgetOfExactType` и при отсутствии скоупа не
выставляет `_hadUnsatisfiedDependencies`. Из-за этого виджет, вызвавший
`maybeOf(listen: true)` без скоупа над собой и позже перенесённый по
`GlobalKey` под скоуп, не получит `didChangeDependencies`. *medium*

**P3-20.** `IsBuildingExtension.isBuilding` (`is_building.dart:9`) проверяет
только `SchedulerPhase.persistentCallbacks`, а `BuildOwner.buildScope`
выполняется и при `idle` — внутри `runApp` и `WidgetTester.pumpWidget`. Для
внутреннего потребителя путь сегодня недостижим, но расширение публичное.
*medium*

#### Вердикт

**Исправлено, с уточнением к находке.** Волна 12, `495629b`.

`WidgetTester.pumpWidget` этот случай **не** воспроизводит: под тестовым биндингом
первая сборка идёт в `persistentCallbacks`, а не в `idle`. Воспроизводит явный
`buildOwner.buildScope` вне кадра — так строит первое дерево `runApp`, и на этом
построен тест.

`isBuilding` теперь спрашивает и `buildOwner.debugBuilding`. В release этого флага
нет вовсе, там остаётся только фаза — сказано в дартдоке. `runOutsideFrame` заодно
просит кадр: отложенный колбэк без кадра не выполнится никогда.

### Известное и уже записанное

**`previous.pop()` обходит внешний `PopScope(canPop: false)`.**
`navigation_node.dart:75-108`. Уже зафиксировано в `docs/handoff.md` и
разобрано в `2026-08-15[9]`, находка 3. Ревью добавляет к этому одно
уточнение: путь достижим и при `onPop == null`, то есть **по умолчанию**.
`ModalRoute.onPopInvokedWithResult` (проверено по SDK 3.29.0) вызывает все
`PopEntry` маршрута независимо от их собственного `canPop`, поэтому вето
чужого `PopScope` доходит до узла как `didPop == false`; дальше
`widget.onPop?.call(...)` даёт `null`, паттерн `final bool? canPop` его
матчит, `canPop ?? true` — истина, и узел зовёт `pop`, который на защиту не
смотрит вовсе. Ни `doc/utils.md`, ни `README.md`, ни дартдок
`NavigationNode` об этом не предупреждают, и внешнего `PopScope` нет ни в
одном тесте.

### Не подтвердилось

**`.vscode/` в архиве.** Гипотеза, что `.pubignore`, заменяющий `.gitignore`,
пропустит `.vscode/settings.json` с локальным путём к SDK, выглядела
правдоподобно. Проверка `dart pub publish --dry-run`: в списке из 419 строк
`.vscode` нет. Находка снята.

**Мутация на связь с `_initSucceeded`.** `docs/handoff.md` пишет, что связь
`AsyncControllerScopeElementBase` с приватным полем соседнего слоя «закрыта
комментарием в коде и мутацией в тестах». Grep по `test/` даёт только
комментарий, из чего можно заключить, что мутации не было, — но мутационное
тестирование артефактов в репозитории не оставляет, а поведенчески связь
действительно закреплена: тест «builds the ready branch and tears the
controller down once» упадёт, если присваивание `_initSucceeded` переедет.
Заявление handoff корректно.

## Architecture review

**Сильные стороны.**

Трёхслойная схема (`Core` → `Base` → готовый виджет) работает: она
действительно даёт три разных уровня входа, и в новом семействе повторена без
отклонений. Линейная цепочка наследования семейств означает, что исправление
в `AsyncScopeCore` доезжает до всех — и это подтверждается: волны чистки
исправляли ядро один раз, а не пять.

Разделение синхронной и асинхронной половин разбора (`onUnmount` до
`disposeAsync`, оба на обоих путях — и при удалении с дерева, и при `close()`)
— сильное решение, которого нет у большинства пакетов такого класса. Оно
закрывает реальную проблему: подписка, которую нужно снять немедленно, не
должна ждать закрытия базы данных.

Координация через `KeyedAccessQueues` и `ChildRegistry` вынесена в файл без
единого импорта Flutter и покрыта отдельными unit-тестами — граница проведена
правильно.

**Слабые места.**

*Инварианты семейства не отличимы от хуков.* Это корень P2-12 и, шире, целого
класса рисков. `abstract base class` в экспортируемой библиотеке даёт
потребителю право наследоваться, и в одном «Overriding block» соседствуют
методы, которые он обязан переопределить (`buildOnReady`), и методы, которые
он не должен трогать никогда (`initDataAsync` в контроллерном слое). Различить
их можно только чтением реализации. `@nonVirtual`/`@mustCallSuper`
расставлены точечно — на `ScopeController` они есть, на инвариантах семейств
нет.

*Дублирование девятки параметров.* Три идентичных блока полей и три
идентичных блока проброса в элемент, ~150 строк
(`async_scope_base.dart:10-76` и `:167-195`, `async_data_scope_base.dart`,
`async_controller_scope_base.dart`). Дублирование уже дало расхождение — P1-2,
— и, кроме него, расхождение дартдоков: у `AsyncScopeBase` каждый таймаут
снабжён «Defaults to…» и абзацем про `FlutterError.reportError`, у
`AsyncDataScopeBase` нет ни того ни другого.

*Три параллельные иерархии состояний.* `AsyncScopeState`,
`AsyncDataScopeInitState<P,T>`, `ScopeInitState<P,D>` — одно и то же понятие в
трёх невзаимозаменяемых видах. Пользователь, переходящий между семействами,
переписывает `switch`.

*Граница пересборки взята по кадру* (`scope_widget_core.dart:19-34`). Решение
вынужденное — у Flutter нет хука «зависимый начинает сборку», и это честно
объяснено в комментарии. Но у него два следствия: документированное
(зависимый, перестроенный дважды за кадр, копит оба набора селекторов) и
недокументированное (P2-15). Плюс глобальное изменяемое состояние на уровне
библиотеки.

**Спорное.**

Публичный `ScopeDependency` выставляет `init()`/`runInit()`/`dispose()`/
`runDispose()` (`scope_dependency.dart:33-49`) — внутреннюю механику
жизненного цикла, о которой `doc/full_scope.md` не говорит ничего. Прямой
вызов `init()` поднимает зависимость мимо учёта состояний. Перед 0.10.0 стоит
либо спрятать эту пятёрку, либо описать её инварианты.

`AsyncControllerScopeCore` — единственный `*Core` в пакете без
`of`/`maybeOf`/`select`; потребитель, строящий семейство на нём, вынужден
звать `AsyncDataScopeCore.of<W, E, C>`, то есть выходить из своего слоя.

## Testing review

**Что покрыто, и покрыто хорошо.** 222 теста, и это не количество ради
количества: почти каждый написан от конкретного дефекта, ассертит эффект (кто
освободил ресурс, кто дождался, какая ошибка дошла), а не факт вызова, и почти
везде рядом стоит «control»-тест. Сильнее всего закрыты ровно те места, где
обычно не закрыто ничего: гонки post-frame колбэков, отмена инициализации на
середине, переезд элемента по `GlobalKey`, четыре диагностики смены
`scopeKey`, `close()` во всех четырёх состояниях, порядок разбора на обоих
путях, дерево из десяти зависимостей с четырнадцатью комбинациями падений.

**Чего сьюта не ловит — по убыванию риска.**

1. **Дерево зависимостей, отменённое на полпути через виджет.** Все
   виджет-тесты `Scope` используют синхронные инициализаторы, то есть дерево
   всегда успевает достроиться. Путь «пользователь ушёл со сплеш-экрана во
   время загрузки» — заголовочное обещание пакета — проверяется только на
   голом контейнере и только для *упавшего* инициализатора. Показательно, что
   помощник `handleInit(cancel:)`
   (`test/scope_auto_dependencies_test.dart:229-266`) принимает параметр
   отмены, но **ни один живой тест его не передаёт**.
2. **Падающие хуки контроллера.** `cleanup_after_user_error_test.dart` —
   файл, весь смысл которого «пользовательский хук упал, обязательная уборка
   всё равно прошла», — содержит группы для `AsyncScope`, `AsyncDataScope` и
   `Scope`, и не содержит для `AsyncControllerScope`. Это ровно то семейство,
   которое добавлено последним и которого касаются P2-3 и P2-4.
3. **Поверхность параметров публичных виджетов.** Ни один тест не
   конструирует `AsyncScope`/`AsyncDataScope` с пер-скоупным таймаутом — все
   тесты таймаутов идут через рукописные подклассы. Тест-«таблица
   параметров» не скомпилировался бы сегодня, и это был бы ответ на вопрос,
   можно ли публиковать (P1-2).
4. **Публичные фасады без единого теста.** `LiteScope`, `LiteScopeState`,
   `ScopeWidgetBase`, `ScopeStateNotifier`, `ScopeStateWithErrorNotifier`:
   grep по `test/` даёт нули. `test/lite_scope_test.dart` работает с
   `LiteScopeCore` напрямую, обходя публичный слой. Тонкие прослойки — по
   15-20 строк проброса; ошибка в одном пробросе не будет замечена.
5. **Затенение скоупа того же типа вложенным** — базовый инвариант
   DI-контейнера («ближайший выигрывает») не проверен ни разу.
6. **Ветка «брошенное ожидание завершилось ошибкой»**
   (`async_scope_core.dart:800-818`): все тесты истечений держат `Completer`,
   который никогда не завершается, поэтому `work.catchError` не срабатывает
   ни разу. Если он пропадёт, отложенный сбой станет unhandled async error —
   краш через произвольное время после ухода экрана.
7. **Фильтрация по уровню логирования.** Дефолт — `off`, издатель по
   умолчанию — `print`. Что порог работает, не проверено; порог живёт во
   внешнем `logger_builder`, то есть контракт с чужим пакетом не закреплён.

**Тесты-пустышки и хрупкость.**

`test/async_scope_state_test.dart` целиком: оба теста сравнивают число
открывающих и закрывающих скобок в `toString()`. Тест пройдёт при
`toString() => ''` (0 == 0) и при возврате имени класса без ошибки, прогресса
и стектрейса — то есть заявленную ветку `progress == null ? '' : …` он не
различает. Тавтологический ассерт в `scope_logger_test.dart:32-36`:
`expect(drop, isA<ScopeLogTransformer>())` не может упасть, потому что
следующая строка не скомпилировалась бы при несовпадении типов.

`test/scope_auto_dependencies_test.dart` — 1100 строк, 14 почти одинаковых
тестов, каждый пиннит два golden-списка строк. Любое косметическое изменение
формулировки состояния ломает 28 списков разом; при этой цене соседние
состояния (`ScopeDependencyDisposalCancelled`, `ScopeDependencyDisposalFailed`)
не проверяются вовсе.

Три расходящиеся приватные копии `_settle` рядом с общим
`test/utils/settle.dart`, причём копия в `lite_scope_test.dart` делает
`tester.pump()` без длительности — фейковое время в ней не идёт вовсе.
Ловушка для будущего автора тестов: имя то же, поведение другое.

**Достоверность раздела «Пробелы в покрытии» в `docs/handoff.md`.** Проверено
по фактическим тестам. Утверждение «Крупных пробелов не осталось. Покрыты все
слои» неверно (пункты 3 и 4 выше). Два пункта устарели в хорошую сторону:
`ScreenshotReplacer` теперь покрыт двумя прямыми виджет-тестами
(`lite_scope_test.dart:827-942`), а `throwWhenDisposed` — прямо, с проверкой
текста сообщения (`listenable_utils_test.dart:29-45`). Про `isRoot` формулировка
пессимистична: пустой внутренний стек покрыт, а вот действительно непокрытая
связка `isRoot` + `onPop` не отмечена.

## Performance and reliability

**Надёжность.** Ключевой вывод: пакет очень аккуратен в *ожидаемых* отказах и
менее аккуратен в *неожиданных*. Четыре ожидания разбора ограничены,
таймеры для них берутся из `Zone.root` (правильно — иначе рушатся чужие
виджет-тесты), завершение `_initCompleter` проверено по всем семи веткам
выхода, двойной разбор невозможен, ключи не теряются. Но там, где бросает
пользовательский код в неожиданном месте, картина хуже: P1-4, P1-5, P1-6,
P2-2, P2-3, P2-6 — все шесть об одном и том же, о непойманном исключении из
чужого колбэка.

**Гонки.** Целенаправленно проверены и дефектов не найдено: `AccessEntry`
попадает в очередь синхронно (состояние «создан, но не в очереди»
недостижимо), провал поиска координатора происходит строго до создания
записи, снимок детей в `waitForChildren` переживает бросок из `onTimeout`,
повторный `unregister()` — no-op, `_isDisposing` проверяется во всех точках,
где выполнение может застать начавшийся разбор, — кроме одной
(`performRebuild`, `async_scope_core.dart:316`), где сценарий требует
довольно экзотического пользовательского кода.

**Производительность.**

- *Notify-only пересборка строит поддерево впустую* (P2-5) — самое дорогое из
  найденного, потому что попадает на каждое уведомление.
- *`model` аллоцирует обёртку на каждое чтение* (P3-4) — мусор на каждый билд
  и на каждый прогон селектора.
- *`runStreamGuarded` строит суб-логгер на каждый вызов* (P3-15) — работа,
  квадратичная по числу живых скоупов, при выключенном логгере.
- *`ListenableSelector` переподписывается на каждой пересборке*, если
  `selector` — захватывающее замыкание (обычный способ его написать).
  Сравнение по identity здесь правильное решение; не хватает предупреждения в
  дартдоке.

Ничего из этого не является узким местом само по себе; всё четыре — работа,
которую можно не делать.

**Размер архива.** 752 KB сжатых, 419 файлов. Из них 95 — платформенная
обвязка примеров (`example/*/macos/` — 88 файлов, ~672 KB, включая иконку на
100 KB; `example/scopo_demo/web/` — 7 файлов, 42 KB). Ни для чтения примеров,
ни для их запуска на другой платформе она не нужна.

## Maintainability

**Что сделано хорошо.** Комментарии в этом пакете — редкость по качеству: они
объясняют не «что делает строка», а «почему именно так, и что будет иначе», и
при проверке оказываются верными. Комментарий над `_performAsyncDispose`
(`:653-659`) описывает четырёхстадийную конструкцию точнее, чем это сделал бы
внешний документ. Комментарий у `_initSucceeded` (`:153-166`) объясняет, зачем
поле существует отдельно от `model.state`. Комментарий у `_awaitBounded`
(`:752-768`) объясняет выбор `Zone.root` двумя независимыми причинами.

**Главный риск сопровождения** — тот, что дал три P1: **исправления
применяются по месту, а не по классу**. Механизм видно: находка приходит с
конкретным `file:line`, тест пишется на неё же, гейт зеленеет, работа
закрывается. Вопрос «а где ещё живёт этот же дефект» в процессе не
предусмотрен. Дешёвое лекарство — при закрытии находки делать grep по
соседним реализациям (последовательная/параллельная группа,
синхронная/асинхронная половина, три семейства с одинаковыми полями) и
записывать результат в отчёт волны.

**Дублирование.** Девятка параметров в трёх семействах (~150 строк). Три
иерархии состояний. Девять вариантов `select` с разным числом типовых
аргументов. Около 80 публичных типов на 8 100 строк — много; после 1.0 всё
это придётся поддерживать.

**Расхождение кода и документации** — систематическое, а не случайное:
13 расхождений из 43 проверенных утверждений. Причина структурная: врезки с
кодом в README, `doc/*.md` и дартдоке никем не проверяются. `dart doc
--dry-run` не анализирует содержимое ```dart-блоков, а `docs/ru/check.sh`
сверяет blob-хеши переводов, но не соответствие врезки исходнику. Отсюда и
P1-1, и P2-16, и P3-1. Лечится тем, что врезки выносятся в `example/` или в
тест и вставляются оттуда.

**Мёртвый и почти мёртвый код в публичном API:**
`ScopeDependencyNoDisposalRequired` (не создаётся нигде),
`ScopeStateWithErrorModel`/`Notifier`/`View` (не используются в `lib/`, не
покрыты, документированы неверно), `ScopeDependenciesExtension.asStream`
(ноль использований), недостижимые ветки `runStreamGuarded.onPause/onResume`.
Удалять после публикации — ломающее изменение.

## Positive findings

Это стоит сохранить:

1. **Комментарии-обоснования.** Описаны выше. Их надо беречь при рефакторинге:
   они единственный носитель части знания о пакете.
2. **`_awaitBounded` с таймером из `Zone.root`** (`async_scope_core.dart:769-833`)
   — правильное решение неочевидной проблемы, плюс «abandoned, not forgotten»:
   брошенная работа не забывается, её поздний сбой репортится.
3. **`_debugCheckScopeKeyOwnership`** (`:339-421`) — четыре различных
   диагностики с точным описанием последствий каждой. Образец того, как надо
   сообщать о нарушении контракта.
4. **Разделение `onUnmount` и `disposeAsync`** на обоих путях ухода скоупа,
   включая `close()`, который оставляет элемент смонтированным.
5. **`_closeCompleter`** (`lite_scope_core.dart:243-261`): один разбор на
   элемент, и все вызывающие получают его результат — включая ошибку.
6. **`scope_coordination.dart`** — чистые структуры без Flutter, отдельно
   протестированные.
7. **`_hasData` отдельно от значения** — правильное решение для nullable `T`
   (жаль, применённое не везде, см. P3-8).
8. **Тесты, написанные от дефекта,** с проверкой нагруженности откатом.
   Практика редкая и очень ценная.
9. **Гейт из восьми команд** и правило «сначала прогон, потом заявление».

## Prioritized action plan

| Priority | Problem | Impact | Recommended action | Estimated effort |
| --- | --- | --- | --- | --- |
| P1 | Первый пример README не компилируется (`unmount` → `onUnmount`) | Первое впечатление на pub.dev: две главные вкладки | Правка в 3 файлах + зеркало; добавить `example/README.md` в оба цикла `docs/ru/check.sh` | 30 мин |
| P1 | `AsyncScope`/`AsyncDataScope` не пробрасывают 9 параметров | Две самые рекламируемые формы без настройки жизненного цикла; `doc/debug.md` врёт | 18 строк `super.` в два конструктора; тест-таблица параметров | 1 ч |
| P1 | Синхронный провал init не даёт `buildOnError` | Вечный спиннер на самой частой ошибке конфигурации | Перевод модели в `AsyncScopeError` в `catch` до `rethrow`; тест на состояние модели | 2 ч |
| P1 | Падающий диспозер в `concurrent` обрывает соседей | Утечка ресурсов без возможности ретрая | `handleError` на каждого ребёнка до `_mergeStreams`; не ставить `_isDisposalDone` при отмене; тест | 3 ч |
| P1 | Упавший `ScopeState.onUnmount` пропускает unmount зависимостей | Подписки живут после ухода скоупа | `try`/`catch` по образцу `disposeAsync` ниже; тест в `cleanup_after_user_error_test.dart` | 1 ч |
| P1 | Бросок селектора замораживает элемент скоупа | В release — тихая потеря реактивности поддерева | `try`/`catch` вокруг `notifyClients`; перенести ассерты `performRebuild` после `super`; тест | 3 ч |
| P2 | `waitForChildren()` без дефолта ждёт вечно | Дедлок вместо задержки, вопреки документации | `timeout ?? ScopeConfig.defaultWaitForChildrenTimeout` | 15 мин |
| P2 | `failure =` вместо `failure ??=` в двух из трёх стадий | Теряется первопричина каскадного сбоя | Две правки в одну строку | 15 мин |
| P2 | `finally` контроллера вытесняет ошибку `init()` | Настоящая причина отказа исчезает бесследно | `try`/`catch` вокруг `performDispose()` в `finally` | 1 ч |
| P2 | Разбор контроллера при упавшем `init()` не ограничен | Бесконечный `buildOnInitializing` без диагностики | `_awaitBounded` с `disposeAsyncTimeout` либо правка документации | 1-2 ч |
| P2 | Notify-only пересборка строит поддерево впустую | Аллокация всего дерева виджетов на каждое уведомление | Кешировать построенный виджет и отдавать его при `_shouldOnlyNotify` | 2 ч |
| P2 | `CompositeListenableSubscription.cancel()` обрывается | Утечка слушателей; debug падает там, где release работает | Сделать `cancel()` идемпотентным | 30 мин |
| P2 | Пустой стектрейс у ошибки зависимости | Crashlytics получает запись без стека | Передавать `stackTrace` вместо `StackTrace.empty` | 30 мин |
| P2 | Ошибки разбора зависимостей идут только в выключенный лог | Незакрытые ресурсы не диагностируются | Добавить `FlutterError.reportError` | 30 мин |
| P2 | `.value(value: null)` компилируется | Голый null-check без имени скоупа | Ассерт с диагностикой либо не-nullable параметр | 1 ч |
| P2 | `LiteScope.of`/`select` падают до готовности | Null-check вместо внятной ошибки; вместе с P1-6 — заморозка | Бросок с сообщением о фазе скоупа | 1 ч |
| P2 | `close()` состояния ищет скоуп по дереву | Падение на легальном пути; можно закрыть чужой скоуп | `close() => _scopeElement.close()` | 15 мин |
| P2 | Инварианты семейств не запечатаны | Потребитель молча отключает освобождение контроллера | `@nonVirtual`/`@mustCallSuper` на 3 метода | 30 мин |
| P2 | `doc/scope_notifier.md` описывает `AsyncScope` неверно | Неверная ментальная модель ключевого семейства | Переписать раздел «State models» | 1 ч |
| P2 | `asStream` содержит `this as T` | Ошибка типа переносится в рантайм | Дженерик по получателю; ломающее, строка в CHANGELOG | 1 ч |
| P2 | Подписки из `didChangeDependencies` теряются | Пропущенные оповещения, `_cached` устаревает навсегда | `assert(context.debugDoingBuild)` в `_find` + строка в `doc/base.md` | 1 ч |
| P2 | `context.read<Api>()` в примерах нового семейства | Флагманский пример релиза не компилируется | Заменить на форму scopo | 30 мин |
| P2 | `AsyncControllerScope` отсутствует в навигации | Главная новинка наполовину невидима | 4 строки в README, `doc/base.md`, `doc/full_scope.md` + зеркала | 30 мин |
| P3 | 20 находок: dartdoc-пример `ProgressIterator`, `NaN` в `Progress`, мёртвые публичные типы, аллокация `model`, идемпотентность `performInit`, `data` до ready, nullable `T`, `@nodoc`, `@visibleForTesting`, `ScopeConfig` без `reset`, `StateAsNotifier`, упавший `onPop`, суб-логгер в `runStreamGuarded`, устаревшие ссылки в документации | По отдельности мелко; вместе — качество публичной поверхности перед 1.0 | Разобрать одной волной после P1/P2 | 1 день |
| — | Раздел «Пробелы в покрытии» в `docs/handoff.md` неточен | Ложная уверенность там, где принимается решение о публикации | Переписать по факту | 30 мин |
| — | 95 файлов платформенной обвязки примеров в архиве | 752 KB архива, из них ~700 KB не нужны потребителю | Взвесить исключение `example/*/macos/`, `example/scopo_demo/web/` в `.pubignore` | 30 мин |

## Проверка и ограничения

**Что запускалось** (закреплённый тулчейн, Flutter 3.29.0 через fvm, коммит
`9296648`):

| проверка | результат |
| --- | --- |
| `fvm flutter test` | 222 теста, все зелёные |
| `fvm flutter analyze` (корень) | `No issues found!` |
| `analyze` во всех трёх `example/*` | `No issues found!` в каждом |
| `fvm dart format --set-exit-if-changed lib test` | 84 файла, 0 changed |
| `fvm dart doc --dry-run` | 0 warnings, 0 errors |
| `fvm dart pub publish --dry-run` | 0 warnings, архив 752 KB, 419 файлов |
| `sh docs/ru/check.sh` | переводы актуальны: 15 |
| тесты `example/scopo_demo` (вне гейта) | 2 теста, зелёные |

**Как велось ревью.** Семь независимых разборов по областям (ядро
`AsyncScope`; `AsyncControllerScope` и `AsyncDataScope`; `full_scope` и
зависимости; виджетный слой; утилиты и окружение; тестовая сьюта; публичная
поверхность и документация), каждый с запретом на правку файлов. Затем
сведение с проверкой каждой существенной находки по коду — часть заявленного
при этом не подтвердилась и в отчёт не вошла (`.vscode/` в архиве; отсутствие
мутационной проверки связи с `_initSucceeded`). Утверждения о механике Flutter
сверены с исходниками SDK 3.29.0
(`framework.dart`, `navigator.dart`, `routes.dart`).

**Ограничения.**

- Код не менялся, тесты на находки не писались: все утверждения о поведении
  выведены из чтения кода пакета и SDK, а не из воспроизведения. Для
  находок P1-3, P1-4, P1-5, P1-6, P2-3, P2-6 воспроизведение — первый шаг
  исправления, и оно же проверит оценку.
- Покрытие в строках не измерялось (`--coverage` не запускался). «Не
  покрыто» везде означает «нет теста, в котором эта ветка достижима по
  чтению кода и по grep».
- Поведение на web-целях не проверялось: разбор семантики `async*` сделан по
  VM-реализации (`_internal/vm/lib/async_patch.dart`); для `dart2js`/DDC
  контроллер `async*`-генератора другой, а на его семантике держится
  корректность `finally` в `AsyncControllerScopeElementBase.initDataAsync`.
- `logger_builder` (внешний пакет владельца) прочитан выборочно: оценка
  стоимости `withAddedName` в P3-15 аналитическая, профилирования не было.
- `example/scopo_demo` (≈70 файлов) прочитан выборочно — точки использования
  публичного API и тесты; утверждать, что все файлы компилируются, нельзя
  (хотя `analyze` по нему чист).
- Точный момент обрыва вложенной группы в P1-4 зависит от того, где именно
  генератор окажется в момент отмены; асимметрия защиты между
  последовательной и параллельной группой подтверждена прямым чтением, сам
  сценарий — рассуждением.

## Рекомендация

**0.10.0 публиковать после закрытия шести P1.** Четыре из них — правки на
несколько строк; две (P1-4, P1-6) требуют теста и аккуратности.

P2 стоит разобрать одной волной до публикации: половина из них — расхождения
документации с кодом, которые после публикации станут «поведением, на которое
кто-то полагается».

Отдельно и вне списка находок: стоит завести правило «закрыл находку — найди
её же в соседней реализации». Три P1 из шести — это одно и то же исправление,
не доехавшее до второго места.
