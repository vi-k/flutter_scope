# ScopeWidget

Two things live under this name. `ScopeWidgetBase` is the simplest scope of the
package, usable as it is: a widget that hands its own parameters to its subtree.
`ScopeWidgetCore` and `ScopeWidgetElementBase` are the pair every other family
extends — the place where subscriptions are kept, where `notifyDependents`
decides not to rebuild the subtree, and where a scope hooks into the element
lifecycle.

Read the first section to use the family. Read the rest when writing a scope of
your own, or when a scope rebuilt more — or less — than expected.

## ScopeWidgetBase

The parameters of a widget are already immutable data provided by an ancestor;
`ScopeWidgetBase` turns them into a scope so that descendants can subscribe to
one parameter at a time instead of rebuilding on every change of the widget.

```dart
final class ApiConfig extends ScopeWidgetBase<ApiConfig> {
  final String apiKey;
  final Uri baseUrl;

  const ApiConfig({
    super.key,
    super.tag,
    required this.apiKey,
    required this.baseUrl,
    required super.child,
  });

  static String apiKeyOf(BuildContext context) =>
      ScopeWidgetBase.select<ApiConfig, String>(
        context,
        (widget) => widget.apiKey,
      );

  @override
  Widget build(BuildContext context) => child;
}
```

`build` is what the scope shows — the same role `buildChild()` plays for the
other families. Returning the `child` the constructor took is the usual shape,
which is why `child` is declared `required` here: the base class allows it to be
omitted, and a scope that shows nothing is rarely what anyone wants.

Three accessors come from the base class, and all of them return the widget:

```dart
ScopeWidgetBase.of<ApiConfig>(context, listen: false);      // ApiConfig
ScopeWidgetBase.maybeOf<ApiConfig>(context, listen: false);  // ApiConfig?
ScopeWidgetBase.select<ApiConfig, String>(context, (w) => w.apiKey);
```

Re-exposing them as named statics, as `apiKeyOf` above, is worth the three
lines: the call site stops repeating type arguments, and the scope decides what
its subtree is allowed to read.

Where the values come from is the parent's business. When the parent rebuilds
`ApiConfig` with a different `apiKey`, the dependents that selected `apiKey` are
rebuilt and the ones that selected `baseUrl` are not — the filtering is
described in the `base` topic.

One trap is worth naming: the `context` handed to `build` is the scope's own
element. A lookup from it finds this very scope, so `ApiConfig.apiKeyOf(context)`
inside `build` subscribes the scope to itself, and a self-notification rebuilds
the whole subtree rather than a dependent. Read the parameters directly —
`apiKey` is a field, and `build` is a method of the same object.

## The pair behind every family

```dart
final class MyScope extends ScopeWidgetCore<MyScope, MyScopeElement> {
  const MyScope({super.key, super.tag});

  @override
  MyScopeElement createScopeElement() => MyScopeElement(this);
}

final class MyScopeElement
    extends ScopeWidgetElementBase<MyScope, MyScopeElement> {
  MyScopeElement(super.widget);

  @override
  void init() {
    // Acquire whatever the scope owns…
    super.init();
  }

  @override
  void dispose() {
    super.dispose();
    // …and release it here.
  }

  @override
  Widget buildChild() => const SizedBox.shrink();
}
```

Both hooks are `@mustCallSuper`, and the order above is the one the package's
own families keep: acquire before `super.init()`, release after
`super.dispose()`. The two halves mirror each other, so whatever a layer owns
outlives everything the layers under it set up.

That is the whole contract: a widget that knows how to create its element, and
an element that knows what to build. `ScopeWidgetBase` is exactly this, with
`buildChild()` delegating to the `build` of the widget. Everything else the
package offers — a model, a notifier, an asynchronous initialization, a
dependency container — is added on top of the same two classes.

`updateShouldNotify` returns `true` unconditionally, which sounds wasteful and
is not: it only means the element is asked to notify its dependents, and each
dependent is then filtered by its own selectors. A scope has no way to know
what its descendants care about, so the decision belongs to them.

## notifyDependents

`notifyDependents()` tells the subscribed descendants that something changed
**without rebuilding the subtree**. It is what makes a scope affordable for
values that change often:

```dart
@override
void init() {
  model.addListener(notifyDependents);
  super.init();
}
```

That is `ScopeNotifier` in full — every `notifyListeners()` of the model becomes
a notification, and only the widgets whose selected value actually changed are
rebuilt. The state of a `Scope` or a `LiteScope` calls the same method by hand
after mutating itself.

The mechanism is worth knowing because it explains the constraints. A dependent
is notified through `didChangeDependencies`, and that can only run while a frame
is being built. So the element marks itself dirty, and on the resulting rebuild
it notifies its clients and skips updating its child — the subtree keeps its
elements, its states and its scroll positions untouched.

## When the subtree is rebuilt anyway

Three cases override the notify-only path, and each is deliberate.

**The parent updated the scope widget.** A new widget can mean new parameters
and a different `buildChild()`, so the subtree is rebuilt even if a
notify-only rebuild was already pending.

**The scope declared `autoSelfDependence`.** An element that rebuilds its own
subtree as its state advances cannot use the shortcut, because its `buildChild`
returns a different branch each time. `AsyncScope` sets it for good.
`LiteScope` is more precise: it starts with the flag on, while the waiting,
initializing and error branches replace one another, and clears it in
`buildOnReady()` — from the moment the ready branch is on screen, notifications
stop rebuilding the subtree.

**A self-dependency fired.** An element may subscribe to its own scope;
`InheritedElement` refuses to record that (an assert in `notifyClients`), so
those subscriptions are kept in a separate list and notified before the others.
When one of them changes, the subtree is rebuilt — the element that selected the
value is the element that builds the subtree.

## Names in the log

`toStringShort` of a scope widget is `MyScope(#4e0b7)`, or `MyScope(cart)` when
a `tag` was given; the element prints its own type and hash. The logger of a
scope takes its name from the first, which is why a `tag` is the cheapest way to
tell two scopes of the same type apart in the output. The `debug` topic has the
format.

## Where to go next

| topic | what it covers |
| --- | --- |
| `base` | the lookup protocol these classes implement: `of`, `select`, `listen` |
| `ScopeModel`, `ScopeNotifier` | the first two families built on this pair |
| `Scope` | the full family, and what `notifyDependents` means for a state |
| `debug` | the log, and what a `tag` does to it |
