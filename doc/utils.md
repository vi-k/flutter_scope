# utils

Helpers that ship with the package but belong to no scope family. They are
exported because the scopes themselves are built on them and an application
tends to want the same tools; nothing here needs a scope above it.

| helper | what it is |
| --- | --- |
| `ListenableListenExtension.listen` | `Stream`-style subscription to a `Listenable` |
| `ListenableSelectExtension.select` | a listener called only when a selected value changes |
| `ListenableSelector` | the widget form of that selector |
| `ListenableView` | a read-only façade over a `Listenable` |
| `StateAsNotifier` | a mixin that makes a `State` listenable |
| `NavigationNode` | a nested `Navigator` that keeps its routes inside the scope |
| `ProgressIterator`, `Progress` | step counting for an initialization |
| `ScreenshotReplacer` | freezes a subtree into the image it last painted |
| `CompareUtils` | four comparison functions with names |
| `IsBuildingExtension` | is a frame being built, and how to wait for the end of it |

## Listening to a Listenable

`addListener` and `removeListener` require keeping the callback around, which
is why a closure cannot be unsubscribed without storing it somewhere. `listen`
returns the subscription instead, the way `Stream` does:

```dart
final subscription = counter.listen(() => print(counter.value));
…
subscription.cancel();
```

`CompositeListenableSubscription` collects several of them and cancels the lot
in one call.

`select` narrows the callback to one value:

```dart
final subscription = model.select(
  (model) => model.userName,
  (model, userName) => print(userName),
);
```

The listener runs only when the selected value changes. By default that means
`!=`, and `compare:` replaces the test with one of your own. It answers the same
question, so `true` means changed: `notIdentical` for a value that is replaced
rather than mutated, a field-by-field comparison for a record, and so on.
Passing `identical` there reports the opposite of what it is asked — the same
object counts as a change and a replacement goes unnoticed. This is the same
idea `select` uses on a scope, without a widget tree involved.

`ListenableSelector` is the widget wrapping the same mechanism:

```dart
ListenableSelector<Counter, int>(
  listenable: counter,
  selector: (counter) => counter.value,
  builder: (context, counter, value, child) => Text('$value'),
);
```

The `child` it takes is passed back to `builder` untouched, the standard way of
keeping a subtree out of the rebuild.

`ListenableView` wraps a `Listenable` so that only `addListener` and
`removeListener` are reachable — hand it out when the subtree may listen but
must not notify. `ScopeStateModelView` in the `ScopeNotifier` topic is the same
idea applied to a state model.

`StateAsNotifier` goes the other way: mix it into a `State` and the state
itself becomes a `Listenable`, with a `notifyListeners()` for its own use. The
`ChangeNotifier` behind it is created on the first listener and disposed of with
the state, so a state nobody listens to costs nothing.

## NavigationNode

A nested `Navigator` whose routes stay inside the current scope. A dialog, a
bottom sheet or a pushed screen opened through it is built below the scope
rather than above it, so everything the scope provides is still reachable from
those routes — which is not true of the root navigator of an application.

```dart
NavigationNode(child: const ScreenBody())
```

`navigatorKey` exposes the inner `NodeNavigatorState` when a caller needs to
push from outside. It is fixed for the lifetime of the node — it is the key the
nested navigator is built with, so another one would mean another navigator and
an empty stack — and handing over a different one is refused by an assertion.
Hold it in a `State` field rather than writing `GlobalKey()` inside `build`.

`isRoot` marks a node that must not forward a pop any further. `onPop`
intercepts the system back gesture: return `true` to let the pop through,
`false` to keep the route, or a `Future<bool>` to decide after asking something
— a confirmation dialog, typically.

An asynchronous `onPop` is asked once at a time: a back press arriving while an
answer is still pending is dropped rather than starting a second question. And
an answer is only acted on if it still applies — if the route the node sits on
was closed by something else, or buried under a newer one, a `true` takes
nothing, since a pop would otherwise take whatever is on top instead of what
was asked about.

System back first asks the node's nested navigator to close its top route. Only
when that navigator has nothing left to pop do `onPop` and `isRoot` decide what
happens outside the node. The two never compete: on a root node the hook is
asked as it is anywhere else, and an answer of `true` still takes nothing, since
a root node has nothing outside it to let the pop through to. Such a hook is
there for the press itself — a "press again to exit", or a `SystemNavigator
.pop()` the application makes on its own terms.

A node never empties itself. `Navigator.pop()` on its first page — from the back
arrow of an `AppBar`, say — leaves the node instead of taking that page away: an
ordinary node hands the pop to the navigator above it, as often as it is asked,
and a root node keeps it and does nothing.

Nor does it empty the navigator above. A node placed on the first route of the
application has nothing outside it to hand a pop to, and hands over nothing —
whichever way the pop reached it. `isRoot` is still worth setting there: it says
so at the node rather than leaving it to be discovered from the stack.

`PreviousNavigatorExtension.previous` gives the navigator above a given one,
which is how a node forwards a pop it cannot handle itself.

## ProgressIterator

Step counting for an initialization that knows how many steps it has:

```dart
final progress = ProgressIterator(3);

progress.nextStep(); // 1/3
progress.nextStep(); // 2/3
progress.add(1);     // 3/3
progress.isCompleted; // true
```

`Progress` is the value it produces: `number`, `total`, `progress` as a
fraction between 0 and 1, and a `toString` of `2/3`. The fraction holds those
bounds whatever the pair says: a task of no steps at all reads as complete
rather than as the `NaN` of `0 / 0`, so it can go straight into a
`LinearProgressIndicator`. Stepping past the total is a mistake in the caller
and is caught by an assertion.

Reporting these from an initialization is the `AsyncScope` topic;
`ScopeAutoDependencies` uses exactly this to report a step per dependency — see
the `Scope` topic.

## ScreenshotReplacer

Renders its child once, captures what was painted, and then shows the image in
its place. The package uses it for `close()`: the last frame of a scope is
frozen while the asynchronous disposal runs, so the closing screen is drawn
over a still picture rather than over a subtree that is being torn down.

```dart
ScreenshotReplacer(
  onCompleted: () => print('captured, or given up on'),
  child: const HomeScreen(),
);
```

A subtree that is never painted — inside an `Offstage`, or in the unselected
branch of an `IndexedStack` — cannot be captured. The attempt is therefore
bounded by `ScreenshotReplacer.maxRetries` frames, after which `onCompleted` is
called anyway and the live child stays in place. `onCompleted` fires exactly
once per state, whichever way it ended, including when the widget is removed
from the tree first.

## The two small ones

`CompareUtils` is `equals`, `notEquals`, `identical` and `notIdentical` as named
functions, for the places that take a comparison as a parameter — `compare:`
above, among others — where a tear-off reads better than a lambda.

`IsBuildingExtension` extends `SchedulerBinding`. `isBuilding` says whether a
frame is currently being built, and `runOutsideFrame(action)` runs the action
now if it is safe, or in a post-frame callback if a frame is in progress. This
is what a scope uses to keep a notification out of the middle of a build.

## Where to go next

| topic | what it covers |
| --- | --- |
| `ScopeNotifier` | the scope form of `select`, and the state models |
| `Scope` | `ProgressIterator` in the dependency container, and `close()` |
| `LiteScope` | `close()` and the screenshot in their own family |
