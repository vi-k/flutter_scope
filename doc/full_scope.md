# Scope

`Scope` is the main building block of the package: a widget that owns a
container of dependencies, initializes it asynchronously, builds a state on top
of it, provides both to its subtree, and finally disposes of everything in
reverse order — after its own child scopes are gone.

One scope is three types:

1. the widget — a `Scope` subclass. Its constructor parameters are the scope
   parameters, and its builders cover the waiting, initializing, error and
   closing branches.
2. the dependency container — a `ScopeDependencies` implementation, built by
   `initDependencies` before the state exists.
3. the state — a `ScopeState` subclass; the same thing as the `State` of a
   `StatefulWidget`, except that `dependencies` is already available in
   `initState`.

The lighter families (`ScopeWidgetBase`, `ScopeModel`, `ScopeNotifier`,
`AsyncScope`, `AsyncDataScope`, `AsyncControllerScope`, `LiteScope`) drop one
part or another. `Scope` is
the full set.

## The initialization branch

`initDependencies` returns a `Stream<ScopeInitState<P, D>>` with two kinds of
events: `ScopeProgress(progress)` any number of times, and `ScopeReady(deps)`
once. A stream rather than a `Future`, for two reasons: it can report progress,
and it can be cancelled — if the widget leaves the tree while the container is
still being built, the subscription is cancelled and a half-built container is
never handed to a state.

What the scope shows, and what it calls, in order:

| Phase                                                     | Builder                                                                       |
| --------------------------------------------------------- | ----------------------------------------------------------------------------- |
| waiting for `scopeKey` and for the first event of the stream | `buildOnWaiting` — may return `null`, then `buildOnInitializing(context, null)` |
| a `ScopeProgress` arrived                                 | `buildOnInitializing(context, progress)`                                      |
| `ScopeReady` arrived                                      | `wrapState` around the `build` of the state from `createState`                 |
| the stream failed                                         | `buildOnError(context, error, stackTrace, progress)`                          |
| `close()` is running                                      | `buildOnClosing`, over a frozen screenshot of the ready subtree when one can be taken |

`wrapState` wraps the ready branch only, so a widget that every branch needs (a
`MaterialApp`, typically) is built inside each builder instead.

`pauseAfterInitialization` holds the ready branch back for a fixed duration
after `ScopeReady`, so that a loading indicator is not replaced within the same
frame it appeared in. `ScopeConfig.pauseAfterInitializationEnabled` turns all of
those pauses off at once — see the `debug` topic.

A container that only needs one `await` can be written by hand:

```dart
final class AppDependencies implements ScopeDependencies {
  final SharedPreferences sharedPreferences;

  AppDependencies({required this.sharedPreferences});

  static Stream<ScopeInitState<String, AppDependencies>> init() async* {
    yield ScopeProgress('Initializing storage…');
    final sharedPreferences = await SharedPreferences.getInstance();

    yield ScopeReady(AppDependencies(sharedPreferences: sharedPreferences));
  }

  /// Lets go of whatever cannot wait for the asynchronous teardown.
  @override
  void onUnmount() {}

  /// Called after the state has been disposed of. May be asynchronous.
  @override
  Future<void> dispose() async {}
}
```

`ScopeDependenciesExtension.asStream` shortens the degenerate case of a
container that needs no asynchronous work at all:
`AppDependencies().asStream<String>()` yields a single
`ScopeReady`.

The three function types the scope is built from are named as well, for anyone
passing them around: `ScopeInitFunction`, `ScopeWaitingBuilder`,
`ScopeInitBuilder` and `ScopeErrorBuilder`.

## ScopeAutoDependencies

Writing the stream by hand stops scaling as soon as the dependencies have an
order, some of them can be built in parallel, and each has its own teardown.
`ScopeAutoDependencies` is the ready-made implementation: describe the tree once
in `buildDependencies`, and its `init` walks the tree, reports progress per
dependency, and disposes of whatever was already built if something fails.

