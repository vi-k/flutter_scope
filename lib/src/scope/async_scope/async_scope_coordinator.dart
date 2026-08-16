part of '../scope.dart';

/// Owns the `scopeKey` queues of its subtree, and is the wait root for the
/// scopes in it that have no parent scope above them.
///
/// A scope with a `scopeKey` waits on the queue owned by the nearest
/// [AsyncScopeCoordinator] above it, so two scopes under different
/// coordinators never wait for one another even when their `scopeKey`s are
/// equal. Independently, a scope also registers with the nearest
/// [AsyncScopeParent] above it — a parent scope if there is one, or this
/// coordinator otherwise — so that something waits for it to finish disposing
/// of itself; [waitForChildren] waits for exactly those scopes.
///
/// {@category AsyncScope}
final class AsyncScopeCoordinator extends ScopeWidgetCore<AsyncScopeCoordinator,
    _AsyncScopeCoordinatorElement> {
  /// Creates a coordinator over [child].
  const AsyncScopeCoordinator({
    super.key,
    super.tag,
    required super.child,
  });

  @override
  // ignore: library_private_types_in_public_api
  _AsyncScopeCoordinatorElement createScopeElement() =>
      _AsyncScopeCoordinatorElement(this);

  /// The nearest coordinator above [context], the one whose queues a scope
  /// with a `scopeKey` takes its place in.
  ///
  /// Each coordinator keeps its own keys: scopes under different coordinators
  /// never wait for one another, even when their keys are equal.
  ///
  /// A scope resolves this *before* it creates its [AccessEntry], so the one
  /// failure that can happen while the entry does not yet exist stays where
  /// there is nothing to release.
  static _AsyncScopeCoordinatorElement _elementOf(BuildContext context) =>
      ScopeWidgetCore.maybeOf<AsyncScopeCoordinator,
          _AsyncScopeCoordinatorElement>(
        context,
        listen: false,
      ) ??
      (throw FlutterError(
        'No `$AsyncScopeCoordinator`.\n'
        'The `$AsyncScopeCoordinator` is missing in the context. Add it to'
        ' the widget tree so that all your scopes that need it can access it.'
        ' The most universal solution is to place it above `$MaterialApp`.'
        ' A scope with a `scopeKey` needs it to be coordinated with the other'
        ' scopes that share the key.',
      ));

  /// Waits for the scopes registered with the nearest coordinator at the time
  /// of the call.
  ///
  /// These are the scopes that have no parent scope above them; a scope with a
  /// parent scope is awaited by that parent instead. A scope that registers
  /// while the wait is already running is not awaited by it, and is still
  /// registered once it is over.
  ///
  /// [timeout] defaults to [ScopeConfig.defaultWaitForChildrenTimeout], the
  /// same default the scopes themselves use; pass a [Duration] to override it
  /// for this call only. An expiry is not fatal: the awaited scopes that never
  /// finished are dropped and the future completes normally, so a scope that
  /// never finishes disposing of itself degrades into a delay instead of a
  /// deadlock. Removing the limit entirely is done through [ScopeConfig], not
  /// here.
  ///
  /// [onTimeout] defaults to reporting the [TimeoutException] through
  /// [FlutterError.reportError], so an expiry is never silent; pass a callback
  /// to handle it instead.
  static Future<void> waitForChildren(
    BuildContext context, {
    Duration? timeout,
    void Function(TimeoutException error, StackTrace stackTrace)? onTimeout,
  }) {
    final element = _elementOf(context);
    // The message the registry builds knows nothing about the widget tree, so
    // the coordinator puts its own name in front of it. The name is read here,
    // while the element is still mounted: the wait outlives the tree in the
    // very cases this helper exists for, and `Element.widget` throws once the
    // element has been unmounted.
    final name = element.widget.toStringShort(showHashCode: true);

    return element.waitForChildren(
      timeout: timeout ?? ScopeConfig.defaultWaitForChildrenTimeout,
      onTimeout: onTimeout ??
          (error, stackTrace) => FlutterError.reportError(
                FlutterErrorDetails(
                  exception: TimeoutException(
                    '$name ${error.message}',
                    error.duration,
                  ),
                  stack: stackTrace,
                  library: 'scopo',
                ),
              ),
    );
  }
}

final class _AsyncScopeCoordinatorElement extends ScopeWidgetElementBase<
    AsyncScopeCoordinator,
    _AsyncScopeCoordinatorElement> with AsyncScopeParent {
  _AsyncScopeCoordinatorElement(super.widget);

  final _queues = KeyedAccessQueues();

  @override
  Widget buildChild() => widget.child;

  Future<void> enter(
    Object key,
    AccessEntry entry, {
    Duration? timeout,
    void Function(TimeoutException error, StackTrace stackTrace)? onTimeout,
  }) =>
      _queues.enter(key, entry, timeout: timeout, onTimeout: onTimeout);
}
