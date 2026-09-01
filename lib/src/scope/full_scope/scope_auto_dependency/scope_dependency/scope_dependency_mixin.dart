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

  /// Told the path of each step of this subtree as it is entered, before the
  /// step does anything.
  ///
  /// The other half of what [init] yields once the step is done. Set by the
  /// enclosing group, which wraps it in its own `_path` — the very assembly
  /// the completed step travels through on its way up, so the two halves
  /// cannot come to report different paths for one step.
  ///
  /// A second channel rather than a second kind of stream element, because
  /// the stream is the public [ScopeDependency.init] and its element type is
  /// what a caller's own implementation returns; and because the container
  /// counts its steps by the elements of that stream, so a mark travelling it
  /// would move every progress bar by one.
  void Function(String path)? _onStepStarted;

  /// The same, for the disposal walk.
  void Function(String path)? _onDisposalStepStarted;

  /// Told the path of each step of this subtree as it comes back.
  ///
  /// The exit half of [_onDisposalStepStarted], wired by the same code, wrapped
  /// by the same `_path` and travelling the same way — so the pair cannot come
  /// apart depending on who drove the walk. It used to travel the stream of
  /// [ScopeDependency.dispose] instead, which belongs to whoever subscribed:
  /// a walk driven by hand, or one this node only joined, left the container
  /// hearing entries with nothing behind them, and every step read as a
  /// release that hung.
  void Function(String path)? _onDisposalStepEnded;

  /// Told what ended a step of this subtree, when what ended it was a throw.
  ///
  /// The third outcome an entry can have, beside the exit and the silence of a
  /// step still running. Without it an observer that heard the entry has no
  /// way to tell a release that failed from one that hung — and it heard that
  /// entry on the container's behalf however the walk was started, so it has
  /// to hear this the same way. The failure used to reach the container only
  /// through the stream of the walk, which belongs to whoever subscribed.
  ///
  /// Carries the path for the same reason the other two do: the name of the
  /// failing dependency is assembled on the way up, by the same `_path` the
  /// marks travel through, and [ScopeObserver.onError] is handed a
  /// [ScopeDependencyException] built from it at the top. Reported from the
  /// node itself, the name would be the leaf's own and the groups above it
  /// would be missing.
  void Function(String path, Object error, StackTrace stackTrace)?
      _onDisposalStepFailed;

  /// Points both entry channels of [dependency] at the given callbacks.
  ///
  /// The one place either channel is ever assigned. It used to be two
  /// near-identical methods -- one on [ScopeDependencyGroup], one on
  /// [ScopeAutoDependencies] -- set from five sites between them, so that a
  /// new kind of group, or a `_runDispose` that did not go through
  /// `_disposalOrder`, would lose the marks of its whole subtree without a
  /// word. What actually differs between the two callers is only what a mark
  /// is told to do: a group wraps it in its own path segment, a container
  /// hands it to its observer. That is what they pass in; the wiring itself
  /// is the same both times, and is now written once.
  ///
  /// A dependency of the caller's own making is not a [ScopeDependencyMixin]
  /// and has nowhere to take these, so it announces neither entry itself. Its
  /// completed initialization step still arrives, since that half travels the
  /// stream of [ScopeDependency.init], which is the part of the contract it
  /// does implement; and its release is announced for it — by the group above
  /// it as the path comes through, or, for such a dependency standing as the
  /// root, by the container's own listener.
  static void _wireStepsStarted(
    ScopeDependency dependency, {
    required void Function(String path) onStepStarted,
    required void Function(String path) onDisposalStepStarted,
    required void Function(String path) onDisposalStepEnded,
    required void Function(String path, Object error, StackTrace stackTrace)
        onDisposalStepFailed,
  }) {
    if (dependency is! ScopeDependencyMixin) {
      return;
    }

    dependency
      .._onStepStarted = onStepStarted
      .._onDisposalStepStarted = onDisposalStepStarted
      .._onDisposalStepEnded = onDisposalStepEnded
      .._onDisposalStepFailed = onDisposalStepFailed;
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
    // A tree that is being initialized is not a tree that has been disposed
    // of, whatever a previous walk wrote down. It matters for the one tree
    // that can be walked before it is ever initialized: nothing was released,
    // because nothing had been taken, but the walk still marked the disposal
    // done -- and the node kept saying [ScopeDependencyInitial], which is what
    // lets this method run at all. Left standing, that mark made the tree
    // answer `disposalRequired` with `false` from the first instant of a life
    // it had only just begun, and the teardown after it walked past
    // everything the initializer had taken.
    _isDisposalDone = false;

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
    // Before the joiner below and before any mark is written, for the reason
    // `ScopeAutoDependencies._runDispose` refuses the same thing one level up.
    // A dependency parked inside its initializer has registered nothing yet,
    // so the walk reads it as one with nothing to release and marks it as
    // passed by -- and the group above it then skips it by `disposalRequired`
    // for as long as it lives. What the initializer registers a moment later
    // is called by nothing, ever.
    //
    // The container's guard stands on the container's own door. This is the
    // other one: the tree is handed out by `ScopeAutoDependencies.root`, and
    // a tree belongs to whoever drives one -- public, documented, and it met
    // no guard at all. Every node between that door and the parked leaf is
    // initializing too, a group being one for as long as its children are, so
    // asking here closes the way in wherever it was entered.
    if (_initializing) {
      throw StateError(
        '$wrappedName is initializing right now, and a `dispose()` started '
        'here would walk a tree whose dependencies have not registered their '
        'teardown yet: one parked inside its initializer looks like a '
        'dependency with nothing to release, and what it registers a moment '
        'later would never be called by anything. Await the initialization '
        'that is running, or cancel it, and dispose of the tree once it has '
        'ended.',
      );
    }

    // Joined rather than repeated, the way `ScopeAutoDependencies.dispose()`
    // joins its own one level up -- and for a heavier reason than tidiness.
    //
    // A second walk arriving while the first was parked in a disposer found
    // that child already stripped of its hook -- taken off before the `await`,
    // so that a disposer runs exactly once -- decided there was nothing to do
    // there, and walked on to the child below it. In a `sequential` group that
    // is the child the parked one is built on top of, and the group's whole
    // promise is that it is released after, never beside. `[b started, a
    // released, b released]` is what came out. The second walk then reported
    // itself finished while the first was still holding, so a caller that
    // waited on it went on to use what it thought it had given back.
    //
    // The joiner is told when the walk is over and is given no paths of its
    // own: they were handed to whoever asked first, and a walk cannot yield
    // them twice without every node keeping a copy of its own history for as
    // long as it lives.
    while (true) {
      final running = _disposalInFlight;
      if (running == null) {
        break;
      }

      // Raises what that walk raised, if it raised anything: both callers
      // asked for the same disposal, and telling the second that it went well
      // is the same untruth as telling it the walk is over when it is not.
      await running.future;

      // Over, and everything it was due to release is released. Its work
      // counts as ours.
      if (_isDisposalDone) {
        return;
      }

      // Stopped halfway instead -- a caller cancelled it. The tree still needs
      // disposing of, and this caller is one who asked for that, so the loop
      // goes round: either somebody else has started a walk in the meantime
      // and it is joined too, or the way is clear and it is walked below.
    }

    final inFlight = Completer<void>();
    _disposalInFlight = inFlight;
    // Nobody has to join, and a completer completed with an error nobody
    // listens to is an unhandled asynchronous error. This listener is not the
    // one that swallows it: `catchError` answers a future of its own, and a
    // joiner still hears what the walk raised.
    unawaited(inFlight.future.catchError((Object _) {}));
    _disposalFailure = null;

    // Whether the walk got to its end, however it got there.
    //
    // The state cannot answer this, and used to be asked: anything other than
    // [ScopeDependencyInitialized] was read as "the walk finished". That holds
    // for a walk that finished -- the line after the `yield*` has just put
    // [ScopeDependencyDisposed] there -- and it is wrong for every cancelled
    // walk that started from somewhere else. A tree in
    // [ScopeDependencyFailed] or [ScopeDependencyCancelled] is one a caller
    // leads by hand after an initialization went wrong, and
    // [ScopeDependencyDisposalCancelled] is the second cancellation of the
    // second `dispose()` this class promises to allow. Stopped halfway, each
    // of those said it was done: [ScopeDependencyGroup.disposalRequired] then
    // answered `false`, the children the walk never reached went on holding
    // what they took, and `_prepareDependencies` built a new tree over the
    // top of them without a word. Only the first of the four -- the one that
    // started from `Initialized` -- was ever accounted for.
    var walkEnded = false;

    try {
      yield* runStreamGuarded(
        _runDispose,
        _handleDisposalPostCancelError,
        debugName: name,
        observable: this,
      ).handleError(_handleDisposalError);
      walkEnded = true;
      _state = switch (_state) {
        final _ScopeDependencyWithErrors state when state.hasErrors => state,
        // A node that never ran goes on saying so.
        // [ScopeDependencyMixin._markNothingToDispose] keeps
        // [ScopeDependencyInitial] on a child for exactly this reason, and
        // says why: "not initialized" is the true thing to say about it. The
        // node the walk passes through itself was saying the opposite --
        // [ScopeDependencyDisposed] -- so a dump of a tree that was built and
        // then let go of without ever being initialized had a root claiming a
        // teardown over children that had never started.
        ScopeDependencyInitial() => _state,
        _ => const ScopeDependencyDisposed(),
      };
    } finally {
      // Let go of the walk before the joiners are woken, so that one of them
      // starting a walk of its own from the continuation finds the way clear.
      _disposalInFlight = null;
      if (_disposalFailure case final failure?) {
        inFlight.completeError(failure.error, failure.stackTrace);
      } else {
        inFlight.complete();
      }

      // Catch the cancellation.
      if (walkEnded) {
        _isDisposalDone = true;
      } else if (_state is ScopeDependencyInitialized) {
        _state = ScopeDependencyDisposalCancelled();
      }
    }
  }

  /// The walk running right now, joined by anyone who asks for a second.
  ///
  /// Cleared as that walk ends, so a later call runs again: a walk a caller
  /// stopped halfway leaves the tree still asking to be disposed of, and the
  /// call that picks it up must not be turned into a joiner of something that
  /// is already over.
  Completer<void>? _disposalInFlight;

  /// What the walk running right now has failed with, for the joiners.
  ///
  /// Recorded where the failure actually passes rather than caught around the
  /// walk: `yield*` hands a delegated stream's error to the listener and goes
  /// on with the next statement, so a `catch` around it never runs and the
  /// generator finishes as though nothing had gone wrong. A `catch` is what
  /// stood here, and it made this class promise the joiners a failure it then
  /// never gave them.
  AsyncError? _disposalFailure;

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
    // Kept for whoever joined this walk; the first one is the one they get,
    // as it is the one the walk itself carries out.
    _disposalFailure ??= AsyncError(error, stackTrace);
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
