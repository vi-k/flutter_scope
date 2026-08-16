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
  /// Returns `null` if the scope is not found.
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
  /// Throws an error if the scope is not found.
  static S of<
          W extends ScopeCore<W, E, D, S>,
          E extends ScopeElementBase<W, E, D, S>,
          D extends ScopeDependencies,
          S extends ScopeCoreState<W, E, D, S>>(BuildContext context) =>
      ScopeContext.of<W, E>(
        context,
        listen: false,
      )._globalStateKey.currentState!;

  /// Selects and returns a specific value from the state [S] of the scope [W]
  /// using the [selector] and becomes **dependent** on it.
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
        (element) => selector(element._globalStateKey.currentState!),
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
  Widget buildOnInitializing(Object? progress);

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
  Stream<AsyncScopeInitState> initAsync() => initDependencies().map(
        (state) {
          switch (state) {
            case ScopeProgress(:final progress):
              return AsyncScopeProgress(progress);
            case ScopeReady(:final dependencies):
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

    _dependencies?.onUnmount();

    if (failure case final failure?) {
      Error.throwWithStackTrace(failure.error, failure.stackTrace);
    }
  }

  @override
  Future<void> disposeAsync() async {
    AsyncError? failure;

    // The state releases what it owns first, the dependencies after it -- and
    // the second half is not the first half's to cancel. A state that failed
    // to let go of its own is still a state whose dependencies are holding
    // theirs, and this is the only place left to give those back.
    try {
      await super.disposeAsync();
      // ignore: avoid_catching_errors
    } on Object catch (error, stackTrace) {
      failure = AsyncError(error, stackTrace);
    }

    final result = _dependencies?.dispose();
    if (result is Future<void>) {
      await result;
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

  /// Initializes the scope asynchronously.
  @override
  FutureOr<void> initAsync() {}

  /// Disposes the scope asynchronously.
  @override
  FutureOr<void> disposeAsync() {}

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
