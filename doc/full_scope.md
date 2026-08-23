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
| waiting for `scopeKey` and for the first event of the stream | `buildOnWaiting` — may return `null`, then `buildOnProgress(context, null)` |
| a `ScopeProgress` arrived                                 | `buildOnProgress(context, progress)`                                      |
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
passing them around: `ScopeInitCallback`, `ScopeWaitingBuilder`,
`ScopeProgressBuilder` and `ScopeErrorBuilder`.

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
          dep.dispose = apiClient.close;

          await apiClient.init();
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

- `dep(name, init)` — a single dependency. The `ScopeDependencyHandle` handed to `init` is
  where the reverse operations are registered: `dep.unmount` runs synchronously
  before anything is released, `dep.dispose` is awaited during the disposal.
  Setting neither is fine — a dependency that owns nothing needs no teardown.
  The name must not be empty.
- `sequential(name, [...])` — a `ScopeDependencyGroup` whose children are
  initialized one after another, and torn down in reverse order — both
  `dep.unmount` and `dep.dispose`.
- `concurrent(name, [...])` — the same, except that the children are
  initialized (and disposed of) in parallel, so progress arrives in completion
  order rather than declaration order.

Groups nest freely and a group name may be empty (see the paths below).

The **first** type parameter of `ScopeAutoDependencies` is the class being
declared — `HomeDependencies extends ScopeAutoDependencies<HomeDependencies,
…>`. It is what the container hands the scope once the tree is up, so it is what
`Scope.of` returns to the subtree. Naming another container there is the one
mistake this parameter invites, and it is refused before anything is built: the
type of the container that finishes cannot be the type of a container that never
started.

The **second** is what `buildDependencies` receives: `void` for the container
above, which needs nothing from the outside; declare `BuildContext` instead when
a dependency has to read something from the tree.

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
the step counter of a `ProgressIterator` (`number`, `total`, and `value` as a
fraction between 0 and 1). That object is what `buildOnProgress` receives,
so a progress bar with a caption needs nothing else:

```dart
@override
Widget buildOnProgress(
  BuildContext context,
  covariant ScopeAutoDependenciesProgress? progress,
) =>
    Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        LinearProgressIndicator(value: progress?.value ?? 0),
        Text(progress?.path ?? ''),
      ],
    );
```

`autoDisposeOnError` (`true` by default) is what makes a failed initialization
clean up after itself: when the tree did not reach the initialized state, the
container's `dispose` runs before the error reaches `buildOnError`. Override it
with `false` to keep the half-built tree for inspection.

### Register the teardown the moment you have something to tear down

The disposal releases what a dependency **registered**, not what it finished
with: an initializer that took a resource and set `dep.dispose` keeps that
resource whether it then succeeded, failed or was cancelled. Which puts the
whole weight on where the registration sits.

```dart
// Wrong: the migration throws, nothing is registered, and the database stays
// open with nobody left to close it.
dep('database', (dep) async {
  final database = await Database.open();
  await database.migrate();
  dep.dispose = database.close;
}),
```

```dart
// Right: registered before anything else can fail.
dep('database', (dep) async {
  final database = await Database.open();
  dep.dispose = database.close;

  await database.migrate();
}),
```

The rule reads as one line: **acquire, register, then carry on.** Nothing
between the acquisition and the registration may `await`, throw, or be
cancelled — and in Dart the first of those implies the other two.

`dep.dispose` may be reassigned as the initializer goes, which is what a
dependency that builds several things in sequence does: register a closure that
releases everything taken so far, and widen it after each step. Setting neither
`dep.dispose` nor `dep.unmount` is fine for a dependency that owns nothing —
after the teardown it says `no disposal required`, so a tree dump still shows
that the walk reached it.

### What a failure costs, and what it does not

A failed dependency stops its own group, and the teardown above releases
everything already built — provided each leaf registered what it took. Where the
walk stops is worth knowing:

- **A sequential group** stops at the first failure; the children before it are
  released in reverse order.
- **A concurrent group** cancels the arms still running when one of them fails.
  A cancelled arm is resumed only as far as its next suspension point, so it may
  stop mid-way — and this is the second reason to register early: whatever it
  had already registered is still released, whatever it had not is not.
- **The disposal itself does not stop at a failure.** Each release is guarded on
  its own, the walk finishes, and the first failure is passed on afterwards.
  Every failure is recorded on the dependency it belongs to and readable through
  `flattenDependenciesWithErrors()`.

And with `autoDisposeOnError` set to `false`, releasing the half-built tree is
yours to do.

### A hand-written container cleans up after itself

