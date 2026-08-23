# base

Every scope family of this package — `ScopeWidgetBase`, `ScopeModel`,
`ScopeNotifier`, `AsyncScope`, `AsyncDataScope`, `AsyncControllerScope`,
`LiteScope` and `Scope` — stands on the same three types. Together they say what a scope is to the widget
tree: an `InheritedWidget` that can be found from below, an element that owns
whatever the scope holds, and one lookup protocol shared by all of them.

| type | what it is |
| --- | --- |
| `ScopeInheritedWidget` | the `InheritedWidget` every scope widget descends from |
| `ScopeContext` | the lookup protocol: `of`, `maybeOf`, `select` |
| `ScopeInheritedElement` | what the element of a scope has to provide |

An application never instantiates them. The layer is still worth reading twice
over: it is where the difference between `of`, `select` and `listen: false` is
decided — identically in every family — and it is the contract to implement
when writing a scope of your own.

## The widget

```dart
abstract base class ScopeInheritedWidget extends InheritedWidget {
  final Object? tag;

  const ScopeInheritedWidget({super.key, this.tag, super.child});
}
```

`tag` names one particular scope. Two scopes of the same type are otherwise
indistinguishable in the output, where an untagged scope appears as
`CounterScope(#4e0b7)` and a tagged one as `CounterScope(cart)` — see the
`debug` topic for the format. Every family forwards a `tag` parameter to this
constructor, so any scope can be tagged.

The `child` needs a word of warning, because it is not what a scope displays. A
plain `InheritedWidget` wraps a subtree passed to it; a scope builds its own
through `buildChild()`, which is where the waiting, initializing, error and
closing branches of the richer families come from. The constructor still
accepts a `child`, so a family that wants the plain behaviour can pass one and
use it from `buildChild()`; nothing in the package does. The default is a
placeholder that refuses to create an element at all — if a scope ever builds
that `child` instead of its own, the failure is immediate rather than subtle.

## The element

```dart
abstract interface class ScopeInheritedElement<W extends ScopeInheritedWidget>
    implements ScopeContext<W> {
  W get widget;

  @mustCallSuper
  void init();

  @mustCallSuper
  void dispose();

  Widget buildChild();
}
```

`init()` runs once, after the element is mounted and before its first
`buildChild`. If it throws, that is the end of the scope: the hook is not
attempted again, the scope shows an error instead of its subtree, and every
later build reports the same failure. `dispose()` runs when the element is
unmounted, and it runs after a failed `init()` too — an attempt that gave up
halfway may already hold something, and this is where it is given back, so a
family disposer has to expect a partially initialized scope. Both are
`@mustCallSuper`: a family that overrides them extends the lifecycle rather
than replacing it. The mounted element is connected to its ancestors, so an
`init()` hook may look one up with `listen: false`; subscribing from the hook
is not supported and an assertion says so. Everything a scope owns — a model, a
notifier subscription, a dependency container, a place in the queue of a
`scopeKey` — is acquired in the first and released in the second.

The element is also the `ScopeContext` of its own scope: what a descendant
receives from `of` is this object, which is why `select` can read the current
value straight from it.

The bookkeeping behind all of that — the per-dependent subscriptions, the
rebuild that only notifies instead of rebuilding the subtree — lives in
`ScopeWidgetElementBase`, described in the `ScopeWidget` topic. Implementing
`ScopeInheritedElement` from scratch is not the intended path; extending that
class is.

## Finding a scope

Three entry points, all static on `ScopeContext`, where `W` is the widget type
and `C` is the context type of the family:

```dart
ScopeContext.maybeOf<W, C>(context, listen: false); // C?, null if not found
ScopeContext.of<W, C>(context, listen: false);      // C, throws if not found
ScopeContext.select<W, C, V>(context, selector);    // V, throws if not found
```

In practice these are called through the wrapper each family exposes, so that
the type arguments stay short and correct:

```dart
final config = ScopeWidgetBase.of<ApiConfig>(context, listen: false);
final apiKey = ScopeWidgetBase.select<ApiConfig, String>(
  context,
  (widget) => widget.apiKey,
);
```

The search itself is `getElementForInheritedWidgetOfExactType<W>()`: ancestors
only, and the **exact** type — a scope declared as `class CartScope extends
ShopScope` is not found by asking for `ShopScope`. Looking a scope up never
rebuilds anything by itself; what a caller subscribes to is decided by the
argument below.

## listen, and what it costs

`listen: false` looks the scope up and subscribes to nothing. The caller is
never rebuilt because of that scope. This is what code outside `build` wants —
a button handler reaching for a service, a callback reading the current state
once:

```dart
onPressed: () => ScopeModel.of<Cart>(context, listen: false).clear(),
```

`listen: true` subscribes to **every** change of that scope. The dependent is
rebuilt whenever the scope notifies, whether or not anything it reads has
changed.

`select` subscribes to one value and is the reason a scope can serve a large
subtree cheaply. It has no `listen` parameter — selecting is listening — and no
`maybe` variant: a missing scope is an error rather than a null.

## What select actually does

```dart
final userName = ScopeModel.select<Session, String>(
  context,
  (session) => session.userName,
);
```

The selector runs immediately, and the pair `(value, selector)` is stored as
the dependent's subscription. When the scope later notifies, every stored pair
of every dependent is re-evaluated: the dependent is rebuilt only if
`selector(scope) != value` for at least one of them. A widget that selected
`userName` sleeps through a change of `cartTotal`.

