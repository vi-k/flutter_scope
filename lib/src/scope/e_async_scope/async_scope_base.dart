part of '../scope.dart';

/// {@category AsyncScope}
abstract base class AsyncScopeBase<W extends AsyncScopeBase<W>>
    extends AsyncScopeCore<W, _AsyncScopeElement<W>> {
  /// Serializes this scope with the others that share the key.
  ///
  /// A scope with a key starts only once the previous holder has finished
  /// disposing of itself. Needs an [AsyncScopeCoordinator] above it.
  final Object? scopeKey;

  /// How long to wait for [scopeKey]; `null` waits indefinitely.
  ///
  /// Defaults to [ScopeConfig.defaultScopeKeysTimeout].
  final Duration? scopeKeyTimeout;

  /// Called when the wait for [scopeKey] expires.
  ///
  /// The expiry is reported through [FlutterError.reportError] either way,
  /// and the scope proceeds as if the wait had succeeded.
  final void Function()? onScopeKeyTimeout;

  /// How long to wait for the child scopes; `null` waits indefinitely.
  ///
  /// Defaults to [ScopeConfig.defaultWaitForChildrenTimeout].
  final Duration? waitForChildrenTimeout;

  /// Called when the wait for the child scopes expires.
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
  Stream<AsyncScopeInitState> initAsync(BuildContext context);

  /// Called synchronously when the scope leaves the tree.
  void onUnmount() {}

  /// Releases what [initAsync] acquired.
  ///
  /// Awaited, and called only when the initialization succeeded.
  FutureOr<void> disposeAsync();

  /// Built while waiting for a `scopeKey` and for the first event.
  ///
  /// Returning `null` falls back to [buildOnInitializing].
  Widget? buildOnWaiting(BuildContext context) => null;

  /// Built while the initialization is running.
  Widget buildOnInitializing(BuildContext context);

  /// Built once the scope is ready.
  Widget buildOnReady(BuildContext context);

  /// Built when the initialization failed.
  Widget buildOnError(
    BuildContext context,
    Object error,
    StackTrace stackTrace,
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
  Duration? get waitForChildrenTimeout => widget.waitForChildrenTimeout;

  @override
  void onWaitForChildrenTimeout() => widget.onWaitForChildrenTimeout?.call();

  @override
  Duration? get pauseAfterInitialization => widget.pauseAfterInitialization;

  @override
  void mount(Element? parent, Object? newSlot) {
    super.mount(parent, newSlot);
    widget.onMount(this);
  }

  @override
  Stream<AsyncScopeInitState> initAsync() => widget.initAsync(this);

  @override
  void unmount() {
    widget.onUnmount();
    super.unmount();
  }

  @override
  FutureOr<void> disposeAsync() => widget.disposeAsync();

  @override
  Widget buildOnState(AsyncScopeState state) => switch (state) {
        AsyncScopeWaiting() =>
          widget.buildOnWaiting(this) ?? widget.buildOnInitializing(this),
        AsyncScopeProgress() => widget.buildOnInitializing(this),
        AsyncScopeReady() => widget.buildOnReady(this),
        AsyncScopeError(:final error, :final stackTrace) =>
          widget.buildOnError(this, error, stackTrace),
      };
}
