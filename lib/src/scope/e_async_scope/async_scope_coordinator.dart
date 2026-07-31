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
  const AsyncScopeCoordinator({
    super.key,
    super.tag,
    required super.child,
  });

  @override
  // ignore: library_private_types_in_public_api
  _AsyncScopeCoordinatorElement createScopeElement() =>
      _AsyncScopeCoordinatorElement(this);

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

  /// Takes [entry] into the queue of [key] of the nearest coordinator.
  ///
  /// Each coordinator keeps its own keys: scopes under different coordinators
  /// never wait for one another, even when their keys are equal.
  static Future<void> _enter(
    BuildContext context,
    Object key,
    AccessEntry entry, {
    Duration? timeout,
    void Function(TimeoutException error, StackTrace stackTrace)? onTimeout,
  }) =>
      _elementOf(context)
          .enter(key, entry, timeout: timeout, onTimeout: onTimeout);

  /// Waits for the scopes that registered with this coordinator.
  ///
  /// These are the scopes that have no parent scope above them; a scope with a
  /// parent scope is awaited by that parent instead.
  static Future<void> waitForChildren(
    BuildContext context, {
    Duration? timeout,
    void Function(TimeoutException error, StackTrace stackTrace)? onTimeout,
  }) =>
      _elementOf(context)
          .waitForChildren(timeout: timeout, onTimeout: onTimeout);
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
