part of '../../scope.dart';

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

    final tree = switch (root) {
      // Nothing has been built yet.
      null => _root = buildDependencies(context),
      // Built, but never initialized: this *is* that first initialization.
      ScopeDependency(state: ScopeDependencyInitial()) => root,
      // The previous tree is done: its disposal walk reached its end, so
      // nothing it acquired is still held and a new tree can stand where it
      // stood.
      _ when _disposalIsOver(root) => _root = _rebuildAfterDisposal(context),
      _ => throw StateError(
          '$T has already been initialized (${root.stateToString()}) and has'
          ' not been disposed of. Dispose of it before initializing it again:'
          ' a second `init()` builds the tree afresh and runs every'
          ' initializer over the same container, whose fields the first run'
          ' has already assigned — and where that run is still holding'
          ' something, nothing would ever release it.',
        ),
    };

    // The one place the root's entry channels are set. `_root` is assigned
    // nowhere else, so no tree can reach either walk unwired; [init] and
    // [_runDispose] used to do it, once each, and a third entry point would
    // have had to remember. The marks of the whole subtree below travel the
    // segments the groups put in place in their own constructors.
    ScopeDependencyMixin._wireStepsStarted(
      tree,
      onStepStarted: (path) =>
          notifyObserver((observer) => observer.onStepStarted(this, path)),
      onDisposalStepStarted: (path) => notifyObserver(
        (observer) => observer.onDisposalStepStarted(this, path),
      ),
      onDisposalStepEnded: (path) =>
          notifyObserver((observer) => observer.onDisposalProgress(this, path)),
      onDisposalStepFailed: (path, error, stackTrace) => notifyObserver(
        (observer) => observer.onError(
          this,
          ScopePhase.disposal,
          // Named the way the failure that travels the walk is named: the
          // observer is told which dependency failed, and `onError` has no
          // path of its own to tell it with.
          ScopeDependencyException(path, error, stackTrace),
          stackTrace,
        ),
      ),
    );

    return tree;
  }

  /// Whether the disposal of [root] ran to its end.
  ///
  /// This used to ask `disposalRequired` instead, which is a different
  /// question: it means "is anything still held", and a tree whose
  /// dependencies registered no disposer answers `false` to it from the
  /// moment it is built. So a second `init()` on such a container — no
  /// `dispose()` anywhere in sight — walked past the guard and rebuilt the
  /// tree, over a container whose `late final` fields the first run had
  /// already assigned. What came out was a `LateInitializationError` from
  /// inside a dependency's initializer: it read as a mistake in the caller's
  /// own code, and it was a contradiction between two promises of this
  /// package. Nothing leaked, which is why it went unnoticed.
  ///
  /// A dependency of the caller's own making keeps no such flag, so it is
  /// asked the older question. It is the only thing it can answer.
  bool _disposalIsOver(ScopeDependency root) => root is ScopeDependencyMixin
      ? root._isDisposalDone
      : !root.disposalRequired;

  /// Whether an earlier run has already assigned this container's fields.
  ///
  /// Only ever goes from `false` to `true`: the branch that sets it is the one
  /// that builds a tree over a container that has run and been given back, and
  /// every run after that one takes it too.
  bool _isRerun = false;

  ScopeDependency _rebuildAfterDisposal(C context) {
    _isRerun = true;

    return buildDependencies(context);
  }

  /// [error] with the reason added, where the container knows one the error
  /// does not carry.
  ///
  /// A `late final` field an earlier run assigned throws on the second
  /// assignment, and what comes out names the dependency and nothing else:
  /// the reader is shown a `LateInitializationError` from inside their own
  /// initializer, which reads as a mistake they made there. The container is
  /// the one that knows this is a second run over the same fields.
  ///
  /// **Matching on the text of the error is the only way there is.** `late`
  /// failures are `LateError` from `dart:_internal`, which a package cannot
  /// import; both the "already initialized" and the "not initialized" cases
  /// are that one class, so they cannot be told apart by type either; and
  /// `LateInitializationError` is not a type at all -- it exists only in the
  /// message. What makes the match acceptable is its failure mode: a message
  /// changed by some future SDK costs the hint and nothing else, and the drift
  /// is caught by a test that runs on the declared floor.
  Object _explainRerunFailure(Object error) {
    if (!_isRerun || error is! ScopeDependencyException || error.hint != null) {
      return error;
    }

    final text = '${error.error}';
    if (!text.contains('LateInitializationError') ||
        !text.contains('has already been initialized')) {
      return error;
    }

    return ScopeDependencyException(
      error.name,
      error.error,
      error.stackTrace,
      hint: 'this is a second `init()` over the same container, and a '
          '`late final` field an earlier run assigned refuses the second '
          'assignment. Declare it `late`, or initialize a fresh container. '
          'The `Scope` topic says what `late final` costs here.',
    );
  }

  /// Initialize the scope dependencies.
  Future<T> init(C context, ScopeInitContext ctx) async {
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
    // Declared out here because the `finally` waits for it: what the
    // cancellation starts inside the `try` is finished after it.
    Future<void>? walkStopped;
    try {
      notifyObserver((observer) => observer.onInit(this));

      // The walk of the tree is still a stream -- that half of the package has
      // not moved -- so this is where the two forms meet. The body waits on
      // [walked]; the subscription feeds it.
      final walked = Completer<void>();
      final subscription = dependencies.init().listen(
        (path) {
          final step = progressIterator.nextStep();
          final progress = ScopeAutoDependenciesProgress(path, step);
          notifyObserver((observer) => observer.onProgress(this, progress));
          ctx.progress(progress);
        },
        // Through the subscription and not through a `try` around the walk: an
        // error of a delegated stream goes to the listener, and a `catch`
        // would never run. That is the defect R3 of the post-wave review found
        // here; this is the channel the error does travel.
        onError: (Object error, StackTrace stackTrace) {
          if (!walked.isCompleted) {
            walked.completeError(
              _explainRerunFailure(error),
              stackTrace,
            );
          }
        },
        onDone: () {
          if (!walked.isCompleted) {
            walked.complete();
          }
        },
        cancelOnError: true,
      );

      // What the cancellation used to do by itself. A cancelled `async*` took
      // the subscription of its `yield*` with it; a body has to hand the
      // cancellation on, and this is where it does. The wait ends here rather
      // than in the walk, which goes on unwinding whatever it was in the
      // middle of -- and the `finally` below is what waits for the result of
      // that unwinding.
      final unregister = ctx.onCancel(() {
        // Kept rather than awaited: `onCancel` is synchronous, and what it
        // starts here is finished by the `finally` below. Waiting matters --
        // the walk unwinds through its own `finally`s, and a teardown that
        // began before those had run met a tree that was still initializing
        // and refused to dispose of itself.
        walkStopped = subscription.cancel();
        if (!walked.isCompleted) {
          walked.completeError(const ScopeInitCancelled(), StackTrace.current);
        }
      });

      try {
        await walked.future;
      } finally {
        unregister();
      }

      if (!dependencies.isInitialized) {
        throw StateError(
          'The dependency tree of $T finished its walk without initializing. '
          'That is what a container says when it was cancelled, and a caller '
          'driving the tree by hand is the only one who can see it.',
        );
      }
      notifyObserver((observer) => observer.onReady(this));

      return this as T;
    } finally {
      // Put down first, before the teardown below rather than after it. By
      // here the run is over -- it failed, or the subscription was cancelled
      // -- and what follows is the disposal of what it built. Left standing,
      // it would be the container refusing its own cleanup through the guard
      // that keeps a *caller* from disposing of a container mid-run.
      //
      // The window this opens is closed by the guard behind it: an `init()`
      // arriving here meets a tree that is neither initialized nor finished
      // being disposed of, and `_prepareDependencies` refuses it; a
      // `dispose()` joins the walk this `finally` is already running.
      _initializing = false;

      // Before anything is released: the walk was told to stop, and until it
      // has, the tree is still initializing -- and a tree that is initializing
      // refuses to be disposed of, by the guard that keeps a caller from
      // disposing of a container mid-run. The old form got this for free,
      // because cancelling the stream is what ended the generator.
      if (walkStopped case final stopped?) {
        await stopped;
      }

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
    // Before anything is announced, so a refused disposal opens no pair the
    // observer would wait forever to see closed.
    //
    // The fourth diagonal, and the last: a second `init()` during the first is
    // refused, a second `init()` on a tree not given back is refused, a second
    // `dispose()` joins the walk already running -- and this one used to go
    // ahead. A dependency parked inside its initializer has registered nothing
    // yet, so the walk read it as one with nothing to release, marked it
    // disposed of and reported success, all before the initialization had
    // reached `ScopeReady`. The disposer registered a moment later then hung
    // on a dependency every later walk skips, and the next `init()` -- legal,
    // because the tree now claims its disposal ran to the end -- built a new
    // tree over one that was still holding.
    //
    // A scope never gets here: it cancels the subscription to `init()` first,
    // and cancelling disposes of what the run had built. This is for whoever
    // drives the container by hand, and it tells them to do what the scope
    // does.
    //
    // What the cancellation then amounts to depends on [autoDisposeOnError],
    // so the message asks rather than assumes. With the opt-out the
    // cancellation unmounts and stops -- keeping the half-built tree is the
    // whole point of turning it off -- and a caller who followed the flat
    // "cancelling releases what it had built" was left holding everything the
    // run had taken, in the one mode where the extra step matters most.
    if (_initializing) {
      final afterCancelling = autoDisposeOnError
          ? 'cancelling the subscription releases what it had built'
          : 'cancelling the subscription unmounts what it had built and '
              'leaves the rest of it standing, this container having turned '
              '`autoDisposeOnError` off, so dispose of it once the '
              'cancellation has come back';

      throw StateError(
        '$T is initializing right now, and a `dispose()` started here would '
        'walk a tree whose dependencies have not registered their teardown '
        'yet: one parked inside its initializer looks like a dependency with '
        'nothing to release, and what it registers a moment later would never '
        'be called by anything. Cancel the initialization that is running -- '
        '$afterCancelling -- or await it before disposing of the container.',
      );
    }

    final dependencies = _root;
    if (dependencies == null) {
      return;
    }

    final completer = Completer<void>();

    void reportFailure(Object error, StackTrace stackTrace) {
      // The observer half only for a root of the caller's own making, on the
      // same terms as the exit below: a root of the package's own making has
      // announced this failure from inside the walk, where it happened and
      // beside the entry it ends.
      if (dependencies is! ScopeDependencyMixin) {
        notifyObserver(
          (observer) => observer.onError(
            this,
            ScopePhase.disposal,
            // Named, the way the two other senders of this hook name theirs:
            // the observer is told which dependency failed, and `onError` has
            // no path of its own to tell it with. A foreign root is one step,
            // so its name is the whole path.
            ScopeDependencyException(dependencies.name, error, stackTrace),
            stackTrace,
          ),
        );
      }

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
    }

    notifyObserver((observer) => observer.onDispose(this));
    try {
      dependencies.dispose().listen(
        (path) {
          // Only for a root of the caller's own making, which has no channel
          // to announce from. A root of the package's own making has already
          // sent this exit from inside the walk, and reporting it again here
          // would double every step of a disposal the container drove itself.
          if (dependencies is! ScopeDependencyMixin) {
            notifyObserver(
              (observer) => observer.onDisposalProgress(this, path),
            );
          }
        },
        onError: reportFailure,
        onDone: completer.complete,
        cancelOnError: false,
      );

      await completer.future;
      // ignore: avoid_catching_errors
    } on Object catch (error, stackTrace) {
      // `dispose()` is a public interface method, and one of the caller's own
      // making is free to throw before it ever returns a stream -- the
      // package's own cannot, its `dispose()` being an `async*` whose body
      // does not run until it is listened to. Such a throw used to leave
      // through the future this method hands its caller, past the handler
      // above and past the `onDisposed` below: the entry had been announced,
      // and nothing ever closed it.
      reportFailure(error, stackTrace);
    }

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
