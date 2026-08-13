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
  /// instead of returning a value.
  void setError(Object error, StackTrace stackTrace) {
    _error = (error, stackTrace);
    notifyListeners();
  }

  @override
  ScopeStateWithErrorModelView<S> asUnmodifiable() =>

      /// Wraps a notifier into a read-only view of it.
      /// Wraps [notifier] into a read-only view of it.
      ScopeStateWithErrorModelView(this);
}

/// {@category ScopeNotifier}
base class ScopeStateWithErrorModelView<S extends Object>
    extends ScopeStateModelView<S> implements ScopeStateWithErrorModel<S> {
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
