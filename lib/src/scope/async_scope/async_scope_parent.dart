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
/// The [ScopeObservable] constraint is what lets an expired wait for the
/// children reach `ScopeConfig.observer` from here, under the same label the
/// rest of the scope's events carry. Every element of the package already
/// answers to it; a parent of your own has to, and [debugLabel] is all it
/// asks for.
///
/// {@category AsyncScope}
mixin AsyncScopeParent on Diagnosticable implements ScopeObservable {
  final _childRegistry = ChildRegistry();

  /// The name a report about this parent's children is prefixed with.
  ///
  /// [toStringShort] by default, which for an element is its own type and hash.
  /// The elements of the built-in families answer with the name of their widget
  /// instead, because that is the name carrying `tag` — the label an application
  /// chose for this particular scope — and because it is the name the two
  /// neighbouring waits already use: [AsyncScopeCoordinator.waitForChildren] and
  /// a scope's own teardown. Override it in a parent of your own if it has a
  /// better name to give.
  ///
  /// Read while the parent is still mounted, never at expiry: a wait outlives
  /// the tree in the very cases it exists for, and `Element.widget` throws once
  /// the element is unmounted.
  @protected
  String get reportName => toStringShort();

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
  /// same default [AsyncScopeCoordinator.waitForChildren] applies. Pass
  /// [ScopeTimeout.none] to wait with no limit at all for this call alone;
  /// setting that default to `null` does the same for every wait at once.
  ///
  /// This is the one place the limit is resolved — a scope's own teardown and
  /// [AsyncScopeCoordinator.waitForChildren] both pass their value through
  /// untouched, because resolving twice would turn a [ScopeTimeout.none] into
  /// the `null` that means "take the default" on the way in.
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
    final name = onTimeout == null ? reportName : null;

    return _childRegistry.waitForChildren(
      // The default is substituted here rather than left to the registry,
      // which reads `null` as "no limit at all". Called without arguments --
      // the natural way -- this would otherwise be the one wait in the
      // package that can hang for ever, while the same method on
      // [AsyncScopeCoordinator] gives up on time.
      timeout:
          resolveTimeout(timeout, ScopeConfig.defaultWaitForChildrenTimeout),
      onTimeout: (error, stackTrace) {
        // Before the caller's handler and independent of it: a custom
        // [onTimeout] replaces the default *report*, not the reporting of the
        // package about itself. This is the one point all three waits for
        // children pass through -- a scope's own teardown, this method called
        // from a parent, and [AsyncScopeCoordinator.waitForChildren] -- so
        // announcing it here is what makes the expiry visible whichever way
        // the wait was asked for.
        notifyObserver(
          (observer) => observer.onTimeout(this, 'its child scopes'),
        );

        if (onTimeout != null) {
          onTimeout(error, stackTrace);

          return;
        }

        FlutterError.reportError(
          FlutterErrorDetails(
            exception: TimeoutException(
              '$name ${error.message}',
              error.duration,
            ),
            stack: stackTrace,
            library: 'scopo',
          ),
        );
      },
    );
  }

  ChildEntry _registerChild(String reportName) =>
      _childRegistry.registerChild(reportName);
}
