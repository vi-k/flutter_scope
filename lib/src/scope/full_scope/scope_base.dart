part of '../scope.dart';

/// A function that initializes scope dependencies and yields [ScopeInitState]
/// updates.
///
/// {@category Scope}
typedef ScopeInitFunction<P extends Object, D extends ScopeDependencies>
    = Stream<ScopeInitState<P, D>> Function(BuildContext context);

/// A builder function used to display a waiting widget while the [Scope] is
/// waiting for a [Scope.scopeKey] and [Scope.initDependencies] to send their
/// first state.
///
/// {@category Scope}
typedef ScopeWaitingBuilder = Widget? Function(BuildContext context);

/// A builder function used to display a widget while the [Scope] is
/// initializing dependencies.
///
/// Contains optional [progress] data dynamically yielded during
/// initialization.
///
/// {@category Scope}
typedef ScopeInitBuilder<P extends Object> = Widget Function(
  BuildContext context,
  P? progress,
);

/// A builder function used to display an error widget if scope initialization
/// fails.
///
/// {@category Scope}
typedef ScopeErrorBuilder<P extends Object> = Widget Function(
  BuildContext context,
  Object error,
  StackTrace stackTrace,
  P? progress,
);

/// A base class for creating scopes with dependency injection and state
/// management.
///
/// Extends [ScopeCore] to provide lifecycle, initialization, and configuration
/// handling.
///
/// {@category Scope}
abstract base class Scope<W extends Scope<W, D, S>, D extends ScopeDependencies,
        S extends ScopeState<W, D, S>>
    extends ScopeCore<W, _ScopeElement<W, D, S>, D, S> {
  /// A key used to synchronize the initialization of the scope.
  final Object? scopeKey;

  /// The timeout duration for the [scopeKey] before it triggers
  /// [onScopeKeyTimeout].
  final Duration? scopeKeyTimeout;

  /// A callback invoked when the [scopeKeyTimeout] expires.
  final void Function()? onScopeKeyTimeout;

  /// The timeout duration for cancelling the initialization during the
  /// teardown, before it triggers [onInitCancellationTimeout].
  final Duration? initCancellationTimeout;

  /// A callback invoked when the [initCancellationTimeout] expires.
  final void Function()? onInitCancellationTimeout;

  /// The timeout duration for the asynchronous teardown of this scope, before
  /// it triggers [onDisposeAsyncTimeout].
  final Duration? disposeAsyncTimeout;

  /// A callback invoked when the [disposeAsyncTimeout] expires.
  final void Function()? onDisposeAsyncTimeout;

  /// The timeout duration for waiting to dispose child scopes.
  final Duration? waitForChildrenTimeout;

  /// A callback invoked when the [waitForChildrenTimeout] expires.
  final void Function()? onWaitForChildrenTimeout;

  /// An optional duration to pause after initialization is successful.
  final Duration? pauseAfterInitialization;

  /// Creates a scope.
  const Scope({
    super.key,
    super.tag,
    this.scopeKey,
    this.scopeKeyTimeout,
    this.onScopeKeyTimeout,
    this.initCancellationTimeout,
    this.onInitCancellationTimeout,
    this.disposeAsyncTimeout,
    this.onDisposeAsyncTimeout,
    this.waitForChildrenTimeout,
    this.onWaitForChildrenTimeout,
    this.pauseAfterInitialization,
    super.child, // Not used by default. You can use it at your own discretion.
  });

  /// Initializes the scope's dependencies and streams the initialization
  /// state.
  Stream<ScopeInitState<Object, D>> initDependencies(BuildContext context);

  /// Builds a widget to display while waiting for [scopeKey] and
  /// [initDependencies] to send their first state.
  Widget? buildOnWaiting(BuildContext context) => null;

  /// Builds a widget to display while the scope is initializing dependencies.
  Widget buildOnInitializing(BuildContext context, Object? progress);

  /// Builds a widget to display if an error occurs during initialization.
  Widget buildOnError(
    BuildContext context,
    Object error,
    StackTrace stackTrace,
    Object? progress,
  );

  /// Creates the state for this scope.
  S createState();

  /// Wraps the state builder with additional widgets, if needed.
  Widget wrapState(BuildContext context, D dependencies, Widget child) => child;

  /// Builds a widget to display while the scope is closing.
  Widget? buildOnClosing(BuildContext context) => null;

  @override
  // ignore: library_private_types_in_public_api
  _ScopeElement<W, D, S> createScopeElement() => _ScopeElement(this as W);

  /// Looks up and returns the parameters of the scope [W].
  ///
  /// If [listen] is true, the widget will be rebuilt when the scope changes.
  static W paramsOf<W extends Scope<W, D, S>, D extends ScopeDependencies,
          S extends ScopeState<W, D, S>>(
    BuildContext context, {
    required bool listen,
  }) =>
      listen
          ? ScopeContext.select<W, _ScopeElement<W, D, S>, W>(
              context,
              (element) => element.widget,
            )
          : ScopeContext.of<W, _ScopeElement<W, D, S>>(
              context,
              listen: false,
            ).widget;

  /// Selects and returns a specific parameter of the scope [W] using the
  /// [selector] and becomes **dependent** on it.
  static V selectParam<W extends Scope<W, D, S>, D extends ScopeDependencies,
          S extends ScopeState<W, D, S>, V extends Object?>(
    BuildContext context,
    V Function(W widget) selector,
  ) =>
      ScopeContext.select<W, _ScopeElement<W, D, S>, V>(
        context,
        (element) => selector(element.widget),
      );

  /// Tries to find and return the state [S] of the scope [W] from the given
  /// [context].
  ///
  /// Returns `null` if the scope is not found.
  static S? maybeOf<W extends Scope<W, D, S>, D extends ScopeDependencies,
          S extends ScopeState<W, D, S>>(BuildContext context) =>
      ScopeContext.maybeOf<W, _ScopeElement<W, D, S>>(
        context,
        listen: false,
      )?._globalStateKey.currentState;

  /// Finds and returns the state [S] of the scope [W] from the given
  /// [context].
  ///
  /// Throws an error if the scope is not found.
  static S of<W extends Scope<W, D, S>, D extends ScopeDependencies,
          S extends ScopeState<W, D, S>>(BuildContext context) =>
      ScopeContext.of<W, _ScopeElement<W, D, S>>(
        context,
        listen: false,
      )._stateOrThrow;

  /// Selects and returns a specific value from the state [S] of the scope [W]
  /// using the [selector] and becomes **dependent** on it.
  static V select<W extends Scope<W, D, S>, D extends ScopeDependencies,
          S extends ScopeState<W, D, S>, V extends Object?>(
    BuildContext context,
    V Function(S scope) selector,
  ) =>
      ScopeContext.select<W, _ScopeElement<W, D, S>, V>(
        context,
        (element) => selector(element._stateOrThrow),
      );
}

