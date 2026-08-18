# scopo

> Перевод `README.md` (blob `05842a5b3f2f9da299674342a128f0651b597cd1`).
> Правится в том же коммите, что и оригинал; проверка — `sh docs/ru/check.sh`.

[![pub version](https://img.shields.io/pub/v/scopo)](https://pub.dev/packages/scopo)
[![license](https://img.shields.io/github/license/vi-k/scopo)](https://github.com/vi-k/scopo/blob/main/LICENSE)

Flutter-пакет для управления скоупами: внедрение зависимостей, состояние и
жизненный цикл внутри дерева виджетов. Скоуп владеет своими зависимостями,
инициализирует их асинхронно, отдаёт их своему поддереву и утилизирует по
порядку — после того, как исчезнут его дочерние скоупы.

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
  никогда — собственное поддерево скоупа.
- **Аккуратное закрытие**: `close()` замораживает поддерево снимком и показывает
  `buildOnClosing`, пока идёт асинхронная утилизация.
- **Специализированные скоупы**: облегчённые варианты для параметров виджета,
  обычных моделей, `Listenable` и для асинхронной работы, которой не нужен
  контейнер зависимостей.
- **Журнал**: встроенный уровневый логгер со сменными форматированием и выводом.

## Установка

```sh
flutter pub add scopo
```

```dart
import 'package:scopo/scopo.dart';
```

## Scope

`Scope` — основной строительный блок. У него три части:

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
  Widget buildOnInitializing(
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

**Подробнее:** тема [Scope](https://github.com/vi-k/scopo/blob/main/doc/full_scope.md).

## Специализированные скоупы

Облегчённые варианты для случаев, когда полный `Scope` — это слишком.

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

**Подробнее:** тема [ScopeWidget](https://github.com/vi-k/scopo/blob/main/doc/scope_widget.md).

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

**Подробнее:** тема [ScopeModel](https://github.com/vi-k/scopo/blob/main/doc/scope_model.md).

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

**Подробнее:** тема [ScopeNotifier](https://github.com/vi-k/scopo/blob/main/doc/scope_notifier.md).

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
        init: (context) async* {
          yield AsyncScopeProgress('connecting');
          await connection.open();

          yield AsyncScopeReady();
        },
        dispose: () => connection.close(),
        initBuilder: (context, progress) => Text('$progress'),
        errorBuilder: (context, error, stackTrace, progress) => Text('$error'),
        builder: (context) => const HomeScreen(),
      );
}
```

**Подробнее:** тема [AsyncScope](https://github.com/vi-k/scopo/blob/main/doc/async_scope.md).

### AsyncDataScope

`AsyncScope` плюс одно значение: данные, полученные в `init`, передаются в
`builder` и в `dispose`. Потомки читают их через
`AsyncDataScope.of<Database>(context, listen: false).data`.

```dart
class DatabaseGate extends StatelessWidget {
  const DatabaseGate({super.key});

  @override
  Widget build(BuildContext context) => AsyncDataScope<Database>(
        init: (context) async* {
          yield AsyncDataScopeProgress('opening the database');

          yield AsyncDataScopeReady(await Database.open());
        },
        dispose: (database) => database.close(),
        initBuilder: (context, progress) => Text('$progress'),
        errorBuilder: (context, error, stackTrace, progress) => Text('$error'),
        builder: (context, database) => DatabaseView(database: database),
      );
}
```

**Подробнее:** тема [AsyncDataScope](https://github.com/vi-k/scopo/blob/main/doc/async_data_scope.md).

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
  Widget buildOnInitializing(BuildContext context) => const SizedBox.shrink();

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

`AsyncControllerScope<C>` — то же самое с колбэком `create` вместо наследования.

**Подробнее:** тема [AsyncControllerScope](https://github.com/vi-k/scopo/blob/main/doc/async_controller_scope.md).

### LiteScope

`Scope` без контейнера зависимостей: состояние создаётся без асинхронной фазы
зависимостей и всё равно получает полный жизненный цикл скоупа — `initAsync`,
`disposeAsync`, `notifyDependents`, `close`, `scopeKey` и ожидание дочерних
скоупов. Хорошо подходит для состояния экрана, владеющего объектами, которые
надо освобождать.

```dart
final class ScreenScope extends LiteScope<ScreenScope, ScreenScopeState> {
  const ScreenScope({super.key, super.scopeKey});

  /// Показывается на первых кадрах и пока ждут [scopeKey]. Если вернуть
  /// отсюда `null`, придётся переопределить [buildOnInitializing].
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
  Future<void> disposeAsync() async => controller.dispose();

  @override
  Widget build(BuildContext context) =>
      ListView(controller: controller, children: const [Text('item')]);
}
```

Все семейства выше показаны рядом, с живым журналом каждого вызова жизненного
цикла, в приложении
[scopo_demo](https://github.com/vi-k/scopo/tree/main/example/scopo_demo).

**Подробнее:** тема [LiteScope](https://github.com/vi-k/scopo/blob/main/doc/lite_scope.md).

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

## Журнал и настройка

Журнал по умолчанию выключен. Уровни — `verbose`, `debug`, `info`, `error`, и у
каждого уровня свой публикатор, поэтому форматирование и вывод можно заменять
поуровнево.

```dart
void main() {
  ScopeConfig.logger.level = ScopeLogLevel.info;

  ScopeConfig.logger[ScopeLogLevel.debug].publisher = ScopeLogFormatter(
    format: ScopeLogger.defaultFormat,
    output: debugPrint,
  );

  // Сколько скоуп ждёт свой `scopeKey` и утилизации своих детей (по три
  // секунды по умолчанию; `null` — без ограничения).
  ScopeConfig.defaultScopeKeyTimeout = const Duration(seconds: 5);
  ScopeConfig.defaultWaitForChildrenTimeout = null;

  runApp(const App(title: 'scopo'));
}
```

`ScopeConfig.pauseAfterInitializationEnabled = false` отключает искусственные
задержки `pauseAfterInitialization` — полезно в тестах.

## Что ещё в коробке

- `NavigationNode` — вложенный `Navigator`, который удерживает диалоги, шторки и
  открытые экраны внутри текущего скоупа.
- `ProgressIterator` — счёт шагов (`1/3`, `2/3`, …) для прогресса
  инициализации.
- `ScreenshotReplacer` — рисует поддерево один раз, затем подменяет его снятым
  изображением; используется, чтобы удержать последний кадр, пока скоуп
  закрывается. Поддерево, которое никогда не рисовалось, снять нельзя, поэтому
  попытки ограничены `ScreenshotReplacer.maxRetries`, после чего
  `buildOnClosing` рисуется поверх живого поддерева.

## Примеры

- [minimal](https://github.com/vi-k/scopo/tree/main/example/minimal) — один
  скоуп, асинхронно инициализируемые `SharedPreferences`, экраны загрузки и
  ошибки, счётчик.
- [scopo_demo](https://github.com/vi-k/scopo/tree/main/example/scopo_demo) —
  демонстрация каждого семейства скоупов с консолью, показывающей события
  жизненного цикла, плюс вложенные скоупы, `scopeKey`, отложенное закрытие и
  узлы навигации: десять вкладок.
- [navigation_node](https://github.com/vi-k/scopo/tree/main/example/navigation_node)
  — `NavigationNode` сам по себе, шестью уроками: вложенные навигаторы, диалоги,
  принадлежащие экрану, `onPop`, `isRoot` и системный «назад», который можно
  нажать на десктопе, с журналом, показывающим, что ответило на каждое нажатие.

## Документация

- [API reference](https://pub.dev/documentation/scopo/latest/)
- [pub.dev package page](https://pub.dev/packages/scopo)
- [changelog](https://github.com/vi-k/scopo/blob/main/CHANGELOG.md)

По теме на семейство; каждая рассказывает то, чего не может справочник API:
порядок происходящего, разменные решения и ловушки. Ссылки ниже ведут в
репозиторий, где эти страницы лежат как `doc/*.md`; те же страницы отрисованы
на pub.dev как Topics — внутри справочника по API выше.

| тема | начинать здесь ради |
| --- | --- |
| [base](https://github.com/vi-k/scopo/blob/main/doc/base.md) | `of`, `select`, `listen` и того, как скоуп вообще находят |
| [ScopeWidget](https://github.com/vi-k/scopo/blob/main/doc/scope_widget.md) | пары «виджет — элемент», от которой наследуются все семейства |
| [ScopeModel](https://github.com/vi-k/scopo/blob/main/doc/scope_model.md) | владения обычным объектом |
| [ScopeNotifier](https://github.com/vi-k/scopo/blob/main/doc/scope_notifier.md) | владения `Listenable` |
| [AsyncScope](https://github.com/vi-k/scopo/blob/main/doc/async_scope.md) | асинхронного жизненного цикла, `scopeKey`, координатора |
| [AsyncDataScope](https://github.com/vi-k/scopo/blob/main/doc/async_data_scope.md) | того же, но с производимым значением |
| [AsyncControllerScope](https://github.com/vi-k/scopo/blob/main/doc/async_controller_scope.md) | то же, где это значение — контроллер с собственным жизненным циклом |
| [LiteScope](https://github.com/vi-k/scopo/blob/main/doc/lite_scope.md) | класса состояния с этим циклом и `close()` |
| [Scope](https://github.com/vi-k/scopo/blob/main/doc/full_scope.md) | полного семейства: зависимости, состояние, четыре ветки |
| [debug](https://github.com/vi-k/scopo/blob/main/doc/debug.md) | журнала, таймаутов и настройки для тестов |
| [utils](https://github.com/vi-k/scopo/blob/main/doc/utils.md) | хелперов, которые едут вместе с пакетом |
