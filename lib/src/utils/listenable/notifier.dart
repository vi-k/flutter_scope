import 'package:flutter/foundation.dart';

import '../check_disposed.dart';

/// @nodoc
@visibleForTesting
class TestNotifier with Notifier {
  List<void Function()?> get listeners => _listeners;

  int get count => _count;

  bool get notifyingListeners => _notifyingListeners;
}

/// @nodoc
mixin Notifier implements Listenable {
  static final _emptyListeners = List<void Function()?>.filled(0, null);

  /// The list of listeners.
  ///
  /// For performance it always keeps the same underlying type and is never
  /// growable. A listener is removed by nulling out its slot first.
  var _listeners = _emptyListeners;
  var _debugDisposed = false;
  var _count = 0;
  var _notifyListenersCounter = 0;
  var _notifyingListeners = false;
  var _listenersMarkedForRemove = 0;

  @protected
  bool get hasListeners => _listeners.isNotEmpty;

  @override
  void addListener(void Function() listener) {
    assert(debugAssertNotDisposed(this, _debugDisposed, 'disposeListenable'));

    if (_count == _listeners.length) {
      if (_count == 0) {
        _listeners = List<VoidCallback?>.filled(1, null);
      } else {
        final newListeners = List<VoidCallback?>.filled(_count * 2, null);
        for (var i = 0; i < _count; i++) {
          newListeners[i] = _listeners[i];
        }
        _listeners = newListeners;
      }
    }
    _listeners[_count++] = listener;
  }

  @override
  void removeListener(void Function() listener) {
    final index = _listeners.indexOf(listener);
    if (index == -1) return;

    _listeners[index] = null;
    _listenersMarkedForRemove++;
    if (!_notifyingListeners) {
      _packListeners();
    }
  }

  void _packListeners() {
    final newLength = _count - _listenersMarkedForRemove;
    if (newLength <= _listeners.length ~/ 2) {
      final newListeners = List<void Function()?>.filled(newLength, null);

      for (var i = 0, j = 0; i < _count; i++) {
        if (_listeners[i] case final listener?) {
          newListeners[j++] = listener;
        }
      }

      _listeners = newListeners;
    } else {
      for (var i = 0, j = 0; i < newLength; i++) {
        if (_listeners[i] == null) {
          if (j <= i) {
            j = i + 1;
          }

          while (_listeners[j] == null) {
            j++;
          }

          _listeners[i] = _listeners[j];
          _listeners[j] = null;
          j++;
        }
      }
    }

    _count = newLength;
    _listenersMarkedForRemove = 0;
  }

  /// Call all the registered listeners.
  ///
  /// Listeners that are added during this iteration will not be visited.
  /// Listeners that are removed during this iteration will not be visited
  /// after they are removed.
  @protected
  @visibleForTesting
  void notifyListeners() {
    assert(debugAssertNotDisposed(this, _debugDisposed, 'disposeListenable'));

    _notifyingListeners = true;
    final counter = ++_notifyListenersCounter;

    // notifyListeners can be called again while notifying. The old loop is
    // then interrupted: the new one calls both those that have to be notified
    // again and those the previous loop did not reach.
    //
    // Listeners added during the notification are not notified.
    final count = _count;
    for (var i = 0; i < count; i++) {
      try {
        _listeners[i]?.call();
        if (counter != _notifyListenersCounter) {
          return;
        }
      } catch (exception, stack) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: exception,
            stack: stack,
            library: 'scopo',
            context: ErrorDescription(
              'while dispatching notifications for $runtimeType',
            ),
            informationCollector: () => <DiagnosticsNode>[
              DiagnosticsProperty<Notifier>(
                'The $runtimeType sending notification was',
                this,
                style: DiagnosticsTreeStyle.errorProperty,
              ),
            ],
          ),
        );
      }
    }

    if (_listenersMarkedForRemove > 0) {
      _packListeners();
    }
  }

  void disposeNotifier() {
    assert(debugAssertNotDisposed(this, _debugDisposed, 'disposeListenable'));
    assert(
      !_notifyingListeners,
      'The `disposeListenable()` method on $this was called during the call to'
      ' `notifyListeners()`. This is likely to cause errors since it modifies'
      ' the list of listeners while the list is being used.',
    );
    assert(() {
      _debugDisposed = true;
      return true;
    }());

    _listeners = _emptyListeners;
    _count = 0;
  }
}
