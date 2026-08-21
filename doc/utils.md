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
| `IsBuildingExtension` | is a build running, and how to wait for the end of it |

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
— a confirmation dialog, typically. The context it is given is one from inside
the node, so `showDialog(useRootNavigator: false)` puts that dialog in the node,
below everything the node stands under.

An asynchronous `onPop` is asked once at a time: a back press arriving while an
answer is still pending is dropped rather than starting a second question. And
an answer is only acted on if it still applies — if the route the node sits on
was closed by something else, or buried under a newer one, a `true` takes
nothing, since a pop would otherwise take whatever is on top instead of what
was asked about.

Anything that falls over on the way — the question itself, or a guard the
application put on the route, which is read when the node asks what a pop there
would do — is reported through `FlutterError.reportError` rather than left in a
chain nobody holds, where it would surface as an unhandled zone error far from
the widget that caused it. The press is simply not acted on, and the next one is
asked as usual.

System back first asks the node's nested navigator to close its top route —
and "route" includes what a `Drawer` or a `showBottomSheet` puts on the page
without pushing anything, so a node takes none of that away. Only when that
navigator has nothing left to pop do `onPop` and `isRoot` decide what
happens outside the node. The two never compete: on a root node the hook is
asked as it is anywhere else, and an answer of `true` still takes nothing, since
a root node has nothing outside it to let the pop through to. Such a hook is
there for the press itself — a "press again to exit", or a `SystemNavigator
.pop()` the application makes on its own terms.

A node never empties itself. `Navigator.pop()` on its first page — from the back
arrow of an `AppBar`, say — leaves the node instead of taking that page away: an
ordinary node hands the pop to the navigator above it, as often as it is asked,
and a root node keeps it and does nothing.

Nor does it empty the navigator above, or overrule it. Handing a pop over is
asking, not taking: a node placed on the first route of the application has
nothing outside it to hand a pop to and hands over nothing, and a `PopScope` the
application put around the node is answered by the application, not walked past.
`isRoot` is still worth setting on a node that is the first route: it says so at
the node rather than leaving it to be discovered from the stack.

An `AppBar` on the node's first page draws a back arrow, and pressing it leaves
the node. That is the node's doing: the page is the first route of its own
navigator, so nothing about that navigator implies a way back. A root node draws
no arrow there, since it keeps a pop to itself and there would be nowhere to go.

`onPop` answers a pop the route is *asked* about, which is more than the system
back and less than every pop. The node is a `PopEntry` of the route it stands
on, so `Navigator.maybePop()` and the back arrow of an `AppBar` above the node
reach the hook as much as a system back does. `Navigator.pop()` does not: it
takes the route rather than asking it, and no `PopEntry` is consulted. A button
of your own that has to go through the hook wants `maybePop`.

A node stands aside for a press the route will handle by itself. A `Drawer` or a
`showBottomSheet` above the node puts a local history entry on the route the
node stands on, and a route asks its `PopEntry`s before it looks at that entry —
so a node that always said "do not pop" took a press whose whole job was to
close a drawer, and with an `onPop` that refused, the drawer could not be closed
with back at all. `ModalRoute.willHandlePopInternally` is what the node reads,
at press time, and it means "somebody else's entry": the node gave up keeping
one of its own precisely because a route reports only whether that list is
empty.

**`enabled` is for several nodes on one route**, of which one is on screen: a
node per tab of an `IndexedStack`, which builds every branch and shows one. A
route asks each of its `PopEntry`s and calls each of them back, so one press
unwound the stack of every tab at once, the hidden ones included. Which node is
the one on screen cannot be worked out from inside — a hidden branch answers
`TickerMode.of(context)` and `ModalRoute.of(context)` exactly as a shown one
does — so the application says it:

```dart
NavigationNode(enabled: i == _tab, child: tabs[i])
```

A disabled node takes no place on the route: it is not asked and it is not
called back, while its nested navigator keeps its stack and goes on answering
`Navigator.of(context)` from inside. Nodes nested one inside another never need
this — an inner node registers on the page of the navigator above it rather than
on the route both stand on. The ambiguity is Flutter's own: two `PopScope`s on
one route are both consulted.

`PreviousNavigatorExtension.previous` gives the navigator above a given one,
which is how a node forwards a pop it cannot handle itself.

## ProgressIterator

Step counting for an initialization that knows how many steps it has:

```dart
final progress = ProgressIterator(3);

progress.nextStep(); // 1/3
progress.nextStep(); // 2/3
progress.addSteps(1); // 3/3
progress.isCompleted; // true
```

`Progress` is the value it produces: `number`, `total`, `value` as a
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
called anyway — and the child is taken away all the same, with nothing in the
picture's place. Giving up on the picture is not giving up on replacing the
child: what waits on `onCompleted` waits in order to let go of whatever the
child holds, and a child left standing gives that caller the report without the
thing it was reported for. `onCompleted` fires exactly once per state,
whichever way it ended, including when the widget is removed from the tree
first.

## The two small ones

`CompareUtils` is `equals`, `notEquals`, `identical` and `notIdentical` as named
functions, for the places that take a comparison as a parameter — `compare:`
above, among others — where a tear-off reads better than a lambda.

`IsBuildingExtension` extends `SchedulerBinding`. `isBuilding` says whether a
build is running, and `runOutsideFrame(action)` runs the action now if it is
safe, or in a post-frame callback if one is. This is what a scope uses to keep
a notification out of the middle of a build.

A build is not only what a frame runs: `runApp` builds the first tree with no
frame in progress, and marking an element dirty from inside *that* is refused
just the same. `isBuilding` therefore adds two sources to the frame phase — the
rebuilds of this package's own scopes, which it counts itself, and the build
owner's flag, which it can only ask behind an assertion because that is the
only place the flag exists. So the one case left unanswered is a build that
neither belongs to a frame nor to this package, in a release build.

## Where to go next

| topic | what it covers |
| --- | --- |
| `ScopeNotifier` | the scope form of `select`, and the state models |
| `Scope` | `ProgressIterator` in the dependency container, and `close()` |
| `LiteScope` | `close()` and the screenshot in their own family |
