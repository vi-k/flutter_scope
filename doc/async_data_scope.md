# AsyncDataScope

`AsyncScope` that produces a value. The initialization ends with the object it
built, the subtree reads it from the scope, and the disposal receives it back.
Everything else — the states, the ordered teardown, `scopeKey`, the waiting for
child scopes — is the `AsyncScope` topic, and this page only covers what the
value changes.

Reach for it when the scope exists *because of* an object: a database handle, a
socket, a decoded file. When the objects are already reachable and only their
lifecycle matters, `AsyncScope` is one type parameter lighter; when there are
several of them with an order and a teardown each, the `Scope` topic has the
dependency container.

```dart
AsyncDataScope<Database>(
  initData: (context) async* {
    yield AsyncDataScopeProgress('opening the database');

    yield AsyncDataScopeReady(await Database.open());
  },
  disposeData: (database) => database.close(),
  progressBuilder: (context, progress) => Text('$progress'),
  errorBuilder: (context, error, stackTrace, progress) => Text('$error'),
  builder: (context, database) => DatabaseView(database: database),
);
```

`AsyncDataScopeBase` is the subclassable form, with `initData`, `disposeData`,
`onMount`, `onUnmount` and the four builders as overrides.

## The value in each place

```dart
AsyncDataScopeReady(await Database.open())
```

is where the value enters. The element stores it as the ready state is applied,
and from that moment on:

- **`builder`** receives it as its second argument — the ready branch never has
  to check for `null`;
- **`disposeData`** receives it too, and runs only if the initialization succeeded,
  so the argument always exists;
- **`onUnmount`** receives `T?` instead: it fires the moment the scope leaves the
  tree, which may be long before there is a value, or after a failure;
- **descendants** read it from the context (below).

The progress side is typed loosely on purpose: `AsyncDataScopeProgress` carries
an `Object?`, and the builders receive it as `Object?`. The value being built is
what the type parameter is for; the progress is a caption.

### A value that never arrives is a value nobody releases

`AsyncDataScopeReady` is the handover, and until it happens the value belongs to
the initialization alone. The scope has never seen it, so it cannot release it:
`disposeData` runs only when the initialization succeeded, and `onUnmount` is handed
`null`.

That is what makes this family's version of the trap easy to walk into — the
value exists, in a local variable, and looks as though the scope is looking
after it:

```dart
// Wrong: the database is open, and `disposeData` will never be called with it.
initData: (context) async* {
  final database = await Database.open();

  yield AsyncDataScopeProgress('migrating');
  await database.migrate();             // throws

  yield AsyncDataScopeReady(database);
},
disposeData: (database) => database.close(),
```

```dart
// Right: not handed over yet means still mine to close.
initData: (context) async* {
  final database = await Database.open();
  var handedOver = false;

  try {
    yield AsyncDataScopeProgress('migrating');
    await database.migrate();

    yield AsyncDataScopeReady(database);
    handedOver = true;
  } finally {
    if (!handedOver) {
      await database.close();
    }
  }
},
disposeData: (database) => database.close(),
```

`finally`, and not `catch`: a failing step is only one of the two ways this
initialization ends early. The other is a cancellation — the scope removed from
the tree, or `close()`d, before it was ready — and it raises nothing, so a
`catch` is never reached. See the `AsyncScope` topic for the whole of it; here
the trap is worse, because a `yield` inside the guard is itself a point the
cancellation can end the body at.

Two ways to avoid writing the guard at all: build the value in one step that
cannot fail halfway, or use the dependency container of the `Scope` family,
which does exactly this bookkeeping for a whole tree of resources. And if the
value is an object with a lifecycle of its own rather than a plain resource,
`AsyncControllerScope` disposes of it on every path, including the one where
its `init()` threw.

### Why `builder` is handed the value, when `ScopeModel`'s is not

`ScopeModel.builder` takes a context and nothing else, and the widgets below it
reach the model through `of` or `select`. The difference is not an oversight in
either family; it follows from what the two objects are.

A model lives as long as the scope and changes while it does, so what matters
about it is *when* somebody reads it: a widget that reads it through `select`
is subscribed to the part it read and is rebuilt when that part changes. Handing
the model to the builder would give it an unsubscribed reference and encourage
reading the whole object where a selector would do.

A value here is produced once, by `initData`, and never replaced. There is nothing
to subscribe to and nothing to miss, and there is exactly one branch in which
it exists at all — the ready one, which is what `builder` builds. Passing it is
what makes that branch free of `data!` and `isInitialized`, and it is the same
reason `dispose(data)` and `unmount(T? data)` receive it.

## Reading it from the subtree

```dart
final database = AsyncDataScope.of<Database>(context, listen: false).data;
```

`of`, `maybeOf` and `select` return an `AsyncDataScopeContext`, which adds three
members to everything `AsyncScopeContext` has:

| member | before the value arrives | after |
| --- | --- | --- |
| `data` | throws `StateError('Not initialized')` | the value |
| `dataOrNull` | `null` | the value |
| `hasData` | `false` | `true` |

A widget under `builder` is by definition below a ready scope and can use
`data`. A widget that may also be built while the scope is still initializing —
one in `progressBuilder`, or one reached from elsewhere in the tree — should use
`dataOrNull`, or check `hasData` first.

For a nullable `T` — `AsyncDataScope<Session?>` — `dataOrNull` cannot answer
the question at all: it is `null` on both sides of the moment the value
arrives, since `null` is a value the initialization may legitimately produce.
`hasData` is the difference, and `data` is the other way of asking: it throws
while there is nothing and returns the `null` once there is. The same
ambiguity reaches `onUnmount`, which is handed a `T?` and cannot tell the two
apart on its own.

"Before the value arrives" is a shade earlier than `isInitialized`. The value
is caught as it goes past; the state of the scope is applied at the end of the
frame, or after the whole of `pauseAfterInitialization`, which is deliberately
longer. In that window the scope is still building `progressBuilder` while `data`
already answers — and that is the window the teardown of a scope that left
early runs in, which is why `disposeData` can be promised the value at all.

`select` is the cheap way in when only a part of the value matters:

```dart
final name = AsyncDataScope.select<Profile, String>(
  context,
  (scope) => scope.data.name,
);
```

The type arguments read the way they do everywhere else in the package — the
scope's own type first, the selected type last. The selector receives the
context rather than the data, so it can reach `dataOrNull` or `hasError` as
well.

## What the value does not do

Storing the value does not make it observable. `AsyncDataScope` notifies its
dependents when its **state** changes — waiting, progress, ready, error — and
not when something inside the value changes. A `Database` that gains rows
notifies nobody.

That is the same trade `ScopeModel` makes, and the ways out are the same: make
the value a `Listenable` and put a `ScopeNotifier` under this scope, or expose a
stream from it and let the widgets that care listen.

## In the debugger

The element adds the value to its diagnostics, so the widget inspector and
`debugDumpApp()` show `data: Database(…)` next to the scope — `null` until the
initialization succeeds, which makes the two states easy to tell apart when a
subtree does not look the way it should.

## Where to go next

| topic | what it covers |
| --- | --- |
| `AsyncScope` | the states, the ordered teardown, `scopeKey`, the coordinator |
| `Scope` | several dependencies with an order, a progress per dependency, and a state class |
| `ScopeNotifier` | making the value itself observable |
| `base` | `of`, `select`, `listen` |
