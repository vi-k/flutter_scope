# ScopeNotifier

`ScopeModel` for a `Listenable`. Everything from that topic holds — `create`
and `dispose`, the `.value` constructor, the three levels of the family — with
one addition that changes how the scope is used: the element subscribes to the
model, so a `notifyListeners()` reaches the subtree without anything above the
scope being rebuilt.

```dart
ScopeNotifier<Counter>(
  create: (context) => Counter(),
  dispose: (counter) => counter.dispose(),
  builder: (context) => const CounterText(),
);
```

```dart
class CounterText extends StatelessWidget {
  const CounterText({super.key});

  @override
  Widget build(BuildContext context) {
    final value = ScopeNotifier.select<Counter, int>(
      context,
      (counter) => counter.value,
    );

    return TextButton(
      onPressed: ScopeNotifier.of<Counter>(context, listen: false).increment,
      child: Text('$value'),
    );
  }
}
```

Pressing the button mutates the counter, the counter notifies its listeners,
the scope notifies its dependents, and `CounterText` is rebuilt — but only
because the value it selected changed. A sibling that selected something else
sleeps through it, and the subtree between the scope and the button is not
rebuilt at all.

## The whole difference

```dart
@override
void init() {
  model.addListener(notifyDependents);
  super.init();
}

@override
void dispose() {
  super.dispose();
  model.removeListener(notifyDependents);
}
```

That is the entire element. `notifyDependents` is described in the
`ScopeWidget` topic; what matters here is that it does not rebuild the scope's
own subtree, which is what makes a high-frequency `Listenable` — an animation,
a scroll position, a text controller — affordable to put in a scope.

The subscription belongs to the element, so it lasts exactly as long as the
model does, and a model created by `create` is disposed of after the listener
has been removed.

## Swapping the model

The `.value` constructor takes a `Listenable` somebody else owns, and it may be
handed a *different* one on a later build:

```dart
ScopeNotifier.value(value: currentPlayer, builder: ...)
```

When the widget is rebuilt with another `value`, the element moves its listener
from the old model to the new one. "Another" means another object, not another
value: two models that compare `==` are still two listener lists, so the move is
decided by identity. Descendants then see the new model through the same
accessors, and their selectors compare against the values they captured from
the old one — so a switch to a model with different values rebuilds exactly the
widgets those values differ for.

As with `ScopeModel.value`, the scope does not own a model given this way: no
`dispose` is called for it.

What cannot change is which constructor the scope was built with. `.value` and
the owning constructor are two different answers to "who releases this model",
and the answer is fixed for the lifetime of the element — an assertion refuses
a rebuild that changes it. To switch, give the widget a different `Widget.key`:
the framework then builds a new element, which reads the mode afresh and
releases whatever the old one owned.

## State models

Six types in this family exist for scopes whose state is a single immutable
value that changes over time — a trio, and the same trio with a failed state
beside the value. `AsyncScope` is built on the first three; the second three are
offered for a family of your own:

| type | what it is |
| --- | --- |
| `ScopeStateModel<S>` | a `Listenable` with a `state` of type `S` — the read side |
| `ScopeStateNotifier<S>` | a `ChangeNotifier` implementing it, with `update(S)` |
| `ScopeStateModelView<S>` | an unmodifiable view of a notifier |
| `ScopeStateWithErrorModel<S>` | the read side, plus a failed state |
| `ScopeStateWithErrorNotifier<S>` | its notifier, with `update(S)` and `setError` |
| `ScopeStateWithErrorModelView<S>` | an unmodifiable view of that notifier |

`update(S value)` notifies only when the value actually changed, and what
"changed" means is a method you can override:

```dart
base class PlayerState extends ScopeStateNotifier<Player> {
  PlayerState(super.initialState);

  @override
  bool equals(Player previous, Player current) => previous.id == current.id;
}
```

The default `equals` returns `false` — every `update` notifies. That is the
safe default for a mutable object being re-assigned; override it when the state
is a value type and repeated equal updates are common.

`asUnmodifiable()` wraps a notifier into a `ScopeStateModelView`, which forwards
`state`, `addListener` and `removeListener` and nothing else. Hand that to the
subtree when the state must be readable but not settable from below.

The error-carrying pair is the interesting one, and nothing in the package
uses it. `setError` stores the error with its stack trace, `hasError` reports
it — and reading `state` afterwards **rethrows** that error with its original
stack trace instead of returning a value, so a builder that reads `state`
fails loudly on a scope that has failed rather than rendering a stale value.

A failure is not terminal, though: `update` puts it down as it stores the new
state. A state handed over is a state that can be read, so recovering is what
an update after `setError` means, and there is nothing else it could mean. The
listeners hear about it even when the value is the one from before the failure
— `equals` compares two values, and this change is between a state that throws
and one that does not.

```dart
model
  ..setError(failure, stackTrace)   // `state` throws from here on
  ..update(recovered);              // and stops: `hasError` is false again
```

That is not how the asynchronous families model a failure. They hold an
ordinary `ScopeStateNotifier` and put the failure *in* the state, as an
`AsyncScopeError` beside `AsyncScopeWaiting`, `AsyncScopeProgress` and
`AsyncScopeReady`: reading `AsyncScope.of(context, listen: true).state` never
throws, and `hasError` is derived from what the state is. Both shapes work;
which one to pick depends on whether a failed scope still has something to
show.

## Where to go next

| topic | what it covers |
| --- | --- |
| `ScopeModel` | the family this one extends: `create`, `dispose`, `.value`, lifetime |
| `ScopeWidget` | `notifyDependents` and why it skips the subtree |
| `base` | `of`, `select`, `listen` |
| `AsyncScope` | a family built on `ScopeStateNotifier`, with the failure inside the state |
