part of '../../../scope.dart';

/// {@category Scope}
mixin ScopeDependencyMixin implements ScopeDependency {
  late final _log = log.withAddedName(
    () => '$ScopeDependencyMixin(#${shortHash(this)})',
  );

  @override
  ScopeDependencyState get state => _state;
  ScopeDependencyState _state = const ScopeDependencyInitial();

  /// Whether [runDispose] has already run to its end.
  ///
  /// The state used to answer this on its own, because a disposal that was
  /// over always said [ScopeDependencyDisposed]. It cannot any more: a
  /// dependency that collected errors keeps them, so a group that was disposed
  /// of *because* something under it failed still says
  /// [ScopeDependencyFailed]. Kept apart from the state, so
  /// [ScopeDependency.disposalRequired] can still tell a disposal that is due
  /// from one that is done.
  bool _isDisposalDone = false;

  /// Automates the initialization process.
  ///
  /// Runs [init], handles the errors and sets the matching state.
  ///
  /// Initialization succeeds not when there are no errors, but only when the
  /// generator IS NOT CANCELLED. That is, the initiator may leave the stream
  /// running after an error, and the initialization then formally ends in
  /// [ScopeDependencyInitialized]; or it may end the stream without any error
  /// at all, and the initialization then ends in [ScopeDependencyCancelled].
  ///
  /// [init] may report several errors, because a group of dependencies rather
  /// than a single one can hide behind it. Errors that were already handled,
  /// that is the errors of the child dependencies, are ignored. An error of
  /// this dependency leads to [ScopeDependencyFailed] and is wrapped into a
  /// [ScopeDependencyException] to be passed on in that form. Only the first
  /// such error is kept in the state, on the assumption that one dependency
  /// has no reason to report several.
  @override
  Stream<String> runInit() async* {
    assert(_state is ScopeDependencyInitial);

    try {
      yield* runStreamGuarded(
        init,
        _handleInitializationPostCancelError,
        debugName: name,
      ).handleError(_handleInitializationError);
      if (_state is! ScopeDependencyFailed) {
        _state = const ScopeDependencyInitialized();
      }
    } finally {
      // Catch the cancellation.
      if (_state is ScopeDependencyInitial) {
        _state = ScopeDependencyCancelled();
      }
    }
  }

  /// Automates the disposal process.
  ///
  /// A state that carries errors survives the disposal untouched:
  /// [ScopeDependencyDisposed] says nothing at all, and the error list is the
  /// only record of what went wrong. A group is disposed of *because*
  /// something under it failed — [ScopeDependencyGroup.disposalRequired]
  /// covers [ScopeDependencyFailed] — so overwriting its state threw that
  /// record away exactly where it was needed, and with the default
  /// [ScopeAutoDependencies.autoDisposeOnError] that happened before the
  /// caller ever saw it. A failed *leaf* is never disposed of at all, so it
  /// always kept its errors; the groups now behave the same way.
  @override
  Stream<String> runDispose() async* {
    try {
      yield* runStreamGuarded(
        dispose,
        _handleDisposalPostCancelError,
        debugName: name,
      ).handleError(_handleDisposalError);
      _state = switch (_state) {
        final _ScopeDependencyWithErrors state when state.hasErrors => state,
        _ => const ScopeDependencyDisposed(),
      };
    } finally {
      _isDisposalDone = true;

      // Catch the cancellation.
      if (_state is ScopeDependencyInitialized) {
        _state = ScopeDependencyDisposalCancelled();
      }
    }
  }

  void _addErrorToState(
    Object error,
    StackTrace stackTrace,
    _ScopeDependencyWithErrors Function(Object error, StackTrace stackTrace)
        defaultState,
  ) {
    _state = switch (_state) {
      final _ScopeDependencyWithErrors state => state.addError(
          error,
          stackTrace,
        ),
      ScopeDependencySuccessStates() => defaultState(error, stackTrace),
    };
  }

  void _handleError(
    Object error,
    StackTrace stackTrace,
    ScopeDependencyFailedStates Function(Object error, StackTrace stackTrace)
        defaultState,
  ) {
    _log.d(() => '[handleError] $wrappedName', error: error);

    // Add the error to the state.
    _addErrorToState(error, stackTrace, defaultState);

    // Pass the error on.
    if (error is ScopeDependencyException) {
      // Pass the error on, prefixing its path with the name of this
      // dependency. An anonymous group (name == '') adds neither its own
      // segment nor a separator, otherwise the path would gain a leading or
      // a doubled '/'.
      Error.throwWithStackTrace(
        ScopeDependencyException(
          name.isEmpty ? error.name : '$name/${error.name}',
          error.error,
          error.stackTrace,
        ),
        stackTrace,
      );
    } else {
      // Wrap our own errors so that the name is passed upwards.
      //
      // With the trace of the failure, not an empty one: this is the trace
      // that travels up the tree and reaches `buildOnError`, and a crash
      // reporter handed `StackTrace.empty` has nothing to work from. The
      // original is kept inside the exception as well, where a reader who
      // knows to look can find it -- but nobody is told to look.
      Error.throwWithStackTrace(
        ScopeDependencyException(name, error, stackTrace),
        stackTrace,
      );
    }
  }

  void _handleInitializationError(Object error, StackTrace stackTrace) {
    _handleError(error, stackTrace, ScopeDependencyFailed.new);
  }

  void _handleDisposalError(Object error, StackTrace stackTrace) {
    _handleError(error, stackTrace, ScopeDependencyDisposalFailed.new);
  }

  void _handlePostCancelError(
    Object error,
    StackTrace stackTrace,
    ScopeDependencyCancelledStates Function(Object error, StackTrace stackTrace)
        defaultState,
  ) {
    _log.d(() => '[handlePostCancelError] $wrappedName', error: error);

    if (error is ParallelWaitError<void, List<AsyncError?>>) {
      for (final error in error.errors.nonNulls) {
        _handlePostCancelError(error.error, error.stackTrace, defaultState);
      }
      return;
    }

    // Add the error to the state.
    _addErrorToState(error, stackTrace, defaultState);
  }

  void _handleInitializationPostCancelError(
    Object error,
    StackTrace stackTrace,
  ) {
    _handlePostCancelError(
      error, //
      stackTrace,
      ScopeDependencyCancelled.new,
    );
  }

  void _handleDisposalPostCancelError(Object error, StackTrace stackTrace) {
    _handlePostCancelError(
      error, //
      stackTrace,
      ScopeDependencyDisposalCancelled.new,
    );
  }
}
