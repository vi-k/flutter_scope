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

`ScopeObserver` is a class of twelve methods, every one of them empty. A subclass
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

`ScopeConfig.observer` holds one observer, and wanting two is ordinary — the
one above beside `ScopePrintObserver` while you are working. That is
`ScopeCompositeObserver`:

```dart
ScopeConfig.observer = const ScopeCompositeObserver([
  ScopePrintObserver(),
  CrashReporter(),
]);
```

It is part of the package rather than something to write by hand, and that is
the point of it. The empty hooks above are what keep an ordinary observer
compiling when a new one is added later — and a delegate is the one subclass
that
gains nothing from them: the new hook would arrive with the empty
implementation of the base, and every observer behind the delegate would stop
hearing that event without a word from anywhere. This one is written with the
class it forwards. An observer that throws does not stop the ones after it
either; the failure is reported and the rest are asked.

The hooks are called synchronously, from the build, the initialization or the
teardown they belong to. That is what makes them useful — the order the lines
come out in is the order the package did the work — and it is also why one that
throws is caught rather than left to escape; see "When the observer itself
fails" below.

## The twelve hooks

| hook | what happened |
| ---------------------------- | ----------------------------------------- |
| `onInit(target)` | an initialization has begun |
| `onStepStarted(target, path)` | one step of it has begun |
| `onProgress(target, progress)` | one step of it is done |
| `onReady(target)` | it finished successfully |
| `onCancelled(target)` | it was cancelled before it finished |
| `onDispose(target)` | a teardown has begun |
| `onDisposalStepStarted(target, path)` | one step of it has begun |
| `onDisposalProgress(target, path)` | one step of it is done |
| `onDisposed(target)` | a teardown has finished |
| `onError(target, phase, error, stackTrace)` | something failed |
| `onTimeout(target, what)` | a bounded wait expired |
| `onTrace(target, message)` | a step of the machinery below the lifecycle |

Four of them are the dependency container's steps — `onStepStarted` and
`onProgress` for an initialization, `onDisposalStepStarted` and
`onDisposalProgress` for a teardown — and they are two pairs: an entry and an
exit for each half of its lifecycle. Both entries are sent from inside the step
and before it awaits anything, which is what makes the pairs worth reading —
see "The last entry with no exit" below. `onProgress` is the one of the four
that a scope sends as well, on its own account; the other three come from a
container and nowhere else.

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
under its own label, beside the scope that owns it: `onInit`, then
`onStepStarted`/`onProgress` per dependency initialized, `onReady` or
`onCancelled`, and then `onDispose`,
`onDisposalStepStarted`/`onDisposalProgress` per dependency released,
`onDisposed`.

A single dependency sends nothing but `onTrace`: the two points where it
handles an error of its own, and the steps of the guarded stream its `init()`
and `dispose()` run through. The four step events above are its steps but the
container's events — they arrive under the container's label, which is the
label an observer that filters by target is already holding.

### The last entry with no exit

`onStepStarted` is sent from inside the step, before the initializer awaits
anything, and `onProgress` for that same step is sent once it is done. So the
recording of an initialization that hung ends with the path of the step it
hung in:

```text
scopo | AppDeps(#1a2b7) | initialize…
scopo | AppDeps(#1a2b7) | initialize storage/db…
scopo | AppDeps(#1a2b7) | progress: storage/db (1/3)
scopo | AppDeps(#1a2b7) | initialize network/session…
```

`network/session` was entered and never came back. Nothing else in the
recording says so: `progress` counts what finished, and the step after
`storage/db` is only guessable for a `sequential` group — a `concurrent` one
has several steps in flight at once, and the number of the last completed one
says nothing about which of them is stuck.

`onDisposalStepStarted` and `onDisposalProgress` are the same pair for the
teardown, and are read the same way.

Two things the pairs promise, and one they do not:

- **the path of the two halves is the same string.** It is assembled by the
  same groups, through the same code, on the way up — so `path` can be used as
  the key of a map that opens on the entry and closes on the exit;
- **a release is announced only when there is one to run.** A dependency that
  registered nothing, or only an `unmount`, has no asynchronous teardown, and
  a bare entry for it would read as a release that hung. It is walked past in
  silence instead, so an unmatched entry always means what it looks like;
- **a dependency of your own making announces no entry.** One that implements
  `ScopeDependency` rather than being built by `dep`, `sequential` or
  `concurrent` has nowhere to take the mark from. Its `onProgress` still
  arrives: that half travels the stream of `init()`, which is the part of the
  contract such a dependency does implement.

Unlike `onProgress`, an entry is **not** passed on to the scope that owns the
container — see the note at the end of the section below.

### What `onProgress` carries

`progress` is an `Object?` because the two sources report different things,
each already typed on its own terms:

- from a scope, the value its initialization reported as progress: whatever
  the application yielded — a `String` on the splash screen, in most of them;
- from a dependency container that is initializing, a
  `ScopeAutoDependenciesProgress`, which carries the `path` of the dependency
  just built along with `name`, `number`, `total` and `value`. A `Scope` whose
  container builds its dependencies passes the same value on, so it arrives
  twice: once under the container's label and once under the scope's.

