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

  /// Creates a lite scope.
  const LiteScope({
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

  //
  // Overriding block
  //

  /// Pre-initialization.
  ///
  /// Override this method if you need to perform pre-initialization before the
  /// state is created. In that case, also override the [buildOnInitializing]
  /// and [buildOnError] methods.
  Stream<AsyncScopeInitState> init() => Stream.value(AsyncScopeReady());

  /// Waiting builder.
  ///
  /// A builder waiting for access to the widget (see [scopeKey]) and the first
  /// [init] event.
  ///
  /// **Required, and the only builder here that is** — which is the other way
  /// round from the families that initialize something, where
  /// `buildOnInitializing` is the required one. The rule behind both is the
  /// same: exactly one branch before the ready one has to be written, and it
  /// is the branch that scope is certain to reach. A [LiteScope] initializes
  /// nothing of its own, so the branch it always has is this one — the frames
  /// spent waiting for a `scopeKey` and for the first event — while
  /// [buildOnInitializing] and [buildOnError] belong to an [init] most scopes
  /// never override.
  ///
  /// Returning `null` is allowed only when [buildOnInitializing] is
  /// overridden, since something has to be on screen: `null` here means "show
  /// the initializing branch instead", and the default of that one throws.
  Widget? buildOnWaiting(BuildContext context);

  /// Pre-initialization builder.
  ///
  /// Reached only by a scope that overrides [init], which is why it is
  /// optional: a scope that pre-initializes nothing has no progress to build.
  /// The default throws rather than returning a blank screen — a branch
  /// nobody wrote is a mistake, and a scope that shows nothing while it
  /// initializes looks like one that never initializes at all.
  Widget buildOnInitializing(BuildContext context, Object? progress) =>
      throw UnimplementedError(
        '$runtimeType overrides `init()` but not `buildOnInitializing()`. A '
        'scope that pre-initializes has frames to fill before it is ready, '
        'and this is the branch that fills them. Override it, or drop the '
        '`init()` override -- the default one is ready at once and never '
        'comes here.',
      );

  /// Error builder.
  ///
  /// Reached only by a scope that overrides [init], and optional for the same
  /// reason as [buildOnInitializing]: an initialization that does not exist
  /// cannot fail.
  ///
  /// The default throws, and carries the failure it was called for in the
  /// message: left out, that failure would be replaced on screen by the
  /// missing-builder error, and the reason the scope failed at all would go
  /// with it.
  Widget buildOnError(
    BuildContext context,
    Object error,
    StackTrace stackTrace,
    Object? progress,
  ) =>
      throw UnimplementedError(
        '$runtimeType overrides `init()` but not `buildOnError()`, and the '
        'initialization it never wrote a branch for has just failed with: '
        '$error',
      );

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
  /// Answers `null` on two conditions, not one: there is no such scope above
  /// [context], or there is one whose state does not exist yet. The state is
  /// created in the ready branch, so a scope still waiting for its `scopeKey`,
  /// still initializing, failed, or taken down by `close()` answers `null`
  /// exactly as an absent scope does. [of] tells the two apart; this does
  /// not.
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
  /// Throws on two conditions, not one: there is no such scope above
  /// [context], or there is one whose state does not exist yet. The state is
  /// created in the ready branch, so a scope still waiting for its `scopeKey`,
  /// still initializing, failed, or taken down by `close()` has none to give.
  /// The message says which of the two it was, and what state the scope was
  /// in — read it from below `buildOnReady()`, or check `isInitialized`
  /// first.
  static S of<W extends LiteScope<W, S>, S extends LiteScopeState<W, S>>(
    BuildContext context,
  ) =>
      ScopeContext.of<W, _LiteScopeElement<W, S>>(
        context,
        listen: false,
      )._stateOrThrow;

  /// Selects and returns a specific value from the state [S] of the scope [W]
  /// using the [selector] and becomes **dependent** on it.
  ///
  /// Reaches the state through the same door as [of], and throws on the same
  /// two conditions.
  static V select<W extends LiteScope<W, S>, S extends LiteScopeState<W, S>,
          V extends Object?>(
    BuildContext context,
    V Function(S scope) selector,
  ) =>
      ScopeContext.select<W, _LiteScopeElement<W, S>, V>(
        context,
        (element) => selector(element._stateOrThrow),
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
  Widget wrapState(Widget child) => widget.wrapState(this, child);

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
