part of '../../scope.dart';

/// {@category ScopeNotifier}
abstract interface class ScopeStateWithErrorModel<S extends Object>
    implements ScopeStateModel<S> {
  @override
  S get state;

  bool get hasError;

  Object get error;

  StackTrace get stackTrace;
}

/// {@category ScopeNotifier}
base class ScopeStateWithErrorNotifier<S extends Object>
    extends ScopeStateNotifier<S> implements ScopeStateWithErrorModel<S> {
  (Object, StackTrace)? _error;

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

  void setError(Object error, StackTrace stackTrace) {
    _error = (error, stackTrace);
    notifyListeners();
  }

  @override
  ScopeStateWithErrorModelView<S> asUnmodifiable() =>
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
