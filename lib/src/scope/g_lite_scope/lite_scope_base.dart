part of '../scope.dart';

/// A base class for creating lite scopes without dependency management payload.
///
/// Extends [LiteScopeCore] to provide lifecycle and initialization handling.
///
/// {@category LiteScope}
abstract base class LiteScope<W extends LiteScope<W, S>,
        S extends LiteScopeState<W, S>>
    extends LiteScopeCore<W, _LiteScopeElement<W, S>, S> {
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

  /// The timeout duration for waiting to dispose child scopes.
  final Duration? waitForChildrenTimeout;

  /// A callback invoked when the [waitForChildrenTimeout] expires.
  final void Function()? onWaitForChildrenTimeout;

  /// An optional duration to pause after initialization is successful.
  final Duration? pauseAfterInitialization;

  /// Creates a lite scope.
  const LiteScope({
    super.key,
    super.tag,
    this.scopeKey,
    this.scopeKeyTimeout,
    this.onScopeKeyTimeout,
    this.initCancellationTimeout,
    this.onInitCancellationTimeout,
    this.waitForChildrenTimeout,
    this.onWaitForChildrenTimeout,
    this.pauseAfterInitialization,
    super.child, // Not used by default. You can use it at your own discretion.
  });

  //
  // Overriding block
  //

  /// Pre-initialization.
  ///
  /// Override this method if you need to perform pre-initialization before the
  /// state is created. In that case, also override the [buildOnInitializing]
  /// and [buildOnError] methods.
  Stream<AsyncScopeInitState> init() => Stream.value(AsyncScopeReady());

  /// Waiting buider.
  ///
  /// A builder waiting for access to the widget (see [scopeKey]) and the first
  /// [init] event.
  ///
  /// The method may return `null` if the [buildOnInitializing] method is
  /// overridden.
  Widget? buildOnWaiting(BuildContext context);

  /// Pre-initialization builder.
  ///
  /// This method will only be called if you have overridden [init].
  Widget buildOnInitializing(BuildContext context, Object? progress) =>
      throw UnimplementedError();

  /// Error builder.
  ///
  /// This method will only be called if you have overridden [init].
  Widget buildOnError(
    BuildContext context,
    Object error,
    StackTrace stackTrace,
    Object? progress,
  ) =>
      throw UnimplementedError();

  /// Creates the state for this scope.
  S createState();

  /// Wraps the state builder with additional widgets, if needed.
  Widget wrapState(BuildContext context, Widget child) => child;

  /// Builds a widget to display while the scope is closing.
  Widget? buildOnClosing(BuildContext context) => null;

  //
  // End of overriding block
  //

  @override
  // ignore: library_private_types_in_public_api
  _LiteScopeElement<W, S> createScopeElement() => _LiteScopeElement(this as W);

  /// Looks up and returns the parameters of the scope [W].
  ///
  /// If [listen] is true, the widget will be rebuilt when the scope changes.
  static W paramsOf<W extends LiteScope<W, S>, S extends LiteScopeState<W, S>>(
    BuildContext context, {
    required bool listen,
  }) =>
      listen
          ? ScopeContext.select<W, _LiteScopeElement<W, S>, W>(
              context,
              (element) => element.widget,
            )
          : ScopeContext.of<W, _LiteScopeElement<W, S>>(
              context,
              listen: false,
            ).widget;

  /// Selects and returns a specific parameter of the scope [W] using the
  /// [selector] and becomes **dependent** on it.
  static V selectParam<W extends LiteScope<W, S>,
          S extends LiteScopeState<W, S>, V extends Object?>(
    BuildContext context,
    V Function(W widget) selector,
  ) =>
      ScopeContext.select<W, _LiteScopeElement<W, S>, V>(
        context,
        (element) => selector(element.widget),
      );

  /// Tries to find and return the state [S] of the scope [W] from the given
  /// [context].
  ///
  /// Returns `null` if the scope is not found.
  static S? maybeOf<W extends LiteScope<W, S>, S extends LiteScopeState<W, S>>(
    BuildContext context,
  ) =>
      ScopeContext.maybeOf<W, _LiteScopeElement<W, S>>(
        context,
        listen: false,
      )?._globalStateKey.currentState;

  /// Finds and returns the state [S] of the scope [W] from the given
  /// [context].
  ///
  /// Throws an error if the scope is not found.
  static S of<W extends LiteScope<W, S>, S extends LiteScopeState<W, S>>(
    BuildContext context,
  ) =>
      ScopeContext.of<W, _LiteScopeElement<W, S>>(
        context,
        listen: false,
      )._globalStateKey.currentState!;

  /// Selects and returns a specific value from the state [S] of the scope [W]
  /// using the [selector] and becomes **dependent** on it.
  static V select<W extends LiteScope<W, S>, S extends LiteScopeState<W, S>,
          V extends Object?>(
    BuildContext context,
    V Function(S scope) selector,
  ) =>
      ScopeContext.select<W, _LiteScopeElement<W, S>, V>(
        context,
        (element) => selector(element._globalStateKey.currentState!),
      );
}

/// The default element underlying [LiteScope].
final class _LiteScopeElement<W extends LiteScope<W, S>,
        S extends LiteScopeState<W, S>>
    extends LiteScopeElementBase<W, _LiteScopeElement<W, S>, S> {
  _LiteScopeElement(super.widget);

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
  Duration? get waitForChildrenTimeout => widget.waitForChildrenTimeout;

  @override
  void onWaitForChildrenTimeout() => widget.onWaitForChildrenTimeout?.call();

  @override
  Duration? get pauseAfterInitialization => widget.pauseAfterInitialization;

  @override
  Stream<AsyncScopeInitState> initAsync() => widget.init();

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
  Widget? buildOnClosing() => widget.buildOnClosing(this);
}

/// The state implementation for [LiteScope].
///
/// Extends [LiteScopeCoreState].
///
/// {@category LiteScope}
abstract base class LiteScopeState<W extends LiteScope<W, S>,
        S extends LiteScopeState<W, S>>
    extends LiteScopeCoreState<W, _LiteScopeElement<W, S>, S> {
  //
  // Overriding block
  //

  /// Initializes the scope asynchronously.
  @override
  FutureOr<void> initAsync() {}

  /// Disposes of the scope asynchronously.
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
