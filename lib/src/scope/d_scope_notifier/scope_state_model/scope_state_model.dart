part of '../../scope.dart';

/// {@category ScopeNotifier}
abstract interface class ScopeStateModel<S extends Object>
    implements Listenable {
  S get state;
}

/// {@category ScopeNotifier}
base class ScopeStateNotifier<S extends Object> extends ChangeNotifier
    implements ScopeStateModel<S> {
  S _state;

  ScopeStateNotifier(S initialState) : _state = initialState;

  @override
  S get state => _state;

  void update(S value) {
    if (!equals(_state, value)) {
      _state = value;
      notifyListeners();
    }
  }

  bool equals(S previous, S current) => false;

  ScopeStateModelView<S> asUnmodifiable() => ScopeStateModelView(this);
}

/// {@category ScopeNotifier}
base class ScopeStateModelView<S extends Object> implements ScopeStateModel<S> {
  final ScopeStateNotifier<S> _notifier;

  ScopeStateModelView(ScopeStateNotifier<S> notifier) : _notifier = notifier;

  @override
  S get state => _notifier.state;

  @override
  void addListener(VoidCallback listener) => _notifier.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _notifier.removeListener(listener);
}
