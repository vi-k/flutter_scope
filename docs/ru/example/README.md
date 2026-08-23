# example

> Перевод `example/README.md` (blob `f59dd4426173097fcb0d7247ab9b8ed0406ab5d2`).
> Правится в том же коммите, что и оригинал; проверка — `sh docs/ru/check.sh`.

Полный обзор scopo — в
[scopo_demo](https://github.com/vi-k/scopo/tree/main/example/scopo_demo): десять
интерактивных демонстраций, охватывающих все семейства скоупов, вложенные
скоупы, `scopeKey`, отложенное закрытие и узлы навигации.

Отдельно про `NavigationNode` — вложенные навигаторы, диалоги, принадлежащие
экрану, `onPop`, `isRoot` и системный «назад», который можно нажать на
десктопе, — в
[navigation_node](https://github.com/vi-k/scopo/tree/main/example/navigation_node):
шесть уроков с журналом, показывающим, что ответило на каждое нажатие.

Минимальный пример ниже показывает простое приложение-счётчик, в котором
`SharedPreferences` инициализируется асинхронно, до показа интерфейса.
Состояния загрузки и ошибки обрабатываются аккуратно. Полный исходный код на
GitHub: [minimal](https://github.com/vi-k/scopo/tree/main/example/minimal).

```dart
import 'package:flutter/material.dart';
import 'package:scopo/scopo.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  ScopeConfig.observer = const ScopePrintObserver();

  runApp(const App(title: 'scopo minimal demo'));
}

/// Скоуп [App].
///
/// Состоит из трёх частей:
///
/// 1. [App] — главный виджет скоупа. Даёт доступ к собственным параметрам
///    через [App.paramsOf] и [App.selectParam], а к [AppState] — через
///    [App.of] и [App.select].
///
/// 2. [AppDependencies] — контейнер зависимостей с асинхронной
///    инициализацией.
///
/// 3. [AppState] — состояние. То же, что [State] у [StatefulWidget], но с
///    быстрым доступом к зависимостям.
final class App extends Scope<App, AppDependencies, AppState> {
  final String title;

  const App({
    super.key,
    required this.title,
  }) : super(pauseAfterInitialization: const Duration(milliseconds: 500));

  /// Метод инициализации зависимостей.
  @override
  Stream<ScopeInitState<String, AppDependencies>> initDependencies(
    BuildContext context,
  ) =>
      AppDependencies.init(context);

  /// [App.paramsOf] даёт доступ к параметрам виджета [App] — например, к
  /// [title].
  ///
  /// Если [listen] равен `true` (по умолчанию), потребитель подписывается на
  /// изменения.
  ///
  /// На деле подписка срабатывает при каждой пересборке виджета, независимо
  /// от того, менялись ли параметры: [Widget] не даёт механизма их сравнения.
  /// Для более точной подписки берите [App.selectParam].
  static App paramsOf(BuildContext context, {bool listen = true}) =>
      Scope.paramsOf<App, AppDependencies, AppState>(context, listen: listen);

  /// [App.selectParam] даёт доступ к выбранному параметру [App].
  static V selectParam<V>(
    BuildContext context,
    V Function(App widget) selector,
  ) =>
      Scope.selectParam<App, AppDependencies, AppState, V>(context, selector);

  /// [App.of] даёт доступ к [AppState].
  ///
  /// В нашем случае — без подписки на изменения. Чтобы подписаться, берите
  /// [App.select].
  static AppState of(BuildContext context) =>
      Scope.of<App, AppDependencies, AppState>(context);

  /// [App.select] даёт доступ к выбранному параметру [AppState].
  static V select<V>(
    BuildContext context,
    V Function(AppState state) selector,
  ) =>
      Scope.select<App, AppDependencies, AppState, V>(context, selector);

  /// На уровне скоупа [App] приходится создавать [MaterialApp] в каждой из
  /// веток.
  Widget _app({required Widget child}) {
    return MaterialApp(
      title: title,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: child,
    );
  }

  /// Ветка, которая строится во время инициализации скоупа.
  @override
  Widget buildOnProgress(
    BuildContext context,
    covariant String? progress,
  ) =>
      _app(child: SplashScreen(progress: progress));

  /// Ветка, которая строится, когда инициализация упала.
  @override
  Widget buildOnError(
    BuildContext context,
    Object error,
    StackTrace stackTrace,
    covariant String? progress,
  ) =>
      _app(child: ErrorScreen(error: error));

  /// Виджеты, которые окажутся в дереве между [App] и [AppState].
  ///
  /// [wrapState] зовут, только когда скоуп в готовом состоянии.
  @override
  Widget wrapState(
    BuildContext context,
    AppDependencies dependencies,
    Widget child,
  ) =>
      _app(child: child);

  /// [createState] зовут, только когда скоуп в готовом состоянии.
  @override
  AppState createState() => AppState();
}

/// [AppDependencies] — контейнер зависимостей с асинхронной
/// инициализацией.
final class AppDependencies implements ScopeDependencies {
  final SharedPreferences sharedPreferences;

  const AppDependencies({required this.sharedPreferences});

  /// Инициализация зависимостей сделана через генератор потока. Это
  /// позволяет следить за её прогрессом и отменить её, если виджет уйдёт с
  /// дерева раньше, чем она закончится.
  static Stream<ScopeInitState<String, AppDependencies>> init(
    BuildContext context,
  ) async* {
    SharedPreferences? sharedPreferences;

    yield ScopeProgress('init $SharedPreferences');
    sharedPreferences = await SharedPreferences.getInstance();

    yield ScopeReady(AppDependencies(sharedPreferences: sharedPreferences));
  }

  @override
  void onUnmount() {}

  @override
  Future<void> dispose() async {}
}

/// Состояние скоупа, то же самое, что [State] у [StatefulWidget].
///
/// [params] — быстрый доступ к параметрам скоупа (параметрам виджета [App]).
///
/// [dependencies] — быстрый доступ к зависимостям скоупа ([AppDependencies]).
///
/// [notifyDependents] — уведомляет и обновляет подписчиков (зависимых) без
/// [setState], то есть не перестраивая ни себя, ни своё поддерево (не вызывая
/// собственный [build]). Перестроятся только те подписчики, кто подписан на
/// изменившееся.
final class AppState extends ScopeState<App, AppDependencies, AppState> {
  late int _counter;
  int get counter => _counter;

  @override
  void initState() {
    super.initState();
    _counter = dependencies.sharedPreferences.getInt('counter') ?? 0;
  }

  /// Увеличивает счётчик и уведомляет подписчиков (зависимых).
  Future<void> increment() async {
    _counter++;
    notifyDependents();
    await dependencies.sharedPreferences.setInt('counter', _counter);
  }

  @override
  Widget build(BuildContext context) {
    return const HomeScreen();
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key, required this.progress});

  final String? progress;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Text(progress ?? '')));
  }
}

class ErrorScreen extends StatelessWidget {
  const ErrorScreen({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.error,
      body: Center(
        child: Text(
          '$error',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onError,
              ),
        ),
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Подписка на изменения заголовка.
    final title = App.selectParam(context, (state) => state.title);

    // Подписка на изменения счётчика.
    final counter = App.select(context, (state) => state.counter);

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
      ),
      body: Center(
        child: Text(
          '$counter',
          style: Theme.of(context).textTheme.displayLarge,
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Достаём [AppState] и зовём [AppState.increment].
          App.of(context).increment();
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
```
