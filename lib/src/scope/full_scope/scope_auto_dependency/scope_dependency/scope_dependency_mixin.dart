part of '../../../scope.dart';

/// {@category Scope}
mixin ScopeDependencyMixin implements ScopeDependency, ScopeObservable {
  @override
  String get debugLabel => name;

  @override
  ScopeDependencyState get state => _state;
  ScopeDependencyState _state = const ScopeDependencyInitial();

  /// Whether [dispose] has already run to its end.
  ///
  /// The state used to answer this on its own, because a disposal that was
  /// over always said [ScopeDependencyDisposed]. It cannot any more: a
  /// dependency that collected errors keeps them, so a group that was disposed
  /// of *because* something under it failed still says
  /// [ScopeDependencyFailed]. Kept apart from the state, so
  /// [ScopeDependency.disposalRequired] can still tell a disposal that is due
  /// from one that is done.
  bool _isDisposalDone = false;

  /// Records that the walk passed this dependency by because it holds nothing.
  ///
  /// A dependency that registered no disposer is skipped by its group — there
  /// is nothing to run for it. Skipped in silence it went on saying
  /// `initialized` after the whole tree had been torn down, so a dump of a
  /// scope that was fully disposed of read as though half of it were still
  /// alive. [ScopeDependencyNoDisposalRequired] exists for exactly this and had
  /// no other way of being reached.
  ///
  /// A dependency that never ran keeps [ScopeDependencyInitial]: "not
  /// initialized" is the true thing to say about it, and it is not what this
  /// state means.
  void _markNothingToDispose() {
    if (_isDisposalDone) {
      return;
    }

    _isDisposalDone = true;
    if (_state is ScopeDependencyInitialized) {
      _state = const ScopeDependencyNoDisposalRequired();
    }
  }

  /// The initialization step itself, run and accounted for by [init].
  Stream<String> _runInit();

  /// The release step itself, run and accounted for by [dispose].
  Stream<String> _runDispose();

  /// Automates the initialization process.
  ///
  /// Runs [_runInit], handles the errors and sets the matching state.
  ///
  /// Initialization succeeds not when there are no errors, but only when the
  /// generator IS NOT CANCELLED. That is, the initiator may leave the stream
  /// running after an error, and the initialization then formally ends in
  /// [ScopeDependencyInitialized]; or it may end the stream without any error
  /// at all, and the initialization then ends in [ScopeDependencyCancelled].
  ///
  /// [_runInit] may report several errors, because a group of dependencies rather
  /// than a single one can hide behind it. Errors that were already handled,
  /// that is the errors of the child dependencies, are ignored. An error of
  /// this dependency leads to [ScopeDependencyFailed] and is wrapped into a
  /// [ScopeDependencyException] to be passed on in that form. Only the first
  /// such error is kept in the state, on the assumption that one dependency
  /// has no reason to report several.
  @override
  Stream<String> init() async* {
    assert(_state is ScopeDependencyInitial);

    // [_state] cannot answer this: it stays [ScopeDependencyInitial] for the
    // whole of the run below and leaves it only at the end, so a second call
    // arriving while the first is parked on an `await` finds every check
    // satisfied. A leaf has one [ScopeDependencyHandle], and running the
    // initializer again replaces it -- along with the `unmount` and `dispose`
    // the first run registered on it, which is everything that could ever give
    // back what that run had taken.
    if (_initializing) {
      throw StateError(
        '$wrappedName is initializing right now. A second `init()` would run '
        'its initializer again and replace what the first one registered, so '
        'whatever that run had already taken would be left with nothing to '
        'release it. Await the initialization that is running.',
      );
    }
    _initializing = true;

    try {
      yield* runStreamGuarded(
        _runInit,
        _handleInitializationPostCancelError,
        debugName: name,
        observable: this,
      ).handleError(_handleInitializationError);
      if (_state is! ScopeDependencyFailed) {
        _state = const ScopeDependencyInitialized();
      }
    } finally {
      _initializing = false;
      // Catch the cancellation.
      if (_state is ScopeDependencyInitial) {
        _state = ScopeDependencyCancelled();
      }
    }
  }

  /// Whether [init] is running right now.
  bool _initializing = false;

  /// Automates the disposal process.
  ///
  /// A state that carries errors survives the disposal untouched:
  /// [ScopeDependencyDisposed] says nothing at all, and the error list is the
  /// only record of what went wrong. A group is disposed of *because*
  /// something under it failed — [ScopeDependencyGroup.disposalRequired]
  /// covers [ScopeDependencyFailed] — so overwriting its state threw that
  /// record away exactly where it was needed, and with the default
  /// [ScopeAutoDependencies.autoDisposeOnError] that happened before the
  /// caller ever saw it. A failed *leaf* keeps its errors by the same rule, and
  /// it is disposed of all the same: what decides that is whether the
  /// initializer took anything, not how it ended
  /// (`_ScopeDependencyImpl.disposalRequired`). The groups now behave the same
  /// way.
  @override
  Stream<String> dispose() async* {
    try {
      yield* runStreamGuarded(
        _runDispose,
        _handleDisposalPostCancelError,
        debugName: name,
        observable: this,
      ).handleError(_handleDisposalError);
      _state = switch (_state) {
        final _ScopeDependencyWithErrors state when state.hasErrors => state,
        _ => const ScopeDependencyDisposed(),
      };
    } finally {
      // Catch the cancellation.
      if (_state is ScopeDependencyInitialized) {
        _state = ScopeDependencyDisposalCancelled();
      } else {
        // Only a walk that reached its end is done. Marked done either way, a
        // disposal a caller stopped halfway made the tree stop saying it
        // needed disposing of -- and the next `init()` then replaced it, so
        // everything the walk never reached was left holding what it took
        // with nobody able to reach it.
        _isDisposalDone = true;
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
      ScopeDependencyAnySuccess() => defaultState(error, stackTrace),
    };
  }

  void _handleError(
    Object error,
    StackTrace stackTrace,
    ScopeDependencyAnyFailed Function(Object error, StackTrace stackTrace)
        defaultState,
  ) {
    notifyObserver(
      (observer) =>
          observer.onTrace(this, '[handleError] $wrappedName: $error'),
    );

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
    ScopeDependencyAnyCancelled Function(Object error, StackTrace stackTrace)
        defaultState,
  ) {
    notifyObserver(
      (observer) => observer.onTrace(
        this,
        '[handlePostCancelError] $wrappedName: $error',
      ),
    );

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
