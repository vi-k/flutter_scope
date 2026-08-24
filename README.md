# scopo

[![pub version](https://img.shields.io/pub/v/scopo)](https://pub.dev/packages/scopo)
[![license](https://img.shields.io/github/license/vi-k/scopo)](https://github.com/vi-k/scopo/blob/main/LICENSE)

A Flutter package for managing scopes: dependency injection, state, and
lifecycle inside the widget tree. A scope owns its dependencies, initializes
them asynchronously, provides them to its subtree, and disposes of them in
order — after its child scopes are gone.

## Why another one

`provider`, `riverpod` and `get_it` answer one question: how a value reaches
the widget that needs it. scopo answers a different one — **how a value is
owned over time**: when it is built, what the screen shows while it is being
built, what happens if the widget leaves before it is ready, and in what order
things are let go on the way out.

That is worth a package only when the objects have a lifecycle of their own — a
database, a socket, a player, a signed-in session. What scopo adds:

- **initialization is a `Stream`**, so a scope has a loading branch, a progress
  value and an error branch without a state machine of your own;
- **an unfinished initialization is cancelled**, and whatever it already took is
  given back; the widget leaving the tree is enough to start that;
- **disposal is ordered** — a scope waits for its child scopes before releasing
  its own dependencies, so nothing is released while something below still holds
  it;
- **`scopeKey` serialises two scopes over one resource**: a re-created scope
  waits for the previous holder of the same key to finish letting go;
- **`close()` keeps the last frame on screen** while an asynchronous teardown
  runs, instead of tearing the subtree away mid-flight;
- **every step is observable** through a typed observer — the failures included.

Riverpod covers part of this: `FutureProvider` and `AsyncValue` give the loading
and error branches, and `ref.onDispose` releases what a provider took. What it
does not give is *waiting* — `onDispose` is a synchronous callback, so "release
the database only once every scope that used it has finished letting go" has
nowhere to go. Disposal there follows the provider graph and its listeners; here
it follows the widget tree.

**When not to take scopo.** If your dependencies are built synchronously and
released by a single `dispose()`, everything above costs you something and buys
you nothing: `provider` is smaller, better known, and enough.

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
  scope's own subtree. `setState` is the other half and is untouched: it
  rebuilds the state's own subtree and reaches no subscriber.
- **Graceful closing**: `close()` freezes the subtree as a screenshot and shows
  `buildOnClosing` while the asynchronous disposal is running.
- **Nine families**: from a widget that only passes its own parameters down to
  a full scope with a dependency container — take the smallest that fits.
- **Observable lifecycle**: a typed observer is told about every
  initialization, progress step, failure and teardown.

## Installation

```sh
flutter pub add scopo
```

```dart
import 'package:scopo/scopo.dart';
```

## The families

Eight of them, and the right one is the smallest that fits. They are listed here
from the smallest up — the same order the topics are in — and the largest,
`Scope`, gets a section of its own below.

| what you own | take |
| --- | --- |
| nothing but the widget's own parameters | `ScopeWidgetBase` |
| a plain object with a `dispose()` | `ScopeModel` |
| a `Listenable` — `ChangeNotifier`, `ValueNotifier`, … | `ScopeNotifier` |
| objects that already exist, but whose lifecycle the tree has to drive | `AsyncScope` |
| a value built asynchronously | `AsyncDataScope` |
| …and that value is a controller with an `init` and a `dispose` of its own | `AsyncControllerScope` |
| a state object with the full asynchronous lifecycle and `close()` | `LiteScope` |
| a container of dependencies **and** a state on top of it | `Scope` |

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

**In depth:** the topic [ScopeWidget](https://pub.dev/documentation/scopo/latest/topics/ScopeWidget-topic.html).

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

**In depth:** the topic [ScopeModel](https://pub.dev/documentation/scopo/latest/topics/ScopeModel-topic.html).

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

**In depth:** the topic [ScopeNotifier](https://pub.dev/documentation/scopo/latest/topics/ScopeNotifier-topic.html).

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

**In depth:** the topic [AsyncScope](https://pub.dev/documentation/scopo/latest/topics/AsyncScope-topic.html).

### AsyncDataScope

`AsyncScope` plus one value: the data produced by `initData` is passed to
`builder` and to `disposeData`. Descendants read it with
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

**In depth:** the topic [AsyncDataScope](https://pub.dev/documentation/scopo/latest/topics/AsyncDataScope-topic.html).

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

`AsyncControllerScope<C>` is the same thing with a `createController` callback
instead of a subclass.

**In depth:** the topic [AsyncControllerScope](https://pub.dev/documentation/scopo/latest/topics/AsyncControllerScope-topic.html).

### LiteScope

`Scope` without the dependency container: the state is created without an async
dependency phase, and still gets the full scope lifecycle — `initStateAsync`,
`disposeStateAsync`, `notifyDependents`, `close`, `scopeKey`, and waiting for child
scopes. A good fit for per-screen state that owns disposable objects.

```dart
final class ScreenScope extends LiteScope<ScreenScope, ScreenScopeState> {
  const ScreenScope({super.key, super.scopeKey});

  /// Shown on the first frames, and while waiting for [scopeKey]. Returning
  /// `null` here requires overriding [buildOnProgress].
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
  Future<void> disposeStateAsync() async => controller.dispose();

  @override
  Widget build(BuildContext context) =>
      ListView(controller: controller, children: const [Text('item')]);
}
```

Every family, this one and the full `Scope` below, is demonstrated side by
side with a live log of each lifecycle call in the
[scopo_demo](https://github.com/vi-k/scopo/tree/main/example/scopo_demo) app.

**In depth:** the topic [LiteScope](https://pub.dev/documentation/scopo/latest/topics/LiteScope-topic.html).

## Scope: the full family

The largest of them, and the one the others are cut down from. It has three
parts:

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

The two halves are separate on purpose, and nothing here disables `setState` —
a scope state is an ordinary `State` and keeps it. Which one to call follows
from who has to see the change:

| what has to update | call |
| --- | --- |
| descendants subscribed with `select` / `selectParam` | `notifyDependents()` |
| the widgets the state's own `build` returns | `setState()` |
| both | both |

Bumping a field and calling `notifyDependents()` alone is the mistake worth
naming: the subscribers see the new value and the state's own `build` does not
run, so anything it draws from that field stays as it was.

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

**In depth:** the topic [Scope](https://pub.dev/documentation/scopo/latest/topics/Scope-topic.html).

## Accessors: the type arguments, once

The section above gives `App` five static wrappers, and every one of them names
the same three types again:

```dart
static V select<V>(BuildContext context, V Function(AppState state) selector) =>
    Scope.select<App, AppDependencies, AppState, V>(context, selector);
```

That is fifteen lines per scope, and a scope is something an application has
dozens of. The triple cannot be inferred — Dart has no way to read the type
arguments of a supertype at the call site — so it has to be written down
somewhere. The only question is how many times.

Once:

```dart
final class App extends Scope<App, AppDependencies, AppState> {
  static const access = ScopeAccess<App, AppDependencies, AppState>();
  …
}

// and from a descendant:
final counter = App.access.select(context, (state) => state.counter);
final title = App.access.selectParam(context, (widget) => widget.title);
App.access.of(context).increment();
```

The accessor holds nothing and decides nothing: each of its methods is the
static of the same name with the arguments already filled in. Every family has
one, and takes the type arguments that family takes:

| family | accessor |
| --- | --- |
| `ScopeWidgetBase` | `ScopeWidgetAccess<W>` |
| `ScopeModelBase` | `ScopeModelAccess<W, M>` |
| `ScopeNotifierBase` | `ScopeNotifierAccess<W, M>` |
| `AsyncScopeBase` | `AsyncScopeAccess<W>` |
| `AsyncDataScopeBase` | `AsyncDataScopeAccess<W, T>` |
| `AsyncControllerScopeBase` | `AsyncControllerScopeAccess<W, C>` |
| `LiteScope` | `LiteScopeAccess<W, S>` |
| `Scope` | `ScopeAccess<W, D, S>` |

**What it costs**: one more step at every call site — `App.access.select(…)`
rather than `App.select(…)`. Nothing else changes, and the statics stay exactly
where they were: a scope that wants its accessors under names of its own, or
one that exposes only two of the five, still writes them by hand. The accessor
is the shortest way to have all of them, not the only way to have any.

**Or let a template write the wrappers.** The editor templates that ship with
the package take the other route: their skeletons write the five statics out in
full, so a descendant reads `App.select(context, …)` and nothing had to be
typed. Use the accessor when you write the scope by hand, a template when you
do not.

**Installing them.** They ship with the package, so they are already on the
machine. For VS Code — and Cursor, Windsurf and Antigravity, which share the
format — copy the snippets into the project:

```sh
mkdir -p .vscode
cp "$(find ~/.pub-cache/hosted/pub.dev -maxdepth 1 -name 'scopo-*' | sort | tail -1)"/ide/scopo.code-snippets .vscode/
```

For IntelliJ IDEA and Android Studio there is no import button on the Live
Templates page any more. The file goes into the configuration directory of the
IDE, under `templates/`, named after the group it declares — the XML says
`scopo`, so the file is `scopo.xml` — and the IDE is restarted:

```sh
# Android Studio on macOS; for IntelliJ IDEA the directory is
# ~/Library/Application Support/JetBrains/<product>/
DIR=~/Library/Application\ Support/Google/AndroidStudio<version>/templates
mkdir -p "$DIR"
cp "$(find ~/.pub-cache/hosted/pub.dev -maxdepth 1 -name 'scopo-*' | sort | tail -1)"/ide/scopo-live-templates.xml "$DIR/scopo.xml"
```

The group then appears under **Settings → Editor → Live Templates**.

All eleven are listed in
[`ide/README.md`](https://github.com/vi-k/scopo/blob/main/ide/README.md), and
the topic
[base](https://pub.dev/documentation/scopo/latest/topics/base-topic.html) says
how templates and accessors relate.

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

## Observing and configuration

The package says nothing until `ScopeConfig.observer` is assigned. A
`ScopeObserver` has one hook per lifecycle event — `onInit`, `onProgress`,
`onReady`, `onCancelled`, `onDispose`, `onDisposed`, `onError`, `onTimeout`,
`onTrace` — all of them empty, so a subclass overrides only what it needs.
`ScopePrintObserver` comes with the package and writes a line per event.

```dart
void main() {
  ScopeConfig.observer = const ScopePrintObserver();

  // How long a scope waits for its `scopeKey` and for its children to be
  // disposed of (3 seconds each by default; `null` means no timeout).
  ScopeConfig.defaultScopeKeyTimeout = const Duration(seconds: 5);
  ScopeConfig.defaultWaitForChildrenTimeout = null;

  runApp(const App(title: 'scopo'));
}
```

`ScopeConfig.pauseAfterInitializationEnabled = false` disables the artificial
`pauseAfterInitialization` delays — useful in tests.

## Testing

The same observer that prints in an app records in a test, which turns the
lifecycle into a value to assert on — compare the whole list at once and a
missing event is caught along with one too many:

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

Three things worth knowing before the first test:

- **`ScopeConfig.reset()` does not clear the observer.** One left behind goes on
  recording into the next test's list, so clear it explicitly, as above.
- **Tag the scopes you assert on.** An untagged scope labels itself with a short
  hash that differs on every run.
- **The teardown is asynchronous, and `pumpAndSettle` does not wait it out.** It
  moves the fake clock; a disposal that awaits real work — or one of the four
  timeouts, which are measured on real time on purpose — is still running when
  the test ends. Wait for the event you care about instead of assuming the
  frame settled it.

**In depth:** the topic [debug](https://pub.dev/documentation/scopo/latest/topics/debug-topic.html).

## Also in the box

- `ProgressIterator` — step counting (`1/3`, `2/3`, …) for initialization
  progress.
- `ScreenshotReplacer` — renders a subtree once, then replaces it with the
  captured image; used to keep the last frame while a scope is closing. A
  subtree that is never painted cannot be captured, so the attempt is bounded
  by `ScreenshotReplacer.maxRetries`, after which the subtree is taken away
  with nothing in the picture's place — waiting for the screenshot is how the
  scope waits to let go of what that subtree holds, so leaving it standing
  would defeat the wait.

**Nested navigation moved out.** `NavigationNode` shipped here up to 0.10.0 and
is now the [navigation_node](https://pub.dev/packages/navigation_node) package
— a nested `Navigator` that keeps dialogs, bottom sheets and pushed screens
under the scope that opened them. It depends on nothing but Flutter, which is
why it left; the pair works exactly as it did. Add the package and change one
import.

## Examples

- [minimal](https://github.com/vi-k/scopo/tree/main/example/minimal) — one
  scope, `SharedPreferences` initialized asynchronously, loading and error
  screens, a counter. Minimal in files rather than in lines: it walks through
  the full `Scope`, commented step by step. For the smallest thing that works,
  see the table of families above.
- [scopo_demo](https://github.com/vi-k/scopo/tree/main/example/scopo_demo) — a
  demo of every scope family with a console showing the lifecycle events, plus
  nested scopes, `scopeKey`, deferred closing, and navigation nodes: ten tabs.

## Documentation

- [API reference](https://pub.dev/documentation/scopo/latest/)
- [pub.dev package page](https://pub.dev/packages/scopo)
- [changelog](https://github.com/vi-k/scopo/blob/main/CHANGELOG.md)

One topic per family, each covering what the API reference cannot: the order
things happen in, the trade-offs, and the traps. The links below go to the
Topics of the API reference above, which always show the latest release; the
same pages live in the repository as `doc/*.md`, which is where to read them
alongside the source of a version you have pinned.

| topic | start here for |
| --- | --- |
| [base](https://pub.dev/documentation/scopo/latest/topics/base-topic.html) | `of`, `select`, `listen`, and how a scope is found at all |
| [ScopeWidget](https://pub.dev/documentation/scopo/latest/topics/ScopeWidget-topic.html) | the widget/element pair every family extends |
| [ScopeModel](https://pub.dev/documentation/scopo/latest/topics/ScopeModel-topic.html) | owning a plain object |
| [ScopeNotifier](https://pub.dev/documentation/scopo/latest/topics/ScopeNotifier-topic.html) | owning a `Listenable` |
| [AsyncScope](https://pub.dev/documentation/scopo/latest/topics/AsyncScope-topic.html) | the asynchronous lifecycle, `scopeKey`, the coordinator |
| [AsyncDataScope](https://pub.dev/documentation/scopo/latest/topics/AsyncDataScope-topic.html) | the same, producing a value |
| [AsyncControllerScope](https://pub.dev/documentation/scopo/latest/topics/AsyncControllerScope-topic.html) | the same, where that value is a controller with a lifecycle of its own |
| [LiteScope](https://pub.dev/documentation/scopo/latest/topics/LiteScope-topic.html) | a state class with that lifecycle, and `close()` |
| [Scope](https://pub.dev/documentation/scopo/latest/topics/Scope-topic.html) | the full family: dependencies, state, four branches |
| [debug](https://pub.dev/documentation/scopo/latest/topics/debug-topic.html) | the observer, timeouts, and the test setup |
| [utils](https://pub.dev/documentation/scopo/latest/topics/utils-topic.html) | the helpers that come with the package |
