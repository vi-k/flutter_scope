# scopo

> Перевод `README.md` (blob `98a4feeab5db18cc23dffcf988ad6e3a102c7f62`).
> Правится в том же коммите, что и оригинал; проверка — `sh docs/ru/check.sh`.

[![pub version](https://img.shields.io/pub/v/scopo)](https://pub.dev/packages/scopo)
[![license](https://img.shields.io/github/license/vi-k/scopo)](https://github.com/vi-k/scopo/blob/main/LICENSE)

Flutter-пакет для управления скоупами: внедрение зависимостей, состояние и
жизненный цикл внутри дерева виджетов. Скоуп владеет своими зависимостями,
инициализирует их асинхронно, отдаёт их своему поддереву и утилизирует по
порядку — после того, как исчезнут его дочерние скоупы.

## Зачем ещё один

`provider`, `riverpod` и `get_it` отвечают на один вопрос: как значение
доходит до виджета, которому оно нужно. scopo отвечает на другой — **как
значением владеют во времени**: когда его создают, что показывает экран, пока
оно создаётся, что будет, если виджет уйдёт раньше, чем оно готово, и в каком
порядке всё отпускают на выходе.

Это стоит отдельного пакета только тогда, когда у объектов есть собственный
жизненный цикл — база данных, сокет, плеер, сессия вошедшего пользователя. Что
даёт scopo:

- **инициализация — это `Stream`**, поэтому у скоупа есть ветка загрузки,
  значение прогресса и ветка ошибки без собственной машины состояний;
- **недоделанную инициализацию отменяют**, а взятое ею возвращают; чтобы это
  началось, достаточно убрать виджет с дерева;
- **разбор идёт по порядку** — скоуп дожидается дочерних скоупов, прежде чем
  отпустить собственные зависимости, так что ничего не отпускают, пока за него
  держится что-то снизу;
- **`scopeKey` выстраивает два скоупа в очередь за одним ресурсом**:
  пересозданный скоуп ждёт, пока предыдущий владелец того же ключа закончит
  отпускать;
- **`close()` удерживает на экране последний кадр**, пока идёт асинхронный
  разбор, вместо того чтобы вырвать поддерево на полпути;
- **каждый шаг наблюдаем** типизированным наблюдателем — отказы в том числе.

Riverpod закрывает часть этого: `FutureProvider` и `AsyncValue` дают ветки
загрузки и ошибки, а `ref.onDispose` отпускает взятое провайдером. Чего он не
даёт — это *ожидания*: `onDispose` — синхронный колбэк, поэтому фразе
«отпустить базу только после того, как её отпустят все скоупы, которые ею
пользовались» там негде поместиться. Разбор там идёт по графу провайдеров и их
слушателей; здесь — по дереву виджетов.

**Когда scopo брать не стоит.** Если зависимости создаются синхронно и
отпускаются одним `dispose()`, всё перечисленное чего-то стоит и ничего не даёт:
`provider` меньше, известнее и его достаточно.

## Возможности

- **Скоупы**: виджет, который владеет зависимостями и состоянием и отдаёт то и
  другое своим потомкам.
- **Асинхронная инициализация**: инициализация — это `Stream`. Она сообщает о
  прогрессе, ведёт ветки загрузки и ошибки и отменяется, если скоуп уйдёт с
  дерева раньше, чем она закончится.
- **Утилизация по порядку**: скоуп дожидается утилизации дочерних скоупов,
  прежде чем утилизировать собственные зависимости
  (`waitForChildrenTimeout`), а `scopeKey` заставляет пересозданный скоуп
  подождать предыдущий скоуп с тем же ключом.
- **Выборочные перестроения**: `select` и `selectParam` подписывают потомка на
  одно значение; `notifyDependents` перестраивает только этих потомков и
  никогда — собственное поддерево скоупа. `setState` — вторая половина, и он
  не тронут: перестраивает собственное поддерево состояния и до подписчиков не
  доходит.
- **Аккуратное закрытие**: `close()` замораживает поддерево снимком и показывает
  `buildOnClosing`, пока идёт асинхронная утилизация.
- **Девять семейств**: от виджета, который только отдаёт вниз собственные
  параметры, до полного скоупа с контейнером зависимостей — берут самое
  маленькое из подходящих.
- **Наблюдаемый жизненный цикл**: типизированному наблюдателю сообщают о каждой
  инициализации, шаге прогресса, отказе и разборе.

## Установка

```sh
flutter pub add scopo
```

```dart
import 'package:scopo/scopo.dart';
```

## Семейства

Их восемь, и нужное — самое маленькое из подходящих. Ниже они идут от меньшего
к большему, в том же порядке, что и темы; самому большому, `Scope`, отведён
отдельный раздел следом.

| чем владеете | что брать |
| --- | --- |
| ничем, кроме собственных параметров виджета | `ScopeWidgetBase` |
| обычным объектом с `dispose()` | `ScopeModel` |
| `Listenable` — `ChangeNotifier`, `ValueNotifier`, … | `ScopeNotifier` |
| объектами, которые уже есть, но их жизненным циклом должно править дерево | `AsyncScope` |
| значением, которое создаётся асинхронно | `AsyncDataScope` |
| …и это значение — контроллер с собственными `init` и `dispose` | `AsyncControllerScope` |
| объектом состояния с полным асинхронным циклом и `close()` | `LiteScope` |
| контейнером зависимостей **и** состоянием поверх него | `Scope` |

### ScopeWidgetBase

Отдаёт поддереву собственные параметры виджета. Потомки подписываются
попараметрно, поэтому изменение постороннего параметра их не перестраивает.

```dart
final class ApiConfig extends ScopeWidgetBase<ApiConfig> {
  final String apiKey;

  const ApiConfig({
    super.key,
    required this.apiKey,
    required super.child,
  });

  static String apiKeyOf(BuildContext context) =>
      ScopeWidgetBase.select<ApiConfig, String>(
        context,
        (widget) => widget.apiKey,
      );

  @override
  Widget build(BuildContext context) => child;
}
```

**Подробнее:** тема [ScopeWidget](https://pub.dev/documentation/scopo/latest/topics/ScopeWidget-topic.html).

### ScopeModel

Владеет обычным объектом Dart: `create` его создаёт, `dispose` освобождает.
Модель не наблюдаемая, поэтому потомков уведомляют, когда перестраивается сам
виджет `ScopeModel`, а селектор затем отсеивает неизменившиеся значения.
Наследуйтесь от `ScopeModelBase`, чтобы получить именованный скоуп со своими
статическими аксессорами.

```dart
class UserGate extends StatelessWidget {
  const UserGate({super.key});

  @override
  Widget build(BuildContext context) => ScopeModel<UserModel>(
        create: (context) => UserModel('Alice'),
        dispose: (model) => model.dispose(),
        builder: (context) => const UserView(),
      );
}

class UserView extends StatelessWidget {
  const UserView({super.key});

  @override
  Widget build(BuildContext context) {
    // Без подписки:
    final user = ScopeModel.of<UserModel>(context, listen: false);

    // С подпиской на выбранное значение:
    final name = ScopeModel.select<UserModel, String>(
      context,
      (model) => model.name,
    );

    return Text('$name (${user.name})');
  }
}
```

**Подробнее:** тема [ScopeModel](https://pub.dev/documentation/scopo/latest/topics/ScopeModel-topic.html).

### ScopeNotifier

То же, что `ScopeModel`, но для `Listenable` (`ChangeNotifier`,
`ValueNotifier`, …): скоуп подписывается на модель и перестраивает тех потомков,
у которых изменилось выбранное значение. `ScopeNotifierBase` — вариант для
наследования.

```dart
class CounterGate extends StatelessWidget {
  const CounterGate({super.key});

  @override
  Widget build(BuildContext context) => ScopeNotifier<Counter>(
        create: (context) => Counter(),
        dispose: (counter) => counter.dispose(),
        builder: (context) => const CounterText(),
      );
}

class CounterText extends StatelessWidget {
  const CounterText({super.key});

  @override
  Widget build(BuildContext context) {
    // Перестраивается на `notifyListeners`, и только если выбранное
    // значение изменилось.
    final value = ScopeNotifier.select<Counter, int>(
      context,
      (counter) => counter.value,
    );

    return TextButton(
      onPressed: ScopeNotifier.of<Counter>(context, listen: false).increment,
      child: Text('$value'),
    );
  }
}
```

**Подробнее:** тема [ScopeNotifier](https://pub.dev/documentation/scopo/latest/topics/ScopeNotifier-topic.html).

### AsyncScope

Асинхронные инициализация и утилизация без контейнера зависимостей: берите его,
когда объекты уже доступны (синглтон, репозиторий из родительского скоупа) и
деревом нужно управлять только их жизненным циклом. Потомки читают текущее
состояние через `AsyncScope.of(context, listen: …).state`.

```dart
class ConnectionGate extends StatelessWidget {
  const ConnectionGate({super.key});

  @override
  Widget build(BuildContext context) => AsyncScope(
        initScope: (context) async* {
          yield AsyncScopeProgress('connecting');
          await connection.open();

          yield AsyncScopeReady();
        },
        disposeScope: () => connection.close(),
        progressBuilder: (context, progress) => Text('$progress'),
        errorBuilder: (context, error, stackTrace, progress) => Text('$error'),
        builder: (context) => const HomeScreen(),
      );
}
```

**Подробнее:** тема [AsyncScope](https://pub.dev/documentation/scopo/latest/topics/AsyncScope-topic.html).

### AsyncDataScope

`AsyncScope` плюс одно значение: данные, полученные в `initData`, передаются в
`builder` и в `disposeData`. Потомки читают их через
`AsyncDataScope.of<Database>(context, listen: false).data`.

```dart
class DatabaseGate extends StatelessWidget {
  const DatabaseGate({super.key});

  @override
  Widget build(BuildContext context) => AsyncDataScope<Database>(
        initData: (context) async* {
          yield AsyncDataScopeProgress('opening the database');

          yield AsyncDataScopeReady(await Database.open());
        },
        disposeData: (database) => database.close(),
        progressBuilder: (context, progress) => Text('$progress'),
        errorBuilder: (context, error, stackTrace, progress) => Text('$error'),
        builder: (context, database) => DatabaseView(database: database),
      );
}
```

**Подробнее:** тема [AsyncDataScope](https://pub.dev/documentation/scopo/latest/topics/AsyncDataScope-topic.html).

### AsyncControllerScope

`AsyncDataScope`, значением которого выступает контроллер со своим жизненным
циклом. Скоуп создаёт его, дожидается `init`, велит отпустить внешний мир в
момент ухода с дерева и дожидается `dispose` — на любом пути, включая те два,
на которых написанный руками вариант контроллер теряет: упавший `init` и
`init`, прерванный до завершения. Берите его, когда скоуп существует потому,
что что-то должно **работать**, пока кусок дерева на экране, а не потому, что
что-то должно показываться.

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

final class PlayerController extends ScopeController {
  final Api api;

  StreamSubscription<Track>? _subscription;

  PlayerController({required this.api});

  /// Дожидается до построения готовой ветки. `mounted` говорит, на месте ли
  /// ещё скоуп после `await`.
  @override
  Future<void> init() async {
    final session = await api.openSession();
    if (!mounted) return;

    _subscription = session.tracks.listen(_onTrack);
  }

  /// Синхронно, в момент ухода скоупа с дерева.
  @override
  void onUnmount() => unawaited(_subscription?.cancel());

  /// С ожиданием, после `onUnmount`.
  @override
  Future<void> dispose() async => api.closeSession();
}
```

`AsyncControllerScope<C>` — то же самое с колбэком `createController` вместо
наследования.

**Подробнее:** тема [AsyncControllerScope](https://pub.dev/documentation/scopo/latest/topics/AsyncControllerScope-topic.html).

### LiteScope

`Scope` без контейнера зависимостей: состояние создаётся без асинхронной фазы
зависимостей и всё равно получает полный жизненный цикл скоупа — `initStateAsync`,
`disposeStateAsync`, `notifyDependents`, `close`, `scopeKey` и ожидание дочерних
скоупов. Хорошо подходит для состояния экрана, владеющего объектами, которые
надо освобождать.

```dart
final class ScreenScope extends LiteScope<ScreenScope, ScreenScopeState> {
  const ScreenScope({super.key, super.scopeKey});

  /// Показывается на первых кадрах и пока ждут [scopeKey]. Если вернуть
  /// отсюда `null`, придётся переопределить [buildOnProgress].
  @override
  Widget? buildOnWaiting(BuildContext context) => const SizedBox.shrink();

  @override
  ScreenScopeState createState() => ScreenScopeState();

  static ScreenScopeState of(BuildContext context) =>
      LiteScope.of<ScreenScope, ScreenScopeState>(context);
}

final class ScreenScopeState
    extends LiteScopeState<ScreenScope, ScreenScopeState> {
  final controller = ScrollController();

  /// Его дожидаются до того, как скоуп уйдёт с дерева.
  @override
  Future<void> disposeStateAsync() async => controller.dispose();

  @override
  Widget build(BuildContext context) =>
      ListView(controller: controller, children: const [Text('item')]);
}
```

Все семейства — и это, и полный `Scope` ниже — показаны рядом, с живым
журналом каждого вызова жизненного
цикла, в приложении
[scopo_demo](https://github.com/vi-k/scopo/tree/main/example/scopo_demo).

**Подробнее:** тема [LiteScope](https://pub.dev/documentation/scopo/latest/topics/LiteScope-topic.html).

## Scope: полное семейство

Самое большое из них, и то, из которого урезаны остальные. У него три
части:

1. виджет скоупа (`Scope`) — параметры его конструктора и есть параметры
   скоупа;
2. контейнер зависимостей (`ScopeDependencies`) — инициализируется асинхронно
   до создания состояния;
3. состояние (`ScopeState`) — то же, что `State` у `StatefulWidget`, но с
   прямым доступом к зависимостям.

### 1. Зависимости

Реализуйте `ScopeDependencies` и инициализируйте его генератором потока: именно
это позволяет скоупу сообщать о прогрессе и отменять недоделанную инициализацию,
когда виджет убирают с дерева.

```dart
final class AppDependencies implements ScopeDependencies {
  final SharedPreferences sharedPreferences;

  AppDependencies({required this.sharedPreferences});

  static Stream<ScopeInitState<String, AppDependencies>> init() async* {
    yield ScopeProgress('Initializing storage…');
    final sharedPreferences = await SharedPreferences.getInstance();

    yield ScopeReady(AppDependencies(sharedPreferences: sharedPreferences));
  }

  /// Отпускает то, что не может ждать асинхронного разбора. Выполняется
  /// один раз и всегда до `dispose` — и когда скоуп ушёл с дерева, и когда
  /// его закрыли через `close()`.
  @override
  void onUnmount() {}

  /// Вызывается после того, как состояние утилизировано. Может быть
  /// асинхронным.
  @override
  Future<void> dispose() async {}
}
```

### 2. Состояние

Наследуйтесь от `ScopeState`. К моменту выполнения `initState` зависимости уже
готовы. `notifyDependents` обновляет подписанных потомков, не перестраивая
собственное поддерево состояния.

Половины разведены намеренно, и `setState` здесь ничем не отключён: состояние
скоупа — обычный `State` и сохраняет его. Что звать, следует из того, кто
должен увидеть изменение:

| что должно обновиться | вызов |
| --- | --- |
| потомки, подписанные через `select` / `selectParam` | `notifyDependents()` |
| виджеты, которые возвращает собственный `build` состояния | `setState()` |
| и то и другое | оба |

Стоит назвать ошибку прямо: поменять поле и позвать один `notifyDependents()`
— подписчики увидят новое значение, а собственный `build` состояния не
выполнится, и всё, что он рисует по этому полю, останется прежним.

```dart
final class AppState extends ScopeState<App, AppDependencies, AppState> {
  late int _counter;
  int get counter => _counter;

  @override
  void initState() {
    super.initState();
    _counter = dependencies.sharedPreferences.getInt('counter') ?? 0;
  }

  Future<void> increment() async {
    _counter++;
    notifyDependents();
    await dependencies.sharedPreferences.setInt('counter', _counter);
  }

  @override
  Widget build(BuildContext context) => const HomeScreen();
}
```

### 3. Виджет скоупа

Наследуйтесь от `Scope` и предоставьте `initDependencies`, `createState` и
виджеты для веток инициализации и ошибки. `wrapState` оборачивает только готовую
ветку, поэтому виджеты, общие для всех веток (например, `MaterialApp`), обычно
создают в каждом билдере.

```dart
final class App extends Scope<App, AppDependencies, AppState> {
  final String title;

  const App({super.key, required this.title});

  @override
  Stream<ScopeInitState<String, AppDependencies>> initDependencies(
    BuildContext context,
  ) =>
      AppDependencies.init();

  @override
  AppState createState() => AppState();

  @override
  Widget buildOnProgress(
    BuildContext context,
    covariant String? progress,
  ) =>
      MaterialApp(home: Scaffold(body: Center(child: Text(progress ?? ''))));

  @override
  Widget buildOnError(
    BuildContext context,
    Object error,
    StackTrace stackTrace,
    covariant String? progress,
  ) =>
      MaterialApp(home: Scaffold(body: Center(child: Text('$error'))));

  /// Виджеты между [App] и [AppState] в готовой ветке.
  @override
  Widget wrapState(
    BuildContext context,
    AppDependencies dependencies,
    Widget child,
  ) =>
      MaterialApp(title: title, home: child);

  /// Вспомогательные методы доступа для потомков.
  static AppState of(BuildContext context) =>
      Scope.of<App, AppDependencies, AppState>(context);

  static V select<V>(
    BuildContext context,
    V Function(AppState state) selector,
  ) =>
      Scope.select<App, AppDependencies, AppState, V>(context, selector);

  static V selectParam<V>(
    BuildContext context,
    V Function(App widget) selector,
  ) =>
      Scope.selectParam<App, AppDependencies, AppState, V>(context, selector);
}
```

### 4. Доступ из потомков

`Scope.of` никогда не подписывает — им пользуются, чтобы звать методы. Чтобы
перестраиваться на изменения, подпишитесь на одно значение через `select`
(состояние) или `selectParam` (параметры скоупа). Есть ещё `Scope.paramsOf` и
`Scope.maybeOf`.

```dart
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Подписка на одно значение: перестраивается, только когда меняется
    // `counter`.
    final counter = App.select(context, (state) => state.counter);

    // Подписка на параметр скоупа.
    final title = App.selectParam(context, (widget) => widget.title);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(child: Text('$counter')),
      floatingActionButton: FloatingActionButton(
        // Читает состояние, не подписываясь на него.
        onPressed: () => App.of(context).increment(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
```

**Подробнее:** тема [Scope](https://pub.dev/documentation/scopo/latest/topics/Scope-topic.html).

## Аксессоры: типовые аргументы, один раз

В разделе выше у `App` пять статических обёрток, и каждая заново называет одни
и те же три типа:

```dart
static V select<V>(BuildContext context, V Function(AppState state) selector) =>
    Scope.select<App, AppDependencies, AppState, V>(context, selector);
```

Это пятнадцать строк на скоуп, а скоупов в приложении десятки. Тройку не
вывести — в Dart нет способа прочитать типовые аргументы супертипа на месте
вызова, — так что записать её где-то придётся. Вопрос только в том, сколько раз.

Один:

```dart
final class App extends Scope<App, AppDependencies, AppState> {
  static const access = ScopeAccess<App, AppDependencies, AppState>();
  …
}

// и у потомка:
final counter = App.access.select(context, (state) => state.counter);
final title = App.access.selectParam(context, (widget) => widget.title);
App.access.of(context).increment();
```

Аксессор ничего не хранит и ничего не решает: каждый его метод — статический
метод того же имени с уже подставленными аргументами. Он есть у каждого
семейства и берёт те же типовые аргументы, что и семейство:

| семейство | аксессор |
| --- | --- |
| `ScopeWidgetBase` | `ScopeWidgetAccess<W>` |
| `ScopeModelBase` | `ScopeModelAccess<W, M>` |
| `ScopeNotifierBase` | `ScopeNotifierAccess<W, M>` |
| `AsyncScopeBase` | `AsyncScopeAccess<W>` |
| `AsyncDataScopeBase` | `AsyncDataScopeAccess<W, T>` |
| `AsyncControllerScopeBase` | `AsyncControllerScopeAccess<W, C>` |
| `LiteScope` | `LiteScopeAccess<W, S>` |
| `Scope` | `ScopeAccess<W, D, S>` |

**Чего это стоит**: одного лишнего звена на каждом вызове —
`App.access.select(…)` вместо `App.select(…)`. Больше не меняется ничего, и
статические методы остаются на месте: скоуп, которому нужны аксессоры под
своими именами или только два из пяти, по-прежнему пишет их руками. Аксессор —
самый короткий способ иметь их все, а не единственный способ иметь хоть один.

**Либо пусть обёртки напишет шаблон.** Шаблоны редакторов, которые едут с
пакетом, идут другим путём: их скелеты выписывают все пять статик целиком, так
что потомок читает `App.select(context, …)`, а набирать не пришлось ничего.
Аксессор — когда скоуп пишут руками, шаблон — когда нет.

**Как их поставить.** Они едут вместе с пакетом, то есть уже лежат на вашей
машине. Для VS Code — а также Cursor, Windsurf и Antigravity, у них общий
формат, — скопируйте сниппеты в проект:

```sh
mkdir -p .vscode
cp "$(find ~/.pub-cache/hosted/pub.dev -maxdepth 1 -name 'scopo-*' | sort | tail -1)"/ide/scopo.code-snippets .vscode/
```

Для IntelliJ IDEA и Android Studio кнопки импорта на странице Live Templates
больше нет. Файл кладут в каталог настроек IDE, в подпапку `templates/`, под
именем группы, которую он объявляет: XML объявляет `scopo`, значит файл —
`scopo.xml`. После этого IDE перезапускают:

```sh
# Android Studio на macOS; для IntelliJ IDEA каталог —
# ~/Library/Application Support/JetBrains/<продукт>/
DIR=~/Library/Application\ Support/Google/AndroidStudio<версия>/templates
mkdir -p "$DIR"
cp "$(find ~/.pub-cache/hosted/pub.dev -maxdepth 1 -name 'scopo-*' | sort | tail -1)"/ide/scopo-live-templates.xml "$DIR/scopo.xml"
```

Группа появится в **Settings → Editor → Live Templates**.

Все одиннадцать перечислены в
[`ide/README.md`](https://github.com/vi-k/scopo/blob/main/ide/README.md), а как
шаблоны соотносятся с аксессорами, говорит тема
[base](https://pub.dev/documentation/scopo/latest/topics/base-topic.html).

## scopeKey

`scopeKey` выстраивает в очередь скоупы, которые не должны пересекаться: новый
скоуп с тем же ключом ждёт, пока предыдущий не закончит утилизацию своих
зависимостей. Для этого над пользующимися ключом скоупами нужен
`AsyncScopeCoordinator` — самое универсальное место для него над `MaterialApp`:

```dart
AsyncScopeCoordinator(child: MaterialApp(home: HomeScreen()))
```

Каждый координатор замыкает `scopeKey` на собственное поддерево: два скоупа с
одинаковым ключом под разными координаторами никогда не ждут друг друга, и
обслуживает скоуп всегда ближайший координатор сверху. Очереди принадлежат
элементу координатора, поэтому очерёдность держится ровно столько, сколько живёт
этот элемент: замена самого координатора — другой `ValueKey`, другое место в
дереве — выбрасывает его очереди вместе с ним, и поэтому его место выше всего,
что может быть заменено.

Координатор заодно является корнем ожидания для тех скоупов своего поддерева, у
которых нет скоупа выше, так что
`AsyncScopeCoordinator.waitForChildren(context)` — это способ дождаться таких
скоупов верхнего уровня: например, перед разбором теста или завершением
заставки:

```dart
await AsyncScopeCoordinator.waitForChildren(context);
```

Он дожидается скоупов, зарегистрированных на момент вызова, и, как всякое другое
ожидание в пакете, ограничен — переданным `timeout`, а иначе
`ScopeConfig.defaultWaitForChildrenTimeout`. Истечение не является ошибкой,
которую обязан обработать вызывающий: future завершается нормально, а
`TimeoutException` уходит в `FlutterError.reportError`, если не задан колбэк
`onTimeout`.

## Наблюдение и настройка

Пакет молчит, пока не присвоен `ScopeConfig.observer`. У `ScopeObserver` по
хуку на событие жизненного цикла — `onInit`, `onProgress`, `onReady`,
`onCancelled`, `onDispose`, `onDisposed`, `onError`, `onTimeout`, `onTrace`, —
и все они пустые, так что наследник переопределяет только нужное.
`ScopePrintObserver` едет в комплекте и пишет по строке на событие.

```dart
void main() {
  ScopeConfig.observer = const ScopePrintObserver();

  // Сколько скоуп ждёт свой `scopeKey` и утилизации своих детей (по три
  // секунды по умолчанию; `null` — без ограничения).
  ScopeConfig.defaultScopeKeyTimeout = const Duration(seconds: 5);
  ScopeConfig.defaultWaitForChildrenTimeout = null;

  runApp(const App(title: 'scopo'));
}
```

`ScopeConfig.pauseAfterInitializationEnabled = false` отключает искусственные
задержки `pauseAfterInitialization` — полезно в тестах.

## Тестирование

Тот же наблюдатель, который в приложении печатает, в тесте записывает — и
превращает жизненный цикл в значение, о котором можно писать ожидания.
Сравнивайте список целиком: так ловится и пропавшее событие, и лишнее:

```dart
late RecordingObserver observer;

setUp(() {
  observer = RecordingObserver();
  ScopeConfig.observer = observer;
  ScopeConfig.pauseAfterInitializationEnabled = false;
});

tearDown(() {
  ScopeConfig.observer = null;
  ScopeConfig.reset();
});
```

Три вещи, которые стоит знать до первого теста:

- **`ScopeConfig.reset()` наблюдателя не сбрасывает.** Забытый наблюдатель
  продолжит записывать в список следующего теста — снимайте его явно, как выше.
- **Помечайте тегом скоупы, о которых пишете ожидания.** Скоуп без тега
  подписывается коротким хешем, а он в каждом прогоне свой.
- **Разбор асинхронный, и `pumpAndSettle` его не дожидается.** Он двигает
  фейковые часы; разбор, ожидающий настоящей работы, — как и все четыре
  таймаута, которые нарочно меряются по реальному времени, — на момент конца
  теста ещё идёт. Дожидайтесь нужного события, а не считайте, что кадр всё
  доделал.

**Подробнее:** тема [debug](https://pub.dev/documentation/scopo/latest/topics/debug-topic.html).

## Вложенная навигация

Каждый маршрут в приложении на Flutter обычно строит один `Navigator` наверху, и
стоит он **выше** любого скоупа в дереве — поэтому `Navigator.push`,
`showDialog` и `showModalBottomSheet` строят новый маршрут рядом с экраном,
который его открыл, а не под ним. Всё, что экран поставил над своим содержимым,
в предках этого маршрута не значится, и скоуп не исключение: диалог, открытый
изнутри скоупа, или экран, открытый с него же, прочитать его не может.

[navigation_node](https://pub.dev/packages/navigation_node) — вложенный
`Navigator`, который ставят **под** скоуп вместо этого. `Navigator.push` и
`showModalBottomSheet` уже берут ближайший навигатор по умолчанию, а
`showDialog(useRootNavigator: false)` просит его явно — в обоих случаях маршрут
теперь строится внутри поддерева скоупа, а не рядом с ним: диалог, шторка или
открытый экран из-под узла читают тот же скоуп, что и экран, с которого их
открыли.

Он жил внутри scopo до 0.10.0 включительно; он не зависит ни от чего, кроме
Flutter, — потому и уехал. Добавьте пакет, поправьте один импорт, и пара
работает ровно как работала — вкладка `navigation_node` в
[scopo_demo](https://github.com/vi-k/scopo/tree/main/example/scopo_demo)
открывает один и тот же диалог, шторку и экран из скоупа с узлом и без него,
рядом друг с другом.

## Что ещё в коробке

- `ProgressIterator` — счёт шагов (`1/3`, `2/3`, …) для прогресса
  инициализации.
- `ScreenshotReplacer` — рисует поддерево один раз, затем подменяет его снятым
  изображением; используется, чтобы удержать последний кадр, пока скоуп
  закрывается. Поддерево, которое никогда не рисовалось, снять нельзя, поэтому
  попытки ограничены `ScreenshotReplacer.maxRetries`, после чего поддерево
  всё равно убирают, и на место картинки не встаёт ничего: снимка ждут ровно
  затем, чтобы отпустить то, что это поддерево держит, — оставить его стоять
  значило бы обессмыслить ожидание.

## Примеры

- [minimal](https://github.com/vi-k/scopo/tree/main/example/minimal) — один
  скоуп, асинхронно инициализируемые `SharedPreferences`, экраны загрузки и
  ошибки, счётчик. Минимальный по файлам, а не по строкам: разбирает полный
  `Scope` с комментариями по шагам. Самое маленькое, что работает, — в таблице
  семейств выше.
- [scopo_demo](https://github.com/vi-k/scopo/tree/main/example/scopo_demo) —
  демонстрация каждого семейства скоупов с консолью, показывающей события
  жизненного цикла, плюс вложенные скоупы, `scopeKey`, отложенное закрытие и
  узлы навигации: десять вкладок.

## Документация

- [API reference](https://pub.dev/documentation/scopo/latest/)
- [pub.dev package page](https://pub.dev/packages/scopo)
- [changelog](https://github.com/vi-k/scopo/blob/main/CHANGELOG.md)

По теме на семейство; каждая рассказывает то, чего не может справочник API:
порядок происходящего, разменные решения и ловушки. Ссылки ниже ведут в Topics
справочника по API выше — там всегда последний релиз; те же страницы лежат в
репозитории как `doc/*.md`, и читать их стоит оттуда, если у вас закреплена
другая версия.

| тема | начинать здесь ради |
| --- | --- |
| [base](https://pub.dev/documentation/scopo/latest/topics/base-topic.html) | `of`, `select`, `listen` и того, как скоуп вообще находят |
| [ScopeWidget](https://pub.dev/documentation/scopo/latest/topics/ScopeWidget-topic.html) | пары «виджет — элемент», от которой наследуются все семейства |
| [ScopeModel](https://pub.dev/documentation/scopo/latest/topics/ScopeModel-topic.html) | владения обычным объектом |
| [ScopeNotifier](https://pub.dev/documentation/scopo/latest/topics/ScopeNotifier-topic.html) | владения `Listenable` |
| [AsyncScope](https://pub.dev/documentation/scopo/latest/topics/AsyncScope-topic.html) | асинхронного жизненного цикла, `scopeKey`, координатора |
| [AsyncDataScope](https://pub.dev/documentation/scopo/latest/topics/AsyncDataScope-topic.html) | того же, но с производимым значением |
| [AsyncControllerScope](https://pub.dev/documentation/scopo/latest/topics/AsyncControllerScope-topic.html) | то же, где это значение — контроллер с собственным жизненным циклом |
| [LiteScope](https://pub.dev/documentation/scopo/latest/topics/LiteScope-topic.html) | класса состояния с этим циклом и `close()` |
| [Scope](https://pub.dev/documentation/scopo/latest/topics/Scope-topic.html) | полного семейства: зависимости, состояние, четыре ветки |
| [debug](https://pub.dev/documentation/scopo/latest/topics/debug-topic.html) | наблюдателя, таймаутов и настройки для тестов |
| [utils](https://pub.dev/documentation/scopo/latest/topics/utils-topic.html) | хелперов, которые едут вместе с пакетом |
