part of '../scope.dart';

/// A core abstract class for scopes, bridging dependency injection with state
/// management.
///
/// {@category Scope}
abstract base class ScopeCore<
    W extends ScopeCore<W, E, D, S>,
    E extends ScopeElementBase<W, E, D, S>,
    D extends ScopeDependencies,
    S extends ScopeCoreState<W, E, D, S>> extends LiteScopeCore<W, E, S> {
  /// Creates the widget half of a scope.
  const ScopeCore({
    super.key,
    super.tag,
    super.child, // Not used by default. You can use it at your own discretion.
  });

  /// Looks up and returns the parameters of the scope [W].
  ///
  /// If [listen] is true, the widget will be rebuilt when the scope changes.
  static W paramsOf<
          W extends ScopeCore<W, E, D, S>,
          E extends ScopeElementBase<W, E, D, S>,
          D extends ScopeDependencies,
          S extends ScopeCoreState<W, E, D, S>>(
    BuildContext context, {
    required bool listen,
  }) =>
      listen
          ? ScopeContext.select<W, E, W>(
              context,
              (element) => element.widget,
            )
          : ScopeContext.of<W, E>(
              context,
              listen: false,
            ).widget;

  /// Selects and returns a specific parameter of the scope [W] using the
  /// [selector] and becomes **dependent** on it.
  static V selectParam<
          W extends ScopeCore<W, E, D, S>,
          E extends ScopeElementBase<W, E, D, S>,
          D extends ScopeDependencies,
          S extends ScopeCoreState<W, E, D, S>,
          V extends Object?>(
    BuildContext context,
    V Function(W widget) selector,
  ) =>
      ScopeContext.select<W, E, V>(
        context,
        (element) => selector(element.widget),
      );

  /// Tries to find and return the state [S] of the scope [W] from the given
  /// [context].
  ///
  /// Answers `null` on two conditions, not one: there is no such scope above
  /// [context], or there is one whose state does not exist yet. The state is
  /// created in the ready branch, so a scope still waiting for its `scopeKey`,
  /// still initializing, failed, or taken down by `close()` answers `null`
  /// exactly as an absent scope does. [of] tells the two apart; this does
  /// not.
  static S? maybeOf<
          W extends ScopeCore<W, E, D, S>,
          E extends ScopeElementBase<W, E, D, S>,
          D extends ScopeDependencies,
          S extends ScopeCoreState<W, E, D, S>>(BuildContext context) =>
      ScopeContext.maybeOf<W, E>(
        context,
        listen: false,
      )?._globalStateKey.currentState;

  /// Finds and returns the state [S] of the scope [W] from the given
  /// [context].
  ///
  /// Throws on two conditions, not one: there is no such scope above
  /// [context], or there is one whose state does not exist yet. The state is
  /// created in the ready branch, so a scope still waiting for its `scopeKey`,
  /// still initializing, failed, or taken down by `close()` has none to give.
  /// The message says which of the two it was, and what state the scope was
  /// in — read it from below `buildOnReady()`, or check `isInitialized`
  /// first.
  static S of<
          W extends ScopeCore<W, E, D, S>,
          E extends ScopeElementBase<W, E, D, S>,
          D extends ScopeDependencies,
          S extends ScopeCoreState<W, E, D, S>>(BuildContext context) =>
      ScopeContext.of<W, E>(
        context,
        listen: false,
      )._stateOrThrow;

  /// Selects and returns a specific value from the state [S] of the scope [W]
  /// using the [selector] and becomes **dependent** on it.
  ///
  /// Reaches the state through the same door as [of], and throws on the same
  /// two conditions.
  static V select<
          W extends ScopeCore<W, E, D, S>,
          E extends ScopeElementBase<W, E, D, S>,
          D extends ScopeDependencies,
          S extends ScopeCoreState<W, E, D, S>,
          V extends Object?>(
    BuildContext context,
    V Function(S scope) selector,
  ) =>
      ScopeContext.select<W, E, V>(
        context,
        (element) => selector(element._stateOrThrow),
      );
}

