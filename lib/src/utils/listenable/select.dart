part of 'listen.dart';

/// A helper extension that adds a [select] method to [Listenable]. It allows
/// listening to a specific value of the [Listenable] (selector), triggering the
/// listener only when that value changes.
///
/// {@category utils}
extension ListenableSelectExtension<L extends Listenable> on L {
  /// Listen to a specific value of the [Listenable].
  ///
  /// In the usual case, we listen to all changes of [Listenable].
  ///
  /// This method allows us to call the [listener] only when the value returned
  /// by [selector] has changed.
  ///
  /// Example:
  ///
  /// ```dart
  /// final subscription = listenable.select(
  ///     (listenable) => listenable.counter,
  ///     (listenable, counter) => print(counter),
  /// );
  /// ```
  ///
  /// By default a value counts as changed when it is not [Object.==] to the
  /// previous one. [compare] replaces that test, and answers the same
  /// question: `true` means the value changed and the listener runs.
  ///
  /// Example:
  ///
  /// ```dart
  /// final subscription = listenable.select(
  ///     (listenable) => listenable.data,
  ///     (listenable, data) => print(data),
  ///     compare: (previous, current) => !identical(previous, current),
  /// );
  /// ```
  ListenableSelectSubscription<T> select<T extends Object?>(
    T Function(L listenable) selector,
    void Function(L listenable, T value) listener, {
    bool Function(T previous, T current)? compare,
  }) {
    late final ListenableSelectSubscription<T> subscription;

    void handle() {
      // A `Listenable` of the caller's own is free to dispatch over a copy of
      // its list taken before `cancel()` removed this one from it, and then
      // this runs after the subscription is over. Nothing in the package does
      // that; a listener called after it was taken back is still not something
      // to hand to the caller.
      if (subscription._isDisposed) {
        return;
      }

      final newValue = selector(this);
      if (compare?.call(subscription._value, newValue) ??
          subscription._value != newValue) {
        // Written before the listener runs and taken back if it fails. Before,
        // because a listener is free to notify again and the value it has
        // already been given must not start a walk of its own; taken back,
        // because a listener that threw did not receive anything, and leaving
        // the value marked as delivered filtered out the next notification
        // carrying it -- the listener was then never told, ever. The one most
        // likely to throw is a `setState` from inside somebody else's build,
        // which raises in debug and does nothing in release, so this was a
        // widget stuck on an old value in debug alone.
        final previous = subscription._value;
        subscription._value = newValue;
        try {
          listener(this, newValue);
          // ignore: avoid_catching_errors
        } on Object {
          subscription._value = previous;

          rethrow;
        }
      }
    }

    // The first value is read before the listener is registered, and the
    // subscription exists before it too. A selector that fails on this first
    // read used to do so with the listener already in place and no
    // subscription handed back to take it away, and the next notification then
    // reached a `late` field nobody had assigned.
    subscription = ListenableSelectSubscription._(this, handle, selector(this));

    addListener(handle);

    return subscription;
  }
}

/// A subscription on selected value changes from a [Listenable].
///
/// {@category utils}
final class ListenableSelectSubscription<T extends Object?>
    extends ListenableSubscription {
  T _value;

  ListenableSelectSubscription._(
    super._listenable,
    super._callback,
    this._value,
  ) : super._();

  /// The value the selector returned last.
  T get value => _value;
}
