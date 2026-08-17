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
    C extends Object?> implements ScopeDependencies {
  late final _log = log.withAddedName(() => '$T(#${shortHash(this)})');

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

    final dependencies = _prepareDependencies(context);
    final progressIterator = ProgressIterator(dependencies.count);

    try {
      _log.d('initialize…');
      yield* dependencies.runInit().map((path) {
        final step = progressIterator.nextStep();
        _log.d(() => 'progress: $path ($step)');
        return ScopeProgress(ScopeAutoDependenciesProgress(path, step));
      });

      if (dependencies.isInitialized) {
        yield ScopeReady(this as T);
        _log.d('initialized');
      }
    } finally {
      if (!dependencies.isInitialized) {
        _log.d('not initialized');

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
          _log.e('unmount error', error: error, stackTrace: stackTrace);
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
          await dispose();
        }
      }
    }
  }

  @override
  void onUnmount() {
    _root?.onUnmount();
  }

  @override
  Future<void> dispose() async {
    final dependencies = _root;
    if (dependencies == null) {
      return;
    }

    final completer = Completer<void>();

    _log.d('dispose…');
    dependencies.runDispose().listen(
      (path) {
        _log.d(path);
      },
      onError: (Object error, StackTrace stackTrace) {
        _log.e('dispose error', error: error, stackTrace: stackTrace);

        // And reported, not only logged. This method never re-throws -- the
        // teardown above it goes on whatever the dependencies say -- so a
        // report is the one way out a failure has, and the log it used to
        // have to itself is off by default.
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
    _log.d('disposed');
  }

  /// A single dependency called [name].
  ///
  /// The `DepHelper` handed to `init` is where the teardown is registered.
  /// The name must not be empty.
  ScopeDependency dep(String name, FutureOr<void> Function(DepHelper) init) =>
      ScopeDependency(name, init);

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
          ScopeDependencySuccessStates() => false,
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
