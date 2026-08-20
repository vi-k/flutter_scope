# debug

The observer and the global settings of the package. Everything on this page is
static and lives in `ScopeConfig`, so the usual place to set it up is `main()`,
before `runApp`.

## The observer

The package is silent until it is given somewhere to speak.
`ScopeConfig.observer` is `null` by default; assign a `ScopeObserver` and every
scope in the application starts reporting through it.

```dart
void main() {
  ScopeConfig.observer = const ScopePrintObserver();

  runApp(const App());
}
```

`ScopeObserver` is a class of nine methods, every one of them empty. A subclass
overrides what it wants and inherits the silence of the rest, so an observer
that only cares about failures is one method long:

```dart
final class CrashReporter extends ScopeObserver {
  const CrashReporter();

  @override
  void onError(
    ScopeObservable target,
    ScopePhase phase,
    Object error,
    StackTrace? stackTrace,
  ) =>
      crashlytics.recordError(
        error,
        stackTrace,
        reason: '${target.debugLabel}: ${phase.name}',
      );
}
```

`ScopeObserver` is a `base class`, so a subclass of your own is declared `base`
or `final` — `final` unless you mean it to be extended further.

The hooks are called synchronously, from the build, the initialization or the
teardown they belong to. That is what makes them useful — the order the lines
come out in is the order the package did the work — and it is also why one that
throws is caught rather than left to escape; see "When the observer itself
fails" below.

## The nine hooks

| hook | what happened |
| ---------------------------- | ----------------------------------------- |
| `onInit(target)` | an initialization has begun |
| `onProgress(target, progress)` | one step of it is done |
| `onReady(target)` | it finished successfully |
| `onCancelled(target)` | it was cancelled before it finished |
| `onDispose(target)` | a teardown has begun |
| `onDisposed(target)` | a teardown has finished |
| `onError(target, phase, error, stackTrace)` | something failed |
| `onTimeout(target, what)` | a bounded wait expired |
| `onTrace(target, message)` | a step of the machinery below the lifecycle |

### Who sends them

A family with no initialization phase of its own — `ScopeWidget`, `ScopeModel`,
`ScopeNotifier`, `AsyncScopeCoordinator` — reports `onInit` when its element is
initialized, and `onDispose`/`onDisposed` as a pair around its teardown. That
is all such a scope has to say when it works; one whose `init()` throws says
`onError` with `ScopePhase.initialization` and nothing else. Before this
reporting existed it said nothing at all: its lifecycle was visible only to a
debugger.

A family that runs an initialization — everything built on the asynchronous
element: `AsyncScope`, `AsyncDataScope`, `AsyncControllerScope`, `LiteScope`
and `Scope` — reports that phase instead, in the detail the phase has:
`onInit`, then `onProgress` per step, then `onReady` or `onCancelled`; and, on
the way out, `onDispose` and `onDisposed`. Nothing reports both halves — the
structural pair is suppressed for these families, so a `LiteScope` produces one
`onInit`, not two.

Three things that order does not say, and all three matter to an observer
that pairs events up:

- **`onCancelled` does not always follow an `onInit`.** A scope still queued
  for its `scopeKey` when it is taken off the tree never started an
  initialization of its own, so there was nothing to announce: its whole
  recording is `onCancelled`, `onDispose`, `onDisposed`. The cancellation
  genuinely happens in the queue, before the initialization this family would
  otherwise report;
- **`onDispose` and `onDisposed` always come as a pair.** `onDispose` is sent
  by every teardown, including one of a scope that never became ready and has
  nothing of its own to release, and `onDisposed` is sent even when the
  teardown failed — after the `onError` that says so, not instead of it. So a
  leak counter or a span tracker that opens on one and closes on the other
  stays balanced whichever way the scope went;
- **for a family with no phase of its own, that same pair requires the
  `onInit` that would open it.** `ScopeWidget`, `ScopeModel`, `ScopeNotifier`
  and `AsyncScopeCoordinator` report `onDispose`/`onDisposed` only for an
  element whose `init()` succeeded; one that threw, or never ran, reports
  neither half — nothing was announced as open, so nothing is announced as
  closed, even though the element still tears itself down internally. This is
  the one point where the two kinds of family differ: the phase-reporting
  families above can still close a teardown that opened with no `onInit` at
  all, as the previous bullet shows. The failure itself is not lost either
  way — `init()` is the one hook both kinds run before anything else, and a
  throw from it reports `onError` with `ScopePhase.initialization` for both.

