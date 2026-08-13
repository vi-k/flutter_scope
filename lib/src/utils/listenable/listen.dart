import 'dart:async';

import 'package:flutter/foundation.dart';

import '../check_disposed.dart';

part 'select.dart';

/// A helper extension that adds a `listen` method to `Listenable`, similar to
/// `Stream.listen`. It returns a `ListenableSubscription` that can be easily
/// canceled.
///
/// {@category utils}
extension ListenableListenExtension on Listenable {
  /// Listen to the [Listenable].
  ///
  /// The standard way to subscribe using [addListener] requires using a method
  /// as a callback, which is then used in [removeListener]:
  ///
  /// ```dart
  /// void _listener() {...}
  ///
  /// listenable.addListener(_listener);
  /// ...
  /// listenable.removeListener(_listener);
  /// ```
  ///
  /// If you use a closure, you need to store a reference to it somewhere so
  /// that you can later pass it to [removeListener]:
  ///
  /// ```dart
  /// final closure = () {...};
  /// listenable.addListener(closure);
  /// ...
  /// listenable.removeListener(closure);
  /// ```
  ///
  /// This method adds the same interface used in [Stream] api:
  ///
  /// ```dart
  /// ListenableSubscription subscription = listenable.listen(() {...});
  /// ...
  /// subscription.cancel();
  /// ```
  ///
  /// It stores a reference to the listener inside [ListenableSubscription] so
  /// that it can later remove listener using [ListenableSubscription.cancel].
  ListenableSubscription listen(void Function() callback) {
    addListener(callback);
    return ListenableSubscription._(this, callback);
  }
}

/// A subscription on changes from a [Listenable].
///
/// When you listen on a [Listenable] using [ListenableListenExtension.listen],
/// a [ListenableSubscription] object is returned.
///
/// The subscription saves a reference to the listener so that it can later be
/// removed from listenable using the [Listenable.removeListener] method under
/// the hood.
///
/// Example:
///
/// ```dart
/// final scrollController = ScrollController();
/// final subscription = scrollController.listen(() {...});
/// ...
/// subscription.cancel();
/// ```
///
/// {@category utils}
final class ListenableSubscription {
  final Listenable _listenable;
  final void Function() _callback;
  var _isDisposed = false;

  ListenableSubscription._(this._listenable, this._callback);

  /// Adds this subscription to composite container for subscriptions.
  void addTo(CompositeListenableSubscription compositeSubscription) =>
      compositeSubscription.add(this);

  /// Removes listener from listenable.
  void cancel() {
    assert(debugAssertNotDisposed(this, _isDisposed, 'cancel'));

    if (!_isDisposed) {
      _listenable.removeListener(_callback);
      _isDisposed = true;
    }
  }
}

/// Acts as a container for multiple subscriptions [ListenableSubscription] that
/// can be canceled at once.
///
/// Example 1:
///
/// ```dart
/// final composite = CompositeListenableSubscription();
///
/// ...
///
/// composite
///   ..add(listenable1.listen(listener1))
///   ..add(listenable2.listen(listener2))
///   ..add(listenable3.listen(listener3));
///
/// ...
///
/// composite.cancel();
/// ```
///
/// Example 2:
///
/// ```dart
/// final composite = CompositeListenableSubscription();
///
/// ...
///
/// listenable1.listen(listener1).addTo(composite);
/// listenable2.listen(listener2).addTo(composite);
/// listenable3.listen(listener3).addTo(composite);
///
/// ...
///
/// composite.cancel();
/// ```
///
/// {@category utils}
final class CompositeListenableSubscription {
  final List<ListenableSubscription> _subscriptions = [];
  var _isDisposed = false;

  CompositeListenableSubscription();

  /// Adds new subscription to this composite.
  ///
  /// Throws an exception if this composite was disposed
  void add(ListenableSubscription subscription) {
    throwWhenDisposed(this, _isDisposed, 'cancel');
    _subscriptions.add(subscription);
  }

  /// Removes all subscriptions from this composite.
  void cancel() {
    assert(debugAssertNotDisposed(this, _isDisposed, 'cancel'));
    if (!_isDisposed) {
      _isDisposed = true;
      for (final subscription in _subscriptions) {
        subscription.cancel();
      }
      _subscriptions.clear();
    }
  }
}
