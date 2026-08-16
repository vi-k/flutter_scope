# AsyncScope

A scope whose whole content is a lifecycle: an asynchronous initialization and
an asynchronous disposal, with no dependency container and no state class. Use
it when the objects already exist — a singleton, a connection, a repository
owned by a parent scope — and only their starting and stopping has to follow
the widget tree.

```dart
AsyncScope(
  init: (context) async* {
    yield AsyncScopeProgress('connecting');
    await connection.open();

    yield AsyncScopeReady();
  },
  dispose: () => connection.close(),
  waitingBuilder: (context) => const SizedBox.shrink(),
  initBuilder: (context) => const CircularProgressIndicator(),
  errorBuilder: (context, error, stackTrace) => Text('$error'),
  builder: (context) => const HomeScreen(),
);
```

`AsyncScopeBase` is the subclassable form: the same members as overrides —
`initAsync`, `disposeAsync`, `onMount`, `onUnmount`, `buildOnWaiting`,
`buildOnInitializing`, `buildOnReady`, `buildOnError` — plus `scopeKey`,
`scopeKeyTimeout`, `waitForChildrenTimeout`, their `onTimeout` callbacks and
`pauseAfterInitialization`. `AsyncScopeCore` sits under both for a scope that
needs its own element.

## The four states

`AsyncScopeState` is a sealed hierarchy, and each state drives one builder:

| state | builder | when |
| --- | --- | --- |
| `AsyncScopeWaiting` | `buildOnWaiting`, or `buildOnInitializing` when it returns `null` | mounted; waiting for a `scopeKey` and for the first event |
| `AsyncScopeProgress` | `buildOnInitializing` | `init` reported progress; the value is `progress` |
| `AsyncScopeReady` | `buildOnReady` | `init` yielded `AsyncScopeReady` |
| `AsyncScopeError` | `buildOnError` | `init` failed before it was ready |

`init` is typed to yield `AsyncScopeInitState`, which is the `Progress`/`Ready`
half of that hierarchy: a stream cannot report "waiting" or "failed" as values,
because those two states belong to the scope rather than to the work.

The ready state is not applied in the same frame the event arrives in. Without
`pauseAfterInitialization` the scope schedules a post-frame callback, so the
last progress value gets a frame to itself instead of being replaced within the
frame it appeared in; with it, the ready branch is held back for that duration.
`ScopeConfig.pauseAfterInitializationEnabled = false` turns all such pauses off
globally — see the `debug` topic.

## Reading the state from the subtree

```dart
final scope = AsyncScope.of(context, listen: true);
if (scope.isInitialized) { … }
```

`of`, `maybeOf` and `select` return an `AsyncScopeContext`, which exposes
`state`, `isInitialized` (the state is `AsyncScopeReady`), `hasError`, and
`error` / `stackTrace`, both of which throw a `StateError` when there is no
error. Reading a single field through `select` is the usual way in, since it
subscribes to that field alone — the `base` topic explains the filtering.

## Errors

A stream that fails before the scope is ready puts it into `AsyncScopeError`,
and `buildOnError` receives the error and its stack trace.

Two failures are handled differently, and both deserve to be known.

**A second `AsyncScopeReady`** is a `StateError` — `already initialized`. A
scope becomes ready once; a stream that yields it twice is a bug in the stream,
and the scope says so rather than initializing everything a second time.

**A failure after the scope is already ready** does not switch the screen to
`buildOnError`. It is reported through `FlutterError.reportError` and the scope
stays ready. That is deliberate: the widgets on screen are the ready ones,
whatever `init` acquired still has to be released by `dispose`, and swapping the
subtree for an error screen behind the user's back would strand both. A stream
that keeps working after `AsyncScopeReady` is unusual, but it is exactly the
case where the difference matters.

## Disposal, in order

The teardown runs as one sequence, and every asynchronous step of it is
awaited:

