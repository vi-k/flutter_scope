part of 'scope_config.dart';

/// An object whose lifecycle [ScopeConfig.observer] is told about.
///
/// Implemented by the scope elements of every family, by the container of
/// automatic dependencies and by a single dependency. It is deliberately not
/// implemented by `ScopeDependencies` or `ScopeDependency`: those are yours to
/// implement, and a new member on them would break the code that already does.
///
/// {@category debug}
abstract interface class ScopeObservable {
  /// How this object names itself in a report.
  String get debugLabel;
}

/// What was running when a failure reached [ScopeObserver.onError].
///
/// More values may be added later, so a `switch` over this enum wants a
/// `default` branch.
///
/// {@category debug}
enum ScopePhase {
  /// An initialization, synchronous or asynchronous.
  initialization,

  /// The cancellation of an initialization that was still running.
  initializationCancellation,

  /// The synchronous half of a teardown, before the asynchronous one.
  preparationForDisposal,

  /// The `onUnmount` hook.
  unmount,

  /// A teardown.
  disposal,

  /// A wait nobody was left to hear the end of.
  abandonedWait,
}

/// Hooks called as scopes and their dependencies live and die.
///
/// Assign one to [ScopeConfig.observer]. Every hook is empty, so a subclass
/// overrides only what it needs. Hooks are called synchronously, from the
/// build, the initialization or the teardown they belong to; a hook that
/// throws is reported through [FlutterError.reportError] and does not reach
/// the scope.
///
/// {@category debug}
base class ScopeObserver {
  /// Creates an observer that does nothing.
  const ScopeObserver();

  /// An initialization has begun.
  void onInit(ScopeObservable target) {}

  /// One step of an initialization is done.
  ///
  /// [progress] is what that source reports: the value an `initScope` yielded
  /// for a scope, a `ScopeAutoDependenciesProgress` for a container.
  void onProgress(ScopeObservable target, Object? progress) {}

  /// An initialization has finished successfully.
  void onReady(ScopeObservable target) {}

  /// An initialization was cancelled before it finished.
  void onCancelled(ScopeObservable target) {}

  /// A teardown has begun.
  void onDispose(ScopeObservable target) {}

  /// A teardown has finished.
  void onDisposed(ScopeObservable target) {}

  /// Something failed; [phase] says what was running.
  void onError(
    ScopeObservable target,
    ScopePhase phase,
    Object error,
    StackTrace? stackTrace,
  ) {}

  /// A bounded wait expired; [what] names what was waited for.
  void onTimeout(ScopeObservable target, String what) {}

  /// A step of the machinery below the lifecycle.
  ///
  /// Off by default in `ScopePrintObserver`: this is where the coordination
  /// of `scopeKey`s and the guarded streams report themselves, and a scope
  /// produces a dozen such lines where it produces one of the rest.
  void onTrace(ScopeObservable target, String message) {}
}
