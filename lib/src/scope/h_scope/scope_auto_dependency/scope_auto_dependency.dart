part of '../../scope.dart';

/// {@category Scope}
typedef ScopeAutoDependenciesStream<T extends ScopeDependencies>
    = Stream<ScopeInitState<ScopeAutoDependenciesProgress, T>>;

/// {@category Scope}
abstract base class ScopeAutoDependencies<T extends ScopeDependencies,
    C extends Object?> implements ScopeDependencies {
  late final _log = log.withAddedName(() => '$T(#${shortHash(this)})');

  bool get autoDisposeOnError => true;

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
        if (autoDisposeOnError) {
          await dispose();
        }
      }
    }
  }

  @override
  void unmount() {
    _root?.unmount();
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
      },
      onDone: completer.complete,
      cancelOnError: false,
    );

    await completer.future;
    _log.d('disposed');
  }

  ScopeDependency dep(String name, FutureOr<void> Function(DepHelper) init) =>
      ScopeDependency(name, init);

  ScopeDependency sequential(
    String name,
    Iterable<ScopeDependency> dependencies,
  ) =>
      ScopeDependency.sequential(name, dependencies);

  ScopeDependency concurrent(
    String name,
    Iterable<ScopeDependency> dependencies,
  ) =>
      ScopeDependency.concurrent(name, dependencies);

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

final class ScopeDependencyInfo {
  final int level;
  final String path;
  final ScopeDependency dependency;

  const ScopeDependencyInfo({
    required this.level,
    required this.path,
    required this.dependency,
  });

  String indent([String indent = '  ']) => indent * level;

  @override
  String toString() =>
      '${indent()}${dependency.wrappedName} ${dependency.stateToString()}';
}
