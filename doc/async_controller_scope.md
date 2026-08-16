# AsyncControllerScope

A scope whose whole content is a controller: an object with a lifecycle of its
own, created when the scope mounts, initialized asynchronously, told to stop
when the scope leaves, and released after that. Use it when the scope exists
because something has to *run* while a part of the tree is on screen — a map
overlay driven by a bloc, a poller, a session — rather than because something
has to be *shown*.

```dart
AsyncControllerScope<PlayerController>(
  create: (context) => PlayerController(api: context.read<Api>()),
  initBuilder: (context) => const SizedBox.shrink(),
  errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
  builder: (context, controller) => const PlayerView(),
);
```

`AsyncControllerScopeBase` is the subclassable form, and the one most
controllers end up in, since the controller usually needs things from the tree:

```dart
final class Player extends AsyncControllerScopeBase<Player, PlayerController> {
  const Player({super.key, required super.child}) : super(scopeKey: Player);

  @override
  PlayerController createController(BuildContext context) =>
      PlayerController(api: context.read<Api>());

  @override
  Widget buildOnInitializing(BuildContext context) => const SizedBox.shrink();

  @override
  Widget buildOnError(BuildContext context, Object error, StackTrace stack) =>
      const SizedBox.shrink();

  @override
  Widget buildOnReady(BuildContext context, PlayerController controller) =>
      child;
}
```

`AsyncControllerScopeCore` sits under both, for a scope that needs its own
element. The family is built on the `AsyncDataScope` machinery, so everything
that topic describes — the four states, the ordered teardown, `scopeKey`, the
waiting for child scopes, the four timeouts — applies here unchanged, and the
controller is the value.

## The controller

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
  void onUnmount() => _subscription?.cancel();

  @override
  Future<void> dispose() async => api.closeSession();
}
```

Three methods to write, and none of them has to chain to `super`:

| method | when |
| --- | --- |
| `init()` | once, asynchronously, before the ready branch is built |
| `onUnmount()` | synchronously, the moment the scope leaves the tree |
| `dispose()` | awaited, after `onUnmount`, when the scope is being taken down |

`mounted` is what to check after every `await` inside `init()`: the scope may
have gone while the initialization was suspended, and `onUnmount()` has then
already run.

The three methods the scope calls — `performInit`, `performUnmount`,
`performDispose` — are sealed. They keep `mounted`, they keep the order, and
they make each hook run at most once, so none of that rests on a controller
remembering a convention. They are public rather than hidden, so a controller
can be driven by hand in a test:

```dart
final controller = PlayerController(api: FakeApi());
await controller.performInit();
// …
await controller.performDispose();
```

## What the scope guarantees

The point of the family. A controller created by the scope is released by the
scope, on every path — including the two that are easy to get wrong when the
same thing is written by hand on top of `AsyncDataScope`, where the scope only
learns about the controller if the initialization gets as far as handing it
over:

| what happened | `onUnmount()` | `dispose()` |
| --- | --- | --- |
| the scope left before the asynchronous phase began | no controller was created | — |
| `init()` threw | yes | yes |
| the scope left while `init()` was still running | yes | yes |
| the scope left, and the ready state never arrived | yes | yes |
| the ordinary path: ready, then gone | yes | yes |

`onUnmount()` is the synchronous half and always runs first — at the moment the
scope leaves the tree, not when the asynchronous teardown gets around to it.
That is the difference that matters for a controller driving something outside
itself: it stops reaching the outside world at once, whatever the rest of the
teardown is still waiting for.

A controller that hangs cannot hold anything hostage: the wait for a cancelled
initialization is bounded by `initCancellationTimeout` and the wait for
`dispose()` by `disposeAsyncTimeout` — see the `debug` topic.

## Reading the controller from the subtree

```dart
final controller = AsyncControllerScope.of<PlayerController>(
  context,
  listen: false,
).data;
```

`of`, `maybeOf` and `select` return an `AsyncDataScopeContext`, exactly as in
the `AsyncDataScope` topic: `data` throws before the controller is ready,
`dataOrNull` returns `null`. Widgets under `builder` are below a ready scope
and can use `data`.

The subclassable form has the same three as statics, taking the widget type
first:

```dart
final position = AsyncControllerScopeBase.select<Player, PlayerController, int>(
  context,
  (scope) => scope.data.position,
);
```

## What this family does not do

**It does not make the controller observable.** The scope notifies its
dependents when its *state* changes — waiting, ready, error — and not when
something inside the controller changes. A controller whose values the widgets
have to follow should be a `Listenable` with a `ScopeNotifier.value` under this
scope, or should expose a stream.

**It reports no progress.** `init()` is a `Future<void>`, so there is nothing
between "initializing" and "ready" to show. An initialization that has stages
worth naming belongs in `AsyncDataScope`, whose stream reports them.

**It does nothing with a failed initialization** beyond what every family
does: the error reaches `buildOnError`, which is required precisely so that
the decision is made rather than defaulted. Route it onward from there, or
turn on the package logger — the `debug` topic has both.

## Where next

| topic | what for |
| --- | --- |
| `AsyncDataScope` | the machinery underneath: states, teardown order, `scopeKey` |
| `AsyncScope` | the same lifecycle with no value at all |
| `ScopeNotifier` | making the controller itself observable |
| `debug` | the four timeouts and the log |