Wrapping the two in a common type would have meant inventing a third.

**A disposal is not one of them.** It used to be — the bare `String` path of
the dependency just released arrived here too — and that left one hook meaning
two different things at two different points of the lifecycle, told apart by
the type of a value. It has `onDisposalProgress` of its own now. See "Coming
from 0.12.x" below.

**The entry marks arrive once, not twice.** `onProgress` reaches the scope as
well as the container because it travels the container's initialization
stream, and the scope passes on what that stream yields. `onStepStarted` and
`onDisposalStepStarted` travel a channel of their own — that is what lets them
be sent from inside a step rather than after it — so they arrive under the
container's label only. An observer that wants them beside a scope reads
`target`: the container reports next to the scope that owns it, under a label
of its own.

### `onError` and `ScopePhase`

`phase` says what was running when the failure happened:

| `ScopePhase` | what was running |
| ------------------------------ | ------------------------------------------ |
| `initialization` | the initialization: the `init()` hook or the phase |
| `initializationCancellation` | cancelling an initialization still running |
| `build` | a build of the scope's own subtree |
| `preparationForDisposal` | the synchronous half of the teardown |
| `unmount` | the `onUnmount` hook |
| `disposal` | any `dispose`: `disposeScope`, a dependency's, a controller's, a `ScopeModel`'s |
| `abandonedWait` | a wait that failed after its waiter was gone |

The enum can grow, so a `switch` over it in your own code wants a `default`
branch.

`build` is the one phase you would have seen something of without an observer:
Flutter's build error boundary answers a failing build with an `ErrorWidget`.
The report is added to that rather than put in its place — the `ErrorWidget`
still appears, and the failure also arrives through the channel the rest of the
lifecycle arrives through. Every build of every family passes one point, so the
five `buildOn*` branches, `ScopeWidgetBase.build` and `ScopeModel.build` all
report under this phase.

A widget that is not a scope does not: `ListenableSelector` and the views of
`ScopeNotifier` build like any other widget, and `onError`
needs a `ScopeObservable` to name as the target. Their builds stay where they
were — inside the build error boundary, and nowhere else.

A teardown that fails more than once reports every failure, not the first
alone. A `Scope` tears its state down before its dependencies, and each half is
guarded on its own, so both can fail, and `onError` carries them both.

Where such a failure goes besides the observer depends on whether anybody is
left to be handed it. The asynchronous teardown raises the first one at
whoever asked for it — `close()`, say — and reports the rest. Nothing at all
is raised while the framework is taking a scope off the tree: that caller is a
loop unmounting a whole batch of elements with no boundary around any one of
them, over a list it has already cleared, so a throw there would cost every
scope behind this one the teardown it is owed. Both channels still carry the
failure; neither of them is the throw.

An error reaching `onError` is never the only way it is reported: a scope also
hands its initialization failures to `buildOnError`, and the failures nobody
else can be handed go to `FlutterError.reportError`. Leaving
`ScopeConfig.observer` at `null` therefore hides no error completely.

### What `onTimeout` covers

Every bounded wait reports an expiry through the observer — all seven of them —
and `what` names the one that expired:

| `what` | the wait |
| --- | --- |
| `access to its scopeKey` | a scope queued behind the previous one on the same key |
| `its own teardown` | a scope waiting out `disposeScope` |
| `its state to be disposed of` | the first half of that wait on a `Scope`, which has two |
| `its dependencies to be disposed of` | and the second half |
| `its initialization to be cancelled` | a teardown that arrived while the initialization was still running |
| `its controller to be released` | an `AsyncControllerScope` giving back a controller its own initialization never handed over |
| `its child scopes` | a parent waiting for the scopes below it |
| `the disposal` | a dependency container waiting for the tree it built to be released |

Seven rows and eight labels: a `Scope` has two steps behind `disposeScope` and
bounds each of them, so it reports one of the middle two rather than
`its own teardown`, which is what every other family reports.

