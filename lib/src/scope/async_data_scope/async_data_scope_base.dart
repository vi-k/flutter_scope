part of '../scope.dart';

/// {@category AsyncDataScope}
abstract base class AsyncDataScopeBase<W extends AsyncDataScopeBase<W, T>,
        T extends Object?>
    extends AsyncDataScopeCore<W, _AsyncDataScopeElement<W, T>, T> {
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

  /// How long to wait for the asynchronous teardown; `null` takes the
  /// default.
  ///
  /// Defaults to [ScopeConfig.defaultDisposeScopeTimeout]. Removing the limit
  /// altogether is done there, not here.
  final Duration? disposeScopeTimeout;

  /// Called when the wait for the asynchronous teardown expires.
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

  /// Creates an asynchronous scope producing a value.
  const AsyncDataScopeBase({
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

  /// The initialization, ending with the value.
  Stream<AsyncDataScopeInitState<Object, T>> initData(BuildContext context);

  /// Called synchronously when the scope leaves the tree, and on the way out
  /// of a `close()`.
  ///
  /// The value is `null` when the initialization never produced one. For a
  /// nullable [T] that is the same `null` the initialization may have produced
  /// itself, and the two cannot be told apart from here — read `hasData` off
  /// the scope's context when the difference matters.
  void onUnmount(T? data) {}

  /// Releases the value [initData] produced; awaited.
  FutureOr<void> disposeData(T data);

  /// Built while waiting for a `scopeKey` and for the first event.
  Widget? buildOnWaiting(BuildContext context) => null;

  /// Built while the initialization is running.
  Widget buildOnProgress(BuildContext context, Object? progress);

  /// Built when the initialization failed.
  Widget buildOnError(
    BuildContext context,
    Object error,
    StackTrace stackTrace,
    Object? progress,
  );

  /// Built once the value is there, and receives it.
  Widget buildOnReady(BuildContext context, T data);

  //
  // End of overriding block
  //

  @override
  // ignore: library_private_types_in_public_api
  _AsyncDataScopeElement<W, T> createScopeElement() =>
      _AsyncDataScopeElement<W, T>(this as W);

  /// The nearest scope [W] above [context], or `null`.
  static AsyncDataScopeContext<W, T>?
      maybeOf<W extends AsyncDataScopeBase<W, T>, T extends Object?>(
    BuildContext context, {
    required bool listen,
  }) =>
          ScopeContext.maybeOf<W, AsyncDataScopeContext<W, T>>(
            context,
            listen: listen,
          );

  /// The nearest scope [W] above [context].
  ///
  /// Throws when there is none.
  static AsyncDataScopeContext<W, T>
      of<W extends AsyncDataScopeBase<W, T>, T extends Object?>(
    BuildContext context, {
    required bool listen,
  }) =>
          ScopeContext.of<W, AsyncDataScopeContext<W, T>>(
            context,
            listen: listen,
          );

  /// Subscribes to one value of the scope and returns it.
  static V select<W extends AsyncDataScopeBase<W, T>, T extends Object?,
          V extends Object?>(
    BuildContext context,
    V Function(AsyncDataScopeContext<W, T> context) selector,
  ) =>
      ScopeContext.select<W, AsyncDataScopeContext<W, T>, V>(
        context,
        selector,
      );
}

final class _AsyncDataScopeElement<W extends AsyncDataScopeBase<W, T>,
        T extends Object?>
    extends AsyncDataScopeElementBase<W, _AsyncDataScopeElement<W, T>, T> {
  _AsyncDataScopeElement(super.widget);

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

  /// See `_AsyncScopeElement.init`: the hook runs before the work it precedes.
  @override
  void init() {
    widget.onMount(this);
    super.init();
  }

  @override
  Stream<AsyncDataScopeInitState<Object, T>> initDataAsync() =>
      widget.initData(this);

  @override
  void onUnmount() {
    super.onUnmount();
    widget.onUnmount(_data);
  }

  @override
  FutureOr<void> disposeScope() => widget.disposeData(data);

  @override
  Widget buildOnState(AsyncScopeState state) => switch (state) {
        AsyncScopeWaiting() =>
          widget.buildOnWaiting(this) ?? widget.buildOnProgress(this, null),
        AsyncScopeProgress(:final progress) =>
          widget.buildOnProgress(this, progress),
        AsyncScopeReady() => widget.buildOnReady(this, data),
        AsyncScopeError(:final error, :final stackTrace, :final progress) =>
          widget.buildOnError(this, error, stackTrace, progress),
      };
}
