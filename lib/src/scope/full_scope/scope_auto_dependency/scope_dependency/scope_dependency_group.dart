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
  /// [ScopeDependencyDisposalCancelled] is in the list for the same reason the
  /// other three are: a walk that was stopped halfway left the children it
  /// never reached holding what they took, so the disposal is still due.
  @override
  bool get disposalRequired =>
      !_isDisposalDone &&
      (state is ScopeDependencyInitialized ||
          state is ScopeDependencyFailed ||
          state is ScopeDependencyCancelled ||
          state is ScopeDependencyDisposalCancelled);

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
  Stream<String> _runInit() async* {
    final dependencies = _dependencies //
        .where((d) => d.initializationRequired);
    for (final dependency in dependencies) {
      yield* dependency.init().map(_path);
    }
  }

  @override
  Stream<String> _runDispose() async* {
    final dependencies = _disposalOrder();
    final errors = <AsyncError>[];

    for (final dependency in dependencies) {
      try {
        // Iterated rather than `yield*`-ed: an error inside a delegated stream
        // goes straight to the listener, where no `catch` of ours can see it.
        await for (final path in dependency.dispose()) {
          yield _path(path);
        }
        // ignore: avoid_catching_errors
      } on Object catch (error, stackTrace) {
        // One dependency that cannot let go is no reason to walk away from the
        // ones below it, which are still holding resources of their own. Each
        // failure is already recorded on the dependency it belongs to; the
        // first one is passed upwards once the walk is over.
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
  Stream<String> _runInit() async* {
    // The loop that stood here collected the children so that each could be
    // wired on the way in; the wiring moved to the constructor, and the filter
    // is a filter again. Walked once: `_mergeStreams` collects what it is
    // given before it asks it anything.
    yield* _dependencies //
        .where((dep) => dep.initializationRequired)
        .map((dep) => dep.init())
        ._mergeStreams()
        .map(_path);
  }

  @override
  Stream<String> _runDispose() async* {
    final errors = <AsyncError>[];

    // Each arm keeps its own failure to itself, which is the same rule the
    // sequential group applies and for the same reason -- one dependency that
    // cannot let go is no reason to walk away from the others, which are
    // still holding resources of their own.
    //
    // Here it has to be done before the merge rather than around the walk.
    // An error reaching the merged stream is passed on by `yield*` straight
    // to the listener, where no `catch` of ours can see it, and
    // `runStreamGuarded` answers the first error by cancelling its source --
    // which cancels every arm still running. An arm suspended mid-walk is
    // then resumed only as far as its next `yield`, so a branch stops
    // wherever the cancellation found it and everything below that point
    // stays held. Nothing comes back for it either: `dispose` marks the
    // walk done whichever way it ended.
    //
    // The first failure in time is passed upwards once the merged stream is
    // over, as the sequential group passes on the first in walk order.
    yield* _disposalOrder()
        .map(
          (dep) => dep.dispose().handleError(
                (Object error, StackTrace stackTrace) =>
                    errors.add(AsyncError(error, stackTrace)),
              ),
        )
        ._mergeStreams()
        .map(_path);

    if (errors.firstOrNull case final first?) {
      Error.throwWithStackTrace(first.error, first.stackTrace);
    }
  }
}

extension<T> on Iterable<Stream<T>> {
  /// Merges the streams into one, running them in parallel.
  Stream<T> _mergeStreams() {
    final controller = StreamController<T>(sync: true);

    controller.onListen = () {
      // Collected before it is asked anything, so that the shape of the chain
      // handed in cannot matter. Whether `isEmpty` walks at all depends on
      // which operation is outermost: `MappedIterable` overrides it and
      // delegates to its source, so a chain ending in `map` never runs the
      // mapping function for it; `WhereIterable` has no such override and
      // answers by taking one step, which runs whatever `map` sits further in
      // -- and the walk below then runs that one again.
      //
      // Neither caller ends on a `where` today, so nothing has come of it. It
      // is collected anyway because the function at stake is the one that asks
      // a dependency for its stream: a dependency whose stream begins its work
      // when it is made rather than when it is listened to would begin twice,
      // and that is too quiet a failure to leave hanging on which operation
      // happens to be last.
      final streams = toList(growable: false);
      if (streams.isEmpty) {
        controller.close(); // ignore: discarded_futures
        return;
      }

      final subscriptions = <StreamSubscription<T>>[];

      for (final stream in streams) {
        final subscription =
            stream.listen(controller.add, onError: controller.addError);
        subscriptions.add(subscription);
      }

      // The onDone handlers are attached only after `subscriptions` is fully
      // populated, so that no handler can ever observe a partially filled list
      // and close the controller prematurely.
      for (final subscription in subscriptions) {
        subscription.onDone(() {
          subscriptions.remove(subscription);
          if (subscriptions.isEmpty) {
            controller.close(); // ignore: discarded_futures
          }
        });
      }

      controller
        ..onPause = () {
          for (final subscription in subscriptions) {
            subscription.pause();
          }
        }
        ..onResume = () {
          for (final subscription in subscriptions) {
            subscription.resume();
          }
        }
        ..onCancel = () {
          if (subscriptions.isEmpty) {
            return null;
          }

          return subscriptions
              .map((s) => s.cancel()) // ignore: discarded_futures
              .wait
              .then((_) => null); // ignore: discarded_futures
        };
    };
    return controller.stream;
  }
}
