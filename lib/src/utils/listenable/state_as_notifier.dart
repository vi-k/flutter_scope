import 'package:flutter/widgets.dart';

/// {@category utils}
mixin StateAsNotifier<T extends StatefulWidget> on State<T>
    implements Listenable {
  ChangeNotifier? _notifier;

  @override
  void addListener(VoidCallback listener) {
    (_notifier ??= ChangeNotifier()).addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    _notifier?.removeListener(listener);
  }

  @protected
  void notifyListeners() {
    // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
    _notifier?.notifyListeners();
  }

  @override
  void dispose() {
    _notifier?.dispose();
    super.dispose();
  }
}
