part of '../../scope.dart';

/// {@category Scope}
typedef ScopeAutoDependenciesStream<T extends ScopeDependencies>
    = Stream<ScopeInitState<ScopeAutoDependenciesProgress, T>>;

/// A container that builds its dependency tree and initializes it for you.
///
/// [T] is the class being declared — `final class AppDeps extends
/// ScopeAutoDependencies&lt;AppDeps, BuildContext>`. It is what [init] hands the
/// scope on success, so it is what the subtree gets from `Scope.of`, and the
/// bound is what keeps the two the same thing: naming another container there
/// used to compile and then fail at the end of a successful initialization,
/// with the whole tree already built and nothing left to release it.
///
/// [C] is what [buildDependencies] is given — a `BuildContext` when the tree
/// reads scopes above it, `void` when it needs nothing.
///
/// {@category Scope}
abstract base class ScopeAutoDependencies<T extends ScopeAutoDependencies<T, C>,
    C extends Object?> implements ScopeDependencies, ScopeObservable {
  @override
  String get debugLabel => '$T(#${shortHash(this)})';

  /// Whether a failed initialization disposes of what it managed to build.
  ///
  /// On by default: the container is torn down before the error reaches
  /// `buildOnError`. Turn it off to keep the half-built tree for inspection.
  bool get autoDisposeOnError => true;

  /// The root of the dependency tree.
  ///
  /// Throws before [buildDependencies] has run.
  ScopeDependency get root =>
      _root ?? (throw StateError('dependencies not built'));
  ScopeDependency? _root;

  /// Build the queue of dependencies.
  ScopeDependency buildDependencies(C context);

  /// The tree the next [init] runs against, built afresh when the previous
  /// run is over.
  ///
  /// A [ScopeDependency] goes through its states once: every one of them
  /// asserts that its initialization starts from [ScopeDependencyInitial], so
  /// the tree a disposal left behind cannot be initialized a second time. It
  /// is kept until here rather than dropped by [dispose], so that the outcome
  /// of the run that is over stays readable through [flattenDependencies] for
  /// as long as it is the latest one.
  ///
  /// A tree that is still alive is another matter: replacing it would leak
  /// everything it holds, since nothing would ever dispose of it. That is a
  /// mistake in the caller, and it is named as one.
  ScopeDependency _prepareDependencies(C context) {
    final root = _root;

    return switch (root) {
      // Nothing has been built yet, or the previous tree is done: its
      // disposal has run, so nothing it acquired is still held.
      null => _root = buildDependencies(context),
      _ when !root.disposalRequired && root.state is! ScopeDependencyInitial =>
        _root = buildDependencies(context),
      // Built, but never initialized: this *is* that first initialization.
      _ when root.state is ScopeDependencyInitial => root,
      _ => throw StateError(
          '$T has already been initialized (${root.stateToString()}) and has'
          ' not been disposed of. Dispose of it before initializing it again:'
          ' a second `init()` would abandon everything the first one is'
          ' still holding, and nothing would ever release it.',
        ),
    };
  }

  /// Initialize the scope dependencies.
  Stream<ScopeInitState<ScopeAutoDependenciesProgress, T>> init(
    C context,
  ) async* {
    // Before anything is built, because the cost of finding out late is the
    // whole tree. [T] is the container itself, and the bound on it only says
    // that whatever stands there is *a* container -- naming a different one
    // satisfies it and compiles. That mistake used to surface at the very end
    // of a successful initialization, where `ScopeReady` casts: everything was
    // built and running, the failure came out as a bare `TypeError` from a
    // line the caller never wrote, and nothing released any of it, since the
    // teardown below only runs for a tree that did not finish.
    if (this is! T) {
      throw StateError(
        'The first type argument of ScopeAutoDependencies must be the class '
        'being declared. $runtimeType declares $T there, so the container it '
        'would hand the scope is not the container that built anything. Write '
        '`$runtimeType extends ScopeAutoDependencies<$runtimeType, …>`.',
      );
    }

    // Asked before [_prepareDependencies], because that is what decides
    // whether the tree is reused, and it decides by asking whether the tree
    // has left [ScopeDependencyInitial] -- which a tree that is initializing
    // right now has not: that state is set at the very end of the run. So a
    // second call arriving while the first was parked on an `await` used to be
    // handed the same tree and start it again, and each dependency has one
    // handle: the second run replaced it, and with it the `unmount` and
    // `dispose` the first run had registered. What the first run had already
    // taken was left with nothing to release it.
    if (_initializing) {
      throw StateError(
        '$T is initializing right now, and a second `init()` would run every '
        'initializer of the same tree a second time -- each dependency has '
        'one handle, so the `unmount` and `dispose` registered by the run '
        'already going would be replaced and nothing would ever release what '
        'it had taken. Await the initialization that is running, or dispose '
        'of the container before initializing it again.',
      );
    }

    final dependencies = _prepareDependencies(context);
    final progressIterator = ProgressIterator(dependencies.count);

    _initializing = true;
    try {
      notifyObserver((observer) => observer.onInit(this));
      yield* dependencies.init().map((path) {
        final step = progressIterator.nextStep();
        notifyObserver(
          (observer) => observer.onProgress(
            this,
            ScopeAutoDependenciesProgress(path, step),
          ),
        );
        return ScopeProgress(ScopeAutoDependenciesProgress(path, step));
      });

      if (dependencies.isInitialized) {
        yield ScopeReady(this as T);
        notifyObserver((observer) => observer.onReady(this));
      }
    } finally {
      if (!dependencies.isInitialized) {
        notifyObserver((observer) => observer.onCancelled(this));

        // `unmount` is promised to run exactly once and always before
        // `dispose`, whichever way the scope goes -- and this is one of the
        // ways it goes. An initialization that failed never reaches
        // `ScopeReady`, so the element is never handed the container and its
        // own `onUnmount()` has nothing to call: this is the only pass left.
        // Without it a dependency that took a subscription before the failure
        // kept it forever, while its `dispose` closed the sink underneath.
        //
        // Unconditionally, not only under `autoDisposeOnError`: a container
        // kept for inspection is still a container holding subscriptions, and
        // its owner disposing of it by hand later does not make them wait.
        // A second `onUnmount()` from that owner is a no-op -- the hooks are
        // taken off as they run.
        try {
          dependencies.onUnmount();
          // ignore: avoid_catching_errors
        } on Object catch (error, stackTrace) {
          // Reported, never re-thrown: this `finally` guards the failure the
          // initialization is already carrying, and a hook that throws here
          // would replace it with itself. The disposal below reports its own
          // failures the same way and for the same reason.
          notifyObserver(
            (observer) =>
                observer.onError(this, ScopePhase.unmount, error, stackTrace),
          );
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stackTrace,
              library: 'scopo',
              context: ErrorDescription('while unmounting $T'),
            ),
          );
        }

        if (autoDisposeOnError) {
          await _disposeBounded();
        }
      }

      _initializing = false;
    }
  }

  /// Whether [init] is running right now.
  ///
  /// The tree cannot answer this: it stays in [ScopeDependencyInitial] for the
  /// whole of the run and leaves it only at the end.
  bool _initializing = false;

  /// Awaits [dispose] with a limit, and gives up rather than holding the
  /// generator open for ever.
  ///
  /// This runs while the failure of the initialization is on its way out of
  /// the generator, and nothing downstream sees that failure until the
  /// generator finishes. So a disposer that never completes does not merely
  /// fail to release what it holds: it holds the failure itself, and the scope
  /// above goes on showing its loading branch for good — nothing on screen and
  /// nothing in the console. The neighbouring family bounds the same wait for
  /// the same reason, and says so in
  /// `AsyncControllerScopeElementBase._releaseController`.
  ///
  /// The limit is [ScopeConfig.defaultDisposeScopeTimeout] rather than the
  /// `disposeScopeTimeout` of the scope: a container knows nothing of the
  /// widget that owns it, and works without one. The timer comes from
  /// [Zone.root] because a timer of the current zone would still be pending
  /// when a widget test ends, which is what `flutter_test` ends a test on.
  ///
  /// The default is read through the same resolver the other five bounded
  /// waits read theirs through, and for the same reason: it is one switch, and
  /// a `ScopeTimeout.none` written on it has to mean "no limit at all" here as
  /// well. Read straight out of [ScopeConfig] it meant the opposite — the
  /// marker went on to the timer as the negative length it is made of, and
  /// this wait gave up on its first tick.
  Future<void> _disposeBounded() async {
    final limit = resolveTimeout(null, ScopeConfig.defaultDisposeScopeTimeout);
    // ignore: discarded_futures
    final released = dispose();

    if (limit == null) {
      await released;

      return;
    }

    // Every limit that reaches a timer in this package comes out of
    // `resolveTimeout`, which refuses a negative one. A wait bounded without
    // going through it is how this very method used to expire at once on a
    // `ScopeTimeout.none`, so the timer says so itself rather than trusting
    // its caller.
    assert(!limit.isNegative, 'A wait cannot be bounded by $limit');

    var finished = false;
    final expired = Completer<void>();
    final timer = Zone.root.createTimer(limit, () {
      if (!expired.isCompleted) {
        expired.complete();
      }
    });

    try {
      await Future.any([
        released.whenComplete(() => finished = true),
        expired.future,
      ]);
    } finally {
      timer.cancel();
    }

    if (finished) {
      return;
    }

    // Abandoned, not forgotten: the release may still fail long after nobody
    // is waiting for it, and a failure nobody hears is one more thing lost in
    // the silence this method exists to break.
    unawaited(
      released.catchError((Object error, StackTrace stackTrace) {
        notifyObserver(
          (observer) => observer.onError(
            this,
            ScopePhase.abandonedWait,
            error,
            stackTrace,
          ),
        );
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'scopo',
            context: ErrorDescription('while disposing of $T'),
          ),
        );
      }),
    );

    notifyObserver((observer) => observer.onTimeout(this, 'the disposal'));
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: TimeoutException(
          "$T couldn't dispose of what it built before the initialization "
          'failed',
          limit,
        ),
        stack: StackTrace.current,
        library: 'scopo',
      ),
    );
  }

  @override
  void onUnmount() {
    _root?.onUnmount();
  }

  /// The disposal that is running right now, joined rather than repeated.
  ///
  /// Cleared once it is over, so a later call runs again: a walk a caller
  /// stopped halfway leaves the tree still asking to be disposed of, and a
  /// second call has to be able to pick it up.
  Future<void>? _disposal;

  @override
  Future<void> dispose() =>
      _disposal ??= _runDispose().whenComplete(() => _disposal = null);

  Future<void> _runDispose() async {
    final dependencies = _root;
    if (dependencies == null) {
      return;
    }

    final completer = Completer<void>();

    notifyObserver((observer) => observer.onDispose(this));
    dependencies.dispose().listen(
      (path) {
        notifyObserver((observer) => observer.onProgress(this, path));
      },
      onError: (Object error, StackTrace stackTrace) {
        notifyObserver(
          (observer) =>
              observer.onError(this, ScopePhase.disposal, error, stackTrace),
        );

        // Reported through FlutterError too, not only the observer: this
        // method never re-throws -- the teardown above it goes on whatever
        // the dependencies say -- so this is the one way out a failure has
        // when nothing is assigned to `ScopeConfig.observer` at all.
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'scopo',
            context: ErrorDescription('while disposing of $T'),
          ),
        );
      },
      onDone: completer.complete,
      cancelOnError: false,
    );

    await completer.future;
    notifyObserver((observer) => observer.onDisposed(this));
  }

  /// A single dependency called [name].
  ///
  /// The `ScopeDependencyHandle` handed to `init` is where the teardown is registered.
  /// The name must not be empty.
  ScopeDependency dep(
    String name,
    FutureOr<void> Function(ScopeDependencyHandle) init,
  ) =>
      ScopeDependency(name, init);

  /// A single dependency backed by a [ScopeController].
  ///
  /// The teardown is registered before the initialization is awaited —
  /// "acquire, register, then carry on", the rule a hand-written [dep] follows
  /// by hand. Nothing sits between creating the controller and registering it,
  /// so there is no window in which a controller is up and nothing knows how
  /// to release it; [ScopeController.performUnmount] and
  /// [ScopeController.performDispose] are no-ops until
  /// [ScopeController.performInit] has run, so registering them early costs
  /// nothing.
  ///
  /// [create] is where the caller stores the controller, the same way a [dep]
  /// initializer stores what it built.
  ScopeDependency controllerDep<S extends ScopeController>(
    String name,
    S Function() create,
  ) =>
      dep(name, (handle) async {
        final controller = create();
        handle
          ..unmount = controller.performUnmount
          ..dispose = controller.performDispose;
        await controller.performInit();
      });

  /// A group whose children are initialized one after another.
  ///
  /// They are unmounted and disposed of in reverse order — both halves of the
  /// teardown run the reverse of the construction. An empty [name] adds no
  /// segment to the paths of the children.
  ScopeDependency sequential(
    String name,
    Iterable<ScopeDependency> dependencies,
  ) =>
      ScopeDependency.sequential(name, dependencies);

  /// A group whose children are initialized in parallel.
  ///
  /// Progress therefore arrives in completion order rather than declaration
  /// order. They are disposed of in parallel too; the synchronous `unmount`
  /// half has to run in some order and runs in reverse declaration order, as
  /// it does in a [sequential] group.
  ScopeDependency concurrent(
    String name,
    Iterable<ScopeDependency> dependencies,
  ) =>
      ScopeDependency.concurrent(name, dependencies);

  /// Walks the tree depth-first.
  Iterable<ScopeDependencyInfo> flattenDependencies() sync* {
    yield* _extract(root, 0, '');
  }

  Iterable<ScopeDependencyInfo> _extract(
    ScopeDependency dependency,
    int level,
    String path,
  ) sync* {
    yield ScopeDependencyInfo(level: level, path: path, dependency: dependency);
    switch (dependency) {
      case ScopeDependencyGroup():
        for (final child in dependency.dependencies) {
          yield* _extract(
            child,
            level + 1,
            dependency.name.isEmpty ? path : '$path${dependency.name}/',
          );
        }
      case ScopeDependency():
      // no-op
    }
  }

  /// The entries that hold a real error.
  ///
  /// A `ScopeDependencyException` propagated from a child is not one: this
  /// narrows the walk to where something actually failed.
  Iterable<ScopeDependencyInfo> flattenDependenciesWithErrors() =>
      flattenDependencies().where(
        (info) => switch (info.dependency.state) {
          final _ScopeDependencyWithErrors state => state.errors().any(
                (e) => e.error is! ScopeDependencyException,
              ),
          ScopeDependencyAnySuccess() => false,
        },
      );
}

/// {@category Scope}
final class ScopeDependencyInfo {
  /// How deep in the tree the dependency sits.
  final int level;

  /// The path of the enclosing groups, ending with `/` when not empty.
  final String path;

  /// The dependency itself.
  final ScopeDependency dependency;

  /// Creates an entry of a tree walk.
  const ScopeDependencyInfo({
    required this.level,
    required this.path,
    required this.dependency,
  });

  /// The indentation matching [level], for printing a tree.
  String indent([String indent = '  ']) => indent * level;

  @override
  String toString() =>
      '${indent()}${dependency.wrappedName} ${dependency.stateToString()}';
}