/// The default element underlying [Scope].
final class _ScopeElement<W extends Scope<W, D, S>, D extends ScopeDependencies,
        S extends ScopeState<W, D, S>>
    extends ScopeElementBase<W, _ScopeElement<W, D, S>, D, S> {
  _ScopeElement(super.widget);

  @override
  Object? get scopeKey => widget.scopeKey;

  @override
  Duration? get scopeKeyTimeout => widget.scopeKeyTimeout;

  @override
  void onScopeKeyTimeout() => widget.onScopeKeyTimeout?.call();

  @override
  Duration? get initCancellationTimeout => widget.initCancellationTimeout;

  @override
  void onInitCancellationTimeout() => widget.onInitCancellationTimeout?.call();

  @override
  Duration? get disposeAsyncTimeout => widget.disposeAsyncTimeout;

  @override
  void onDisposeAsyncTimeout() => widget.onDisposeAsyncTimeout?.call();

  @override
  Duration? get waitForChildrenTimeout => widget.waitForChildrenTimeout;

  @override
  void onWaitForChildrenTimeout() => widget.onWaitForChildrenTimeout?.call();

  @override
  Duration? get pauseAfterInitialization => widget.pauseAfterInitialization;

  @override
  Stream<ScopeInitState<Object, D>> initDependencies() =>
      widget.initDependencies(this);

  @override
  Widget? buildOnWaiting() => widget.buildOnWaiting(this);

  @override
  Widget buildOnInitializing(Object? progress) =>
      widget.buildOnInitializing(this, progress);

  @override
  Widget buildOnError(
    Object error,
    StackTrace stackTrace,
    Object? progress,
  ) =>
      widget.buildOnError(this, error, stackTrace, progress);

  @override
  S createState() => widget.createState();

  @override
  Widget wrapState(Widget child) => widget.wrapState(this, dependencies, child);

  @override
  Widget? buildOnClosing() => widget.buildOnClosing(this);
}

/// The state implementation for [Scope].
///
/// Extends [ScopeCoreState] to give convenient access to the [dependencies].
///
/// {@category Scope}
abstract base class ScopeState<W extends Scope<W, D, S>,
        D extends ScopeDependencies, S extends ScopeState<W, D, S>>
    extends ScopeCoreState<W, _ScopeElement<W, D, S>, D, S> {
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