`ScopeAutoDependencies` is what runs the teardown of a failed initialization.
A container written by hand has no such thing behind it: the scope stores the
container when the stream yields `ScopeReady`, and a stream that failed before
that never handed one over. Nothing the scope holds points at it, and its
`dispose()` is never called.

So an `init` written by hand takes the same shape as the one in the `AsyncScope`
topic — what a step took is given back unless the container was handed over:

```dart
static Stream<ScopeInitState<String, AppDependencies>> init() async* {
  final storage = await Storage.open();
  var handedOver = false;

  try {
    yield ScopeProgress('signing in');
    final session = await Session.restore(storage);

    yield ScopeReady(AppDependencies(storage: storage, session: session));
    handedOver = true;
  } finally {
    if (!handedOver) {
      await storage.close();
    }
  }
}
```

`finally`, and not `catch`: a cancellation is the other way this ends early —
the scope removed from the tree before it was ready — and it raises nothing, so
a `catch` is never reached. The `AsyncScope` topic has the whole of it. This is
also the shape the container writes for you: what a dependency registered with
`dep.dispose` is released whether the walk failed or was cancelled.

## Inspecting the tree

Whatever the outcome, the container exposes what it built: `root` is the top
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

`ScopeDependencyNoDisposalRequired` is the state of a dependency that set no
`dep.dispose` and so had nothing to give back: the teardown passes it by, and
this is what it says afterwards. It is a `ScopeDependencyDisposed`, so
`isDisposed` covers both.

`ScopeDependencyDisposalCancelled` is the one state a scope never produces on its
own — nothing in the package cancels a teardown walk halfway. It belongs to
whoever drives one: `dispose()` is a stream, and a caller who listens to it
and cancels the subscription before it is done leaves the dependencies it had not
reached still initialized, and the one it stopped on saying `disposal cancelled`.
Reading it therefore means reading about a teardown of your own.

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
The same strings appear in three places: in `ScopeAutoDependenciesProgress.path`,
in what the container reports to `ScopeConfig.observer` while it initializes and
while it disposes, and in `ScopeDependencyException.name`.

`ScopeDependencyInfo.path` is the one that is not the whole path but the prefix
of it. The walk it comes from visits the groups as well as the leaves, so each
entry carries the path of the groups *around* it — ending with `/`, and empty at
the root — while its own name sits beside it in `dependency.name`. The canonical
path of an entry is therefore `'${info.path}${info.dependency.name}'`.

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
`ScopeDependencyFailed`, keeping the failure it saw — one of them, even when a
`concurrent` group had several children fail in the same instant: the stream a
group runs its children in is guarded, and a guarded stream closes on the first
error. Every dependency keeps its own errors, and
`flattenDependenciesWithErrors()` walks the tree for them. The `stateToString()`
of a group summarizes what it holds: the failed child by name, and any error that
is not itself a `ScopeDependencyException` listed as unresolved.

## Disposal, unmount and close

The teardown of a scope happens in a fixed order, and every asynchronous step of
it is awaited:

1. `onUnmount` — synchronous, always first, and before any asynchronous step
   begins. It runs exactly once, whichever way the scope goes: removed from the
   widget tree, or closed with `close()` while it stays on screen. The scope
   runs `ScopeState.onUnmount` and then forwards to
   `ScopeDependencies.onUnmount`, which `ScopeAutoDependencies` forwards further
   to every `dep.unmount`, in reverse declaration order. This is the place for
   whatever has to happen immediately and cannot wait for the asynchronous
   teardown — unsubscribing, for instance.

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
4. `ScopeState.disposeStateAsync` — the state's own asynchronous teardown, bounded
   by `disposeScopeTimeout` (`ScopeConfig.defaultDisposeScopeTimeout` by
   default), so that a teardown which never completes cannot hold the release
   of the `scopeKey` in step 6.
5. `ScopeDependencies.dispose` — for a `ScopeAutoDependencies`, this walks the
   tree in reverse: the children of a `sequential` group in reverse declaration
   order, the children of a `concurrent` group in parallel, and only those that
   actually registered a `dep.dispose`. **Bounded by `disposeScopeTimeout` of
   its own**, not by what step 4 left of it: one limit around both meant that a
   state which never finished cost the container its whole disposal. A teardown
   where both steps hang therefore reports two expiries — two steps were given
   up on.
6. The `scopeKey`, if any, is released, and the next scope waiting for it is let
   through.

Every step is guarded on its own, and so are the two halves of steps 1 and 4–5:
a failure in one is never a reason to skip what comes behind it. Only one
failure can be passed on, though — that is all a throw carries — and it is the
first one, handed over once the whole teardown is over. Every failure behind it
is reported through `FlutterError.reportError` instead. So a state whose
`onUnmount` threw and whose container threw behind it says both things: the
state's failure through the throw, the container's through a report.

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

