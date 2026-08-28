# Отметка на входе в шаг: наблюдатель слышит, что шаг начался

> **Состояние на 2026-08-28:** решения владельца приняты (§9), работа идёт.
> Объём вышел шире исходной заявки: владелец решил закрыть обе половины
> жизненного цикла контейнера и заодно развести `onProgress` — хуков
> становится двенадцать вместо девяти, и релиз становится **ломающим**.
> **Что это:** дизайн отметок `ScopeObserver` на входе в шаг контейнера
> зависимостей: путь шага сообщается **перед** его запуском, чтобы зависший
> шаг был виден как «последний вход без выхода».
> **Связанные записи:** `2026-08-19[1]-scope-observer-design.md` (сам
> наблюдатель), `2026-08-22[1]-build-phase-design.md` (прошлое расширение
> поверхности наблюдателя), `2026-08-24[5]-controller-dependency-design.md`
> (прошлая правка того же контейнера). Заявка потребителя —
> `tez-taxi-monorepo`, `docs/records/2026-08-28-TT-2375-scopo-step-edge-request.md`
> (тикет TT-2375).

## 1. Зачем

**Разбор зависшего старта на проде.** Заявка пришла от потребителя, который
перешёл с самописного логгера зависимостей на наблюдателя и потерял на этом
одно свойство. Логгер писал пару строк на каждый шаг — `→ имя` перед запуском
и `✓ имя` после, — и правило разбора звучало одной фразой: **последний `→` без
`✓` — это и есть зависший шаг.** Правило не считает и не сопоставляет с
объявлением; оно читается глазами в логе с устройства, которое уже убито.

**Через наблюдателя это правило не воспроизводится.** Контейнер отчитывается
`onProgress` из `init()` — внутри `.map()` над потоком зависимостей
(`scope_auto_dependency.dart:120-129`), а поток отдаёт элемент только после
того, как инициализатор отработал (`scope_dependency_impl.dart:41-48`,
`yield name` стоит за `await result`). Видно последний **завершённый** шаг и
его номер из общего числа — и всё.

Отдельная `ScopeDependency` про свой старт не сообщает вовсе. `onInit` и
`onReady` эмитит контейнер, а не она; из самой зависимости `notifyObserver`
зовётся в трёх местах, и все три — `onTrace` при обработке ошибки да `onError`
при падении `onUnmount` в группе. `doc/debug.md:137` фиксирует это прямым
текстом: «A single dependency sends nothing but `onTrace`».

**Обходного пути нет ни одного, и это проверено.**

- *Вычислить следующий по объявлению.* Для `sequential` потребитель
  теоретически может: `flattenDependencies()` публична, порядок в ней —
  порядок объявления. Для `concurrent` не может никак: шагов в полёте
  несколько, и какой из них зацепился — из номера завершённого не следует.
- *Посмотреть состояние дерева в момент зависания.* Не работает: `_state`
  остаётся `ScopeDependencyInitial` **всю** инициализацию и уходит из него
  только в самом конце — об этом стоит комментарий на месте
  (`scope_dependency_mixin.dart:96-104`, там же и причина: по состоянию нельзя
  отличить «идёт прямо сейчас» от «ещё не начиналось», для того и заведён
  отдельный `_initializing`). То есть в момент зависания все шаги дерева
  выглядят одинаково не начатыми.
- *Держать копию логгера в каждом контейнере старта.* Это ровно то
  дублирование, ради снятия которого потребитель и переходил на наблюдателя.
  Обе копии у него уже удалены.

**Дыра узкая и лежит в одном месте.** У остальных семей её нет: там прогресс
сочиняет сам потребитель в своём `initScope`, и отметку на входе он ставит
сам, ничего для этого не прося у пакета. Просит её именно контейнер
автоматических зависимостей — единственное место, где шаги сочиняет пакет.

## 2. Где ломается

Не в том, чтобы позвать наблюдателя пораньше. **Лист не знает своего пути.**

`path` собирается на подъёме. Лист отдаёт голое `name`
(`scope_dependency_impl.dart:47`), каждая группа наворачивает свой сегмент
через `_path` (`scope_dependency_group.dart:107`), и делает это одинаково в
обеих реализациях — `.map(_path)` стоит и в `_ScopeDependencySequential`, и в
`_ScopeDependencyConcurrent`. Анонимная группа сегмента не добавляет, это
внутри `_path`.

