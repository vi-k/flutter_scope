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
  /// By default, the previous value is compared to the new value using the
  /// operator [Object.==], but this behavior can be changed using [compare].
  ///
  /// Example:
  ///
  /// ```dart
  /// final subscription = listenable.select(
  ///     (listenable) => listenable.data,
  ///     (listenable, data) => print(data),
  ///     compare: (previous, current) => identical(previous, current),
  /// );
  /// ```
  ListenableSelectSubscription<T> select<T extends Object?>(
    T Function(L listenable) selector,
    void Function(L listenable, T value) listener, {
    bool Function(T previous, T current)? compare,
  }) {
    late final ListenableSelectSubscription<T> subscription;

    void handle() {
      final newValue = selector(this);
      if (compare?.call(subscription._value, newValue) ??
          subscription._value != newValue) {
        subscription._value = newValue;
        listener(this, newValue);
      }
    }

    addListener(handle);

    return subscription =
        ListenableSelectSubscription._(this, handle, selector(this));
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

  T get value => _value;
}
