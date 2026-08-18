part of '../scope.dart';

/// {@category AsyncScope}
final class AsyncScope extends AsyncScopeBase<AsyncScope> {
  /// What [onMount] was given, if anything.
  ///
  /// Private because the method it stands behind has the same name, and a
  /// field cannot share a name with a method it implements.
  final void Function(BuildContext context)? _onMount;

  /// What [initScope] was given.
  final Stream<AsyncScopeInitState> Function(BuildContext context) _initScope;

  /// What [onUnmount] was given, if anything.
  final void Function()? _onUnmount;

  /// What [disposeScope] was given.
  final FutureOr<void> Function() _disposeScope;

  /// Built while waiting for a `scopeKey` and for the first event.
  ///
  /// Falls back to [progressBuilder] when omitted.
  final Widget Function(BuildContext context)? waitingBuilder;

  /// Built while the initialization is running.
  ///
  /// The second argument is what the last [AsyncScopeProgress] carried, and
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

  /// Built once the scope is ready.
  final Widget Function(BuildContext context) builder;

  /// Creates an asynchronous scope.
  ///
  /// [onMount], [initScope], [onUnmount] and [disposeScope] are the methods
  /// this widget stands in for, and the parameters carry their names.
  const AsyncScope({
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
    required Stream<AsyncScopeInitState> Function(BuildContext context)
        initScope,
    void Function()? onUnmount,
    required FutureOr<void> Function() disposeScope,
    this.waitingBuilder,
    required this.progressBuilder,
    required this.builder,
    required this.errorBuilder,
  })  : _onMount = onMount,
        _initScope = initScope,
        _onUnmount = onUnmount,
        _disposeScope = disposeScope;

  @override
  void onMount(BuildContext context) => _onMount?.call(context);

  @override
  Stream<AsyncScopeInitState> initScope(BuildContext context) =>
      _initScope(context);

  @override
  void onUnmount() => _onUnmount?.call();

  @override
  FutureOr<void> disposeScope() => _disposeScope();

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
