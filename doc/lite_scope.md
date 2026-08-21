# LiteScope

A state class with the whole scope lifecycle behind it, and no dependency
container in front of it. `initState` and `dispose` as usual, plus an
asynchronous `initStateAsync` and a `disposeStateAsync` the scope waits for,
plus `notifyDependents`, `close()`, `scopeKey` and the waiting for child
scopes.

This is the family for per-screen state that owns things worth releasing
properly — controllers, subscriptions, a socket. `Scope` adds a dependency
container in front of the state; `AsyncScope` drops the state and keeps only
the lifecycle.

```dart
final class ScreenScope extends LiteScope<ScreenScope, ScreenScopeState> {
  const ScreenScope({super.key, super.scopeKey});

  @override
  Widget? buildOnWaiting(BuildContext context) => const SizedBox.shrink();

  @override
  ScreenScopeState createState() => ScreenScopeState();

  static ScreenScopeState of(BuildContext context) =>
      LiteScope.of<ScreenScope, ScreenScopeState>(context);
}

final class ScreenScopeState
    extends LiteScopeState<ScreenScope, ScreenScopeState> {
  final controller = ScrollController();

  @override
  Future<void> disposeStateAsync() async => controller.dispose();

  @override
  Widget build(BuildContext context) =>
      ListView(controller: controller, children: const [Text('item')]);
}
```

## The state

`LiteScopeState` is a `State` with five additions:

| member | what it is |
| --- | --- |
| `initStateAsync()` | asynchronous initialization, started once the state exists |
| `onUnmount()` | synchronous teardown, always before `disposeStateAsync()` |
| `disposeStateAsync()` | asynchronous teardown, awaited before the scope is gone |
| `notifyDependents()` | rebuild the subscribed descendants, not the subtree |
| `close()` | run the teardown while the scope is still on screen |

and three of its own properties: `params` — the scope widget, so its
constructor parameters are readable from the state; `isInitialized`; and
`onInitialized()`, the hook called once the initialization has fully completed.

`State.widget` is not among them, and it never will be: a scope state has no
widget of its own — `params` is the scope widget, and that is the whole answer.
Reading `widget` throws an `UnsupportedError` saying so, which is what a `State`
mixin written for ordinary widgets runs into.

The ordinary `initState` of a `State` still works and still runs synchronously,
and `initStateAsync` is where an `await` belongs. `disposeStateAsync` is what makes a
parent scope — and `close()` — wait for the release to finish rather than fire
and forget it.

**`dispose` is the one to be careful with.** It belongs to Flutter, not to the
scope, and it is not part of the teardown order below: when the scope is
removed from the tree the framework calls it before the scope's own teardown
even begins, and after a `close()` it does not run until the tree comes down —
which may be much later, or never while the closing screen is on show. So the
synchronous half of a scope's teardown goes in `onUnmount()`, which the scope
itself drives:

```dart
@override
void onUnmount() {
  _subscription.cancel();   // must stop reaching this scope, now
  super.onUnmount();
}

@override
Future<void> disposeStateAsync() => _connection.close();   // may take its time
```

`onUnmount()` runs exactly once and always before `disposeStateAsync()`, whichever
way the scope goes. The `BuildContext` is gone by the time it runs on a removed
scope, so it may only touch what the state holds in its own fields.

## Two initializations

There are two phases, and they are not the same thing.

`LiteScope.initScope()` on the **widget** is a pre-initialization: a stream of
`AsyncScopeInitState`, exactly as in the `AsyncScope` topic, running *before*
the state is created. Its default yields `AsyncScopeReady()` at once, which is
why most scopes never override it. Override it when something has to be ready
before `createState`, and then `buildOnProgress` and `buildOnError` have to
be overridden too — their default implementations throw
`UnimplementedError`, on the reasoning that a progress branch nobody wrote is a
mistake rather than a blank screen.

`LiteScopeState.initStateAsync()` on the **state** is the usual one, and it runs
after the state exists — which is why **nothing waits for it**. The state is
created by the ready branch, so by the time this can start, the ready branch has
already built: the first `build` of the state runs before `initStateAsync` has
finished, and so do the ones any change asks for in the meantime.

That makes `isInitialized` part of writing the state rather than a detail:
a `late` field assigned after an `await` and read straight from `build` throws a
`LateInitializationError` on that first build. Either hold the branch back
yourself —

```dart
@override
Widget build(BuildContext context) {
  if (!isInitialized) {
    return const Center(child: CircularProgressIndicator.adaptive());
  }
  …
}
```

— or give the field a value it can be read with before the initialization
replaces it. `onInitialized()` is the other half: it runs once
`initStateAsync()` has finished, and only while the state is still on the tree,
so it is where a first `notifyDependents()` or an animation belongs. Put
whatever has to be ready *before* anything is shown into `initScope()` on the
widget instead, which is the phase that does hold the ready branch back.

`buildOnWaiting` covers the gap before either of them has produced anything —
the frames spent waiting for a `scopeKey` and for the first event. Returning
`null` from it is allowed only when `buildOnProgress` is overridden, since
something has to be on screen.