```dart
final class HomeDependencies
    extends ScopeAutoDependencies<HomeDependencies, void> {
  late final ApiClient apiClient;
  late final Settings settings;
  late final Session session;

  @override
  ScopeDependency buildDependencies(_) => sequential('', [
        dep('apiClient', (dep) async {
          apiClient = ApiClient();
          await apiClient.init();
          dep.dispose = apiClient.close;
        }),
        concurrent('user', [
          dep('settings', (dep) async {
            settings = await Settings.load();
            dep.dispose = settings.save;
          }),
          dep('session', (dep) async {
            session = await Session.restore(apiClient);
            dep.dispose = session.close;
          }),
        ]),
      ]);
}
```

Three builders describe the tree, and all of them return a `ScopeDependency`:

- `dep(name, init)` — a single dependency. The `DepHelper` handed to `init` is
  where the reverse operations are registered: `dep.unmount` runs synchronously
  before anything is released, `dep.dispose` is awaited during the disposal.
  Setting neither is fine — a dependency that owns nothing needs no teardown.
  The name must not be empty.
- `sequential(name, [...])` — a `ScopeDependencyGroup` whose children are
  initialized one after another, and disposed of in reverse order.
- `concurrent(name, [...])` — the same, except that the children are
  initialized (and disposed of) in parallel, so progress arrives in completion
  order rather than declaration order.

Groups nest freely and a group name may be empty (see the paths below). The
second type parameter of `ScopeAutoDependencies` is what `buildDependencies`
receives: `void` for the container above, which needs nothing from the outside;
declare `BuildContext` instead when a dependency has to read something from the
tree.

Wiring the container into the scope is one call, and
`ScopeAutoDependenciesStream` is the alias for the resulting stream type:

```dart
@override
ScopeAutoDependenciesStream<HomeDependencies> initDependencies(
  BuildContext context,
) =>
    HomeDependencies().init(null);
```

With a `BuildContext` container, forward the `context` of `initDependencies`
instead of `null`.

Every event of that stream carries a `ScopeAutoDependenciesProgress`: `path` —
the path of the dependency that has just been initialized — `name`, the last
segment of that path, which is the name the dependency was declared with, plus
the step counter of a `ProgressIterator` (`number`, `total`, and `progress` as a
fraction between 0 and 1). That object is what `buildOnInitializing` receives,
so a progress bar with a caption needs nothing else:

```dart
@override
Widget buildOnInitializing(
  BuildContext context,
  covariant ScopeAutoDependenciesProgress? progress,
) =>
    Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        LinearProgressIndicator(value: progress?.progress ?? 0),
        Text(progress?.path ?? ''),
      ],
    );
```

`autoDisposeOnError` (`true` by default) is what makes a failed initialization
clean up after itself: when the tree did not reach the initialized state, the
container's `dispose` runs before the error reaches `buildOnError`. Override it
with `false` to keep the half-built tree for inspection.

For that inspection the container exposes its tree: `root` is the top
`ScopeDependency`, `flattenDependencies()` walks it depth-first into
`ScopeDependencyInfo` records (`level`, `path`, `dependency`), and
`flattenDependenciesWithErrors()` narrows the walk to the entries that hold a
real error rather than a propagated `ScopeDependencyException`. Each dependency
also carries a `ScopeDependencyState` — `ScopeDependencyInitial`,
`ScopeDependencyInitialized`, `ScopeDependencyFailed`,
`ScopeDependencyCancelled`, `ScopeDependencyDisposed`,
`ScopeDependencyNoDisposalRequired`, `ScopeDependencyDisposalFailed`,
`ScopeDependencyDisposalCancelled` — and the `isInitialized`, `isFailed`,
`isCancelled` and `isDisposed` shorthands of `ScopeDependencyExtension`.

## Dependency paths

A dependency is identified by its path from the root of the tree: the names of
the enclosing groups and its own name, joined with `/`. The format is
canonical — there is **no leading slash**, and an anonymous group (a group whose
name is the empty string) contributes no segment and no separator at all. So the
root group of a tree is usually anonymous, and the paths of its children read as
if it were not there.

For the tree

```dart
sequential('', [
  dep('dep1', …),
  concurrent('concurrent1', [
    dep('dep2', …),
    sequential('sequential1', [
      dep('dep3', …),
    ]),
  ]),
])
```

the paths are `dep1`, `concurrent1/dep2` and `concurrent1/sequential1/dep3`.
The same strings appear in four places: in `ScopeAutoDependenciesProgress.path`,
in `ScopeDependencyInfo.path`, in the `debug` log of the initialization and of
the disposal, and in `ScopeDependencyException.name`.

