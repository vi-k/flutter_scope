part of '../scope.dart';

/// {@category AsyncControllerScope}
final class AsyncControllerScope<C extends ScopeController>
    extends AsyncControllerScopeBase<AsyncControllerScope<C>, C> {
  /// Creates the controller this scope owns.
  final C Function(BuildContext context) create;

  /// Built while waiting for a `scopeKey` and for the controller.
  ///
  /// Falls back to [initBuilder] when omitted.
  final Widget Function(BuildContext context)? waitingBuilder;

  /// Built while the controller is initializing.
  final Widget Function(BuildContext context) initBuilder;

  /// Built when the initialization of the controller failed.
  final Widget Function(
    BuildContext context,
    Object error,
    StackTrace stackTrace,
  ) errorBuilder;

  /// Built once the controller is ready, and receives it.
  final Widget Function(BuildContext context, C controller) builder;

  /// Creates a scope owning a controller.
  const AsyncControllerScope({
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
    required this.create,
    this.waitingBuilder,
    required this.initBuilder,
    required this.builder,
    required this.errorBuilder,
  });

  @override
  C createController(BuildContext context) => create(context);

  @override
  Widget? buildOnWaiting(BuildContext context) => waitingBuilder?.call(context);

  @override
  Widget buildOnInitializing(BuildContext context) => initBuilder(context);

  @override
  Widget buildOnError(
    BuildContext context,
    Object error,
    StackTrace stackTrace,
  ) =>
      errorBuilder(context, error, stackTrace);

  @override
  Widget buildOnReady(BuildContext context, C controller) =>
      builder(context, controller);

  /// The nearest `AsyncControllerScope<C>` above [context], or `null`.
  static AsyncDataScopeContext<AsyncControllerScope<C>, C>?
      maybeOf<C extends ScopeController>(
    BuildContext context, {
    required bool listen,
  }) =>
          ScopeContext.maybeOf<AsyncControllerScope<C>,
              AsyncDataScopeContext<AsyncControllerScope<C>, C>>(
            context,
            listen: listen,
          );

  /// The nearest `AsyncControllerScope<C>` above [context].
  ///
  /// Throws when there is none.
  static AsyncDataScopeContext<AsyncControllerScope<C>, C>
      of<C extends ScopeController>(
    BuildContext context, {
    required bool listen,
  }) =>
          ScopeContext.of<AsyncControllerScope<C>,
              AsyncDataScopeContext<AsyncControllerScope<C>, C>>(
            context,
            listen: listen,
          );

  /// Subscribes to one value of the scope and returns it.
  ///
  /// The controller's type comes first and the selected type second, as
  /// everywhere else in the package.
  static V select<C extends ScopeController, V extends Object?>(
    BuildContext context,
    V Function(AsyncDataScopeContext<AsyncControllerScope<C>, C> context)
        selector,
  ) =>
      ScopeContext.select<AsyncControllerScope<C>,
          AsyncDataScopeContext<AsyncControllerScope<C>, C>, V>(
        context,
        selector,
      );
}