The container of automatic dependencies of a `Scope` reports its own lifecycle
under its own label, beside the scope that owns it: `onInit`, `onProgress` per
dependency initialized, `onReady` or `onCancelled`, and then `onDispose`,
`onProgress` per dependency released, `onDisposed`.

A single dependency sends nothing but `onTrace`: the two points where it
handles an error of its own, and the steps of the guarded stream its `init()`
and `dispose()` run through.

### What `onProgress` carries

`progress` is an `Object?` because the three sources report different things,
each already typed on its own terms:

- from a scope, the value its initialization reported as progress: whatever
  the application yielded — a `String` on the splash screen, in most of them;
- from a dependency container that is initializing, a
  `ScopeAutoDependenciesProgress`, which carries the `path` of the dependency
  just built along with `name`, `number`, `total` and `value`. A `Scope` whose
  container builds its dependencies passes the same value on, so it arrives
  twice: once under the container's label and once under the scope's;
- from a dependency container that is disposing, the bare `String` path of the
  dependency just released.

Wrapping those three in a common type would have meant inventing a fourth.

### `onError` and `ScopePhase`

`phase` says what was running when the failure happened:

| `ScopePhase` | what was running |
| ------------------------------ | ------------------------------------------ |
| `initialization` | the initialization: the `init()` hook or the phase |
| `initializationCancellation` | cancelling an initialization still running |
| `preparationForDisposal` | the synchronous half of the teardown |
| `unmount` | the `onUnmount` hook |
| `disposal` | `disposeScope`, a dependency's or a controller's `dispose` |
| `abandonedWait` | a wait that failed after its waiter was gone |

The enum can grow, so a `switch` over it in your own code wants a `default`
branch.

An error reaching `onError` is never the only way it is reported: a scope also
hands its initialization failures to `buildOnError`, and the failures nobody
else can be handed go to `FlutterError.reportError`. Leaving
`ScopeConfig.observer` at `null` therefore hides no error completely.

### What `onTimeout` covers

Four bounded waits report an expiry through the observer, and `what` names the
one that expired: `its own teardown` (a scope waiting out `disposeScope`),
`its initialization to be cancelled`, `its controller to be released` (an
`AsyncControllerScope` giving back a controller its own initialization never
handed over), and `the disposal` (a dependency container waiting for the tree
it built to be released).

The two remaining bounded waits — for a `scopeKey` and for child scopes — do
not reach the observer. They report through `FlutterError.reportError` and
through the `onScopeKeyTimeout` and `onWaitForChildrenTimeout` callbacks of the
scope itself, which is where they were before the observer existed.

### What `onTrace` covers

Everything below the lifecycle: preparing for initialization and for disposal,
the `scopeKey` queue (waiting for access, obtaining it, giving it up, leaving),
waiting for child scopes, waiting for an initialization to finish, the two
points inside a dependency where an error is handled, and the seven steps of
the guarded stream that every dependency's `init()` and `dispose()` runs
through.

A scope produces a dozen of these where it produces one of everything else,
which is why `ScopePrintObserver` leaves them off. They are what to turn on
when a scope hangs, initializes in an unexpected order, or is disposed of too
late — and nothing else.

## Who the event is about

The first argument of every hook is a `ScopeObservable`, and its only member is
the name the source calls itself by:

| source | `debugLabel` |
| ----------------------------- | ------------------------------------------ |
| a scope element, any family | `CounterScope(#4e0b7)` or `CounterScope(cart)` |
| the container of dependencies | `AppDependencies(#25f53)` |
| a single dependency | its declared name; `[group]` if the group is anonymous |

A `tag` is therefore the cheapest way to tell two scopes of the same type apart
in the output — and the only way to get a label that is the same on every run,
since the short hash is not.

`ScopeObservable` is deliberately not implemented by `ScopeDependencies` or
`ScopeDependency`: those are yours to implement, and a new required member on
them would break the code that already does. Only the classes of the package
produce events, so only they carry the marker.

An observer that wants one kind of source narrows with a pattern rather than a
cast:

