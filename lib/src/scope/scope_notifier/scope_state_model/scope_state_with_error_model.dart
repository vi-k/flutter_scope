part of '../../scope.dart';

/// {@category ScopeNotifier}
abstract interface class ScopeStateWithErrorModel<S extends Object>
    implements ScopeStateModel<S> {
  @override
  S get state;

  /// Whether the state carries an error.
  bool get hasError;

  /// The error, when there is one.
  ///
  /// Throws a [StateError] otherwise.
  Object get error;

  /// The stack trace of [error].
  ///
  /// Throws a [StateError] when there is no error.
  StackTrace get stackTrace;
}

/// {@category ScopeNotifier}
base class ScopeStateWithErrorNotifier<S extends Object>
    extends ScopeStateNotifier<S> implements ScopeStateWithErrorModel<S> {
  (Object, StackTrace)? _error;

  /// Creates a notifier holding `initialState` and no error.
  ScopeStateWithErrorNotifier(super.initialState);

  @override
  bool get hasError => _error != null;

  @override
  S get state => switch (_error) {
        null => super.state,
        (final Object error, final StackTrace stackTrace) =>
          Error.throwWithStackTrace(error, stackTrace),
      };

  @override
  Object get error => _error?.$1 ?? (throw StateError('No error'));

  @override
  StackTrace get stackTrace => _error?.$2 ?? (throw StateError('No error'));

  /// Puts the model into the failed state and notifies the listeners.
  ///
  /// Reading `state` afterwards rethrows [error] with its [stackTrace]
  /// instead of returning a value, until an [update] puts the failure down.
  void setError(Object error, StackTrace stackTrace) {
    _error = (error, stackTrace);
    notifyListeners();
  }

  /// Replaces the state, and puts down a failure the model was holding.
  ///
  /// A state handed over is a state that can be read, so the failure goes with
  /// the same call: recovering is what an update after [setError] means, and
  /// there is nothing else it could mean. Left standing, as it was, the
  /// failure made the update worse than useless — the listeners were told the
  /// state had changed and `state` went on throwing the old failure at every
  /// one of them, so a single attempt at recovery turned a whole subtree into
  /// `ErrorWidget`s.
  @override
  void update(S value) {
    if (_error == null) {
      super.update(value);

      return;
    }

    _error = null;

    // [equals] compares two values, and this change is not one between values:
    // it is between a state that throws and one that does not. Recovering to
    // the value from before the failure is still something every listener has
    // to hear about, so the comparison does not get to silence it.
    if (equals(state, value)) {
      notifyListeners();
    } else {
      super.update(value);
    }
  }

  /// A view of this notifier that can be read and listened to, not set.
  @override
  ScopeStateWithErrorModelView<S> asUnmodifiable() =>
      ScopeStateWithErrorModelView(this);
}

/// {@category ScopeNotifier}
base class ScopeStateWithErrorModelView<S extends Object>
    extends ScopeStateModelView<S> implements ScopeStateWithErrorModel<S> {
  /// Wraps a notifier into a read-only view of it.
  ScopeStateWithErrorModelView(
    ScopeStateWithErrorNotifier<S> super.notifier,
  );

  @override
  ScopeStateWithErrorNotifier<S> get _notifier =>
      super._notifier as ScopeStateWithErrorNotifier<S>;

  @override
  bool get hasError => _notifier.hasError;

  @override
  Object get error => _notifier.error;

  @override
  StackTrace get stackTrace => _notifier.stackTrace;
}
