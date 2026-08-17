part of '../scope.dart';

/// {@category AsyncDataScope}
final class AsyncDataScope<T extends Object?>
    extends AsyncDataScopeBase<AsyncDataScope<T>, T> {
  /// Called when the scope is mounted, before the initialization starts.
  final void Function(BuildContext context)? mount;

  /// The initialization, ending with the value.
  ///
  /// Yields [AsyncDataScopeProgress] any number of times and
  /// [AsyncDataScopeReady] once, carrying the value. Cancelled if the scope
  /// leaves the tree before it finishes.
  final Stream<AsyncDataScopeInitState<Object, T>> Function(
    BuildContext context,
  ) init;

  /// Called synchronously when the scope leaves the tree, and on the way out
  /// of a `close()`.
  ///
  /// The value is `null` when the initialization never produced one. For a
  /// nullable [T] that is the same `null` the initialization may have produced
  /// itself, and the two cannot be told apart from here — read `hasData` off
  /// the scope's context when the difference matters.
  final void Function(T? data)? unmount;

  /// Releases the value [init] produced.
  ///
  /// Awaited, and called only when the initialization succeeded — so the
  /// value always exists here.
  final FutureOr<void> Function(T data) dispose;

  /// Built while waiting for a `scopeKey` and for the first event.
  ///
  /// Falls back to [initBuilder] when omitted.
  final Widget Function(BuildContext context)? waitingBuilder;

  /// Built while the initialization is running.
  ///
  /// The second argument is what the last [AsyncDataScopeProgress] carried, and
  /// `null` before the first one.
  final Widget Function(BuildContext context, Object? progress) initBuilder;

  /// Built when the initialization failed.
  ///
  /// The last argument is the progress the scope had reached when it failed.
  final Widget Function(
    BuildContext context,
    Object error,
    StackTrace stackTrace,
    Object? progress,
  ) errorBuilder;

  /// Built once the value is there, and receives it.
  final Widget Function(BuildContext context, T data) builder;

  /// Creates an asynchronous scope producing a value.
  const AsyncDataScope({
    super.key,
    super.tag,
    super.scopeKey,
    super.scopeKeyTimeout,
    super.onScopeKeyTimeout,
    super.initCancellationTimeout,
    super.onInitCancellationTimeout,
    super.disposeAsyncTimeout,
    super.onDisposeAsyncTimeout,
    super.waitForChildrenTimeout,
    super.onWaitForChildrenTimeout,
    super.pauseAfterInitialization,
    this.mount,
    required this.init,
    this.unmount,
    required this.dispose,
    this.waitingBuilder,
    required this.initBuilder,
    required this.builder,
    required this.errorBuilder,
  });

  @override
  void onMount(BuildContext context) => mount?.call(context);

  @override
  Stream<AsyncDataScopeInitState<Object, T>> initData(BuildContext context) =>
      init(context);

  @override
  void onUnmount(T? data) => unmount?.call(data);

  @override
  FutureOr<void> disposeData(T data) => dispose(data);

  @override
  Widget? buildOnWaiting(BuildContext context) => waitingBuilder?.call(context);

  @override
  Widget buildOnInitializing(BuildContext context, Object? progress) =>
      initBuilder(context, progress);

  @override
  Widget buildOnError(
    BuildContext context,
    Object error,
    StackTrace stackTrace,
    Object? progress,
  ) =>
      errorBuilder(context, error, stackTrace, progress);

  @override
  Widget buildOnReady(BuildContext context, T data) => builder(context, data);

  /// The nearest `AsyncDataScope<T>` above [context], or `null`.
  static AsyncDataScopeContext<AsyncDataScope<T>, T>?
      maybeOf<T extends Object?>(
    BuildContext context, {
    required bool listen,
  }) =>
          ScopeContext.maybeOf<AsyncDataScope<T>,
              AsyncDataScopeContext<AsyncDataScope<T>, T>>(
            context,
            listen: listen,
          );

  /// The nearest `AsyncDataScope<T>` above [context].
  ///
  /// Throws when there is none.
  static AsyncDataScopeContext<AsyncDataScope<T>, T> of<T extends Object?>(
    BuildContext context, {
    required bool listen,
  }) =>
      ScopeContext.of<AsyncDataScope<T>,
          AsyncDataScopeContext<AsyncDataScope<T>, T>>(
        context,
        listen: listen,
      );

  /// Subscribes to one value of the scope and returns it.
  ///
  /// The data type comes first and the selected type second, as everywhere
  /// else: `AsyncDataScope.select<Profile, String>(context, …)` selects a
  /// `String` out of a scope holding a `Profile`.
  static V select<T extends Object?, V extends Object?>(
    BuildContext context,
    V Function(AsyncDataScopeContext<AsyncDataScope<T>, T> context) selector,
  ) =>
      ScopeContext.select<AsyncDataScope<T>,
          AsyncDataScopeContext<AsyncDataScope<T>, T>, V>(
        context,
        selector,
      );
}
