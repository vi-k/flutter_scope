part of '../../scope.dart';

/// {@category ScopeNotifier}
abstract interface class ScopeStateModel<S extends Object>
    implements Listenable {
  /// The current state.
  S get state;
}

/// {@category ScopeNotifier}
base class ScopeStateNotifier<S extends Object> extends ChangeNotifier
    implements ScopeStateModel<S> {
  S _state;

  /// Creates a notifier holding [initialState].
  ScopeStateNotifier(S initialState) : _state = initialState;

  @override
  S get state => _state;

  /// Replaces the state and notifies the listeners.
  ///
  /// Notifies only when [equals] says the value has changed.
  void update(S value) {
    if (!equals(_state, value)) {
      _state = value;
      notifyListeners();
    }
  }

  /// Whether two states are the same for the purpose of notifying.
  ///
  /// Returns `false` by default, so every [update] notifies. Override it
  /// when the state is a value type and equal updates are common.
  bool equals(S previous, S current) => false;

  /// A view of this notifier that can be read and listened to, not set.
  ScopeStateModelView<S> asUnmodifiable() => ScopeStateModelView(this);
}

/// {@category ScopeNotifier}
base class ScopeStateModelView<S extends Object> implements ScopeStateModel<S> {
  final ScopeStateNotifier<S> _notifier;

  /// Wraps [notifier] into a read-only view of it.
  ScopeStateModelView(ScopeStateNotifier<S> notifier) : _notifier = notifier;

  @override
  S get state => _notifier.state;

  @override
  void addListener(VoidCallback listener) => _notifier.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _notifier.removeListener(listener);
}
