part of '../../../scope.dart';

/// {@category Scope}
abstract base class ScopeDependencyGroup with ScopeDependencyMixin {
  @override
  final String name;

  late final List<ScopeDependency> _dependencies;

  /// The children of this group, in declaration order.
  List<ScopeDependency> get dependencies => List.of(_dependencies);

  late final int _count;

  ScopeDependencyGroup._(this.name, Iterable<ScopeDependency> dependencies) {
    _dependencies = List.of(dependencies, growable: false);
    _count = _dependencies.fold<int>(0, (p, e) => p + e.count);

    // Wired here, once, rather than by each walk as it reaches a child. The
    // closures read `_onStepStarted` when they fire and not now, so a group
    // can be wired long before anything above it is: the container points the
    // root at its observer as it prepares the tree, and every segment below is
    // already in place, assembled by the same [_path] the completed step
    // travels through. A child that neither walk ever visits simply never
    // fires what it was handed.
    //
    // Doing it on the walks meant three sites here and two in the container,
    // and the rule that kept them right was unwritten: reach a child any other
    // way -- a new kind of group, a `_runDispose` that does not go through
    // [_disposalOrder] -- and the marks of that whole subtree go missing in
    // silence. Construction is the one moment every child is reached by
    // definition.
    for (final dependency in _dependencies) {
      ScopeDependencyMixin._wireStepsStarted(
        dependency,
        onStepStarted: (path) => _onStepStarted?.call(_path(path)),
        onDisposalStepStarted: (path) =>
            _onDisposalStepStarted?.call(_path(path)),
        onDisposalStepEnded: (path) => _onDisposalStepEnded?.call(_path(path)),
        onDisposalStepFailed: (path, error, stackTrace) =>
            _onDisposalStepFailed?.call(_path(path), error, stackTrace),
      );
    }
  }

  @override
  int get count => _count;

  /// A group holds nothing of its own, so what it needs disposing of is
  /// whatever its children still hold — which is why a group whose
  /// initialization failed or was cancelled is disposed of too.
  ///
  /// [ScopeDependencyMixin._isDisposalDone], and not the state alone: a group
  /// that was disposed of because something under it failed keeps saying
  /// [ScopeDependencyFailed], so that the caller can still read what failed,
  /// and that must not be mistaken for a disposal that is still due.
  @override
  bool get disposalRequired =>
      !_isDisposalDone &&
      (state is ScopeDependencyInitialized ||
          state is ScopeDependencyFailed ||
          state is ScopeDependencyCancelled);

  /// Unmounts every child, in reverse, whatever any one of them makes of it.
  ///
  /// Reverse for the reason the disposal below is reverse: a later child is
  /// built on top of an earlier one, so it has to stop reaching the world
  /// before the one it was built on lets go of anything. Both halves of one
  /// teardown go the same way. Forward, `sequential('', [dep('bus'),
  /// dep('repo')])` unmounted the bus first and left the repository listening
  /// to a source that had already been told to stop.
  ///
  /// The hooks are user code, and one that fails is no reason to leave the
  /// siblings mounted -- each of them has its own subscription to drop. The
  /// first failure is passed on once the walk is over.
  @override
  void onUnmount() {
    AsyncError? failure;

    for (final dependency in _dependencies.reversed) {
      try {
        dependency.onUnmount();
        // ignore: avoid_catching_errors
      } on Object catch (error, stackTrace) {
        if (failure == null) {
          failure = AsyncError(error, stackTrace);
        } else {
          // Both channels, as everywhere else a failure has no caller left to
          // be raised at: a throw carries one failure, the first hook to fail
          // has already claimed it, and everything behind it used to be
          // dropped here without a word -- not to the caller, not to the
          // observer, not to `FlutterError`.
          notifyObserver(
            (observer) =>
                observer.onError(this, ScopePhase.unmount, error, stackTrace),
          );
          _reportFailure(
            error,
            stackTrace,
            'while unmounting a dependency',
          );
        }
      }
    }

    if (failure case final failure?) {
      Error.throwWithStackTrace(failure.error, failure.stackTrace);
    }
  }

  /// The children to walk, innermost first, with the ones that hold nothing
  /// marked as passed by.
  ///
  /// Skipping them is right — there is nothing to run — but skipping them in
  /// silence left them saying `initialized` after the tree had been torn down.
  /// See [ScopeDependencyMixin._markNothingToDispose].
  List<ScopeDependency> _disposalOrder() {
    final order = <ScopeDependency>[];

    for (final dependency in _dependencies.reversed) {
      if (dependency.disposalRequired) {
        order.add(dependency);
      } else if (dependency is ScopeDependencyMixin) {
        dependency._markNothingToDispose();
      }
    }

    return order;
  }

  String _path(String name) => this.name.isEmpty ? name : '${this.name}/$name';

  /// Announces the exit of [dependency]'s step for a child that cannot
  /// announce it itself.
  ///
  /// A dependency of the caller's own making is not a [ScopeDependencyMixin]
  /// and has no channel to be given, so the group speaks for it, from the one
  /// place it sees that child's steps come back: the stream it is already
  /// forwarding. The type test is also what keeps the exit from being
  /// announced twice — a child of the package's own making has sent it from
  /// inside itself before this path ever got here.
  ///
  /// Called before the path is passed upwards, so that the two halves keep the
  /// order they have everywhere else.
  void _announceExitFor(ScopeDependency dependency, String path) {
    if (dependency is! ScopeDependencyMixin) {
      _onDisposalStepEnded?.call(_path(path));
    }
  }

  /// The same, for the throw that ends a step instead of an exit.
  ///
  /// A child of the caller's own making cannot announce its own failure any
  /// more than it can announce its own exit, and the group sees both in the
  /// one place: the stream it is forwarding.
  void _announceFailureFor(
    ScopeDependency dependency,
    Object error,
    StackTrace stackTrace,
  ) {
    if (dependency is! ScopeDependencyMixin) {
      _onDisposalStepFailed?.call(_path(dependency.name), error, stackTrace);
    }
  }

  @override
  String get wrappedName => '[${name.isEmpty ? 'group' : name}]';

  // `ScopeDependencyMixin.debugLabel` falls back to `name`, which a leaf
  // dependency's constructor asserts is never empty but an anonymous group's
  // is by design — the root of a tree is usually one, and so is a nested
  // group with nothing to call itself. Left alone, an anonymous group's
  // report reads `scopo |  | …`, the label collapsed to nothing. `[group]` is
  // the same fallback [wrappedName] already uses for the same case; a named
  // group keeps reporting under its own name, unwrapped, same as before.
  @override
  String get debugLabel => name.isEmpty ? '[group]' : name;

  @override
  String stateToString() {
    switch (state) {
      case final ScopeDependencyAnyFailed state:
        final failedChildren = state
            .errors()
            .where((e) => e.error is ScopeDependencyException)
            .map(
              (e) => switch (e.error) {
                ScopeDependencyException(:final name) => name,
                _ => null,
              },
            )
            .nonNulls
            .toList();
        final errors = state
            .errors()
            .where((e) => e.error is! ScopeDependencyException)
            .toList();

        // One name, in practice: the stream the children run in is guarded, and
        // a guarded stream closes on the first error, so a group keeps one
        // failed child however many fall over at once. The join stays because a
        // diagnostic must not be the thing that throws -- `single` would, on an
        // empty list or on a second name that should not be there.
        return '${state.toString(showCount: false, showErrors: false)}'
            ': ${failedChildren.join(', ')}'
            '${errors.isEmpty //
                ? '' : '. Unresolved errors: $errors'}';

      case final ScopeDependencyState state:
        return '$state';
    }
  }
}