1. **`onUnmount`** — synchronous, and always first. Whatever must stop reaching
   the scope at once is dropped here: subscriptions, listeners. It runs exactly
   once, whichever way the scope goes — removed from the tree, or closed with
   `close()` while it stays on screen.
2. **The wait for a `scopeKey` is cancelled**, if the scope was still queueing
   for one.
3. **The initialization is cancelled.** A generator runs its `finally` when its
   subscription is cancelled, and a failure raised there is reported rather
   than thrown on: abandoning the disposal at that point would leave the scope
   registered with its parent and its `scopeKey` unreleased.
4. **The initialization is awaited** if it could not be cancelled.
5. **The child scopes are awaited**, bounded by `waitForChildrenTimeout`
   (`ScopeConfig.defaultWaitForChildrenTimeout` by default). An expiry is
   reported through `FlutterError.reportError` and the disposal proceeds.
6. **`disposeAsync`** — the scope's own teardown, awaited when it returns a
   future. It runs only when the initialization succeeded: a scope that never
   became ready — still waiting, or failed — has nothing to release.
7. **The scope unregisters from its parent and releases its `scopeKey`**, which
   lets the next scope waiting on that key through.

The order is what makes the family worth using: a parent never disposes of
something while a child is still using it, and a re-created scope never
overlaps with the one it replaces.

## Parents and children

Every asynchronous scope registers with the nearest `AsyncScopeParent` above
it — a parent scope if there is one, an `AsyncScopeCoordinator` otherwise —
and that is what step 5 above waits for. The mixin exposes what it knows:

```dart
scope.hasChildren;    // bool
scope.childrenCount;  // int
await scope.waitForChildren(timeout: …, onTimeout: …);
```

`waitForChildren` awaits the children registered **at the moment of the call**.
A child that registers while the wait is running is not awaited by it, and is
still registered once it is over. On expiry the children that never finished
are dropped, `onTimeout` is called — by default a `FlutterError.reportError`
naming the scope — and the future completes normally either way. Nothing here
deadlocks; it degrades into a delay and a report.

A scope with neither a parent scope nor a coordinator above it registers
nowhere, and nothing waits for it. That is worth knowing before removing a
coordinator that looked decorative.

## scopeKey and the coordinator

`scopeKey` serializes scopes that must not overlap. A scope with a key waits at
the head of a queue until the previous holder of that key has finished
disposing of itself — the whole seven-step sequence above, not just its removal
from the tree.

The queues belong to the nearest `AsyncScopeCoordinator`:

```dart
AsyncScopeCoordinator(child: MaterialApp(home: HomeScreen()))
```

Two consequences follow from "the nearest". Two scopes with equal keys under
different coordinators never wait for one another. And the queues live on the
coordinator's element, so serialization holds only as long as that element
does: replacing the coordinator — a different `ValueKey`, a different place in
the tree — throws its queues away with it. Above everything that can be
replaced is therefore the right place for it, and above `MaterialApp` is the
usual one.

A scope with a `scopeKey` and no coordinator above it fails loudly:

```text
No AsyncScopeCoordinator.
The AsyncScopeCoordinator is missing in the context. Add it to the widget tree
so that all your scopes that need it can access it. The most universal solution
is to place it above MaterialApp. …
```

The coordinator is also the wait root for the scopes in its subtree that have
no parent scope, which is what makes it useful without any `scopeKey` at all:

```dart
await AsyncScopeCoordinator.waitForChildren(context);
```

before tearing down a test, or before leaving a splash screen. Its `timeout`
defaults to `ScopeConfig.defaultWaitForChildrenTimeout`, and an expiry behaves
exactly as above: reported, not thrown.

## Where to go next

| topic | what it covers |
| --- | --- |
| `AsyncDataScope` | this family plus one value produced by the initialization |
| `LiteScope` | a state class with the same lifecycle, and `close()` |
| `Scope` | the full family: a dependency container on top of all this |
| `ScopeNotifier` | the state models this family is built on |
| `debug` | the log of every step above, and the timeout settings |
