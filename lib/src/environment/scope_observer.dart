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

  /// A build of the scope's own subtree.
  ///
  /// The `buildOn*` branch a state-carrying family chose, or the `build` of a
  /// `ScopeWidgetBase` or a `ScopeModel`. Flutter's build error boundary
  /// answers such a failure with an `ErrorWidget` either way — that is what
  /// the subtree shows; this is the same failure told to the observer.
  build,

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

  /// One step of an initialization has begun; [path] names it.
  ///
  /// The other half of [onProgress], which arrives when that same step is
  /// done and carries the same `path`. Sent by a dependency container, from
  /// inside the step and before it awaits anything — so a step that never
  /// finishes is the last path announced here with no [onProgress] behind it,
  /// and that is what this hook is for. Read the other way round, the rule is
  /// "the last entry with no exit is where the initialization stopped", and
  /// it holds for a `concurrent` group too, where several steps are in flight
  /// and the number of the last completed one says nothing about which of
  /// them hung.
  ///
  /// A dependency of your own making — one that implements `ScopeDependency`
  /// rather than being built by `dep`, `sequential` or `concurrent` — has
  /// nowhere to take this from, so its step is not announced. Its
  /// [onProgress] still arrives: that half travels the stream, which is the
  /// part of the contract such a dependency does implement.
  void onStepStarted(ScopeObservable target, String path) {}

  /// One step of an initialization is done.
  ///
  /// [progress] is what that source reports: the value an `initScope` yielded
  /// for a scope, or a `ScopeAutoDependenciesProgress` while a container
  /// initializes.
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
  /// [onDisposed] always follows. Not always sent, though: for a structural
  /// family (no initialization phase of its own), the pair belongs to a
  /// scope that announced [onInit], so one whose `init()` threw or never ran
  /// reports neither half, even though its teardown still runs.
  void onDispose(ScopeObservable target) {}

  /// One step of a disposal has begun; [path] names it.
  ///
  /// The disposal half of [onStepStarted], and the other half of
  /// [onDisposalProgress]. Sent only for a dependency that has something to
  /// release: one that registered nothing, or only an `unmount`, has no
  /// asynchronous release to run and is walked past in silence. So every path
  /// announced here is one [onDisposalProgress] is due for, and a path
  /// announced without it is a release that did not come back.
  void onDisposalStepStarted(ScopeObservable target, String path) {}

  /// One step of a disposal is done; [path] names the dependency released.
  ///
  /// The pair [onStepStarted]/[onProgress] makes for an initialization, made
  /// for a disposal by this hook and [onDisposalStepStarted]. A release used
  /// to be reported through [onProgress] as a bare `String`, which left that
  /// hook meaning two different things at two different points of the
  /// lifecycle and the reader telling them apart by the type of a value.
  void onDisposalProgress(ScopeObservable target, String path) {}

  /// A teardown has finished.
  ///
  /// The scope is gone, which is not the same as everything it held having
  /// come back: a teardown that failed reports [onError] with
  /// [ScopePhase.disposal] and then this, so the pair with [onDispose] closes
  /// whichever way the teardown went.
  void onDisposed(ScopeObservable target) {}

  /// Something failed; [phase] says what was running.
  ///
  /// Not always preceded by [onInit]. The synchronous `init()` hook runs
  /// before either kind of family has announced anything, so a hook that
  /// threw reports [ScopePhase.initialization] on its own — and for a
  /// structural family (no phase of its own) that one event is the scope's
  /// whole recording, since the teardown pair belongs to a scope that
  /// announced [onInit].
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