/// {@category Scope}
final class _ScopeDependencySequential extends ScopeDependencyGroup {
  _ScopeDependencySequential(super.name, super._dependencies) : super._();

  @override
  Future<void> _runInit(
    ScopeInitContext ctx,
    void Function(String path) onStep,
  ) async {
    final dependencies = _dependencies //
        .where((d) => d.initializationRequired);
    for (final dependency in dependencies) {
      // Between the children, which is where a cancelled walk used to stop by
      // itself: a generator ended at its next `yield`, and a `yield` stood
      // exactly here. Asked before the child rather than after it, so a walk
      // that was told to stop takes nothing new.
      ctx.check();
      await dependency.init(ctx, (path) => onStep(_path(path)));
    }
  }

  @override
  Future<void> _runDispose(void Function(String path) onStep) async {
    final dependencies = _disposalOrder();
    final errors = <AsyncError>[];

    for (final dependency in dependencies) {
      try {
        await dependency.dispose((path) {
          _announceExitFor(dependency, path);
          onStep(_path(path));
        });
        // ignore: avoid_catching_errors
      } on Object catch (error, stackTrace) {
        // One dependency that cannot let go is no reason to walk away from the
        // ones below it, which are still holding resources of their own. Each
        // failure is already recorded on the dependency it belongs to; the
        // first one is passed upwards once the walk is over.
        _announceFailureFor(dependency, error, stackTrace);
        errors.add(AsyncError(error, stackTrace));
      }
    }

    if (errors.firstOrNull case final first?) {
      Error.throwWithStackTrace(first.error, first.stackTrace);
    }
  }
}