/// The core element base class for [ScopeCore].
///
/// Extends [LiteScopeElementBase] to provide dependency initialization and
/// management.
///
/// {@category Scope}
abstract base class ScopeElementBase<
        W extends ScopeCore<W, E, D, S>,
        E extends ScopeElementBase<W, E, D, S>,
        D extends ScopeDependencies,
        S extends ScopeCoreState<W, E, D, S>>
    extends LiteScopeElementBase<W, E, S> {
  /// Creates the element of a scope.
  ScopeElementBase(super.widget);

  /// The initialized dependencies for this scope.
  D get dependencies => _dependencies ?? (throw StateError('Not initialized'));
  D? _dependencies;

  //
  // Overriding block
  //

  /// Initializes the dependencies and returns a stream of their initialization
  /// states.
  Stream<ScopeInitState<Object, D>> initDependencies();

  /// Builds a widget to display while waiting.
  @override
  Widget? buildOnWaiting();

  /// Builds a widget to display while the scope is initializing.
  @override
  Widget buildOnProgress(Object? progress);

  /// Builds a widget to display when an error occurs during initialization.
  @override
  Widget buildOnError(
    Object error,
    StackTrace stackTrace,
    Object? progress,
  );

  /// Creates the state for this scope.
  @override
  S createState();

  /// Wraps the state builder with additional widgets, if needed.
  @override
  Widget wrapState(Widget child) => child;

  /// Builds a widget to display while the scope is closing.
  @override
  Widget? buildOnClosing() => null;

  //
  // End of overriding block
  //

  @override
  Stream<AsyncScopeInitState> initScope() => initDependencies().map(
        (state) {
          switch (state) {
            case ScopeProgress(:final progress):
              return AsyncScopeProgress(progress);
            case ScopeReady(:final dependencies):
              // Refused here rather than one layer up, which is where the
              // neighbouring `AsyncDataScope` refuses the same thing and says
              // so in the same words. This `map` runs as the event goes past
              // and the `asyncMap` above only after it, so the check for a
              // second initialization up there arrived to find the field
              // already replaced: the model stayed as it was, the dependents
              // heard nothing, and the container the scope had actually been
              // using was left with nobody to unmount or dispose of it.
              if (_dependencies != null) {
                throw StateError('$W already initialized');
              }

              _dependencies = dependencies;
              return AsyncScopeReady();
          }
        },
      );

  @override
  void onUnmount() {
    AsyncError? failure;

    // The state lets go of its own first, the dependencies after it, in the
    // same order as the asynchronous half below -- and, as there, the second
    // half is not the first half's to cancel. A state that failed to drop
    // what it holds is still a state whose dependencies are holding theirs,
    // and this is the only pass that drops those: `unmountScope()` marks
    // itself done before it calls this, so nothing comes back for a second
    // attempt, and what a dependency releases only in `unmount` would live
    // on until the tree died with it.
    try {
      super.onUnmount();
      // ignore: avoid_catching_errors
    } on Object catch (error, stackTrace) {
      failure = AsyncError(error, stackTrace);
    }

    // Guarded on its own for the same reason, and the two failures are not
    // equals: the state let go first, so its failure is the one that explains
    // whatever the container made of the same teardown. Uncaught, as it was,
    // the container's failure left through the throw and took the state's
    // with it -- the first one vanished without so much as a log line.
    // [ScopeAutoDependencies] never gets this far, since it reports what its
    // children throw itself; a container written against the interface does.
    try {
      _dependencies?.onUnmount();
      // ignore: avoid_catching_errors
    } on Object catch (error, stackTrace) {
      if (failure == null) {
        failure = AsyncError(error, stackTrace);
      } else {
        // Both channels, as everywhere else a failure has no caller left to
        // be raised at: the stage above sends `onError` for the failure that
        // leaves through the throw, and this one would otherwise reach the
        // observer through neither.
        notifyObserver(
          (observer) =>
              observer.onError(this, ScopePhase.unmount, error, stackTrace),
        );
        _reportFailure(error, stackTrace, 'while unmounting the dependencies');
      }
    }

    if (failure case final failure?) {
      Error.throwWithStackTrace(failure.error, failure.stackTrace);
    }
  }

  /// `true`: the two stages below are bounded here, one limit each.
  ///
  /// See [boundsDisposeScopeItself]. A single limit around both gave a state
  /// that never finished the power to skip the container entirely — the wait
  /// expired, the teardown went on to give back the `scopeKey`, and every
  /// dependency stayed held with nothing left to release it.
  @override
  bool get boundsDisposeScopeItself => true;

  @override
  Future<void> disposeScope() async {
    AsyncError? failure;

    // Read once and used for both stages: the parameter says how long *a*
    // release of this scope may take, and there are two of them behind this
    // method. A teardown where both hang therefore reports two expiries, which
    // is what happened — two stages were given up on.
    final limit = resolveTimeout(
      disposeScopeTimeout,
      ScopeConfig.defaultDisposeScopeTimeout,
    );

    Future<void> bounded(Future<void> work, String what) => limit == null
        ? work
        : _awaitBounded(work, limit, what, onDisposeScopeTimeout);

    // The state releases what it owns first, the dependencies after it -- and
    // the second half is not the first half's to cancel. A state that failed
    // to let go of its own is still a state whose dependencies are holding
    // theirs, and this is the only place left to give those back. A state that
    // never finishes is the same case, which is why the limit sits on each
    // half rather than around the pair.
    try {
      await bounded(super.disposeScope(), 'its state to be disposed of');
      // ignore: avoid_catching_errors
    } on Object catch (error, stackTrace) {
      failure = AsyncError(error, stackTrace);
    }

    // Guarded like the half above, and for the same reason: the first failure
    // is the one that leaves through the throw, the second through a report.
    try {
      final result = _dependencies?.dispose();
      if (result is Future<void>) {
        await bounded(result, 'its dependencies to be disposed of');
      }
      // ignore: avoid_catching_errors
    } on Object catch (error, stackTrace) {
      if (failure == null) {
        failure = AsyncError(error, stackTrace);
      } else {
        // Both channels, for the reason given in the half above.
        notifyObserver(
          (observer) =>
              observer.onError(this, ScopePhase.disposal, error, stackTrace),
        );
        _reportFailure(
          error,
          stackTrace,
          'while disposing of the dependencies',
        );
      }
    }

    if (failure case final failure?) {
      Error.throwWithStackTrace(failure.error, failure.stackTrace);
    }
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<D?>('dependencies', _dependencies));
  }
}

/// The core state base class for [ScopeCore].
///
/// Provides convenient access to the initialized [dependencies] and supports
/// asynchronous initialization and disposal.
///
/// {@category Scope}
abstract base class ScopeCoreState<
    W extends ScopeCore<W, E, D, S>,
    E extends ScopeElementBase<W, E, D, S>,
    D extends ScopeDependencies,
    S extends ScopeCoreState<W, E, D, S>> extends LiteScopeCoreState<W, E, S> {
  /// The dependency container, ready before [initState] runs.
  D get dependencies => _scopeElement.dependencies;

  //
  // Overriding block
  //

  @override
  FutureOr<void> initStateAsync() {}

  @override
  FutureOr<void> disposeStateAsync() {}

  @override
  Widget build(BuildContext context);

  //
  // End of overriding block
  //

  /// The parameters defined in the associated scope widget.
  @override
  W get params;

  /// Whether the scope initialization is fully completed.
  @override
  bool get isInitialized;

  /// Called after the state has been successfully initialized.
  @override
  void onInitialized();

  @override
  void notifyDependents();

  /// Closes the scope gracefully.
  @override
  Future<void> close();
}