Отсюда два следствия, и они закрывают самые простые решения:

- **отметка, посланная из листа «как есть», принесёт `name`, а не `path`** —
  и два `dep('db')` в разных ветках дерева станут для потребителя одним и тем
  же именем. Заявка просит именно тот же `path`, что придёт следующим
  `onProgress`, и просит по делу;
- **пронести отметку элементом того же потока нельзя.** `Stream<String>
  init()` — публичный член `ScopeDependency`, интерфейса, который потребитель
  вправе реализовать сам; смена типа элемента ломает его код. И сверх того:
  `progressIterator.nextStep()` в контейнере считает шаги **по элементам этого
  потока** (`scope_auto_dependency.dart:121`), так что передняя отметка,
  поехавшая тем же каналом, сдвинула бы нумерацию у всех, кто рисует полосу
  прогресса.

## 3. Что рассмотрено и отклонено

**Лист шлёт `onInit`/`onReady` от своего имени.** Самое дешёвое: новых имён в
публичной поверхности не появляется вовсе, `ScopeObservable` листом уже
реализован, `debugLabel` у него есть. Отклонено по двум причинам, и вторая
решающая:

- принесёт `name`, а не `path` (§2);
- **сломает потребителю выбор уровня записи.** У него маркер `BootSteps`
  висит на контейнере, и наблюдатель по этому маркеру пишет контейнеры старта
  в `info` вместо verbose. Событие от имени листа придёт от объекта, который
  маркером не помечен, а связи «лист → его контейнер» в API нет и заводить её
  ради этого не стоит.

Сюда же — вариант «сделать `debugLabel` листа полным путём»: он чинит первое
и не чинит второе, а заодно молча меняет текст уже существующих `onTrace` и
`onError`.

**Переиспользовать `onProgress` с новым типом полезной нагрузки.** Тоже без
новых хуков: потребитель разбирает `Object? progress` по типу — так уже
устроено различение «инициализация» (`ScopeAutoDependenciesProgress`) и
«разборка» (голый `String`). Отклонено: документированный смысл `onProgress` —
«one step of it is **done**» (`doc/debug.md:78`), и всякий уже написанный
наблюдатель, печатающий `progress: …`, начнёт врать — по строке на шаг, с
обратным смыслом. Новый хук на `ScopeObserver` при этом не ломающий по
построению: класс `base`, тела пустые, и это в нём заявлено как обещание
(`scope_observer.dart`, дартдок `ScopeCompositeObserver`).

**Публичное состояние «инициализируется прямо сейчас».** Дало бы дамп дерева с
видимыми шагами в полёте, и для `concurrent` тоже. Отклонено дважды: не решает
задачу — на проде дампа нет, есть лог с убитого устройства; и ломает —
`ScopeDependencyState` объявлен `sealed`, а `switch`ей по нему без `default`
в пакете и у потребителей достаточно.

## 4. Правка

Второй канал, не поток: поле-колбэк на `ScopeDependencyMixin`, которое группа
передаёт детям, **оборачивая тем же `_path`**. Композиция получается ровно та
же, что у `.map(_path)` на подъёме, поэтому пути двух каналов разойтись не
могут — сборка одна и та же функция.

**`ScopeDependencyMixin`** — два поля, по одному на половину:

```dart
/// Told the path of each step of this subtree as it is entered, before the
/// step does anything.
///
/// The other half of the pair `init()` yields once the step is done. Set by
/// the enclosing group, which wraps it in its own `_path` — the same
/// assembly the completed step travels through on its way up, so the two
/// halves cannot report different paths.
void Function(String path)? _onStepStarted;

/// The same, for the disposal walk.
void Function(String path)? _onDisposalStepStarted;
```

**`_ScopeDependencyImpl._runInit`** — первой строкой, до всего:

```dart
@override
Stream<String> _runInit() async* {
  // Before the handle, before the initializer: the promise is that this
  // arrives ahead of anything the step awaits.
  _onStepStarted?.call(name);
  final helper = _helper = ScopeDependencyHandle._(this);
  ...
```

Синхронно и до `await`: тело `async*`-генератора выполняется при подписке и
доходит до первого `yield`, а первого `yield` до самого конца нет.

