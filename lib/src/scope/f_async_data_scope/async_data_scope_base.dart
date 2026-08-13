part of '../scope.dart';

/// {@category AsyncDataScope}
abstract base class AsyncDataScopeBase<W extends AsyncDataScopeBase<W, T>,
        T extends Object?>
    extends AsyncDataScopeCore<W, _AsyncDataScopeElement<W, T>, T> {
  /// Serializes this scope with the others that share the key.
  final Object? scopeKey;

  /// How long to wait for [scopeKey]; `null` waits indefinitely.
  final Duration? scopeKeyTimeout;

  /// Called when the wait for [scopeKey] expires.
  final void Function()? onScopeKeyTimeout;

  /// How long to wait for the child scopes; `null` waits indefinitely.
  final Duration? waitForChildrenTimeout;

  /// Called when the wait for the child scopes expires.
  final void Function()? onWaitForChildrenTimeout;

  /// Holds the ready branch back for this long after the initialization.
  final Duration? pauseAfterInitialization;

  /// Creates an asynchronous scope producing a value.
  const AsyncDataScopeBase({
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

  /// The initialization, ending with the value.
  Stream<AsyncDataScopeInitState<Object, T>> initData(BuildContext context);

  /// Called synchronously when the scope leaves the tree.
  ///
  /// The value is `null` when the initialization never finished.
  void onUnmount(T? data) {}

  /// Releases the value [initData] produced; awaited.
  FutureOr<void> disposeData(T data);

  /// Built while waiting for a `scopeKey` and for the first event.
  Widget? buildOnWaiting(BuildContext context) => null;

  /// Built while the initialization is running.
  Widget buildOnInitializing(BuildContext context, Object? progress);

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

  static AsyncDataScopeContext<W, T>?

      /// The nearest scope [W] above [context], or `null`.
      maybeOf<W extends AsyncDataScopeBase<W, T>, T extends Object?>(
    BuildContext context, {
    required bool listen,
  }) =>
          ScopeContext.maybeOf<W, AsyncDataScopeContext<W, T>>(
            context,
            listen: listen,
          );

  static AsyncDataScopeContext<W, T>

      /// The nearest scope [W] above [context].
      ///
      /// Throws when there is none.
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
  Stream<AsyncDataScopeInitState<Object, T>> initDataAsync() =>
      widget.initData(this);

  @override
  void unmount() {
    widget.onUnmount(_data);
    super.unmount();
  }

  @override
  FutureOr<void> disposeAsync() => widget.disposeData(data);

  @override
  Widget buildOnState(AsyncScopeState state) => switch (state) {
        AsyncScopeWaiting() =>
          widget.buildOnWaiting(this) ?? widget.buildOnInitializing(this, null),
        AsyncScopeProgress(:final progress) =>
          widget.buildOnInitializing(this, progress),
        AsyncScopeReady() => widget.buildOnReady(this, data),
        AsyncScopeError(:final error, :final stackTrace, :final progress) =>
          widget.buildOnError(this, error, stackTrace, progress),
      };
}