```dart
final class ScopeAnalytics extends ScopeObserver {
  const ScopeAnalytics();

  @override
  void onReady(ScopeObservable target) {
    if (target case ScopeInheritedElement(:final widget)) {
      analytics.logEvent('scope_ready', {'type': '${widget.runtimeType}'});
    }
  }
}
```

## ScopePrintObserver

The observer that comes with the package writes a line per event:

```dart
ScopeConfig.observer = const ScopePrintObserver();
```

```text
scopo | CounterScope(#4e0b7) | initialize…
scopo | AppDependencies(#25f53) | progress: prefs (1/2)
scopo | CounterScope(#4e0b7) | initialized
scopo | CounterScope(#4e0b7) | initialization failed: Exception: no network
```

The shape is `scopo | <label> | <what happened>`. A failure adds `: <error>`,
and the stack trace on a line of its own when the event carries one.

The phase of a failure is spelled out as English rather than as the name of the
`ScopePhase` value: `initialization failed`, `initialization cancellation
failed`, `preparation for disposal failed`, `unmount failed`, `disposal
failed`, and — the one that does not fit that shape — `an abandoned wait ended
in a failure`.

Two parameters, both optional:

```dart
ScopeConfig.observer = ScopePrintObserver(
  output: debugPrint,
  trace: true,
);
```

`output` is where a line goes; `print` by default. `trace` decides whether
`onTrace` is printed at all, and is `false` by default — which is the whole of
what a level threshold used to do here.

The constructor is `const`, and the observer above is not: `debugPrint` is a
variable Flutter lets you replace, so it is not a constant. `const` works with
the default `output` and with a function of your own that is one.

## When the observer itself fails

The observer is your code, and the package calls it from a build, from an
initialization and from a teardown. A hook that threw out of one of those would
take the scope with it: a scope that never built its ready branch, or a
teardown that stopped halfway with a `scopeKey` still held.

So every call goes through a guard. A hook that throws is reported through
`FlutterError.reportError` with `library: 'scopo'` — a red screen in debug,
`FlutterError.onError` in release — and whatever was reporting the event goes
on. Nothing is swallowed, and nothing is retried.

The same guard refuses re-entry. An observer that produces a scope event while
it is being notified — one that mounts a scope from inside a hook, say — would
otherwise recurse without end; the second notification is refused and reported,
once per refused call, and the first one runs to its end.

## Timeouts

Four waits in the scope lifecycle are bounded by a timeout, and all four
defaults live in `ScopeConfig`:

- `ScopeConfig.defaultScopeKeyTimeout` — how long a scope waits for its
  `scopeKey` to be released by the previous owner;
- `ScopeConfig.defaultInitCancellationTimeout` — how long a teardown waits for
  the initialization to be cancelled;
- `ScopeConfig.defaultDisposeScopeTimeout` — how long a teardown waits for
  `disposeScope`, the scope's own release;
- `ScopeConfig.defaultWaitForChildrenTimeout` — how long a scope waits for its
  child scopes to be disposed of before disposing of itself.

All four are three seconds by default. `null` removes the limit and the scope
waits indefinitely. An expired timeout is not fatal: it is reported through
`FlutterError.reportError`, and the scope then proceeds as if the wait had
succeeded — so a dependency that never completes its disposal degrades into a
delay plus an error report instead of a deadlock.

All four are measured on real time rather than on the clock of the zone the
teardown runs in, which is what a widget test replaces with a fake one. A hang
like the ones they exist for outlives frames, and a scope is usually taken down
between them: a timer belonging to that zone would still be pending when the
tree is gone, and `flutter_test` ends a test on exactly that. So a test of your
own that has to wait one of these out waits in real time — `pump(duration)`
moves the fake clock and reaches none of them.

`pauseAfterInitialization` is the exception, and deliberately: that delay is one
the user sees, so a widget test drives it with `pump(duration)` like any other
animation. The scope puts it out when it is taken down mid-pause.

Every scope can override all four defaults for itself with the
`scopeKeyTimeout`, `initCancellationTimeout`, `disposeScopeTimeout` and
`waitForChildrenTimeout` parameters, and observe an expiry through the
`onScopeKeyTimeout`, `onInitCancellationTimeout`, `onDisposeScopeTimeout` and
`onWaitForChildrenTimeout` callbacks. What a scope cannot do for itself is
remove the limit: `null` there means "take the default", not "wait as long as it
takes". Removing a limit is what the `ScopeConfig` values above are for, and it
applies to every scope at once.

