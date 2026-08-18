part of '../scope.dart';

/// {@category AsyncControllerScope}
abstract base class AsyncControllerScopeBase<
        W extends AsyncControllerScopeBase<W, C>, C extends ScopeController>
    extends AsyncControllerScopeCore<W, _AsyncControllerScopeElement<W, C>, C> {
  /// Serializes this scope with the others that share the key.
  ///
  /// A scope with a key starts only once the previous holder has finished
  /// disposing of itself. Needs an [AsyncScopeCoordinator] above it.
  final Object? scopeKey;

  /// How long to wait for [scopeKey]; `null` takes the default.
  ///
  /// Defaults to [ScopeConfig.defaultScopeKeyTimeout]. Removing the limit
  /// altogether is done there, not here.
  final Duration? scopeKeyTimeout;

  /// Called when the wait for [scopeKey] expires.
  ///
  /// The expiry is reported through [FlutterError.reportError] either way,
  /// and the scope proceeds as if the wait had succeeded.
  final void Function()? onScopeKeyTimeout;

  /// How long the teardown waits for the initialization of the controller to
  /// be cancelled; `null` takes the default.
  ///
  /// Defaults to [ScopeConfig.defaultInitCancellationTimeout]. Removing the
  /// limit altogether is done there, not here.
  final Duration? initCancellationTimeout;

  /// Called when the wait for the cancellation expires.
  ///
  /// The expiry is reported through [FlutterError.reportError] either way,
  /// and the teardown goes on without the initialization.
  final void Function()? onInitCancellationTimeout;

  /// How long to wait for the teardown of the controller; `null` takes the
  /// default.
  ///
  /// Defaults to [ScopeConfig.defaultDisposeScopeTimeout]. Removing the limit
  /// altogether is done there, not here.
  final Duration? disposeScopeTimeout;

  /// Called when the wait for the teardown expires.
  ///
  /// The expiry is reported through [FlutterError.reportError] either way,
  /// and the release goes on without waiting for the teardown to finish.
  final void Function()? onDisposeScopeTimeout;

  /// How long to wait for the child scopes; `null` takes the default.
  ///
  /// Defaults to [ScopeConfig.defaultWaitForChildrenTimeout]. Removing the
  /// limit altogether is done there, not here.
  final Duration? waitForChildrenTimeout;

  /// Called when the wait for the child scopes expires.
  ///
  /// The expiry is reported through [FlutterError.reportError] either way,
  /// and the teardown goes on without the children that never finished.
  final void Function()? onWaitForChildrenTimeout;

  /// Holds the ready branch back for this long after the initialization.
  ///
  /// Keeps a loading indicator on screen long enough to be read.
  /// [ScopeConfig.pauseAfterInitializationEnabled] turns every such pause
  /// off at once.
  final Duration? pauseAfterInitialization;

  /// Creates a scope owning a controller.
  const AsyncControllerScopeBase({
    super.key,
    super.tag,
    this.scopeKey,
    this.scopeKeyTimeout,
    this.onScopeKeyTimeout,
    this.initCancellationTimeout,
    this.onInitCancellationTimeout,
    this.disposeScopeTimeout,
    this.onDisposeScopeTimeout,
    this.waitForChildrenTimeout,
    this.onWaitForChildrenTimeout,
    this.pauseAfterInitialization,
    super.child, // Not used by default. You can use it at your own discretion.
  });

  //
  // Overriding block
  //

  /// Creates the controller this scope owns.
  ///
  /// Called once, at the start of the asynchronous phase.
  C createController(BuildContext context);

  /// Built while waiting for a `scopeKey` and for the controller.
  ///
  /// Returning `null` falls back to [buildOnProgress].
  Widget? buildOnWaiting(BuildContext context) => null;

  /// Built while the controller is initializing.
  Widget buildOnProgress(BuildContext context);

  /// Built when the initialization of the controller failed.
  Widget buildOnError(
    BuildContext context,
    Object error,
    StackTrace stackTrace,
  );

  /// Built once the controller is ready, and receives it.
  Widget buildOnReady(BuildContext context, C controller);

  //
  // End of overriding block
  //

  @override
  // ignore: library_private_types_in_public_api
  _AsyncControllerScopeElement<W, C> createScopeElement() =>
      _AsyncControllerScopeElement<W, C>(this as W);

  /// The nearest scope [W] above [context], or `null`.
  static AsyncDataScopeContext<W, C>? maybeOf<
          W extends AsyncControllerScopeBase<W, C>, C extends ScopeController>(
    BuildContext context, {
    required bool listen,
  }) =>
      ScopeContext.maybeOf<W, AsyncDataScopeContext<W, C>>(
        context,
        listen: listen,
      );

  /// The nearest scope [W] above [context].
  ///
  /// Throws when there is none.
  static AsyncDataScopeContext<W, C>
      of<W extends AsyncControllerScopeBase<W, C>, C extends ScopeController>(
    BuildContext context, {
    required bool listen,
  }) =>
          ScopeContext.of<W, AsyncDataScopeContext<W, C>>(
            context,
            listen: listen,
          );

  /// Subscribes to one value of the scope and returns it.
  static V select<W extends AsyncControllerScopeBase<W, C>,
          C extends ScopeController, V extends Object?>(
    BuildContext context,
    V Function(AsyncDataScopeContext<W, C> context) selector,
  ) =>
      ScopeContext.select<W, AsyncDataScopeContext<W, C>, V>(
        context,
        selector,
      );
}

final class _AsyncControllerScopeElement<
        W extends AsyncControllerScopeBase<W, C>, C extends ScopeController>
    extends AsyncControllerScopeElementBase<W,
        _AsyncControllerScopeElement<W, C>, C> {
  _AsyncControllerScopeElement(super.widget);

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
  Duration? get disposeScopeTimeout => widget.disposeScopeTimeout;

  @override
  void onDisposeScopeTimeout() => widget.onDisposeScopeTimeout?.call();

  @override
  Duration? get waitForChildrenTimeout => widget.waitForChildrenTimeout;

  @override
  void onWaitForChildrenTimeout() => widget.onWaitForChildrenTimeout?.call();

  @override
  Duration? get pauseAfterInitialization => widget.pauseAfterInitialization;

  @override
  C createController(BuildContext context) => widget.createController(context);

  @override
  Widget buildOnState(AsyncScopeState state) => switch (state) {
        AsyncScopeWaiting() =>
          widget.buildOnWaiting(this) ?? widget.buildOnProgress(this),
        // A controller reports no progress: the stream above yields the ready
        // state and nothing else.
        AsyncScopeProgress() => widget.buildOnProgress(this),
        AsyncScopeReady() => widget.buildOnReady(this, data),
        AsyncScopeError(:final error, :final stackTrace) =>
          widget.buildOnError(this, error, stackTrace),
      };
}
