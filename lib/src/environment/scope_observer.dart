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
/// This is a `base class`, so an observer of your own is declared `base`,
/// `final` or `sealed` — `final` unless you mean it to be extended further.
///
/// {@category debug}
base class ScopeObserver {
  /// Creates an observer that does nothing.
  const ScopeObserver();

  /// An initialization has begun.
  void onInit(ScopeObservable target) {}

  /// One step of an initialization is done — or, for a dependency container,
  /// one step of its disposal.
  ///
  /// [progress] is what that source reports: the value an `initScope` yielded
  /// for a scope, a `ScopeAutoDependenciesProgress` while a container
  /// initializes, or the bare `String` path of the dependency a container
  /// just disposed of.
  void onProgress(ScopeObservable target, Object? progress) {}

  /// An initialization has finished successfully.
  void onReady(ScopeObservable target) {}

  /// An initialization was cancelled before it finished.
  ///
  /// Not always preceded by [onInit]. A scope still queued for its `scopeKey`
  /// when it is taken off the tree never started an initialization of its
  /// own, so there was nothing to announce; the cancellation arrives on its
  /// own.
  void onCancelled(ScopeObservable target) {}

  /// A teardown has begun.
  ///
  /// Sent by every family's teardown, exactly once, whatever became of the
  /// initialization it followed: a scope taken down while it was still
  /// loading reports this too, with nothing of its own to release.
  /// [onDisposed] always follows.
  void onDispose(ScopeObservable target) {}

  /// A teardown has finished.
  ///
  /// The scope is gone, which is not the same as everything it held having
  /// come back: a teardown that failed reports [onError] with
  /// [ScopePhase.disposal] and then this, so the pair with [onDispose] closes
  /// whichever way the teardown went.
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

/// A [ScopeObserver] that writes a line per event.
///
/// The line is `scopo | <label> | <what happened>`, and a failure adds
/// `: <error>` and the stack trace on a line of its own.
///
/// {@category debug}
final class ScopePrintObserver extends ScopeObserver {
  /// Creates an observer printing through [output].
  const ScopePrintObserver({
    this.output = print,
    this.trace = false,
  });

  /// Where a line goes; `print` by default.
  final void Function(String line) output;

  /// Whether [onTrace] is printed too.
  final bool trace;

  void _write(ScopeObservable target, String message) =>
      output('scopo | ${target.debugLabel} | $message');

  @override
  void onInit(ScopeObservable target) => _write(target, 'initialize…');

  @override
  void onProgress(ScopeObservable target, Object? progress) =>
      _write(target, 'progress: $progress');

  @override
  void onReady(ScopeObservable target) => _write(target, 'initialized');

  @override
  void onCancelled(ScopeObservable target) =>
      _write(target, 'initialization cancelled');

  @override
  void onDispose(ScopeObservable target) => _write(target, 'dispose…');

  @override
  void onDisposed(ScopeObservable target) => _write(target, 'disposed');

  @override
  void onError(
    ScopeObservable target,
    ScopePhase phase,
    Object error,
    StackTrace? stackTrace,
  ) {
    final suffix = stackTrace == null || stackTrace == StackTrace.empty
        ? ''
        : '\n$stackTrace';
    _write(target, '${_failureMessage(phase)}: $error$suffix');
  }

  @override
  void onTimeout(ScopeObservable target, String what) =>
      _write(target, 'gave up waiting for $what');

  @override
  void onTrace(ScopeObservable target, String message) {
    if (trace) {
      _write(target, message);
    }
  }
}

/// The message [ScopePrintObserver.onError] writes for [phase], without the
/// error or stack trace that follow it.
///
/// This is exhaustive on purpose, with no `default`: [ScopePhase] is defined
/// in this same file, so a phase added later fails this switch at compile
/// time instead of falling through to a name nobody wrote a phrase for. The
/// advice on [ScopePhase] to give an outside `switch` a `default` branch is
/// for callers who cannot make that promise about a release they have not
/// seen yet; this one can.
///
/// Five of the six read as `'<phrase> failed'`; [ScopePhase.abandonedWait]
/// does not, because the deleted logger this mirrors named what the wait was
/// for (`'an abandoned wait for $what ended in a failure'`), and the
/// observer has no `$what` to put there. Rather than force that phrase into
/// the `'<phrase> failed'` shape it does not fit, it stands as the whole
/// message.
String _failureMessage(ScopePhase phase) => switch (phase) {
      ScopePhase.initialization => 'initialization failed',
      ScopePhase.initializationCancellation =>
        'initialization cancellation failed',
      ScopePhase.preparationForDisposal => 'preparation for disposal failed',
      ScopePhase.unmount => 'unmount failed',
      ScopePhase.disposal => 'disposal failed',
      ScopePhase.abandonedWait => 'an abandoned wait ended in a failure',
    };