## pauseAfterInitializationEnabled

`pauseAfterInitialization` is an artificial delay between the moment a scope
becomes ready and the moment its subtree is shown; it exists to keep a loading
indicator visible long enough to be read instead of blinking.

`ScopeConfig.pauseAfterInitializationEnabled = false` switches every such pause
off globally, without touching the widgets that declare it. Set it in the setup
of a widget test, or while stepping through an initialization in the debugger.

## reset()

The switches above — the pause and the four timeouts — are global and outlive
the code that changed them, so a test that raises a timeout and forgets to put
it back hands the next test a different package. `ScopeConfig.reset()` puts all
five back to their defaults:

```dart
void main() {
  tearDown(ScopeConfig.reset);
  …
}
```

`setUp` works as well, and covers a test that failed before its own teardown
ran. The observer is left alone: it is an object rather than a switch, and it is
usually the whole point of the run it was assigned for. A suite that wants it
gone puts it back itself — `ScopeConfig.observer = null`.

## In tests

An observer that records instead of printing turns the lifecycle into a value a
test can assert on. Compare the whole list at once: that catches a missing event
and one too many alike, which a `verify` per event does not.

```dart
final class RecordingObserver extends ScopeObserver {
  final events = <String>[];

  @override
  void onInit(ScopeObservable target) =>
      events.add('init ${target.debugLabel}');

  @override
  void onReady(ScopeObservable target) =>
      events.add('ready ${target.debugLabel}');

  @override
  void onDisposed(ScopeObservable target) =>
      events.add('disposed ${target.debugLabel}');
}

void main() {
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

  testWidgets('the scope initializes once and is disposed of once',
      (tester) async {
    await tester.pumpWidget(const CounterScope(tag: 'counter'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();

    expect(observer.events, [
      'init CounterScope(counter)',
      'ready CounterScope(counter)',
      'disposed CounterScope(counter)',
    ]);
  });
}
```

Two things that expectation depends on. The scope is tagged, because an untagged
one labels itself with a short hash that is different on every run — tag it, or
strip the `(…)` off the label before comparing. And the observer is cleared in
the teardown, because `ScopeConfig.reset()` does not clear it: an observer left
behind goes on recording into the next test's list.

Keep `trace` out of it unless the trace is what the test is about. At that level
a single scope produces a dozen events, and an expectation that lists them all
fails on every unrelated change to the coordination.

See
[example/minimal](https://github.com/vi-k/scopo/blob/main/example/minimal/lib/main.dart)
for the setup of a real application, and
[example/scopo_demo](https://github.com/vi-k/scopo/tree/main/example/scopo_demo)
for a demo that shows every lifecycle call of every scope family side by side.

## Coming from 0.9.x

The nine public names built on `logger_builder` are gone: `ScopeConfig.logger`,
`ScopeLogger`, `ScopeLevelLogger`, `ScopeLog`, `ScopeLogPublisher`,
`ScopeLogFormatter`, `ScopeLogTransformer`, `ScopeLogLevel` and
`ScopeLogCallback`. The package has no external dependencies now.

What each of them was for:

- `ScopeConfig.logger.level = ScopeLogLevel.info` →
  `ScopeConfig.observer = const ScopePrintObserver()`;
- `ScopeLogLevel.debug` → `const ScopePrintObserver(trace: true)`;
- `ScopeLogLevel.off` → `ScopeConfig.observer = null`;
- a publisher that formatted and printed → the `output` of
  `ScopePrintObserver`, or a `ScopeObserver` of your own;
- a publisher that collected the logs into a list to assert on → an observer
  that records, as under "In tests" above;
- a transformer that dropped the logs of one path → an `if` inside the hook,
  on `target.debugLabel` or on the type of `target`;
- routing failures onward by parsing `ScopeLog.message` → `onError`, with the
  error, the stack trace and a `ScopePhase` already separated.

There is no threshold any more, and nothing that takes its place as one value.
Its three jobs are split: `ScopeConfig.observer = null` turns everything off,
an empty hook body turns off one kind of event, and `trace` turns off the
noisiest kind.
