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
  init: (context) async* {
    yield AsyncDataScopeProgress('opening the database');

    yield AsyncDataScopeReady(await Database.open());
  },
  dispose: (database) => database.close(),
  initBuilder: (context, progress) => Text('$progress'),
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
- **`dispose`** receives it too, and runs only if the initialization succeeded,
  so the argument always exists;
- **`unmount`** receives `T?` instead: it fires the moment the scope leaves the
  tree, which may be long before there is a value, or after a failure;
- **descendants** read it from the context (below).

The progress side is typed loosely on purpose: `AsyncDataScopeProgress` carries
an `Object?`, and the builders receive it as `Object?`. The value being built is
what the type parameter is for; the progress is a caption.

## Reading it from the subtree

```dart
final database = AsyncDataScope.of<Database>(context, listen: false).data;
```

`of`, `maybeOf` and `select` return an `AsyncDataScopeContext`, which adds two
members to everything `AsyncScopeContext` has:

| member | before the scope is ready | after |
| --- | --- | --- |
| `data` | throws `StateError('Not initialized')` | the value |
| `dataOrNull` | `null` | the value |

A widget under `builder` is by definition below a ready scope and can use
`data`. A widget that may also be built while the scope is still initializing —
one in `initBuilder`, or one reached from elsewhere in the tree — should use
`dataOrNull`, or check `isInitialized` first.

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
