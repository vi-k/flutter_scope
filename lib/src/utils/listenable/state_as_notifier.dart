import 'package:flutter/widgets.dart';

/// {@category utils}
mixin StateAsNotifier<T extends StatefulWidget> on State<T>
    implements Listenable {
  ChangeNotifier? _notifier;

  /// Whether [dispose] has begun.
  ///
  /// `mounted` cannot answer this: it stays true for the whole of
  /// `State.dispose()` — `StatefulElement.unmount` clears the element only
  /// once that call has returned — and the tail of the same chain is ordinary
  /// ground for the caller's own cleanup. A listener taken from there found
  /// the guard open and the notifier already let go of, and built a fresh one:
  /// nothing disposes of that, and nothing will ever notify it.
  bool _stateGone = false;

  @override
  void addListener(VoidCallback listener) {
    // A state that is gone takes no listeners. Without this the notifier
    // created here would never be disposed of, and the listener would be held
    // by an object nobody will ever notify.
    if (_stateGone || !mounted) {
      return;
    }

    (_notifier ??= ChangeNotifier()).addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    _notifier?.removeListener(listener);
  }

  /// Notifies the listeners of this state.
  ///
  /// Does nothing while nobody listens: the notifier behind it is created
  /// by the first [addListener].
  @protected
  void notifyListeners() {
    // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
    _notifier?.notifyListeners();
  }

  @override
  void dispose() {
    // First, before anything is released: what follows is this state going
    // away, and everything that runs after this line -- here, and in whatever
    // overrode this method -- is the tail of that.
    _stateGone = true;

    // Let go of it, not merely disposed of. A callback that outlives the state
    // -- a stream event, a timer -- still calls [notifyListeners], and a
    // disposed [ChangeNotifier] answers that with "A ChangeNotifier was used
    // after being disposed". Dropping the reference makes those calls the
    // no-ops they were always meant to be.
    _notifier?.dispose();
    _notifier = null;
    super.dispose();
  }
}
