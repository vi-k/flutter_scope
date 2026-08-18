part of '../scope.dart';

/// {@category AsyncScope}
abstract base class AsyncScopeBase<W extends AsyncScopeBase<W>>
    extends AsyncScopeCore<W, _AsyncScopeElement<W>> {
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

  /// How long the teardown waits for the initialization to be cancelled;
  /// `null` takes the default.
  ///
  /// Defaults to [ScopeConfig.defaultInitCancellationTimeout]. Removing the
  /// limit altogether is done there, not here.
  final Duration? initCancellationTimeout;

  /// Called when the wait for the cancellation expires.
  ///
  /// The expiry is reported through [FlutterError.reportError] either way,
  /// and the teardown goes on without the initialization.
  final void Function()? onInitCancellationTimeout;

  /// How long to wait for [disposeScope]; `null` takes the default.
  ///
  /// Defaults to [ScopeConfig.defaultDisposeScopeTimeout]. Removing the limit
  /// altogether is done there, not here.
  final Duration? disposeScopeTimeout;

  /// Called when the wait for [disposeScope] expires.
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

  /// Creates an asynchronous scope.
  const AsyncScopeBase({
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

  /// Called when the scope is mounted, before the initialization starts.
  void onMount(BuildContext context) {}

  /// The initialization.
  ///
  /// Yields [AsyncScopeProgress] any number of times and [AsyncScopeReady]
  /// once.
  Stream<AsyncScopeInitState> initScope(BuildContext context);

  /// Called synchronously when the scope leaves the tree.
  void onUnmount() {}

  /// Releases what [initScope] acquired.
  ///
  /// Awaited, and called only when the initialization succeeded.
  FutureOr<void> disposeScope();

  /// Built while waiting for a `scopeKey` and for the first event.
  ///
  /// Returning `null` falls back to [buildOnProgress].
  Widget? buildOnWaiting(BuildContext context) => null;

  /// Built while the initialization is running.
  ///
  /// [progress] is what the last [AsyncScopeProgress] carried, and `null`
  /// before the first one.
  Widget buildOnProgress(BuildContext context, Object? progress);

  /// Built once the scope is ready.
  Widget buildOnReady(BuildContext context);

  /// Built when the initialization failed.
  Widget buildOnError(
    BuildContext context,
    Object error,
    StackTrace stackTrace,
    Object? progress,
  );

  //
  // End of overriding block
  //

  @override
  // ignore: library_private_types_in_public_api
  _AsyncScopeElement<W> createScopeElement() =>
      _AsyncScopeElement<W>(this as W);

  /// The nearest scope [W] above [context], or `null`.
  static AsyncScopeContext<W>? maybeOf<W extends AsyncScopeBase<W>>(
    BuildContext context, {
    required bool listen,
  }) =>
      ScopeContext.maybeOf<W, AsyncScopeContext<W>>(
        context,
        listen: listen,
      );

  /// The nearest scope [W] above [context].
  ///
  /// Throws when there is none.
  static AsyncScopeContext<W> of<W extends AsyncScopeBase<W>>(
    BuildContext context, {
    required bool listen,
  }) =>
      ScopeContext.of<W, AsyncScopeContext<W>>(
        context,
        listen: listen,
      );

  /// Subscribes to one value of the scope and returns it.
  static V select<W extends AsyncScopeBase<W>, V extends Object?>(
    BuildContext context,
    V Function(AsyncScopeContext<W> context) selector,
  ) =>
      ScopeContext.select<W, AsyncScopeContext<W>, V>(
        context,
        selector,
      );
}

final class _AsyncScopeElement<W extends AsyncScopeBase<W>>
    extends AsyncScopeElementBase<W, _AsyncScopeElement<W>> {
  _AsyncScopeElement(super.widget);

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

  /// Runs [AsyncScopeBase.onMount] before anything the scope does for itself.
  ///
  /// Called from [ScopeWidgetElementBase.init], which is the first point at
  /// which the element is connected to its ancestors and nothing has begun:
  /// the asynchronous phase starts on the build this runs in, once it returns.
  /// Called from `mount()` instead, the hook ran *after* the initialization it
  /// is documented to precede.
  @override
  void init() {
    widget.onMount(this);
    super.init();
  }

  @override
  Stream<AsyncScopeInitState> initScope() => widget.initScope(this);

  @override
  void onUnmount() {
    super.onUnmount();
    widget.onUnmount();
  }

  @override
  FutureOr<void> disposeScope() => widget.disposeScope();

  @override
  Widget buildOnState(AsyncScopeState state) => switch (state) {
        AsyncScopeWaiting() =>
          widget.buildOnWaiting(this) ?? widget.buildOnProgress(this, null),
        AsyncScopeProgress(:final progress) =>
          widget.buildOnProgress(this, progress),
        AsyncScopeReady() => widget.buildOnReady(this),
        AsyncScopeError(:final error, :final stackTrace, :final progress) =>
          widget.buildOnError(this, error, stackTrace, progress),
      };
}
