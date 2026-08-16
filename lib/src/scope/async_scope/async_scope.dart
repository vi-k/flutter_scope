part of '../scope.dart';

/// {@category AsyncScope}
final class AsyncScope extends AsyncScopeBase<AsyncScope> {
  /// Called when the scope is mounted, before the initialization starts.
  final void Function(BuildContext context)? mount;

  /// The initialization.
  ///
  /// Yields [AsyncScopeProgress] any number of times and [AsyncScopeReady]
  /// once. Cancelled if the scope leaves the tree before it finishes.
  final Stream<AsyncScopeInitState> Function(BuildContext context) init;

  /// Called synchronously when the scope leaves the tree.
  final void Function()? unmount;

  /// Releases what [init] acquired.
  ///
  /// Awaited, and called only when the initialization succeeded.
  final FutureOr<void> Function() dispose;

  /// Built while waiting for a `scopeKey` and for the first event.
  ///
  /// Falls back to [initBuilder] when omitted.
  final Widget Function(BuildContext context)? waitingBuilder;

  /// Built while the initialization is running.
  ///
  /// The second argument is what the last [AsyncScopeProgress] carried, and
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

  /// Built once the scope is ready.
  final Widget Function(BuildContext context) builder;

  /// Creates an asynchronous scope.
  const AsyncScope({
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
  Stream<AsyncScopeInitState> initAsync(BuildContext context) => init(context);

  @override
  void onUnmount() => unmount?.call();

  @override
  FutureOr<void> disposeAsync() => dispose();

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
  Widget buildOnReady(BuildContext context) => builder(context);

  /// The nearest [AsyncScope] above [context], or `null`.
  static AsyncScopeContext<AsyncScope>? maybeOf(
    BuildContext context, {
    required bool listen,
  }) =>
      ScopeContext.maybeOf<AsyncScope, AsyncScopeContext<AsyncScope>>(
        context,
        listen: listen,
      );

  /// The nearest [AsyncScope] above [context].
  ///
  /// Throws when there is none.
  static AsyncScopeContext<AsyncScope> of(
    BuildContext context, {
    required bool listen,
  }) =>
      ScopeContext.of<AsyncScope, AsyncScopeContext<AsyncScope>>(
        context,
        listen: listen,
      );

  /// Subscribes to one value of the scope and returns it.
  static V select<V extends Object?>(
    BuildContext context,
    V Function(AsyncScopeContext<AsyncScope> context) selector,
  ) =>
      ScopeContext.select<AsyncScope, AsyncScopeContext<AsyncScope>, V>(
        context,
        selector,
      );
}
