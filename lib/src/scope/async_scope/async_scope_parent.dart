part of '../scope.dart';

/// A scope that waits for the scopes below it before disposing of itself.
///
/// The nearest ancestor with this mixin — a parent scope, or the
/// [AsyncScopeCoordinator] when there is no parent scope — is what a scope
/// registers with. A scope with neither above it registers nowhere and nobody
/// waits for it.
///
/// The mixin sits on the element, and the elements of the built-in families
/// are private, so [hasChildren], [childrenCount] and [waitForChildren] are
/// reachable from a scope of your own — a family built on [AsyncScopeCore],
/// reading them on `this` — rather than from a subtree looking upwards.
/// [AsyncScope.of] and its siblings hand back an [AsyncScopeContext], which
/// carries the state of the scope and none of these. From a subtree, the wait
/// to ask for is [AsyncScopeCoordinator.waitForChildren], which awaits the
/// scopes registered with the nearest coordinator rather than the children of
/// one particular scope.
///
/// {@category AsyncScope}
mixin AsyncScopeParent on Diagnosticable {
  final _childRegistry = ChildRegistry();

  /// Whether any scope is registered with this parent.
  bool get hasChildren => _childRegistry.hasChildren;

  /// How many scopes are registered with this parent.
  int get childrenCount => _childRegistry.childrenCount;

  /// Completes once the children registered with this parent at the time of
  /// the call have finished.
  ///
  /// A child that registers while the wait is already running is not awaited
  /// by it, and is still registered once it is over.
  ///
  /// On [timeout] the awaited children that never finished are dropped and
  /// [onTimeout] is called; the future completes normally either way.
  ///
  /// [timeout] defaults to [ScopeConfig.defaultWaitForChildrenTimeout], the
  /// same default [AsyncScopeCoordinator.waitForChildren] applies. Waiting
  /// with no limit at all is what setting that to `null` means, and it is a
  /// decision for the application rather than for one call.
  ///
  /// [onTimeout] defaults to reporting the [TimeoutException] through
  /// [FlutterError.reportError], the same default
  /// [AsyncScopeCoordinator.waitForChildren] applies, so a dropped child is
  /// never silent; pass a callback to handle it instead.
  Future<void> waitForChildren({
    Duration? timeout,
    void Function(TimeoutException error, StackTrace stackTrace)? onTimeout,
  }) {
    // The message the registry builds knows nothing about the widget tree, so
    // this parent puts its own name in front of it. The name is read here,
    // while the parent is still mounted: the wait outlives the tree in the
    // very cases it exists for, and reading `widget` at expiry time would
    // throw on an element that has been unmounted since.
    final name = onTimeout == null ? toStringShort() : null;

    return _childRegistry.waitForChildren(
      // The default is substituted here rather than left to the registry,
      // which reads `null` as "no limit at all". Called without arguments --
      // the natural way -- this would otherwise be the one wait in the
      // package that can hang for ever, while the same method on
      // [AsyncScopeCoordinator] gives up on time.
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

  ChildEntry _registerChild(String debugName) =>
      _childRegistry.registerChild(debugName);
}
