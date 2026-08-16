import 'package:flutter/widgets.dart';

/// {@category utils}
mixin StateAsNotifier<T extends StatefulWidget> on State<T>
    implements Listenable {
  ChangeNotifier? _notifier;

  @override
  void addListener(VoidCallback listener) {
    // A state that is gone takes no listeners. Without this the notifier
    // created here would never be disposed of, and the listener would be held
    // by an object nobody will ever notify.
    if (!mounted) {
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