An expiry is never announced through the observer alone. The first two of
these also reach `onScopeKeyTimeout` and `onWaitForChildrenTimeout` — the
scope's own callbacks — and every one of them is reported through
`FlutterError.reportError` unless a callback of yours takes that place. Passing
your own `onTimeout` to `waitForChildren` replaces that report, not this
event: the observer is what the package says about itself, not your error
handling.

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
failed`, `build failed`, `preparation for disposal failed`, `unmount failed`,
`disposal failed`, and — the one that does not fit that shape — `an abandoned
wait ended in a failure`.

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

Four kinds of wait in the scope lifecycle are bounded by a timeout, and all
four defaults live in `ScopeConfig`:

- `ScopeConfig.defaultScopeKeyTimeout` — how long a scope waits for its
  `scopeKey` to be released by the previous owner;
- `ScopeConfig.defaultInitCancellationTimeout` — how long a teardown waits for
  the initialization to be cancelled;
- `ScopeConfig.defaultDisposeScopeTimeout` — how long a teardown waits for
  `disposeScope`, the scope's own release;
- `ScopeConfig.defaultWaitForChildrenTimeout` — how long a scope waits for its
  child scopes to be disposed of before disposing of itself.

All four are three seconds by default. `null` removes the limit and every scope
waits indefinitely, and so does `ScopeTimeout.none` — the value below, which
says the same thing for a single scope and is accepted here too. An expired
timeout is not fatal: it is reported through `FlutterError.reportError`, and
the scope then proceeds as if the wait had succeeded — so a dependency that
never completes its disposal degrades into a delay plus an error report instead
of a deadlock.

Two more waits share one of these defaults. The first takes no override of its
own.
When the initialization of a `Scope` fails, the dependency container releases
what it had already built, and that release is bounded by
`ScopeConfig.defaultDisposeScopeTimeout` rather than by the `disposeScopeTimeout`
of the scope: a container knows nothing of the widget that owns it and works
without one, so there is nothing there to read a per-scope value from. It is
bounded at all because it is the path of a failed initialization — nothing
downstream sees that failure until the container lets go, so a disposer that
never finishes leaves the scope above showing its loading branch with nothing
on screen and nothing in the console.

The second is the other half of the teardown of a `Scope`, and it does take the
override. `disposeScope` is one method there and two steps — the state's own
teardown, and then the container's — and each is bounded by
`disposeScopeTimeout` of its own rather than by what the first left of the
other. So a teardown where both steps hang reports two expiries and calls
`onDisposeScopeTimeout` twice: two steps were given up on. Every other family
has one step behind that method and one limit around it.

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
`onWaitForChildrenTimeout` callbacks. `null` there means "take the default",
not "wait as long as it takes" — the second thing is said with
`ScopeTimeout.none`:

```dart
AsyncScope(
  waitForChildrenTimeout: ScopeTimeout.none,   // this scope waits it out
  disposeScopeTimeout: const Duration(seconds: 5),
  …
)
```

It is a `Duration` of its own kind rather than a value to remember, so every
one of these parameters stays a `Duration?` and nothing else about them
changes. `AsyncScopeCoordinator.waitForChildren` and a parent's own
`waitForChildren` take it too, for one call, and so do the four `ScopeConfig`
defaults above.

Being a `Duration` of its own kind is also the one thing to know about it: it
is told apart by its type, so it does not survive being computed with.
`ScopeTimeout.none == const Duration(microseconds: -1)` is `true`, and
`ScopeTimeout.none + Duration.zero` is an ordinary `Duration` — what comes back
from any arithmetic is the negative length behind the marker, which a timer
reads as "expire at once". The package asserts against a negative limit
wherever it resolves one, so this is loud in debug rather than silent; a
timeout is still a value to pass on rather than one to compute with.

**`initCancellationTimeout` is the one that refuses it**, with an assert. A
cancellation waits for the initialization generator to run out, and a generator
suspended on a future that never completes never does — an unbounded wait there
is the hang the limit exists to prevent. Removing that one is a decision for
the whole application, and `ScopeConfig.defaultInitCancellationTimeout` is
where it is made — as `null`, or as the `ScopeTimeout.none` that means the same
thing there. The assert is raised inside the teardown's own guard for that
stage, so it arrives as `onError` with `ScopePhase.initializationCancellation`
and the teardown goes on.

**`pauseAfterInitialization` refuses it too**, with an assert of its own, and
for the opposite reason: a pause is a stretch of time to hold the ready branch
back for rather than a limit on a wait, and "wait as long as it takes" has
nothing to say about one. That assert is raised while the scope is becoming
ready, so it arrives as `onError` with `ScopePhase.initialization` and the
scope shows its error branch.

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

## Coming from 0.12.x

**A dependency container no longer reports its disposal through
`onProgress`.** The release of each dependency arrives at
`onDisposalProgress(target, path)` instead, and the step it belongs to is
announced ahead of it by `onDisposalStepStarted(target, path)`.

An existing `onProgress` override keeps compiling, which is the awkward part of
this one: it still overrides a method that still exists — it just stops being
called for the disposal, and nothing points at the change. If yours told the
two halves apart by the type of `progress`, that branch is now a hook:

```dart
// before
@override
void onProgress(ScopeObservable target, Object? progress) {
  if (progress is String) {
    log('released $progress');
  } else {
    log('built $progress');
  }
}

// after
@override
void onProgress(ScopeObservable target, Object? progress) =>
    log('built $progress');

@override
void onDisposalProgress(ScopeObservable target, String path) =>
    log('released $path');
```

`ScopeCompositeObserver` and `ScopePrintObserver` come with the package and
were changed with it; an observer of your own is the only thing to look at.

**One way this release can fail a build rather than go quiet.** Three names
are added to `ScopeObserver`, and Dart has no overloading: a subclass that
already has a member of its own called `onStepStarted`,
`onDisposalStepStarted` or `onDisposalProgress` now declares an invalid
override. Rare — they are not obvious names for a helper — but it is a
compile error rather than a change of behaviour, so the analyzer names it and
renaming your member settles it.

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
