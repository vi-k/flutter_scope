part of '../scope.dart';

/// A scope that waits for the scopes below it before disposing of itself.
///
/// The nearest ancestor with this mixin — a parent scope, or the
/// [AsyncScopeCoordinator] when there is no parent scope — is what a scope
/// registers with. A scope with neither above it registers nowhere and nobody
/// waits for it.
///
/// {@category AsyncScope}
mixin AsyncScopeParent on Diagnosticable {
  final _childRegistry = ChildRegistry();

  bool get hasChildren => _childRegistry.hasChildren;

  int get childrenCount => _childRegistry.childrenCount;

  /// Completes once the children registered with this parent at the time of
  /// the call have finished.
  ///
  /// A child that registers while the wait is already running is not awaited
  /// by it.
  ///
  /// On [timeout] the children left behind are dropped and [onTimeout] is
  /// called; the future completes normally either way.
  Future<void> waitForChildren({
    Duration? timeout,
    void Function(TimeoutException error, StackTrace stackTrace)? onTimeout,
  }) =>
      _childRegistry.waitForChildren(timeout: timeout, onTimeout: onTimeout);

  ChildEntry _registerChild(String debugName) =>
      _childRegistry.registerChild(debugName);
}
