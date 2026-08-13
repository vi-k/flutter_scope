# scopo_demo

Every scope family, side by side, with a console showing what each one does as
it does it.

```sh
cd example/scopo_demo
flutter run
```

## The layout

Nine tabs, one per family plus two scenarios that need a screen of their own:

| tab | what it demonstrates |
| --- | --- |
| ScopeWidget | a scope over the widget's own parameters, and per-parameter subscriptions |
| ScopeModel | owning a plain object: `create`/`dispose`, `.value`, a named scope |
| ScopeNotifier | the same for a `Listenable`, with selectors filtering the rebuilds |
| AsyncScope | asynchronous initialization and disposal without a container |
| AsyncDataScope | the same, producing a value the subtree reads |
| LiteScope | a state class with the full lifecycle |
| Scope | the full family: a dependency tree, progress per dependency, a state |
| Deferred closing | `close()`: the closing screen over a frozen subtree |
| NavigationNode | a nested `Navigator` whose routes stay inside the scope |

Under each demo is a **console**. It prints the lifecycle calls of the scopes
on that tab as they happen — mounting, initializing, progress, ready,
disposing, disposed — which is the point of the app: the order of those lines
is the behaviour the package is about, and it is hard to see any other way.

## The three examples of each asynchronous tab

The AsyncScope, AsyncDataScope, LiteScope and Scope tabs each hold three
examples, and the difference between them is the whole lesson:

1. **no `scopeKey`** — recreating the scope starts the new one while the old
   one is still disposing of itself; the console shows the two overlapping;
2. **with a `scopeKey`** — the new scope waits in the queue, and the console
   shows it starting only after the previous one has finished;
3. **`scopeKey` + parent and child** — a parent scope waits for its child
   before disposing of itself, so the lines come out inside-out on the way
   down.

Each example has a button that recreates its scope, which is how the three
sequences above are produced.

## Deferred closing and NavigationNode

**Deferred closing** is `close()` with a visible delay: the ready subtree is
frozen into a screenshot, the closing screen is drawn on top of it, and the
button returns only when the disposal is over. It is the tab to look at before
using `close()` for anything real.

**NavigationNode** pushes screens, dialogs and bottom sheets through a nested
`Navigator`, and lets them read the scope above — which is what the root
navigator of an application cannot do. The child screen reads a counter from a
scope that lives outside the route.

## Related

The families are described one topic per page in the
[documentation](https://pub.dev/documentation/scopo/latest/); `example/minimal`
is the same ideas at one tenth the size.