## Errors

An error thrown by a `dep` initializer is wrapped in a
`ScopeDependencyException`, which carries the `name` (the path above), the
original `error` and its `stackTrace`. As the exception travels up through the
enclosing groups, each named group prepends its own segment, so what reaches
`buildOnError` names the exact dependency that failed:

```text
concurrent1/sequential1/dep3: Exception: no network
```

An empty `name` means the anonymous root dependency itself failed.

The group that saw the failure stops requiring initialization and switches to
`ScopeDependencyFailed`; its sibling errors, if a `concurrent` group produced
several, are all kept in the state and reachable through
`flattenDependenciesWithErrors()`. The `stateToString()` of a group summarizes
that: the failed children by name, and any error that is not itself a
`ScopeDependencyException` listed as unresolved.

## Disposal, unmount and close

The teardown of a scope happens in a fixed order, and every asynchronous step of
it is awaited:

1. `onUnmount` — synchronous, always first, and before any asynchronous step
   begins. It runs exactly once, whichever way the scope goes: removed from the
   widget tree, or closed with `close()` while it stays on screen. The scope
   runs `ScopeState.onUnmount` and then forwards to
   `ScopeDependencies.onUnmount`, which `ScopeAutoDependencies` forwards further
   to every `dep.unmount`. This is the place for whatever has to happen
   immediately and cannot wait for the asynchronous teardown — unsubscribing,
   for instance.

   Flutter's own `State.dispose` is not part of this order and cannot be: the
   framework calls it before the whole teardown when the tree takes the scope
   down, and not until the tree comes down after a `close()`. It is sealed on
   `ScopeState` for that reason.
2. An initialization still in flight is cancelled, or awaited if it cannot be
   cancelled. The cancellation is bounded by `initCancellationTimeout`
   (`ScopeConfig.defaultInitCancellationTimeout` by default), so that an
   initialization parked on a future that never completes cannot hold the
   teardown behind it.
3. The child scopes are awaited, so that a parent never disposes of a
   dependency a child is still using. The wait is bounded by
   `waitForChildrenTimeout` (`ScopeConfig.defaultWaitForChildrenTimeout` by
   default).
4. `ScopeState.disposeAsync` — the state's own asynchronous teardown, bounded
   by `disposeAsyncTimeout` (`ScopeConfig.defaultDisposeAsyncTimeout` by
   default), so that a teardown which never completes cannot hold the release
   of the `scopeKey` in step 6.
5. `ScopeDependencies.dispose` — for a `ScopeAutoDependencies`, this walks the
   tree in reverse: the children of a `sequential` group in reverse declaration
   order, the children of a `concurrent` group in parallel, and only those that
   actually registered a `dep.dispose`.
6. The `scopeKey`, if any, is released, and the next scope waiting for it is let
   through.

`close()` starts that same teardown while the scope is still on screen: the
ready subtree is frozen into a screenshot, `buildOnClosing` is shown on top of
it, and the returned future completes when the disposal is done. It is the way
to run "closing…" UI for a scope whose disposal takes a noticeable amount of
time, instead of freezing on the last frame. Taking the screenshot is
best-effort: a subtree that is never painted — one inside an `Offstage`, or in
the unselected branch of an `IndexedStack` — cannot be captured. The attempt is
bounded by `ScreenshotReplacer.maxRetries` frames, after which `close()`
proceeds and `buildOnClosing` runs over the live subtree instead of a frozen
one.

## Access from the subtree

The state is reached through the static helpers of `Scope`, which every scope
normally re-exposes as its own named accessors:

- `Scope.of` and `Scope.maybeOf` — the state, without subscribing. For calling
  methods.
- `Scope.select` — one value derived from the state; the caller is rebuilt only
  when that value changes, and only when the state calls `notifyDependents`.
- `Scope.paramsOf` and `Scope.selectParam` — the same for the scope parameters,
  i.e. the fields of the widget itself.

`notifyDependents` rebuilds the subscribed descendants without rebuilding the
state's own subtree, which is what makes a scope usable for high-frequency
updates. `isInitialized` reports whether the initialization has fully completed,
and `onInitialized` is the hook called right after it has.