/// {@category Scope}
final class _ScopeDependencyConcurrent extends ScopeDependencyGroup {
  _ScopeDependencyConcurrent(super.name, super._dependencies) : super._();

  @override
  Future<void> _runInit(
    ScopeInitContext ctx,
    void Function(String path) onStep,
  ) async {
    final arms = _dependencies.where((dep) => dep.initializationRequired);

    // The arms get a context of their own, and that is the whole of what the
    // merge used to do about a failure: the first arm to fall over gave up on
    // its siblings, because the guarded stream cancelled its source. Here the
    // first failure cancels this handle, the siblings are told at their next
    // step, and the initialization the group belongs to is untouched -- it is
    // waiting for this group to say what became of it.
    //
    // Everything the merge did *besides* that is gone rather than rewritten.
    // It existed because an arm was somebody's `Stream`: it could throw while
    // being built, throw from `listen`, or throw from the lazy chain that
    // produced it, and none of those went where an ordinary failure goes. An
    // arm is now an ordinary call, and an ordinary call that throws is caught
    // by an ordinary `catch`.
    final arm = ScopeInitHandle.childOf(ctx);
    try {
      await Future.wait([
        for (final dependency in arms)
          Future<void>.sync(
            () => dependency.init(
              arm.context,
              (path) => onStep(_path(path)),
            ),
          ).onError<Object>((error, stackTrace) {
            arm.cancel();
            Error.throwWithStackTrace(error, stackTrace);
          }),
      ]);
    } finally {
      // Takes the handle off `ctx` whichever way the group ended, so a scope
      // that outlives this group does not carry its callback around.
      arm.cancel();
    }
  }

  @override
  Future<void> _runDispose(void Function(String path) onStep) async {
    final errors = <AsyncError>[];

    // Each arm keeps its own failure to itself, which is the same rule the
    // sequential group applies and for the same reason -- one dependency that
    // cannot let go is no reason to walk away from the others, which are
    // still holding resources of their own. Swallowed here rather than let
    // out, so that `Future.wait` runs every arm to its end instead of coming
    // back on the first failure.
    //
    // The first failure in time is passed upwards once every arm is over, as
    // the sequential group passes on the first in walk order.
    await Future.wait([
      for (final dependency in _disposalOrder())
        Future<void>.sync(
          () => dependency.dispose((path) {
            _announceExitFor(dependency, path);
            onStep(_path(path));
          }),
        ).onError<Object>((error, stackTrace) {
          _announceFailureFor(dependency, error, stackTrace);
          errors.add(AsyncError(error, stackTrace));
        }),
    ]);

    if (errors.firstOrNull case final first?) {
      Error.throwWithStackTrace(first.error, first.stackTrace);
    }
  }
}
