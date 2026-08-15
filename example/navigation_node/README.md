# navigation_node

`NavigationNode` in six lessons, with a system back you can press on a desktop.

```sh
cd example/navigation_node
flutter run
```

## The idea

A `Navigator` normally sits above every screen of an application. Anything it
pushes — a page, a dialog, a bottom sheet — is therefore built *above* that
screen, outside whatever the screen had set up around it.

`NavigationNode` puts a `Navigator` in the middle of the tree instead. Routes it
opens are built below that point, so everything the screen provides is still
reachable from them. The price of moving the navigator down is that the system
back gesture no longer starts there — and the node's job is to make it behave as
if it did.

## Pressing the system back

Every lesson carries a **System back** button, and pushed pages and dialogs
carry a smaller one. It is not a stand-in for the real gesture:

```dart
// ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
WidgetsBinding.instance.handlePopRoute();
```

The Android back button and back gesture arrive as a `popRoute` message on the
`flutter/navigation` channel, and the only thing the binding does with that
message is call `handlePopRoute`. Nothing downstream — `WidgetsApp`, `PopScope`,
`NavigationNode`, `onPop` — can tell the two apart. Flutter marks the method
`@visibleForTesting` because an application has no reason to raise a back
gesture against itself; demonstrating one is that reason, and it is why you
should not copy this line into an app of your own.

On macOS, which has no system back at all, this button is the only way to see
any of this; on Android the real gesture and the button do the same thing.

The button also reports what came back: `false` means nothing in the app handled
the press, which on a phone is the moment the app closes.

## The lessons

1. **Why a node at all** — the same push with and without a node. One is built
   above the screen and can no longer reach what the screen provides; the other
   lands inside the box, under the screen's scope. Each pushed page says which
   of the two happened to it.
2. **A dialog is a route too** — `showDialog(useRootNavigator: false)` belongs to
   the node: it is built under the screen, so the screen's scope is still there
   to read, and the system back closes it before anything outside hears it.
3. **A page inside can refuse** — the node asks its top page rather than closing
   it, so a `PopScope` on that page is obeyed and the back is spent.
4. **`onPop`: the last word** — asked exactly once, and only once the node has
   nothing of its own left to close. Return `false` to stay, `true` to let the
   pop travel outwards, or a `Future<bool>` to answer after asking the user.
5. **`isRoot` keeps a pop at home** — an ordinary node forwards a pop it cannot
   handle to the navigator above it; a root node keeps it. The two title bars
   say so before you press anything: one has a back arrow, the other has none.
6. **Nodes inside nodes** — a back passes down until it reaches the innermost
   node that has something to close. Everything above stays put.

## What to read while you press

The panel at the bottom of every lesson has two parts.

The line beside the button is Flutter's own `NavigationNotification`: it says
whether anything below can still close a route of its own. This is the very
signal the node reads before it decides whether the back belongs inside it.

Under it is the journal. `◀` marks the press, `↳` marks what answered it, and
plain lines are what the lesson did on its own. Reading the order is the point —
a back that closed an inner page and a back that asked `onPop` look identical on
screen.

Two more readouts sit inside the stages. Each page says whether the screen's
scope — a ticket number, standing in for the controller or repository a real
screen would own — is still an ancestor of it. And the title bar of a node's
first page carries a back arrow whenever the node has somewhere to forward a pop
to, which is the difference between an ordinary node and a root one, visible
without pressing anything.

## What this example leaves out

It uses one scope, a `ScopeModel` holding a ticket number, only to answer the
question a route can ask: am I under the screen or above it? The rest of scopo —
the other scope families, asynchronous initialization, `scopeKey`, deferred
closing — is the subject of [`scopo_demo`](../scopo_demo/README.md), whose
`NavigationNode` tab shows the same widget from the scope's side.

The topic behind all of this is the `utils` page of the
[documentation](https://pub.dev/documentation/scopo/latest/).
