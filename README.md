# scopo

[![pub version](https://img.shields.io/pub/v/scopo)](https://pub.dev/packages/scopo)
[![license](https://img.shields.io/github/license/vi-k/scopo)](https://github.com/vi-k/scopo/blob/main/LICENSE)

A Flutter package for managing scopes: dependency injection, state, and
lifecycle inside the widget tree. A scope owns its dependencies, initializes
them asynchronously, provides them to its subtree, and disposes of them in
order — after its child scopes are gone.

## Features

- **Scopes**: a widget that owns dependencies and a state and provides both to
  its descendants.
- **Async initialization**: initialization is a `Stream`. It reports progress,
  drives the loading and error branches, and is cancelled if the scope leaves
  the tree before it completes.
- **Ordered disposal**: a scope waits for its child scopes to be disposed of
  before disposing of its own dependencies (`waitForChildrenTimeout`), and
  `scopeKey` makes a re-created scope wait for the previous scope with the same
  key.
- **Selective rebuilds**: `select` and `selectParam` subscribe a descendant to a
  single value; `notifyDependents` rebuilds only those descendants, never the
  scope's own subtree.
- **Graceful closing**: `close()` freezes the subtree as a screenshot and shows
  `buildOnClosing` while the asynchronous disposal is running.
- **Specialized scopes**: lightweight variants for widget parameters, plain
  models, `Listenable`s, and for async work that needs no dependency container.
- **Logging**: a built-in level logger with pluggable formatting and output.

## Installation

```sh
flutter pub add scopo
```

```dart
import 'package:scopo/scopo.dart';
```

## Scope

`Scope` is the main building block. It has three parts:

1. the scope widget (`Scope`) — its constructor parameters are the scope
   parameters;
2. a dependency container (`ScopeDependencies`) — initialized asynchronously
   before the state is created;
3. a state (`ScopeState`) — the same as `State` of a `StatefulWidget`, but with
   direct access to the dependencies.

### 1. Dependencies

Implement `ScopeDependencies` and initialize it with a stream generator: this is
what lets the scope report progress and cancel a half-finished initialization
when the widget is removed from the tree.

```dart
final class AppDependencies implements ScopeDependencies {
  final SharedPreferences sharedPreferences;

  AppDependencies({required this.sharedPreferences});

  static Stream<ScopeInitState<String, AppDependencies>> init() async* {
    yield ScopeProgress('Initializing storage…');
    final sharedPreferences = await SharedPreferences.getInstance();

    yield ScopeReady(AppDependencies(sharedPreferences: sharedPreferences));
  }

  /// Lets go of whatever cannot wait for the asynchronous teardown. Runs
  /// once and always before `dispose`, whether the scope left the tree or
  /// was closed with `close()`.
  @override
  void onUnmount() {}

  /// Called after the state has been disposed of. May be asynchronous.
  @override
  Future<void> dispose() async {}
}
```

### 2. State

Extend `ScopeState`. The dependencies are ready by the time `initState` runs.
`notifyDependents` updates the subscribed descendants without rebuilding the
state's own subtree.

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

### 3. The scope widget

Extend `Scope` and provide `initDependencies`, `createState`, and the widgets
for the initializing and error branches. `wrapState` wraps the ready branch
only, so widgets shared by all branches (such as `MaterialApp`) are usually
created in each builder.

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

  /// Widgets placed between [App] and [AppState] in the ready branch.
  @override
  Widget wrapState(
    BuildContext context,
    AppDependencies dependencies,
    Widget child,
  ) =>
      MaterialApp(title: title, home: child);

  /// Access helpers for descendants.
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

### 4. Access from descendants

`Scope.of` never subscribes — use it for calling methods. To rebuild on
changes, subscribe to a single value with `select` (state) or `selectParam`
(scope parameters). `Scope.paramsOf` and `Scope.maybeOf` are available too.

```dart
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Subscribes to a single value: rebuilt only when `counter` changes.
    final counter = App.select(context, (state) => state.counter);

    // Subscribes to a scope parameter.
    final title = App.selectParam(context, (widget) => widget.title);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(child: Text('$counter')),
      floatingActionButton: FloatingActionButton(
        // Reads the state without subscribing to it.
        onPressed: () => App.of(context).increment(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
```

**In depth:** the topic [Scope](https://github.com/vi-k/scopo/blob/main/doc/full_scope.md).

## Specialized scopes

Lightweight alternatives for cases where a full `Scope` is too much.

### ScopeWidgetBase

Provides the widget's own parameters to its subtree. Descendants subscribe per
parameter, so an unrelated parameter change does not rebuild them.

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

**In depth:** the topic [ScopeWidget](https://github.com/vi-k/scopo/blob/main/doc/scope_widget.md).

### ScopeModel

Owns a plain Dart object: `create` builds it, `dispose` releases it. The model
is not observable, so descendants are notified when the `ScopeModel` widget
itself is rebuilt, and a selector then filters out the unchanged values.
Subclass `ScopeModelBase` to get a named scope with its own static accessors.

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
    // Without a subscription:
    final user = ScopeModel.of<UserModel>(context, listen: false);

    // With a subscription to the selected value:
    final name = ScopeModel.select<UserModel, String>(
      context,
      (model) => model.name,
    );

    return Text('$name (${user.name})');
  }
}
```

**In depth:** the topic [ScopeModel](https://github.com/vi-k/scopo/blob/main/doc/scope_model.md).

### ScopeNotifier

The same as `ScopeModel`, but for a `Listenable` (`ChangeNotifier`,
`ValueNotifier`, …): the scope subscribes to the model and rebuilds the
descendants whose selected value has changed. `ScopeNotifierBase` is the
subclassable variant.

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
    // Rebuilt on `notifyListeners`, and only if the selected value changed.
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

**In depth:** the topic [ScopeNotifier](https://github.com/vi-k/scopo/blob/main/doc/scope_notifier.md).

### AsyncScope

Async initialization and disposal without a dependency container: use it when
the objects are already reachable (a singleton, a repository from a parent
scope) and only their lifecycle has to be driven by the tree. Descendants can
read the current state with `AsyncScope.of(context, listen: …).state`.

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

**In depth:** the topic [AsyncScope](https://github.com/vi-k/scopo/blob/main/doc/async_scope.md).

### AsyncDataScope

`AsyncScope` plus one value: the data produced by `init` is passed to `builder`
and to `dispose`. Descendants read it with
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

**In depth:** the topic [AsyncDataScope](https://github.com/vi-k/scopo/blob/main/doc/async_data_scope.md).

### AsyncControllerScope

`AsyncDataScope` whose value is a controller with a lifecycle of its own. The
scope creates it, awaits its `init`, tells it to let go the moment the scope
leaves the tree, and awaits its `dispose` — on every path, including the two
where a hand-written version loses it: an `init` that threw, and an `init`
interrupted before it finished. Reach for it when the scope exists because
something has to *run* while a part of the tree is on screen, rather than
because something has to be shown.

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

  /// Awaited before the ready branch is built. `mounted` says whether the
  /// scope is still there after an `await`.
  @override
  Future<void> init() async {
    final session = await api.openSession();
    if (!mounted) return;

    _subscription = session.tracks.listen(_onTrack);
  }

  /// Synchronous, the moment the scope leaves the tree.
  @override
  void onUnmount() => unawaited(_subscription?.cancel());

  /// Awaited, after `onUnmount`.
  @override
  Future<void> dispose() async => api.closeSession();
}
```

`AsyncControllerScope<C>` is the same thing with a `create` callback instead of
a subclass.

**In depth:** the topic [AsyncControllerScope](https://github.com/vi-k/scopo/blob/main/doc/async_controller_scope.md).

### LiteScope

`Scope` without the dependency container: the state is created without an async
dependency phase, and still gets the full scope lifecycle — `initAsync`,
`disposeAsync`, `notifyDependents`, `close`, `scopeKey`, and waiting for child
scopes. A good fit for per-screen state that owns disposable objects.

```dart
final class ScreenScope extends LiteScope<ScreenScope, ScreenScopeState> {
  const ScreenScope({super.key, super.scopeKey});

  /// Shown on the first frames, and while waiting for [scopeKey]. Returning
  /// `null` here requires overriding [buildOnInitializing].
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

  /// Awaited before the scope leaves the tree.
  @override
  Future<void> disposeAsync() async => controller.dispose();

  @override
  Widget build(BuildContext context) =>
      ListView(controller: controller, children: const [Text('item')]);
}
```

Every family above is demonstrated side by side, with a live log of each
lifecycle call, in the
[scopo_demo](https://github.com/vi-k/scopo/tree/main/example/scopo_demo) app.

**In depth:** the topic [LiteScope](https://github.com/vi-k/scopo/blob/main/doc/lite_scope.md).

## scopeKey

`scopeKey` serializes scopes that must not overlap: a new scope with the same
key waits until the previous one has finished disposing of its dependencies.
It requires an `AsyncScopeCoordinator` above the scopes that use it — the most
universal place is above `MaterialApp`:

```dart
AsyncScopeCoordinator(child: MaterialApp(home: HomeScreen()))
```

Each coordinator scopes `scopeKey` to its own subtree: two scopes with the
same key under different coordinators never wait for one another, and it is
always the nearest coordinator above a scope that serves it. The queues belong
to the coordinator's element, so serialization holds only for as long as that
element does: replacing the coordinator itself — a different `ValueKey`, a
different position in the tree — throws its queues away along with it, which
is why it belongs above everything that can be replaced.

A coordinator is also the wait root for the scopes in its subtree that have no
scope above them, so `AsyncScopeCoordinator.waitForChildren(context)` is the
way to await those top-level scopes — for example before tearing down a test
or finishing a splash screen:

```dart
await AsyncScopeCoordinator.waitForChildren(context);
```

It awaits the scopes registered at the moment of the call, and, like every
other wait in the package, it is bounded — by a `timeout` when one is passed,
by `ScopeConfig.defaultWaitForChildrenTimeout` otherwise. An expiry is not an
error the caller has to handle: the future completes normally and the
`TimeoutException` is reported through `FlutterError.reportError`, unless an
`onTimeout` callback is given.

## Logging and configuration

Logging is off by default. Levels are `verbose`, `debug`, `info`, `error`, and
each level has its own publisher, so formatting and output can be replaced per
level.

```dart
void main() {
  ScopeConfig.logger.level = ScopeLogLevel.info;

  ScopeConfig.logger[ScopeLogLevel.debug].publisher = ScopeLogFormatter(
    format: ScopeLogger.defaultFormat,
    output: debugPrint,
  );

  // How long a scope waits for its `scopeKey` and for its children to be
  // disposed of (3 seconds each by default; `null` means no timeout).
  ScopeConfig.defaultScopeKeyTimeout = const Duration(seconds: 5);
  ScopeConfig.defaultWaitForChildrenTimeout = null;

  runApp(const App(title: 'scopo'));
}
```

`ScopeConfig.pauseAfterInitializationEnabled = false` disables the artificial
`pauseAfterInitialization` delays — useful in tests.

## Also in the box

- `NavigationNode` — a nested `Navigator` that keeps dialogs, bottom sheets and
  pushed screens inside the current scope.
- `ProgressIterator` — step counting (`1/3`, `2/3`, …) for initialization
  progress.
- `ScreenshotReplacer` — renders a subtree once, then replaces it with the
  captured image; used to keep the last frame while a scope is closing. A
  subtree that is never painted cannot be captured, so the attempt is bounded
  by `ScreenshotReplacer.maxRetries`, after which `buildOnClosing` renders over
  the live subtree instead.

## Examples

- [minimal](https://github.com/vi-k/scopo/tree/main/example/minimal) — one
  scope, `SharedPreferences` initialized asynchronously, loading and error
  screens, a counter.
- [scopo_demo](https://github.com/vi-k/scopo/tree/main/example/scopo_demo) — a
  demo of every scope family with a console showing the lifecycle events, plus
  nested scopes, `scopeKey`, deferred closing, and navigation nodes: ten tabs.
- [navigation_node](https://github.com/vi-k/scopo/tree/main/example/navigation_node)
  — `NavigationNode` on its own, in six lessons: nested navigators, dialogs that
  belong to the screen, `onPop`, `isRoot`, and a system back you can press on a
  desktop, with a journal showing what answered each press.

## Documentation

- [API reference](https://pub.dev/documentation/scopo/latest/)
- [pub.dev package page](https://pub.dev/packages/scopo)
- [changelog](https://github.com/vi-k/scopo/blob/main/CHANGELOG.md)

One topic per family, each covering what the API reference cannot: the order
things happen in, the trade-offs, and the traps. The links below go to the
repository, where these pages live as `doc/*.md`; the same pages are rendered
on pub.dev as Topics, inside the API reference above.

| topic | start here for |
| --- | --- |
| [base](https://github.com/vi-k/scopo/blob/main/doc/base.md) | `of`, `select`, `listen`, and how a scope is found at all |
| [ScopeWidget](https://github.com/vi-k/scopo/blob/main/doc/scope_widget.md) | the widget/element pair every family extends |
| [ScopeModel](https://github.com/vi-k/scopo/blob/main/doc/scope_model.md) | owning a plain object |
| [ScopeNotifier](https://github.com/vi-k/scopo/blob/main/doc/scope_notifier.md) | owning a `Listenable` |
| [AsyncScope](https://github.com/vi-k/scopo/blob/main/doc/async_scope.md) | the asynchronous lifecycle, `scopeKey`, the coordinator |
| [AsyncDataScope](https://github.com/vi-k/scopo/blob/main/doc/async_data_scope.md) | the same, producing a value |
| [AsyncControllerScope](https://github.com/vi-k/scopo/blob/main/doc/async_controller_scope.md) | the same, where that value is a controller with a lifecycle of its own |
| [LiteScope](https://github.com/vi-k/scopo/blob/main/doc/lite_scope.md) | a state class with that lifecycle, and `close()` |
| [Scope](https://github.com/vi-k/scopo/blob/main/doc/full_scope.md) | the full family: dependencies, state, four branches |
| [debug](https://github.com/vi-k/scopo/blob/main/doc/debug.md) | logging, timeouts, and the test setup |
| [utils](https://github.com/vi-k/scopo/blob/main/doc/utils.md) | the helpers that come with the package |
