For a full tour of scopo, see
[scopo_demo](https://github.com/vi-k/scopo/tree/main/example/scopo_demo) — 9
interactive demos covering every scope family, nested scopes, `scopeKey`,
deferred closing, and navigation nodes.

The minimal example below demonstrates a simple counter app where
`SharedPreferences` is initialized asynchronously before the UI is shown. It
handles loading states and errors gracefully. Full source on GitHub:
[minimal](https://github.com/vi-k/scopo/tree/main/example/minimal).

```dart
import 'dart:io';

import 'package:ansi_escape_codes/ansi_escape_codes.dart' as ansi;
import 'package:flutter/material.dart';
import 'package:scopo/scopo.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  ScopeConfig.logger.level = ScopeLogLevel.info;

  void setLogPrinter(
    int level,
    ansi.Color foreground, {
    ansi.Color? background,
  }) {
    final printer = ansi.Printer(
      ansiCodesEnabled: !Platform.isIOS,
      defaultStyle: ansi.Style(
        foreground: foreground,
        background: background,
      ),
    );

    ScopeConfig.logger[level].publisher = ScopeLogFormatter(
      format: ScopeLogger.defaultFormat,
      output: printer.print,
    );
  }

  setLogPrinter(ScopeLogLevel.verbose, ansi.Color256.gray7);
  setLogPrinter(ScopeLogLevel.debug, ansi.Color256.gray12);
  setLogPrinter(ScopeLogLevel.info, ansi.Color256.rgb345);
  setLogPrinter(ScopeLogLevel.error, ansi.Color256.rgb400);

  runApp(App(title: 'scopo minimal demo'));
}

/// [App] scope.
///
/// Consists of three components:
///
/// 1. [App] - the main widget of scope. Provides access to its own parameters
///    via [App.paramsOf] and [App.selectParam], and to [AppState] via [App.of]
///    and [App.select].
///
/// 2. [AppDependencies] - the container of dependencies with asynchronous
///    initialization.
///
/// 3. [AppState] - the state. Same as [State] in [StatefulWidget], but with
///    fast access to dependencies.
final class App extends Scope<App, AppDependencies, AppState> {
  final String title;

  const App({
    super.key,
    required this.title,
  }) : super(pauseAfterInitialization: const Duration(milliseconds: 500));

  /// Dependencies initialization method.
  @override
  Stream<ScopeInitState<String, AppDependencies>> initDependencies(
    BuildContext context,
  ) =>
      AppDependencies.init(context);

  /// [App.paramsOf] provides access to the [App] widget parameters, such as
  /// [title].
  ///
  /// If [listen] is set to `true` (by default), the consumer subscribes to
  /// changes.
  ///
  /// In reality, the subscription fires every time the widget is rebuilt,
  /// regardless of whether the parameters have changed, because [Widget]
  /// does not provide a mechanism for comparing parameters. For more precise
  /// subscription, use [App.selectParam].
  static App paramsOf(BuildContext context, {bool listen = true}) =>
      Scope.paramsOf<App, AppDependencies, AppState>(context, listen: listen);

  /// [App.selectParam] provides access to the selected parameter of [App].
  static V selectParam<V>(
    BuildContext context,
    V Function(App widget) selector,
  ) =>
      Scope.selectParam<App, AppDependencies, AppState, V>(context, selector);

  /// [App.of] provides access to the [AppState].
  ///
  /// In our case, without subscription to changes. To subscribe to changes,
  /// use [App.select].
  static AppState of(BuildContext context) =>
      Scope.of<App, AppDependencies, AppState>(context);

  /// [App.select] provides access to the selected parameter of [AppState].
  static V select<V>(
    BuildContext context,
    V Function(AppState state) selector,
  ) =>
      Scope.select<App, AppDependencies, AppState, V>(context, selector);

  /// At the [App] scope level, we need to create [MaterialApp] in each of the
  /// branches.
  Widget _app({required Widget child}) {
    return MaterialApp(
      title: title,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: child,
    );
  }

  /// A branch that is created during scope initialization.
  @override
  Widget buildOnInitializing(
    BuildContext context,
    covariant String? progress,
  ) =>
      _app(child: SplashScreen(progress: progress));

  /// A branch that is created when an initialization error occurs.
  @override
  Widget buildOnError(
    BuildContext context,
    Object error,
    StackTrace stackTrace,
    covariant String? progress,
  ) =>
      _app(child: ErrorScreen(error: error));

  /// Widgets that will be placed in the widget-tree between [App] and
  /// [AppState].
  ///
  /// [wrapState] is only called when the scope is in ready state.
  @override
  Widget wrapState(
    BuildContext context,
    AppDependencies dependencies,
    Widget child,
  ) =>
      _app(child: child);

  /// [createState] is only called when the scope is in ready state.
  @override
  AppState createState() => AppState();
}

/// [AppDependencies] is the container of dependencies with asynchronous
/// initialization.
final class AppDependencies implements ScopeDependencies {
  final SharedPreferences sharedPreferences;

  AppDependencies({required this.sharedPreferences});

  /// Dependency initialization is implemented via a stream generator. This
  /// allows us to track the progress of initialization and cancel it when the
  /// widget is removed from the tree before initialization is complete.
  static Stream<ScopeInitState<String, AppDependencies>> init(
    BuildContext context,
  ) async* {
    SharedPreferences? sharedPreferences;

    yield ScopeProgress('init $SharedPreferences');
    sharedPreferences = await SharedPreferences.getInstance();

    yield ScopeReady(AppDependencies(sharedPreferences: sharedPreferences));
  }

  @override
  void unmount() {}

  @override
  Future<void> dispose() async {}
}

/// Scope state, same as [State] in [StatefulWidget].
///
/// [params] - quick access to scope parameters ([App] widget parameters).
///
/// [dependencies] - quick access to scope dependencies ([AppDependencies]).
///
/// [notifyDependents] - notifies and updates subscribers (dependents) without
/// using [setState], i.e. without rebuilding itself and its own subtree
/// (without calling its own [build]). Only those subscribers who have
/// subscribed to the relevant changes will be rebuilded.
final class AppState extends ScopeState<App, AppDependencies, AppState> {
  late int _counter;
  int get counter => _counter;

  @override
  void initState() {
    super.initState();
    _counter = dependencies.sharedPreferences.getInt('counter') ?? 0;
  }

  /// Increases the counter and notifies subscribers (dependents).
  Future<void> increment() async {
    _counter++;
    notifyDependents();
    await dependencies.sharedPreferences.setInt('counter', _counter);
  }

  @override
  Widget build(BuildContext context) {
    return HomeScreen();
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
    // Subscribe to title changes.
    final title = App.selectParam(context, (state) => state.title);

    // Subscribe to counter changes.
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
          // Access [AppState] and call [AppState.increment].
          App.of(context).increment();
        },
        child: Icon(Icons.add),
      ),
    );
  }
}
```