**`_ScopeDependencyImpl._runDispose`** — не первой строкой, а **после
раннего возврата**:

```dart
final helper = _helper;
final disposer = helper?.dispose;
if (helper == null || disposer == null) {
  return;
}
helper.dispose = null;
_onDisposalStepStarted?.call(name);
```

Иначе зависимость, зарегистрировавшая только `unmount`, объявляла бы вход и
никогда не объявляла выход — ровно тот ложный «зависший шаг», ради которого
всё и делается. `disposalRequired` этого не ловит: у него `unmount` считается
наравне с `dispose`, и он для того так и написан.

**`ScopeDependencyGroup`** — установка детям, одним методом на обе группы и
обе половины:

```dart
/// Hands [dependency] the entry callbacks, prefixed with this group's
/// segment. A dependency of the caller's own making is not a
/// [ScopeDependencyMixin] and has nowhere to take them — its completed step
/// still arrives, its entry does not.
void _wireStepsStarted(ScopeDependency dependency) {
  if (dependency is! ScopeDependencyMixin) {
    return;
  }
  dependency
    .._onStepStarted = (path) => _onStepStarted?.call(_path(path))
    .._onDisposalStepStarted =
        (path) => _onDisposalStepStarted?.call(_path(path));
}
```

Ставятся обе сразу и в обоих обходах: наборы детей у обходов разные —
`initializationRequired` против `_disposalOrder()`, — а лишний канал просто
никогда не сработает.

В `_ScopeDependencySequential` — внутри цикла, перед `init()`/`dispose()`
очередного ребёнка; лишнего обхода не появляется. В
`_ScopeDependencyConcurrent._runInit` детей надо обойти до слияния, а
`_dependencies.where(...)` там ленивый и сейчас вычисляется ровно один раз,
внутри `_mergeStreams` на `onListen`. Поэтому список **материализуется**
(`.toList()`) — иначе фильтр `initializationRequired` вычислится дважды. Само
по себе это ничего не меняет (состояния детей между двумя проходами не
двигаются), но полагаться на это незачем. В
`_ScopeDependencyConcurrent._runDispose` та же оговорка не нужна:
`_disposalOrder()` и так возвращает список, — но вызов надо поднять в
локальную, потому что у него есть побочный эффект (`_markNothingToDispose`) и
звать его дважды нельзя.

**`ScopeAutoDependencies`** — корню, одним приватным методом, который зовут
оба обхода: `init()` после `_prepareDependencies` (он может построить дерево
заново) и до `dependencies.init()`, `_runDispose()` — до
`dependencies.dispose()`:

```dart
void _wireStepsStarted(ScopeDependency dependencies) {
  if (dependencies is! ScopeDependencyMixin) {
    return;
  }
  dependencies
    .._onStepStarted = (path) =>
        notifyObserver((observer) => observer.onStepStarted(this, path))
    .._onDisposalStepStarted = (path) => notifyObserver(
          (observer) => observer.onDisposalStepStarted(this, path),
        );
}
```

Там же, в `_runDispose`, `onProgress` заменяется на `onDisposalProgress` —
это и есть вся ломающая часть правки.

Колбэк после прогона не снимается: дерево живёт до следующего `init()` ради
`flattenDependencies()`, контейнер переживает дерево, а новое дерево получает
новую проводку. Дерево, построенное но ни разу не инициализированное,
переподключается на каждом заходе — это тот же случай, что и первый.

Корень-лист (`dep('x')` прямо корнем) — тоже `ScopeDependencyMixin`, поэтому
проводится и сообщает путь, равный имени. Анонимная группа сегмента не
добавляет, это уже внутри `_path`.

**Порядок событий.** Для одного шага — вход, потом выход. Между шагами
`sequential` перепутаться не может: группа стоит на `yield`, пока элемент не
заберут, а `onProgress` контейнер шлёт внутри `.map()` над этим элементом, то
есть до того, как группа двинется к следующему ребёнку. Для `concurrent`
входы и выходы чередуются — как и должны.

## 5. Публичная поверхность

**Три новых хука, и девять становятся двенадцатью.** Заявка просила один; два
других — решения владельца (§9), и вместе они дают у контейнера четыре события
на две половины жизненного цикла, ни одно из которых не требует разбора
нагрузки по типу.

