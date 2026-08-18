# AsyncControllerScope

> Перевод `doc/async_controller_scope.md` (blob `57c97a7760022e761fc4f4c5448a172fa47c13bd`).
> Правится в том же коммите, что и оригинал; проверка — `sh docs/ru/check.sh`.

Скоуп, всё содержимое которого — контроллер: объект со своим жизненным циклом,
который создаётся при монтировании скоупа, асинхронно инициализируется, получает
команду остановиться, когда скоуп уходит, и освобождается после этого. Берите
его, когда скоуп существует потому, что что-то должно **работать**, пока кусок
дерева на экране, — оверлей карты, который ведут блоки, опросник, сессия, — а не
потому, что что-то должно показываться.

```dart
AsyncControllerScope<PlayerController>(
  createController: (context) => PlayerController(api: ScopeModel.of<Api>(context, listen: false)),
  progressBuilder: (context) => const SizedBox.shrink(),
  errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
  builder: (context, controller) => const PlayerView(),
);
```

`AsyncControllerScopeBase` — форма для наследования, и именно в ней оказывается
большинство контроллеров: им обычно что-то нужно из дерева.

```dart
final class Player extends AsyncControllerScopeBase<Player, PlayerController> {
  const Player({super.key, required super.child}) : super(scopeKey: Player);

  @override
  PlayerController createController(BuildContext context) =>
      PlayerController(api: ScopeModel.of<Api>(context, listen: false));

  @override
  Widget buildOnProgress(BuildContext context) => const SizedBox.shrink();

  @override
  Widget buildOnError(BuildContext context, Object error, StackTrace stack) =>
      const SizedBox.shrink();

  @override
  Widget buildOnReady(BuildContext context, PlayerController controller) =>
      child;
}
```

Под обоими лежит `AsyncControllerScopeCore` — для скоупа, которому нужен свой
элемент. Семейство построено на машинерии `AsyncDataScope`, поэтому всё, что
описано в той теме, — четыре состояния, порядок разбора, `scopeKey`, ожидание
дочерних скоупов, четыре таймаута — действует здесь без изменений, а значением
выступает контроллер.

## Контроллер

```dart
final class PlayerController extends ScopeController {
  final Api api;

  StreamSubscription<Track>? _subscription;

  PlayerController({required this.api});

  @override
  Future<void> init() async {
    final session = await api.openSession();
    if (!mounted) return;

    _subscription = session.tracks.listen(_onTrack);
  }

  @override
  void onUnmount() => unawaited(_subscription?.cancel());

  @override
  Future<void> dispose() async => api.closeSession();
}
```

Писать нужно три метода, и ни одному из них не требуется звать `super`:

| метод | когда |
| --- | --- |
| `init()` | один раз, асинхронно, до того как построится готовая ветка |
| `onUnmount()` | синхронно, в момент ухода скоупа с дерева |
| `dispose()` | с ожиданием, после `onUnmount`, когда скоуп разбирают |

`mounted` — это то, что проверяют после каждого `await` внутри `init()`: скоуп
мог уйти, пока инициализация была приостановлена, и тогда `onUnmount()` уже
отработал.

Три метода, которые зовёт скоуп, — `performInit`, `performUnmount`,
`performDispose` — закрыты от переопределения. Они держат `mounted`, держат
порядок и следят, чтобы каждый хук выполнился не больше одного раза, так что
ничего из этого не опирается на соглашение, о котором контроллер обязан помнить.
Они публичные, а не спрятанные, поэтому контроллер можно вести руками в тесте:

```dart
final controller = PlayerController(api: FakeApi());
await controller.performInit();
// …
await controller.performDispose();
```

Последовательность односторонняя. Второй `performInit` ничего не делает, как и
вызов после `performDispose`: иначе `init()` работал бы с тем, что `dispose()`
уже освободил. Разбор у контроллера тоже один, и его исход видят все, кто звал
`performDispose`: второй вызов присоединяется к уже идущему разбору, а не
возвращается немедленно, и падение, которое увидел первый вызвавший, увидит и
второй.

## Что гарантирует скоуп

То, ради чего семейство и заведено. Контроллер, созданный скоупом, скоупом же и
освобождается — на любом пути, включая те два, которые легко упустить, когда то
же самое пишут руками поверх `AsyncDataScope`: там скоуп узнаёт о контроллере
только если инициализация дошла до передачи.

| что случилось | `onUnmount()` | `dispose()` |
| --- | --- | --- |
| скоуп ушёл до начала асинхронной фазы | контроллер не создавался | — |
| `init()` бросил | да | да |
| скоуп ушёл, пока `init()` ещё шёл | да | да |
| скоуп ушёл, и готовое состояние не доехало | да | да |
| обычный путь: готов, потом ушёл | да | да |

`onUnmount()` — синхронная половина, и она всегда первая: в момент ухода скоупа
с дерева, а не когда до неё доберётся асинхронный разбор. Для контроллера,
который ведёт что-то вовне себя, разница существенная: он перестаёт доставать до
внешнего мира сразу, чего бы ни ждал остальной разбор.

Зависший контроллер не может ничего запереть: ожидание отменённой инициализации
ограничено `initCancellationTimeout`, ожидание `dispose()` —
`disposeScopeTimeout`, см. тему `debug`.

## Чтение контроллера из поддерева

```dart
final controller = AsyncControllerScope.of<PlayerController>(
  context,
  listen: false,
).data;
```

`of`, `maybeOf` и `select` возвращают `AsyncDataScopeContext` — ровно как в теме
`AsyncDataScope`: `data` бросает, пока контроллер не готов, `dataOrNull`
возвращает `null`. Виджеты внутри `builder` находятся под готовым скоупом и
могут пользоваться `data`.

У формы для наследования те же три метода статическими, первым идёт тип
виджета:

```dart
final position = AsyncControllerScopeBase.select<Player, PlayerController, int>(
  context,
  (scope) => scope.data.position,
);
```

## Чего это семейство не делает

**Не делает контроллер наблюдаемым.** Скоуп уведомляет зависимых при изменении
своего **состояния** — ожидание, готовность, ошибка — а не когда что-то
изменилось внутри контроллера. Контроллер, за значениями которого виджеты должны
следить, — это `Listenable` с `ScopeNotifier.value` под этим скоупом, либо поток
наружу.

**Не сообщает прогресс.** `init()` — это `Future<void>`, между «инициализируется»
и «готов» показывать нечего. Инициализация, у которой есть этапы, достойные
подписи, — это `AsyncDataScope`, её поток эти этапы и сообщает.

**Ничего не делает с провалом инициализации** сверх того, что делает любое
семейство: ошибка приезжает в `buildOnError`, который обязателен именно затем,
чтобы решение принимали, а не получали по умолчанию. Оттуда её и направляют
дальше — или включают логгер пакета, тема `debug` описывает и то и другое.

## Куда дальше

| тема | о чём |
| --- | --- |
| `AsyncDataScope` | машинерия под низом: состояния, порядок разбора, `scopeKey` |
| `AsyncScope` | тот же жизненный цикл вовсе без значения |
| `ScopeNotifier` | как сделать наблюдаемым сам контроллер |
| `debug` | четыре таймаута и журнал |
