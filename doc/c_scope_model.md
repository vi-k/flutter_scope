# ScopeModel

A scope that owns one plain Dart object and hands it to its subtree. No
asynchronous phase, no dependency container, no state class: the object is
created when the scope is mounted and released when it leaves the tree.

Use it for anything the tree should own but nothing observes automatically — a
repository, a controller, a service, a form model. When the object is a
`Listenable` and its changes should reach the subtree by themselves, use the
`ScopeNotifier` topic instead; it is this family plus a subscription.

## The three levels

| class | when |
| --- | --- |
| `ScopeModel<M>` | the usual case: a widget with `create`, `dispose` and `builder` |
| `ScopeModelBase<W, M>` | a named scope of your own, with its own accessors |
| `ScopeModelCore<W, E, M>` | an element of your own; the base of the two above |

### ScopeModel

```dart
ScopeModel<Cart>(
  create: (context) => Cart(),
  dispose: (cart) => cart.close(),
  builder: (context) => const CartScreen(),
);
```

`builder` deliberately receives only a context. That context belongs to the
scope's element, so the model is already available through `ScopeModel.of`
and `ScopeModel.select`, with the same lookup and subscription rules that
descendants use. `dispose` runs at the other end of the lifecycle, outside a
build; the element already owns the exact model it created, so it hands that
instance to the callback directly instead of asking teardown code to look it
up through the tree.

`create` runs after the element is mounted, before its first subtree build. If
it throws, the next build retries it; after the first successful return it does
not run again. `dispose` runs once when that successfully-created model's
element is unmounted; a failed `create` attempt has no model to hand to
`dispose`. The `context` handed to `create` is the scope's own element, so an
ancestor scope can be read from it —
`ScopeModel.of<Session>(context, listen: false)` — but with `listen: false`
only: `create` runs outside a build, and a subscription taken there would have
nothing to rebuild.

`ScopeModel.value` takes a model somebody else owns:

```dart
ScopeModel.value(value: cart, builder: (context) => const CartScreen());
```

There is no `dispose` on that constructor at all, and it is not an omission:
whoever created the object disposes of it. The scope only provides it.

Descendants read the model through the same three accessors, and here they
return the model itself rather than a context:

```dart
final cart = ScopeModel.of<Cart>(context, listen: false);
final total = ScopeModel.select<Cart, int>(context, (cart) => cart.total);
```

### ScopeModelBase

Subclass it when the scope deserves a name and its own vocabulary:

```dart
final class CartScope extends ScopeModelBase<CartScope, Cart> {
  const CartScope({
    super.key,
    super.tag,
    required super.create,
    required super.dispose,
    required super.child,
  });

  @override
  Widget build(BuildContext context) => child;

  static Cart of(BuildContext context) =>
      ScopeModelBase.of<CartScope, Cart>(context, listen: false).model;

  static int totalOf(BuildContext context) =>
      ScopeModelBase.select<CartScope, Cart, int>(
        context,
        (scope) => scope.model.total,
      );
}
```

Two differences from `ScopeModel` are worth noticing. `build` is yours, so the
scope decides what it shows instead of taking a `builder`. And the accessors of
the base class return a `ScopeModelContext<W, M>` — the element — so a selector
reads `scope.model` rather than the model directly. Wrapping them in named
statics hides both details from the call site.

`ScopeModelCore` sits under all of this for the case where the element itself
has to be replaced; `ScopeNotifier` is exactly that case.

## What notifies whom

The model is not observed. Nothing inside it can tell the scope that something
changed — mutating a field of `Cart` reaches no descendant on its own.

What the scope does notify on is its own rebuild: when the parent rebuilds the
`ScopeModel` widget, the dependents are notified and their selectors decide who
is actually rebuilt. So a value that changes has to travel through the widget:

```dart
ScopeModel.value(value: cart, builder: (context) => const CartScreen());
```

with a `StatefulWidget` above holding `cart` and calling `setState` — the model
stays the same object, the scope widget is rebuilt, and only the descendants
whose selected value changed follow.

If that reads like a workaround, it is: a model that changes on its own belongs
in `ScopeNotifier`, where a `notifyListeners()` becomes a notification without
any rebuild above. `ScopeModel` is for objects that either do not change or
change only when the tree above them changes.

## Lifetime

`create` is called from `init()` once the element is mounted and before its
first subtree build, so a successfully-created model is ready for anything
below it. A thrown `create` is retried on the next build; after success it is
not called again.

`dispose` is called from `dispose()` of the element, after the base class has
run its own teardown. It is called only for a model the scope created — a
`.value` model is left alone.

The lifetime is the element's, not the widget's. A scope rebuilt with new
parameters keeps its model; a scope removed from the tree loses it. Moving a
scope with a `GlobalKey` moves the element and the model with it.

The disposal here is synchronous. When releasing the object needs an `await`,
this family is the wrong one: `LiteScope` gives a state with `disposeAsync`,
and `Scope` gives a dependency container whose `dispose` is awaited — and both
make a parent wait for their child scopes before tearing themselves down.

## In the debugger

The element adds the model to its diagnostics, so `debugDumpApp()` and the
widget inspector show `model: Cart(3 items)` — whatever the `toString` of the
model returns — next to the scope.

## Where to go next

| topic | what it covers |
| --- | --- |
| `ScopeNotifier` | this family plus a subscription to a `Listenable` |
| `base` | `of`, `select`, `listen`, and why a selector filters rebuilds |
| `ScopeWidget` | the widget/element pair this family extends |
| `LiteScope`, `Scope` | families whose teardown may be asynchronous |