Five consequences are worth keeping in mind.

**The comparison is `!=`,** so the `==` of the selected value decides
everything. Select a field, a record or an immutable value. A selector that
builds a fresh `List` or a new object on every call compares unequal every
time, and the widget rebuilds as if it had never selected at all.

**Selectors accumulate.** Several `select` calls in one `build` create several
subscriptions, and a change in any of them rebuilds the widget once. Reading
three fields of a model is three selects, not one selector returning three
values in a list — see above for why the list would be worse.

**`of(..., listen: true)` wins over any `select` in the same build.** It
subscribes to everything, and a subscription to everything cannot be narrowed
by adding a selector to it — in either order, the widget ends up rebuilt on
every notification. Use one or the other for a given scope in a given `build`.

**The captured value is refreshed on every build.** Subscriptions are
re-established while the dependent builds, as they are anywhere in Flutter, so
the pair a scope compares against is the one from the dependent's latest build,
not from its first.

**A subscription may only be taken from a build**, and an assertion says so.
What a dependent asked for is remembered per build, and the boundary between
one build and the next is taken from the frame — Flutter offers no hook for
"this dependent is about to build". A registration made outside a build
therefore belongs to whichever build shares its frame, and is dropped by the
first build that does not: `didChangeDependencies` runs in the same frame as
the build after it, so a `select` there looks like it works and then
disappears on the first rebuild that comes from the parent rather than from a
change. To react to a change rather than to show it, keep the subscription in
`build` and look the scope up with `listen: false` from
`didChangeDependencies`.

**The builder of a `LayoutBuilder` counts as a build**, and so do those of
`OrientationBuilder` and `SliverLayoutBuilder`: they run from `performLayout`,
inside a build of their own element, and what they return is that element's
subtree. `select` there is honoured like any other, and the assertion lets it
through. The one place it can no longer tell the mistake from the pattern is a
`didChangeDependencies` of a widget that is itself under a layout callback.

## Depending on itself

A scope element may subscribe to its own scope — that is how the richer
families rebuild their own subtree as the initialization advances.
`InheritedElement` forbids it (an assert in `notifyClients` blocks a self
dependency), so those subscriptions are kept apart from the rest and notified
separately. The mechanism belongs to `ScopeWidgetElementBase`; it matters here
only as the reason `ScopeInheritedElement` is an interface a family implements
rather than a mixin an application applies.

## Errors

Both failures are plain exceptions carrying the type that was asked for:

```text
Exception: CounterScope not found in the context
```

`of` and `select` did not find the widget above the context. Either the scope
is genuinely not there, or the context belongs to a widget above it rather than
below — the usual mistake being a lookup from the very `build` that installs
the scope. `maybeOf` returns `null` in the same situation and is the right call
when absence is expected.

A lookup with `listen: true` that found nothing is still remembered as a
dependency, exactly as Flutter's own `dependOnInheritedWidgetOfExactType` would
remember it. A widget that asked when there was no scope above it and is later
carried under one — by a `GlobalKey` — is therefore told its dependencies have
changed and asks again.

```text
Exception: The element of ScopeModel<Counter> is not ScopeModelContext<ScopeModel<Counter>, Counter>
```

The widget was found, but its element is not the context type the call asked
for. This is a mismatch of type arguments — a family's accessor used against a
scope of a different family.

## Accessors and editor templates

Every family finds its scope through statics that take the family's type
arguments — `Scope.select<App, AppDependencies, AppState, V>(context, selector)`
and its four neighbours. Written out as wrappers on the scope, that is the
triple repeated five times per scope.

Each family also ships an accessor object that takes those arguments once:

```dart
final class App extends Scope<App, AppDependencies, AppState> {
  static const access = ScopeAccess<App, AppDependencies, AppState>();
}

final counter = App.access.select(context, (state) => state.counter);
```

It is a forwarder and nothing more — every method is the static of the same
name — so the two are interchangeable, and a scope that wants accessors under
its own names still writes them. The `README` of the package has the table of
all eight.

What is left to type is the class skeleton, and that comes with the package
too: `ide/scopo.code-snippets` for VS Code (and Cursor, Windsurf, Antigravity)
and `ide/scopo-live-templates.xml` for IntelliJ and Android Studio, both in the
package directory alongside `lib/`. Nine templates — one per family, one for a
dependency container, one for the accessor line:

```json
"scopo: The accessor object": {
  "scope": "dart",
  "prefix": "scopo-access",
  "body": ["static const access = ScopeAccess<${1:Widget}>();$0"]
}
```

`ide/README.md` says where each file goes. The skeletons they insert are
compiled by the package's own gate; the live templates are not run by anything,
so an import is what proves them.

## Where to go next

| topic | what it covers |
| --- | --- |
| `ScopeWidget` | the element base every family extends: subscriptions, notify-only rebuilds |
| `ScopeModel`, `ScopeNotifier` | scopes that own a plain object or a `Listenable` |
| `AsyncScope`, `AsyncDataScope` | asynchronous initialization and disposal |
| `AsyncControllerScope` | a scope whose whole content is a controller with a lifecycle of its own |
| `LiteScope` | a scope without a dependency container |
| `Scope` | the full family: dependencies, state, and the four build branches |
| `debug` | the observer, timeouts and what a `tag` looks like in the output |