```dart
/// One step of an initialization has begun; [path] names it.
///
/// The other half of [onProgress], which arrives when that same step is
/// done and carries the same `path`. Sent by the container of automatic
/// dependencies, before the step awaits anything — so a step that never
/// finishes is the last path announced here with no [onProgress] behind it.
void onStepStarted(ScopeObservable target, String path) {}

/// One step of a disposal has begun; [path] names it.
///
/// The disposal half of [onStepStarted], and the other half of
/// [onDisposalProgress]. Sent only for a dependency that has something to
/// release: one that registered no disposer is walked past in silence, so
/// every path announced here is one [onDisposalProgress] is due for.
void onDisposalStepStarted(ScopeObservable target, String path) {}

/// One step of a disposal is done; [path] names the dependency released.
///
/// This used to arrive through [onProgress] as a bare `String`, which made
/// that hook mean two different things and left the reader to tell them
/// apart by the type of a value.
void onDisposalProgress(ScopeObservable target, String path) {}
```

Итог у контейнера — две пары, разложенные по хукам:

| половина | вход | выход |
| --- | --- | --- |
| инициализация | `onStepStarted(target, path)` | `onProgress(target, ScopeAutoDependenciesProgress)` |
| разборка | `onDisposalStepStarted(target, path)` | `onDisposalProgress(target, path)` |

`target` во всех трёх — **контейнер**, не лист: симметрично `onProgress` и,
что важнее, это тот объект, по которому потребитель уже фильтрует (§3).

Полезная нагрузка — голый `String`, а не `ScopeAutoDependenciesProgress`:
номер у начинающегося шага смысла не имеет — `number` означает «сделано
столько-то», а в `concurrent` в полёте их сразу несколько.

**`onProgress` теряет один из трёх источников, и это ломающая правка.**
Раньше разборка контейнера отчитывалась через него голым `String`; теперь у
неё свой хук. Ломает молча — чужой `onProgress` не перестанет компилироваться,
он просто перестанет слышать разборку, и анализатор об этом не скажет.
Поэтому: строка **Breaking** в `CHANGELOG.md` и абзац в `doc/debug.md`, где
раздел «What `onProgress` carries» сокращается с трёх источников до двух.
Слот под неё есть: пакет `0.x`, минорный бамп его несёт.

Что тянется следом:

- **`ScopeCompositeObserver`** — проксирование всех трёх. Он для того и написан
  руками, чтобы расти вместе с классом, и это его единственная работа;
- **`ScopePrintObserver`** — три строки. Многоточие в этом файле уже значит
  «началось» (`initialize…`, `dispose…`), поэтому вход берёт его же:

  ```text
  scopo | AppDeps(#1a2b) | initialize…
  scopo | AppDeps(#1a2b) | initialize storage/db…
  scopo | AppDeps(#1a2b) | progress: storage/db (1/3)
  …
  scopo | AppDeps(#1a2b) | dispose…
  scopo | AppDeps(#1a2b) | dispose storage/db…
  scopo | AppDeps(#1a2b) | disposed storage/db
  scopo | AppDeps(#1a2b) | disposed
  ```

## 6. Что остаётся асимметричным — и это осознанно

- ~~**Разборка.**~~ Закрывается этой же правкой, решением владельца: у
  `dispose()` дыра была та же, и «крыть обе половины одним хуком» —
  единственный вариант, который пришлось бы объяснять потребителю, — снят
  вторым хуком, а не общим. Заодно снята и причина, по которой он вообще
  рассматривался: выход из шага разборки уехал из `onProgress` в свой
  `onDisposalProgress`, так что различать половины по типу нагрузки больше
  нигде не нужно.
- **В `Scope` отметка не пробрасывается.** Прогресс контейнера приходит дважды
  — под меткой контейнера и под меткой скоупа — потому, что едет потоком, а
  скоуп пересылает всё, что из потока пришло (`async_scope_core.dart:733`).
  Отметка потоком не едет и придёт только от контейнера. Потребителю этого
  хватает (он на контейнер и смотрит), но `doc/debug.md:150` обещает «arrives
  twice», и обещание перестанет быть общим правилом — либо дописывается
  оговорка, либо проброс делается руками. §9.
