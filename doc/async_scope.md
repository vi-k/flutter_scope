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
  initBuilder: (context, progress) => Text('$progress'),
  errorBuilder: (context, error, stackTrace, progress) => Text('$error'),
  builder: (context) => const HomeScreen(),
);
```

`AsyncScopeBase` is the subclassable form: the same members as overrides —
`initAsync`, `disposeAsync`, `onMount`, `onUnmount`, `buildOnWaiting`,
`buildOnInitializing`, `buildOnReady`, `buildOnError` — plus `scopeKey`,
`scopeKeyTimeout`, `initCancellationTimeout`, `disposeAsyncTimeout`,
`waitForChildrenTimeout`, their `onTimeout` callbacks and
`pauseAfterInitialization`. `AsyncScopeCore` sits under both for a scope that
needs its own element.

## The four states

`AsyncScopeState` is a sealed hierarchy, and each state drives one builder:

| state | builder | when |
| --- | --- | --- |
| `AsyncScopeWaiting` | `buildOnWaiting`, or `buildOnInitializing` when it returns `null` | mounted; waiting for a `scopeKey` and for the first event |
| `AsyncScopeProgress` | `buildOnInitializing` | `init` reported progress; the value is `progress` |
| `AsyncScopeReady` | `buildOnReady` | `init` yielded `AsyncScopeReady` |
| `AsyncScopeError` | `buildOnError` | `init` failed before it was ready; the progress it had reached comes with it |

`init` is typed to yield `AsyncScopeInitState`, which is the `Progress`/`Ready`
half of that hierarchy: a stream cannot report "waiting" or "failed" as values,
because those two states belong to the scope rather than to the work.

The ready state is not applied in the same frame the event arrives in. Without
`pauseAfterInitialization` the scope schedules a post-frame callback, so the
last progress value gets a frame to itself instead of being replaced within the
frame it appeared in; with it, the ready branch is held back for that duration.
`ScopeConfig.pauseAfterInitializationEnabled = false` turns all such pauses off
globally — see the `debug` topic.

## Progress

Progress is whatever the initialization says it is. `AsyncScopeProgress` carries
an `Object?`, the builders receive an `Object?`, and the package never looks
inside it. A `String` is the common case; anything with a `toString` will do.

```dart
AsyncScope(
  init: (context) async* {
    yield AsyncScopeProgress('connecting');
    await api.connect();

    yield AsyncScopeProgress('loading the profile');
    await api.loadProfile();

    yield AsyncScopeReady();
  },
  dispose: api.close,
  initBuilder: (context, progress) => Center(child: Text('$progress')),
  errorBuilder: (context, error, stackTrace, progress) =>
      Center(child: Text('failed at $progress: $error')),
  builder: (context) => const HomeScreen(),
);
```

Four things are worth knowing about the `progress` argument.

**It is `null` before the first event.** The scope is `AsyncScopeWaiting` from
the moment it is mounted until `init` yields, and if `buildOnWaiting` returns
`null` the waiting branch is `buildOnInitializing(context, null)`. Write the
builder so that `null` means "nothing reported yet" — that is also what it means
in `buildOnError` when the failure came before any progress did.

**The last value gets a frame of its own.** `AsyncScopeReady` is applied in a
post-frame callback, so a progress value yielded immediately before it is
actually painted instead of being replaced within the same frame.
`pauseAfterInitialization` holds the ready branch back further still, which is
what to reach for when the steps are too fast to read.

**Progress after ready is a mistake, and is refused.** The scope is initialized
once; an event arriving after `AsyncScopeReady` — another `ready`, or a late
progress value — is reported through `FlutterError.reportError` and does not
change what is on screen. An initialization that goes on producing values after
the scope is usable wants a `Listenable` under the scope, not this stream.

**No progress at all is fine.** An `init` that yields only `AsyncScopeReady`
never leaves `AsyncScopeWaiting`, so the scope shows `buildOnWaiting` — a
spinner, usually — and then the ready branch.

### Counting steps

For an initialization that knows how many steps it has, `ProgressIterator`
counts them and `Progress` is the value it produces: `number`, `total`,
`progress` as a fraction between 0 and 1, and a `toString` of `2/3`.

```dart
init: (context) async* {
  final steps = ProgressIterator(3);

  yield AsyncScopeProgress(steps.nextStep()); // 1/3
  await api.connect();

  yield AsyncScopeProgress(steps.nextStep()); // 2/3
  await api.loadProfile();

  yield AsyncScopeProgress(steps.nextStep()); // 3/3
  await api.warmUpCache();

  yield AsyncScopeReady();
},
initBuilder: (context, progress) => switch (progress) {
  final Progress progress => LinearProgressIndicator(value: progress.progress),
  _ => const LinearProgressIndicator(),
},
```

The fraction is always between 0 and 1 — an empty task reads as complete rather
than as `NaN` — so it can go straight into a progress indicator. See the `utils`
topic.

### Where the type comes back

`Scope` types its progress: `ScopeInitState<P, D>` carries a `P`, so
`buildOnInitializing` can declare `covariant P? progress` and read fields
instead of calling `toString`. `ScopeAutoDependencies` uses that to report a
`ScopeAutoDependenciesProgress` per dependency — the path, the name and the step
counter in one object. See the `Scope` topic.

`AsyncScope` and `AsyncDataScope` stay untyped on purpose: their type parameter,
where they have one, belongs to the value being built. Progress is a caption.

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
and `buildOnError` receives the error, its stack trace, and the progress the
scope had reached when it failed.

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
3. **The initialization is cancelled**, and the wait for that is bounded by
   `initCancellationTimeout` (`ScopeConfig.defaultInitCancellationTimeout` by
   default). A generator runs its `finally` when its subscription is cancelled,
   and a failure raised there is reported rather than thrown on: abandoning the
   disposal at that point would leave the scope registered with its parent and
   its `scopeKey` unreleased. A cancellation that never finishes at all would
   leave it there just as surely, and needs no failure to do it — cancelling a
   generator means resuming its body and letting it run out, which a body
   parked on a future that never completes never does. When the limit expires
   the initialization is left where it stands, the expiry is reported, and the
   teardown goes on. What the generator itself holds stays held: it waits on
   somebody else's future, and no scope can complete that one for it.
4. **The initialization is awaited** if it could not be cancelled.
5. **The child scopes are awaited**, bounded by `waitForChildrenTimeout`
   (`ScopeConfig.defaultWaitForChildrenTimeout` by default). An expiry is
   reported through `FlutterError.reportError` and the disposal proceeds.
6. **`disposeAsync`** — the scope's own teardown, awaited when it returns a
   future, and bounded by `disposeAsyncTimeout`
   (`ScopeConfig.defaultDisposeAsyncTimeout` by default). It runs only when the
   initialization succeeded: a scope that never became ready — still waiting,
   or failed — has nothing to release. A teardown that never completes is user
   code holding step 7 below, and with it the `scopeKey` of a scope that has
   already left the tree; on expiry that is reported and step 7 runs anyway,
   while the teardown itself is left to finish whenever it does.
7. **The scope unregisters from its parent and releases its `scopeKey`**, which
   lets the next scope waiting on that key through.

Every step is guarded on its own: a failure in one is never a reason to skip
the ones behind it. Only one failure can be passed on, though — that is all a
throw carries — and it is the first one, handed over once the whole sequence is
over: to whoever called `close()`, or, for a scope taken off the tree, to the
zone the teardown ran in. Every failure behind it is reported through
`FlutterError.reportError` instead.

The order is what makes the family worth using: a parent never disposes of
something while a child is still using it, and a re-created scope never
overlaps with the one it replaces.

### An initialization that fails owns its own mess

Step 6 is the one to read twice: **`dispose` runs only when the initialization
succeeded.** A scope that failed halfway never reaches it, and there is no
second hook that does — `onUnmount` runs, but it is handed nothing to work
with.

That is not an oversight. `dispose` is written against a scope that is finished,
and a half-built one is a different thing with a different teardown; only the
code that did the building knows how far it got. So it is the initialization's
job to give back what it took before it failed:

```dart
// Wrong: the connection is open and nobody will ever close it.
init: (context) async* {
  connection = await Api.connect();
  await connection.authenticate();      // throws

  yield AsyncScopeReady();
},
dispose: () => connection.close(),      // never called
```

```dart
// Right: what a step took is given back unless the scope took it over.
init: (context) async* {
  connection = await Api.connect();
  var handedOver = false;

  try {
    await connection.authenticate();

    yield AsyncScopeReady();
    handedOver = true;
  } finally {
    if (!handedOver) {
      await connection.close();
    }
  }
},
dispose: () => connection.close(),
```

**`finally`, and not `catch`** — this is the part that is easy to get wrong. An
initialization ends early in two ways: a step of it fails, or the scope goes
away before it was ever ready, removed from the tree or `close()`d. The second
raises nothing at all. Cancelling an `async*` resumes its body and ends it at
the next `yield`, so `catch` blocks are skipped and only `finally` blocks run —
a guard written as `try`/`catch` gives back what it took when a step throws, and
leaks it when the scope leaves first.

The flag is what keeps the guard quiet afterwards. `yield AsyncScopeReady()` is
the handover, and a body ended at that `yield` never reaches the line below it:
a `finally` that finds the flag still false is exactly the case where the scope
never took the connection over and `dispose` will not be called for it. Once the
flag is set, releasing it is the scope's job and the guard must not do it a
second time.

Keep what the guard awaits able to finish. Nothing downstream sees the failure
until the generator does, so an `await` in the guard holds the failure as well
as the resource: a `close()` that never completes leaves the scope showing its
loading branch for good, with nothing on screen and nothing in the console. The
scope's own waits are all bounded for this reason, and so is the one the
dependency container of the `Scope` family makes on your behalf — a guard you
write yourself is the one place left where a hang is unbounded.

An initialization with several steps like that turns into a pile of nested
`try`s, and that is what the dependency container of the `Scope` family exists
for — see the `Scope` topic. `AsyncControllerScope` closes the same hole from
the other side: its controller is disposed of on **every** path, including the
one where `init()` threw.

## Parents and children

Every asynchronous scope registers with the nearest `AsyncScopeParent` above
it — a parent scope if there is one, an `AsyncScopeCoordinator` otherwise —
and that is what step 5 above waits for. The mixin exposes what it knows:

```dart
hasChildren;    // bool
childrenCount;  // int
await waitForChildren(timeout: …, onTimeout: …);
```

Written without a receiver on purpose: **the mixin sits on the element**, and
the elements of the five built-in families are private. So those three are for
a scope of your own — a family built on `AsyncScopeCore`, reading them on
`this` — and not for a subtree looking upwards. `AsyncScope.of(context, listen:
false)` and its siblings hand back an `AsyncScopeContext`, which carries the
state of the scope and none of this.

From a subtree, the wait to ask for is the coordinator's:

```dart
await AsyncScopeCoordinator.waitForChildren(context);
```

It waits for the scopes registered with the nearest coordinator — the ones with
no parent scope above them — and not for the children of one particular scope.
Waiting for those, from outside the scope that has them, is not something the
built-in families offer.

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