### Two initializations, and what a failure of each leaves behind

A `Scope` initializes **twice**, and the six steps above name hooks from both
halves without saying which is which. Read in that order:

1. **The container.** `initDependencies` builds the dependency tree. Only when
   it yields `ScopeReady` does the scope build its ready branch — and only then
   is there a state at all.
2. **The state.** `createState()`, then `initState()` — where `dependencies`
   are already in place, which is the whole point of the family — then
   `initStateAsync()`, the state's own asynchronous half. `onInitialized()` runs
   right after that succeeds, and `isInitialized` reports it.

The teardown mirrors that pair, and so does what happens when either half
fails:

| what runs | ready, then gone | `initDependencies` failed | state `initStateAsync` failed |
| --- | --- | --- | --- |
| `ScopeState.initState` | yes | **no state exists** | yes |
| `ScopeState.onUnmount` | yes | — | **yes** |
| `dep.unmount` | yes, every dependency | yes, every dependency | yes, every dependency |
| `ScopeState.disposeStateAsync` | yes | — | **no** |
| `dep.dispose` | yes, in reverse | yes, in reverse | yes, in reverse |

On the ordinary path the four run interleaved, state before dependencies in
each half: `ScopeState.onUnmount`, then `dep.unmount`, then
`ScopeState.disposeStateAsync`, then `dep.dispose`. Both halves walk a group the
same way, in reverse of the declaration order: a later dependency is built on
top of an earlier one, so it stops reaching the world before that one lets go
of anything.

**When `initDependencies` failed, the state is the part that never existed.**
`createState()` runs when the ready branch is built, and a scope that failed
never builds it — so there is nothing for `ScopeState.onUnmount` and
`ScopeState.disposeStateAsync` to run on. Do not put the release of something taken
during `initDependencies` in either of them: on the path where it matters most
they are not there to run.

**When the state's `initStateAsync` failed, the state exists and is unmounted, but
not disposed of.** `onUnmount()` runs — it is the synchronous half, and a state
that got as far as `initState()` may already hold a subscription. `disposeStateAsync()`
does not: it is written against a state that finished initializing, and this one
did not. It is the same rule the `AsyncScope` topic states for `dispose` there,
one level down, and it holds for the same reason — only the code that was doing
the building knows how far it got.

**The dependencies are given back on every path**, and on the failing one not
by the element. The element is handed the container only together with
`ScopeReady`, so when `initDependencies` failed it never has one to reach for.
The container tears itself down from inside its own initialization instead,
which is what `ScopeAutoDependencies.autoDisposeOnError` is: `dep.unmount` for
every dependency, then `dep.dispose` for everything that registered one, in
reverse. The promise `dep.unmount` carries — exactly once, always before
`dep.dispose` — holds on that route as it does on the other.

Turning `autoDisposeOnError` off keeps the half-built tree for inspection and
leaves the disposal to you. The unmounting still happens: a container held for
inspection is holding subscriptions, and they should not wait for you to get
round to it.

Read across the families, that is one rule rather than three, though it is easy
to read it as three. **A hook you wrote for a finished thing does not run on
one that never finished; a thing the scope holds on your behalf is given back
whatever happened.** `ScopeState.disposeStateAsync` here and `dispose` in the
`AsyncScope` and `AsyncDataScope` topics are the first kind, and they are
skipped. `dep.dispose` here, and `ScopeController.dispose` in the
`AsyncControllerScope` topic — where the table says `init()` threw → disposed —
are the second kind, and they run.

So the rule of thumb is the one from the `AsyncScope` topic, and it applies to
both halves. Whatever an initialization takes before it fails, that same
initialization gives back — through `dep.dispose` when it was taken through
`dep`, and by its own hand when it was not:

```dart
// Wrong: the connection is open and no hook will ever be handed it.
initDependencies: (context) async* {
  final connection = await Connection.open();
  yield* somethingThatFails();
}

// Right: what this initializer took, this initializer registers.
ScopeDependency buildDependencies(BuildContext context) => sequential('', [
      dep('connection', (dep) async {
        final connection = await Connection.open();
        dep.dispose = connection.close;
      }),
      dep('somethingThatFails', (dep) async { /* ... */ }),
    ]);
```

The same goes for the state's own half: an `initStateAsync()` that takes something
and then throws has to release it before it throws, because `disposeStateAsync()`
will not be called to do it.

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
updates. `setState` is the other half and is untouched — a scope state is an
ordinary `State`: it rebuilds what the state's own `build` returns and reaches
no subscriber. A field both sides read wants both calls.

`isInitialized` reports whether the initialization has fully completed, and
`onInitialized` is the hook called right after it has.