- **Чужая реализация `ScopeDependency`.** Не `ScopeDependencyMixin` — значит
  не проводится и входа не сообщает; завершённый шаг у неё приходит как
  раньше. Прецедент ровно такой же уже есть в `_disposalOrder()`
  (`dependency is ScopeDependencyMixin`). Документируется одной фразой в
  дартдоке хука.

## 7. Тесты

Сперва падающий, потом правка, потом проверка нагруженности откатом — §8
регламента. Через записывающий наблюдатель:

1. `sequential` из двух листьев: порядок событий ровно
   `вход A, выход A, вход B, выход B`;
2. **вход приходит до `await`**: инициализатор паркуется на `Completer`,
   который тест не завершает; вход уже записан, выхода нет. Это и есть та
   самая проверка обещания, ради которого правка делается;
3. `concurrent`: оба входа записаны прежде любого выхода;
4. вложенные группы и анонимная группа: путь входа **посимвольно равен**
   `path` следующего за ним `onProgress`;
5. шаг, который упал: вход есть, выхода нет, `onError` на месте;
6. `ScopeCompositeObserver` пересылает все три новых хука своим;
7. чужая реализация `ScopeDependency` в дереве: прогон не падает, входа по ней
   нет, выход есть;
8. **разборка**: пара вход/выход на каждую зависимость, и путь тот же, что был
   у инициализации;
9. **зависимость, зарегистрировавшая только `unmount`**: ни входа, ни выхода —
   освобождать нечего, и ложной пары «вошли и не вышли» не возникает;
10. выход из шага разборки приходит через `onDisposalProgress`, а `onProgress`
    во время разборки не зовётся вовсе — это проверка ломающей части.

## 8. Объём и версия

`scope_dependency_mixin.dart` (два поля), `scope_dependency_impl.dart` (два
вызова), `scope_dependency_group.dart` (проводка, обе группы, оба обхода),
`scope_auto_dependency.dart` (корень, оба обхода, замена `onProgress` на
`onDisposalProgress`), `scope_observer.dart` (три класса: базовый,
композитный, печатающий). Тесты по §7, плюс правка `test/utils/observer.dart`
— записывающий наблюдатель должен слышать новые хуки, иначе они не попадут ни
в одну проверку.

`CHANGELOG.md` — раздел 0.13.0, со строкой **Breaking** про `onProgress`.
`doc/debug.md`: «The nine hooks» становится двенадцатью — счёт стоит в тексте
и в `doc/debug.md:21` («a class of nine methods»), — три строки таблицы, абзац
«Who sends them», раздел «What `onProgress` carries» сокращается с трёх
источников до двух, оговорка про «arrives twice». `README.md:676` перечисляет
хуки — туда же. Русские зеркала `docs/ru/doc/debug.md` и `docs/ru/README.md`
тем же коммитом, затем `sh docs/ru/stamp.sh`. Гейт §6 целиком.

**Правка ломающая** — не новыми хуками (те приходят с пустым телом), а тем,
что разборка контейнера больше не отчитывается через `onProgress`. Версия —
**0.13.0**: пока пакет `0.x`, минорный бамп несёт слот ломающих, и 0.11.0 —
уже пройденный тому пример.

## 9. Решения владельца

Приняты 2026-08-28, все четыре в одном заходе.

1. **Имя хука — `onStepStarted(target, path)`**, из четырёх предложенных
   (`onStep`, `onStepBegun`, `onProgressStarted` — остальные три).
2. **Разборку крыть той же правкой, и двумя хуками, а не одним общим.**
   Общий хук на обе половины отклонён именно потому, что потребитель не
   отличил бы вход в шаг инициализации от входа в шаг разборки: нагрузка у
   обоих — голый `String`.
3. **Проброс в `Scope` не делать**, оговорку в `doc/debug.md` дописать (§6).
4. **Работу делать сразу**, версия 0.13.0.
5. **Сверх трёх вопросов, по ходу:** развести и `onProgress` — выход из шага
   разборки уезжает в собственный `onDisposalProgress`. Довод владельца лёг
   ровно в шов, который открыло решение 2: держать вход разборки в
   типизированном хуке, а выход из неё — в общем, где половины различаются
   типом нагрузки, было бы перекосом. Цена принята сознательно: правка
   ломающая, и ломающая молча — чужой `onProgress` не перестанет
   компилироваться, он перестанет вызываться.