That is why `buildOnWaiting` is the one builder a `LiteScope` must write, which
is the other way round from `Scope` and the asynchronous families, where
`buildOnProgress` is the required one. The rule behind both is the same:
**exactly one branch before the ready one has to be written, and it is the one
the family is certain to reach.** A `Scope` always initializes a container, so
it always has a progress branch and may skip the waiting one; a `LiteScope`
initializes nothing of its own, so what it always has is the wait. Moving a
screen from `Scope` to `LiteScope` therefore trades one required builder for
another: `buildOnProgress` and `buildOnError` become optional — keep them
only if you override `initScope()` — and `buildOnWaiting` becomes required.

`wrapState` wraps the ready branch alone, so a widget every branch needs is
built inside each builder instead.

## Access from the subtree

```dart
ScreenScope.of(context).controller;                    // the state
LiteScope.select<ScreenScope, ScreenScopeState, int>(  // one value from it
  context,
  (state) => state.itemCount,
);
LiteScope.paramsOf<ScreenScope, ScreenScopeState>(context, listen: false);
LiteScope.selectParam<ScreenScope, ScreenScopeState, Object?>(
  context,
  (widget) => widget.scopeKey,
);
```

`of` and `maybeOf` return the state and never subscribe — they are for calling
methods. `select` subscribes to one value derived from the state, and the
caller is rebuilt only when that value changes **and** only when the state
called `notifyDependents()`. Nothing else in the state is observed: a field
mutated without that call reaches nobody.

`setState` is the other half, and nothing here takes it away — a scope state is
an ordinary `State` and keeps it. The two do not overlap, which is the part an
analogy with `StatefulWidget` gets wrong: `notifyDependents()` rebuilds the
subscribers and leaves this state's own `build` unrun, while `setState`
rebuilds what this state's `build` returns and reaches no subscriber. A field
both sides read wants both calls; a field only one side reads wants only its
own.

`paramsOf` and `selectParam` do the same for the scope widget's own
parameters. Re-exposing all of this as named statics on the scope, as `of`
above, is the usual practice.

## close()

```dart
await ScreenScope.of(context).close();
```

`close()` starts the teardown while the scope is still on screen, and completes
when the disposal is over. The ready subtree is frozen into a screenshot,
`buildOnClosing` is shown on top of it, and the element stays mounted until the
end — which is the point: a scope that takes a noticeable time to release
things shows "closing…" instead of freezing on its last frame.

The screenshot is best-effort in a precise sense: it is installed only when the
scope is actually ready and still mounted, because in any other state nothing
would ever release the barrier and the future would hang. A subtree that is
never painted — inside an `Offstage`, or in the unselected branch of an
`IndexedStack` — cannot be captured either; after `ScreenshotReplacer.maxRetries`
frames `close()` proceeds, and the ready subtree is taken away all the same,
with nothing in the picture's place. It has to be: the whole point of waiting
for the screenshot is to let go of what the subtree holds, and a scope left
standing there keeps its own child scopes mounted and registered — this one
would then wait out its `waitForChildrenTimeout` for a child nobody had taken
away, and release what that child is still reading.

A closing build that fails does not hold the teardown up either. The barrier is
released by the `ScreenshotReplacer` that build mounts, so a `wrapState` or a
`buildOnClosing` that throws used to mean a `close()` that never completed and
four stages that never began. Such a failure now surfaces as the `ErrorWidget`
any failing build turns into, and the teardown behind it goes on.

The default closing overlay reads its colour from the theme **above** the
scope, which for a scope at the root of the application — one whose `wrapState`
builds the `MaterialApp` — is `ThemeData.fallback()`. Write `buildOnClosing`
there, which is what a root scope wants anyway.

Calling `close()` twice does not restart anything: the second call joins the
disposal already running rather than installing a second barrier.

## The teardown, and what waits for it

The order is the one from the `AsyncScope` topic, with the state's own steps in
it: `onUnmount()` of the state runs first, the pre-initialization is cancelled,
the child scopes are awaited (`waitForChildrenTimeout`), `disposeStateAsync()` of
the state runs, and the `scopeKey` is released last so that the next scope with
that key starts only when this one is finished.

Flutter's own `dispose()` of the state sits outside that sequence, on either
side of it depending on how the scope went: before all of it when the tree took
the scope down, after all of it when the scope closed itself. That is the whole
point of `close()` — release first, leave later — and it is why the teardown
the scope guarantees is the `onUnmount()`/`disposeStateAsync()` pair rather than
`dispose()`.

A `LiteScope` is an `AsyncScopeParent` like every asynchronous scope: the
scopes below it register with it, and it waits for them before disposing of
itself. Asking for that wait from a subtree is
`AsyncScopeCoordinator.waitForChildren` — the mixin itself sits on the element,
which is private here; see the `AsyncScope` topic.

## Where to go next

| topic | what it covers |
| --- | --- |
| `AsyncScope` | the lifecycle in full: states, teardown order, `scopeKey`, the coordinator |
| `Scope` | a dependency container in front of the same state |
| `ScopeWidget` | what `notifyDependents` does to the subtree |
| `debug` | the observer that reports every step, and the timeouts |