/// A [ScopeObserver] that hands every event to each of [observers], in order.
///
/// [ScopeConfig.observer] holds one observer, and wanting two is ordinary —
/// [ScopePrintObserver] while developing and a crash reporter of your own
/// beside it:
///
/// ```dart
/// ScopeConfig.observer = const ScopeCompositeObserver([
///   ScopePrintObserver(),
///   CrashReporter(),
/// ]);
/// ```
///
/// **Written here rather than left to be written by hand**, and that is the
/// point of it. [ScopeObserver] is a `base class` whose hooks are empty, so a
/// subclass keeps compiling when a tenth hook is added — which is what
/// protects an ordinary observer from a new version. A delegate is the one
/// subclass that gets nothing from it: the new hook arrives with the empty
/// implementation of the base, and every observer behind the delegate stops
/// hearing that event without a word from anywhere. This one is written with
/// the class it forwards, and grows with it.
///
/// An observer that throws does not stop the ones after it. The package calls
/// an observer from a build, an initialization or a teardown, and a failure
/// there is reported through [FlutterError.reportError] and gone past — the
/// same trade [ScopeConfig.observer] itself makes, applied one level down so
/// that one bad listener is not the whole recording.
///
/// {@category debug}
final class ScopeCompositeObserver extends ScopeObserver {
  /// The observers this one stands in front of, asked in order.
  final List<ScopeObserver> observers;

  /// Creates an observer that forwards to each of [observers].
  const ScopeCompositeObserver(this.observers);

  /// Runs [call] on every observer, guarded one at a time.
  void _each(void Function(ScopeObserver observer) call) {
    for (final observer in observers) {
      try {
        call(observer);
        // ignore: avoid_catching_errors
      } on Object catch (error, stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'scopo',
            context: ErrorDescription(
              'while notifying one of several scope observers',
            ),
          ),
        );
      }
    }
  }

  @override
  void onInit(ScopeObservable target) => _each((o) => o.onInit(target));

  @override
  void onStepStarted(ScopeObservable target, String path) =>
      _each((o) => o.onStepStarted(target, path));

  @override
  void onProgress(ScopeObservable target, Object? progress) =>
      _each((o) => o.onProgress(target, progress));

  @override
  void onReady(ScopeObservable target) => _each((o) => o.onReady(target));

  @override
  void onCancelled(ScopeObservable target) =>
      _each((o) => o.onCancelled(target));

  @override
  void onDispose(ScopeObservable target) => _each((o) => o.onDispose(target));

  @override
  void onDisposalStepStarted(ScopeObservable target, String path) =>
      _each((o) => o.onDisposalStepStarted(target, path));

  @override
  void onDisposalProgress(ScopeObservable target, String path) =>
      _each((o) => o.onDisposalProgress(target, path));

  @override
  void onDisposed(ScopeObservable target) => _each((o) => o.onDisposed(target));

  @override
  void onError(
    ScopeObservable target,
    ScopePhase phase,
    Object error,
    StackTrace? stackTrace,
  ) =>
      _each((o) => o.onError(target, phase, error, stackTrace));

  @override
  void onTimeout(ScopeObservable target, String what) =>
      _each((o) => o.onTimeout(target, what));

  @override
  void onTrace(ScopeObservable target, String message) =>
      _each((o) => o.onTrace(target, message));
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

  // The ellipsis says "begun" here as it does on the two lines above and
  // below it, so the pair reads `initialize db…` / `progress: db (1/3)`.
  @override
  void onStepStarted(ScopeObservable target, String path) =>
      _write(target, 'initialize $path…');

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
  void onDisposalStepStarted(ScopeObservable target, String path) =>
      _write(target, 'dispose $path…');

  @override
  void onDisposalProgress(ScopeObservable target, String path) =>
      _write(target, 'disposed $path');

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
/// Six of the seven read as `'<phrase> failed'`; [ScopePhase.abandonedWait]
/// does not, because the deleted logger this mirrors named what the wait was
/// for (`'an abandoned wait for $what ended in a failure'`), and the
/// observer has no `$what` to put there. Rather than force that phrase into
/// the `'<phrase> failed'` shape it does not fit, it stands as the whole
/// message.
String _failureMessage(ScopePhase phase) => switch (phase) {
      ScopePhase.initialization => 'initialization failed',
      ScopePhase.initializationCancellation =>
        'initialization cancellation failed',
      ScopePhase.build => 'build failed',
      ScopePhase.preparationForDisposal => 'preparation for disposal failed',
      ScopePhase.unmount => 'unmount failed',
      ScopePhase.disposal => 'disposal failed',
      ScopePhase.abandonedWait => 'an abandoned wait ended in a failure',
    };
