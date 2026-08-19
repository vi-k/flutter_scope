# minimal

One scope, in as few files as it takes: `lib/main.dart`, 245 lines.

```sh
cd example/minimal
flutter run
```

## What it shows

`App` is a full `Scope` with all three parts, and the file is laid out in that
order:

1. **`App`** — the scope widget. It carries one parameter, `title`, and exposes
   the four accessors a scope normally re-exports under its own name:
   `paramsOf` and `selectParam` for the parameter, `of` and `select` for the
   state.
2. **`AppDependencies`** — the container, initialized asynchronously.
   `SharedPreferences` is what it waits for, and the progress it reports is the
   `String` shown on the splash screen.
3. **`AppState`** — the state. It reads the counter from the storage in
   `initState`, and `increment()` mutates it, calls `notifyDependents()` and
   writes it back.

The three branches are each built with their own `MaterialApp`, which is what
`wrapState` being ready-only means in practice — `_app({required child})` in
the file exists exactly for that. `pauseAfterInitialization` is set to 500 ms so
that the splash screen can be seen at all on a fast machine.

`main()` also assigns the observer — `ScopeConfig.observer = const
ScopePrintObserver()` — which prints a line per lifecycle event. Run it and the
console shows the scope initializing, reporting progress, becoming ready, and —
when the app is closed — disposing of itself in order.

## What to try

- Pass `trace: true` to the `ScopePrintObserver` in `main()` to see the
  machinery under the lifecycle — the `scopeKey` queue, the guarded streams —
  and not only the milestones.
- Make `AppDependencies.init` throw after the first `yield` to land on the
  error branch.
- Set `ScopeConfig.pauseAfterInitializationEnabled = false` to see how fast the
  ready branch really arrives.

The topics behind all of this are the `Scope` and `debug` pages of the
[documentation](https://pub.dev/documentation/scopo/latest/).
