part of '../scope.dart';

/// {@category AsyncDataScope}
final class AsyncDataScope<T extends Object?>
    extends AsyncDataScopeBase<AsyncDataScope<T>, T> {
  /// What [onMount] was given, if anything.
  ///
  /// Private because the method it stands behind has the same name, and a
  /// field cannot share a name with a method it implements.
  final void Function(BuildContext context)? _onMount;

  /// What [initData] was given.
  final Future<T> Function(BuildContext context, ScopeInitContext ctx)
      _initData;

  /// What [onUnmount] was given, if anything.
  final void Function(T? data)? _onUnmount;

  /// What [disposeData] was given.
  final FutureOr<void> Function(T data) _disposeData;

  /// Built while waiting for a `scopeKey` and for the first event.
  ///
  /// Falls back to [progressBuilder] when omitted.
  final Widget Function(BuildContext context)? waitingBuilder;

  /// Built while the initialization is running.
  ///
  /// The second argument is what the last [AsyncDataScopeProgress] carried, and
  /// `null` before the first one.
  final Widget Function(BuildContext context, Object? progress) progressBuilder;

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
  ///
  /// [onMount], [initData], [onUnmount] and [disposeData] are the methods this
  /// widget stands in for, and the parameters carry their names.
  const AsyncDataScope({
    super.key,
    super.tag,
    super.scopeKey,
    super.scopeKeyTimeout,
    super.onScopeKeyTimeout,
    super.initCancellationTimeout,
    super.onInitCancellationTimeout,
    super.disposeScopeTimeout,
    super.onDisposeScopeTimeout,
    super.waitForChildrenTimeout,
    super.onWaitForChildrenTimeout,
    super.pauseAfterInitialization,
    void Function(BuildContext context)? onMount,
    required Future<T> Function(BuildContext context, ScopeInitContext ctx)
        initData,
    void Function(T? data)? onUnmount,
    required FutureOr<void> Function(T data) disposeData,
    this.waitingBuilder,
    required this.progressBuilder,
    required this.builder,
    required this.errorBuilder,
  })  : _onMount = onMount,
        _initData = initData,
        _onUnmount = onUnmount,
        _disposeData = disposeData;

  @override
  void onMount(BuildContext context) => _onMount?.call(context);

  @override
  Future<T> initData(BuildContext context, ScopeInitContext ctx) =>
      _initData(context, ctx);

  @override
  void onUnmount(T? data) => _onUnmount?.call(data);

  @override
  FutureOr<void> disposeData(T data) => _disposeData(data);

  @override
  Widget? buildOnWaiting(BuildContext context) => waitingBuilder?.call(context);

  @override
  Widget buildOnProgress(BuildContext context, Object? progress) =>
      progressBuilder(context, progress);

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
