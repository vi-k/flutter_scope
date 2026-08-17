part of '../scope.dart';

/// {@category AsyncScope}
abstract base class AsyncScopeCore<W extends AsyncScopeCore<W, E>,
        E extends AsyncScopeElementBase<W, E>>
    extends ScopeModelCore<W, E, AsyncScopeModel> {
  /// Creates the widget half of an asynchronous scope.
  const AsyncScopeCore({
    super.key,
    super.tag,
    super.child, // Not used by default. You can use it at your own discretion.
  });

  /// The element of the nearest scope [W] above [context], or `null`.
  static E? maybeOf<W extends AsyncScopeCore<W, E>,
          E extends AsyncScopeElementBase<W, E>>(
    BuildContext context, {
    required bool listen,
  }) =>
      ScopeContext.maybeOf<W, E>(context, listen: listen);

  /// The element of the nearest scope [W] above [context].
  ///
  /// Throws when there is none.
  static E
      of<W extends AsyncScopeCore<W, E>, E extends AsyncScopeElementBase<W, E>>(
    BuildContext context, {
    required bool listen,
  }) =>
          ScopeContext.of<W, E>(context, listen: listen);

  /// Subscribes to one value of the scope and returns it.
  static V select<W extends AsyncScopeCore<W, E>,
          E extends AsyncScopeElementBase<W, E>, V extends Object?>(
    BuildContext context,
    V Function(E element) selector,
  ) =>
      ScopeContext.select<W, E, V>(context, selector);
}

/// {@category AsyncScope}
abstract base class AsyncScopeElementBase<W extends AsyncScopeCore<W, E>,
        E extends AsyncScopeElementBase<W, E>>
    extends ScopeNotifierElementBase<W, E, AsyncScopeModel>
    with AsyncScopeParent
    implements AsyncScopeContext<W> {
  //
  // Overriding block
  //

  /// The key this scope must hold alone, or `null` when it needs none.
  ///
  /// A scope with a key waits, before it initializes, until every scope that
  /// asked for the same key from the same [AsyncScopeCoordinator] has finished
  /// disposing of itself, and holds it until its own disposal is over. Two
  /// scopes under different coordinators never wait for one another, even when
  /// their keys are equal.
  ///
  /// **This getter is read exactly once, when the initialization starts, and
  /// the answer it gives then -- together with the coordinator above the scope
  /// -- is binding until the scope has finished disposing of itself.** `null`
  /// is one of those answers, not the absence of one: a scope that reads no
  /// key never takes a place in any queue, and nothing takes one for it later.
  ///
  /// So, for as long as it is binding, none of the four ways the answer can go
  /// stale is repaired:
  ///
  /// * a key that **appears** after a scope initialized without one is not
  ///   honoured -- the scope holds nothing and keeps nobody out;
  /// * a key that is **given up** is still held until the disposal releases
  ///   it, so it goes on excluding scopes this one no longer claims to
  ///   exclude;
  /// * a key that **changes** leaves the entry on the old one, which is never
  ///   released for the scope it was meant to keep out, while the new one
  ///   keeps nobody out;
  /// * a scope **moved with a [GlobalKey] under a different coordinator**
  ///   keeps its place in the queue it left, with the same two consequences.
  ///
  /// All four are reported through an `assert`, so they are loud in debug
  /// builds and cost nothing in release builds. None is repaired, because
  /// releasing a key and taking another one is asynchronous and a rebuild is
  /// not.
  ///
  /// Once the disposal has released the key, the answer binds nothing any more
  /// and none of that is reported: an element that outlives its own disposal
  /// -- which is what `close()` leaves behind, still mounted so it can show a
  /// closing screen, and still movable with a [GlobalKey] -- may be rebuilt
  /// and reparented freely.
  ///
  /// To switch a scope to another key, or to move it under another
  /// coordinator, give the widget a different [Widget.key] instead: the
  /// framework then builds a new element, which reads this getter afresh and
  /// releases the old key on its way out.
  Object? get scopeKey => null;

  /// Holds the ready branch back for this long; `null` shows it at once.
  Duration? get pauseAfterInitialization => null;

  /// How long to wait for the `scopeKey`; `null` takes the default.
  Duration? get scopeKeyTimeout => null;

  /// Called when the wait for the `scopeKey` expires.
  void onScopeKeyTimeout() {}

  /// How long to wait for [initAsync] to be cancelled; `null` takes the
  /// default.
  Duration? get initCancellationTimeout => null;

  /// Called when the wait for the cancellation of [initAsync] expires.
  void onInitCancellationTimeout() {}

  /// How long to wait for [disposeAsync]; `null` takes the default.
  Duration? get disposeAsyncTimeout => null;

  /// Called when the wait for [disposeAsync] expires.
  void onDisposeAsyncTimeout() {}

  /// How long to wait for the child scopes; `null` takes the default.
  Duration? get waitForChildrenTimeout => null;

  /// Called when the wait for the child scopes expires.
  void onWaitForChildrenTimeout() {}

  /// The initialization; ready at once by default.
  Stream<AsyncScopeInitState> initAsync() => Stream.value(AsyncScopeReady());

  /// Releases what [initAsync] acquired; awaited.
  FutureOr<void> disposeAsync() {}

  /// Builds the branch belonging to [state].
  Widget buildOnState(AsyncScopeState state);

  //
  // End of overriding block
  //

  /// The read-only face of [_model], made once.
  ///
  /// Everything the scope shows of its state goes through here — [state],
  /// [isInitialized], [hasError], [error], [stackTrace], `buildChild()`,
  /// `debugFillProperties` and every run of every selector — so a wrapper
  /// built on each read was rubbish on every build of every dependent.
  @override
  late final AsyncScopeModel model = _model.asUnmodifiable();
  final _AsyncScopeNotifier _model = _AsyncScopeNotifier();

  /// Keeps the widget reachable during the asynchronous disposal.
  @override
  W get widget => _widget ?? super.widget;
  W? _widget;

  // ignore: cancel_subscriptions
  StreamSubscription<void>? _subscription;

  /// Disposal may begin before the end of asynchronous initialization.
  /// Therefore, we use [_initCompleter] for synchronization.
  final _initCompleter = Completer<void>();

  /// Whether [initAsync] has definitively completed successfully (reached
  /// [AsyncScopeReady]).
  ///
  /// This is tracked separately from `model.state`, because the
  /// `_model.update(state)` call that applies [AsyncScopeReady] to the
  /// model happens inside a `mounted`-guarded post-frame callback (or a
  /// `mounted`-guarded delayed callback, for [pauseAfterInitialization]):
  /// if the element is removed from the tree before that callback runs,
  /// `model.state` never becomes [AsyncScopeReady], even though
  /// [initAsync] itself already succeeded and may have acquired resources
  /// that [disposeAsync] must release. [_performAsyncDispose] uses this
  /// flag instead of `model.state` to decide whether [disposeAsync] must
  /// run, so that scenario doesn't leak.
  bool _initSucceeded = false;

  /// Whether [_performAsyncDispose] has started.
  ///
  /// Disposal may begin while the callbacks that apply [AsyncScopeReady] to the
  /// model are still pending, and `mounted` alone does not cover that: an
  /// element that is closed via `close()` -- rather than removed from the tree
  /// -- stays mounted while [_model] is being disposed of, so a pending
  /// callback would use the disposed notifier.
  bool _isDisposing = false;

  /// The [pauseAfterInitialization] delay, while it is running.
  ///
  /// Kept so the teardown can put it out. A delay nobody holds outlives the
  /// tree: `flutter_test` ends a test on a timer that is still pending once
  /// the tree is gone, so a scope taken off the tree mid-pause failed the
  /// consumer's own widget test for no reason of theirs, and in production
  /// held an unmounted element for the rest of the pause.
  ///
  /// It is a timer of the current zone on purpose, unlike the bounded waits of
  /// the teardown: this delay is one the user sees, and a widget test has to be
  /// able to drive it with its own clock.
  Timer? _pauseTimer;

  AccessEntry? _asyncScopeEntry;

  /// Whether [_performAsyncInit] has read [scopeKey] yet.
  ///
  /// Kept apart from [_acquiredScopeKey], because `null` is a value the getter
  /// may legitimately return and the answer matters either way: a scope that
  /// read no key decided just as irrevocably that it needs none, and nothing
  /// takes an entry for it afterwards.
  bool _scopeKeyObserved = false;

  /// Whether the disposal has released everything the key involved.
  ///
  /// The element outlives its own disposal when it was closed via `close()`
  /// rather than removed from the tree -- that is the whole point of `close()`,
  /// which keeps it mounted so it can show a closing screen, and leaves it
  /// movable with a [GlobalKey]. Once the `finally` of [_performAsyncDispose]
  /// has run, the entry has been `exit()`ed and the scope holds nothing, so
  /// [scopeKey] answering differently from then on contradicts nothing and is
  /// no longer worth reporting. Until then it still does: the entry is in a
  /// queue, and a key that changes mid-close is the very violation the
  /// diagnostic exists for.
  bool _scopeKeySettled = false;

  /// The value [scopeKey] had when [_performAsyncInit] read it, and the
  /// [AsyncScopeCoordinator] element the resulting [_asyncScopeEntry] took its
  /// place on -- the latter `null` when no key was read, or when the lookup
  /// failed and no entry was ever created.
  ///
  /// The answer is given once and cannot be revisited: an entry lives in the
  /// queue of one key of one coordinator and there is no way to move it, and a
  /// key that was never asked for has no entry to move. Both are remembered
  /// here to be able to say so out loud when they change, instead of letting
  /// the mutual exclusion the key exists for quietly stop working.
  Object? _acquiredScopeKey;
  _AsyncScopeCoordinatorElement? _acquiredCoordinator;

  ChildEntry? _asyncScopeParentEntry;

  @override
  bool get autoSelfDependence => true;

  @override
  AsyncScopeState get state => model.state;

  @override
  bool get isInitialized => model.state is AsyncScopeReady;

  @override
  bool get hasError => switch (model.state) {
        AsyncScopeWaiting() ||
        AsyncScopeProgress() ||
        AsyncScopeReady() =>
          false,
        AsyncScopeError() => true,
      };

  @override
  Object get error => switch (model.state) {
        AsyncScopeWaiting() ||
        AsyncScopeProgress() ||
        AsyncScopeReady() =>
          throw StateError('No error'),
        AsyncScopeError(:final error) => error,
      };

  @override
  StackTrace get stackTrace => switch (model.state) {
        AsyncScopeWaiting() ||
        AsyncScopeProgress() ||
        AsyncScopeReady() =>
          throw StateError('No error'),
        AsyncScopeError(:final stackTrace) => stackTrace,
      };

  /// Creates the element of an asynchronous scope.
  AsyncScopeElementBase(super.widget);

  /// Whether the asynchronous initialization has started.
  bool _didStartAsyncInit = false;

  @override
  void dispose() {
    _widget = widget;
    _performAsyncDispose(); // ignore: discarded_futures
    super.dispose();
  }

  @override
  void activate() {
    super.activate();

    // A `close()`d element stays mounted, so it can still be moved in the
    // tree with a `GlobalKey` -- and it comes back here with its disposal
    // already over. Registering it with its new parent would hand that parent
    // an entry nobody will ever complete, since the `finally` that would have
    // unregistered it has long since run.
    if (_isDisposing) {
      assert(_debugCheckScopeKeyOwnership());

      return;
    }

    // A scope whose synchronous [init] failed never reaches its asynchronous
    // phase, so it has nothing to report to a parent and never will. Handing
    // one an entry would make it wait out its whole `waitForChildrenTimeout`
    // on a scope that was never there -- the disposal releases the entry, but
    // only once the tree comes down, which is not when the parent asks.
    if (!_didStartAsyncInit) {
      return;
    }

    // Register again when the widget is moved in the tree with a GlobalKey.
    //
    // Before the ownership check, not after it: a move with a `GlobalKey` is
    // one of the two ways that check can fail, and it fails by raising. Left
    // above this line it would unwind `activate()` in exactly the case it
    // exists to describe, so the scope would leave its old parent's subtree
    // without ever unregistering from it -- the old parent would then wait
    // out its whole `waitForChildrenTimeout` on a child that is alive and
    // well somewhere else. The handoff happens first; the report is what may
    // be lost, and it is not.
    _registerWithParent();

    assert(_debugCheckScopeKeyOwnership());
  }

  @override
  void performRebuild() {
    // The other way: a `scopeKey` getter that starts returning something else
    // -- a new widget with a different key, or a value read from the element's
    // own state.
    assert(_debugCheckScopeKeyOwnership());
    super.performRebuild();

    // `super.performRebuild()` invokes the common sync [init] inside
    // Flutter's build error boundary. A thrown init is terminal and leaves
    // `_didInit` false for good, so the asynchronous phase of a scope that
    // never synchronously came to be does not start at all -- and the one
    // that did starts it exactly once, on the build that ran the hook.
    if (_didInit && !_didStartAsyncInit) {
      _didStartAsyncInit = true;
      _performAsyncInit(); // ignore: discarded_futures
    }
  }

  /// Fails when [scopeKey] no longer gives the answer the initialization read,
  /// or when the coordinator that owns the queue it entered is no longer the
  /// one above the scope.
  ///
  /// The absence of a key counts as an answer: a scope that read `null` never
  /// takes an entry, so a key that turns up afterwards is not honoured either
  /// -- and that is the one case with nothing to see, since there is no
  /// misplaced entry to notice, only a key that quietly excludes nobody.
  ///
  /// A scope that has finished disposing of itself is past all of this: it has
  /// released whatever it held, so the answer is no longer binding on
  /// anything and it may be rebuilt or reparented freely -- which is exactly
  /// what `close()` leaves an element able to do.
  ///
  /// Called from an `assert`, so it costs nothing in release builds -- which
  /// is also why it raises rather than returning `false`: the message is worth
  /// more than the line number.
  bool _debugCheckScopeKeyOwnership() {
    if (!_scopeKeyObserved || _scopeKeySettled) {
      // Either the initialization has not read `scopeKey` yet, so there is no
      // answer to disagree with, or the disposal has released everything it
      // led to, so disagreeing with it costs nothing.
      return true;
    }

    final currentScopeKey = scopeKey;
    // Which coordinator is above the scope only matters once one of its queues
    // is holding an entry: a scope that took none may be moved wherever the
    // tree likes.
    final currentCoordinator = _acquiredCoordinator == null
        ? null
        : ScopeWidgetCore.maybeOf<AsyncScopeCoordinator,
            _AsyncScopeCoordinatorElement>(this, listen: false);

    if (currentScopeKey == _acquiredScopeKey &&
        identical(currentCoordinator, _acquiredCoordinator)) {
      return true;
    }

    final name = widget.toStringShort();
    final acquiredCoordinator =
        _acquiredCoordinator?.toStringShort() ?? 'no $AsyncScopeCoordinator';
    final coordinator =
        currentCoordinator?.toStringShort() ?? 'no $AsyncScopeCoordinator';

    final (String summary, String detail) =
        switch ((_acquiredScopeKey, currentScopeKey)) {
      (null, final appeared?) => (
          'The `scopeKey` of $name appeared after the scope had already'
              ' initialized without one.',
          'The key is read once, when the initialization starts, and this'
              ' scope read none: it never took a place in any queue, and nothing'
              ' takes one for it now. [$appeared] is not honoured -- this scope'
              ' holds nothing, and whoever does hold [$appeared] is not keeping it'
              ' out.',
        ),
      (final acquired?, null) => (
          'The `scopeKey` of $name was given up while the scope was still'
              ' holding it.',
          'It is holding [$acquired] in the queue of $acquiredCoordinator, and'
              ' now claims to need no key at all. The entry stays where it is'
              ' until the disposal releases it, so [$acquired] goes on keeping out'
              ' the scopes this one no longer claims to exclude.',
        ),
      (final acquired?, final asked?) when acquired != asked => (
          'The `scopeKey` of $name changed while the scope was holding one.',
          'It is holding [$acquired] in the queue of $acquiredCoordinator, and'
              ' is now asking for [$asked]. The entry cannot follow: it stays'
              ' where it is, so [$acquired] is never released for the scope it was'
              ' meant to keep out, and [$asked] keeps nobody out.',
        ),
      _ => (
          'The `$AsyncScopeCoordinator` above $name changed while the scope'
              ' was holding a `scopeKey`.',
          'It is holding [$_acquiredScopeKey] in the queue of'
              ' $acquiredCoordinator, and is now under $coordinator. The entry'
              ' cannot follow: it stays in the queue it left, so the key it holds'
              ' there is never released, and under the new coordinator it keeps'
              ' nobody out.',
        ),
    };

    throw FlutterError.fromParts([
      ErrorSummary(summary),
      ErrorDescription(detail),
      ErrorDescription(
        'Releasing a key and taking another one is asynchronous, and a rebuild'
        ' is not, so there is nothing to do about it here.',
      ),
      ErrorHint(
        'The answer `scopeKey` gives when the initialization reads it --'
        ' including `null`, for no key at all -- and the'
        ' `$AsyncScopeCoordinator` above the scope are fixed for the lifetime'
        ' of the element. To use another key, or to move the scope under'
        ' another coordinator, give the widget a different `key`: the'
        ' framework then builds a new element, which reads the key afresh and'
        ' releases the old one on its way out.',
      ),
    ]);
  }

  void _registerWithParent() {
    if (_asyncScopeParentEntry case final ChildEntry entry) {
      entry.unregister();
      _asyncScopeParentEntry = null;
    }

    // A parent scope always wins: the coordinator is the wait root only for a
    // scope that has no scope above it at all. A coordinator placed between
    // two scopes -- the shape of `AsyncScopeCoordinator(child: MaterialApp(…))`
    // inside a root scope -- must not take the parent's place, or the parent
    // would stop waiting for its child.
    AsyncScopeParent? parentScope;
    AsyncScopeParent? coordinator;
    visitAncestorElements((e) {
      if (e case final AsyncScopeParent parent) {
        if (e is _AsyncScopeCoordinatorElement) {
          coordinator ??= parent;
          return true;
        }
        parentScope = parent;
        return false;
      }
      return true;
    });

    _asyncScopeParentEntry = (parentScope ?? coordinator)?._registerChild(
      widget.toStringShort(showHashCode: true),
    );
  }

  Future<void> _performAsyncInit() async {
    assert(model.state is AsyncScopeWaiting);

    _log.d('prepare for initialization');

    // Register with parent scope.
    //
    // `mounted` alone does not cover a disposal that has already run:
    // `close()` keeps the element mounted on purpose, so a callback drained
    // after the disposal is over would hand the parent a *fresh* entry, one
    // registered after the `finally` had unregistered the previous one and
    // that nobody will ever complete. The parent would then burn its whole
    // `waitForChildrenTimeout` on a scope that is already gone.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isDisposing) return;
      _registerWithParent();
    });

    // Everything below either hands `_initCompleter` over to the subscription
    // that completes it, or completes it itself. A failure in between -- the
    // coordinator lookup, or `initAsync()` raising while the stream is being
    // built -- would otherwise leave the completer unsettled forever: this
    // future is discarded, so nothing retries and nothing else settles it,
    // while `_performAsyncDispose` waits for it before it may unregister the
    // scope from its parent. The error is re-thrown untouched, so it still
    // surfaces as an uncaught error of the zone the mount ran in.
    try {
      // `scopeKey` is read exactly once, here. The answer -- a key, or the
      // decision that none is needed -- is what everything below is built on,
      // and what every later rebuild is measured against.
      final acquiredScopeKey = scopeKey;
      _acquiredScopeKey = acquiredScopeKey;
      _scopeKeyObserved = true;

      // Wait for access.
      if (acquiredScopeKey case final scopeKey?) {
        // The coordinator is looked up *before* the entry exists: the lookup
        // is the one step here that can fail without the entry ever reaching
        // a queue, and an entry that reached one has to be released by the
        // `exit()` in `_performAsyncDispose` no matter how the rest goes.
        // Everything below attaches the entry before it awaits anything, so
        // once it is in `_asyncScopeEntry` it is in a queue too, and a
        // failure -- `onScopeKeyTimeout()`, ordinary user code, throwing on
        // an expiry, say -- must not drop it: nothing else would ever release
        // the key, and every later scope on it would wait for an entry nobody
        // completes.
        final coordinator = AsyncScopeCoordinator._elementOf(this);
        final entry = AccessEntry(
          widget.toStringShort(showHashCode: true),
        );
        _asyncScopeEntry = entry;
        _acquiredCoordinator = coordinator;
        _log.d(() => 'wait for access to [$scopeKey]');
        await coordinator.enter(
          scopeKey,
          entry,
          timeout: scopeKeyTimeout ?? ScopeConfig.defaultScopeKeysTimeout,
          onTimeout: (error, stackTrace) {
            FlutterError.reportError(
              FlutterErrorDetails(
                exception: error,
                stack: stackTrace,
                library: 'scopo',
              ),
            );
            onScopeKeyTimeout();
          },
        );
        if (entry.isCancelled) {
          _log.d(() => 'access to [$scopeKey] cancelled');
        } else {
          _log.d(() => 'access to [$scopeKey] obtained');
        }

        // `_isDisposing`, and not `mounted` alone: the disposal reaches the
        // initialization through `_subscription`, which does not exist yet on
        // this side of the `await` -- and a scope closed with `close()` stays
        // mounted on purpose, so `mounted` says nothing about a disposal that
        // has already begun. Without this, a scope on its way out would
        // subscribe to `initAsync()` here and run it to completion, acquiring
        // resources for a scope that no longer exists; `_performAsyncDispose`
        // is meanwhile parked on `_initCompleter`, past the point where it
        // could have cancelled anything.
        if (entry.isCancelled || !mounted || _isDisposing) {
          _log.i('initialization cancelled');
          _initCompleter.complete();
          return;
        }
      }

      _log.i('initialize…');
      _subscription = initAsync().asyncMap((state) {
        // `_initSucceeded`, not `_model.state`: the model only becomes
        // `AsyncScopeReady` inside the post-frame (or delayed) callback
        // scheduled below, so a second `AsyncScopeReady` that arrives before
        // that callback runs would slip past a check on the model and
        // initialize the scope all over again -- a second `_initSucceeded`, a
        // second pending update, and a second `_initCompleter.complete()`.
        if (_initSucceeded) {
          throw StateError('$W already initialized');
        }
        if (_model.state case AsyncScopeError()) {
          throw StateError('$W initialization failed');
        }

        switch (state) {
          case AsyncScopeProgress():
            _log.i(() => 'progress: ${state.progress}');
            _model.update(state);
          case AsyncScopeReady():
            if (pauseAfterInitialization case final pauseAfterInitialization?
                when ScopeConfig.pauseAfterInitializationEnabled) {
              _pauseTimer = Timer(pauseAfterInitialization, () {
                _pauseTimer = null;
                // The `_isDisposing` half is unreachable, and kept anyway:
                // `_performAsyncDispose` sets that flag and cancels this
                // timer in the next statement, with nothing in between, and
                // the only code that can arm a new one is the subscription
                // that the same teardown cancels before its first `await`.
                // Left in as the guard of the callback beside it, which is a
                // post-frame one and cannot be cancelled at all -- a mutation
                // that removes this half is therefore not caught by any test,
                // and cannot be.
                if (mounted && !_isDisposing) {
                  _model.update(state);
                }
              });
            } else {
              // Give the last progress value a chance to be displayed.
              SchedulerBinding.instance
                ..scheduleFrame()
                ..addPostFrameCallback((_) {
                  if (!mounted || _isDisposing) return;
                  _model.update(state);
                });
            }
            _initSucceeded = true;
            _log.i('initialized');
            if (!_initCompleter.isCompleted) {
              _initCompleter.complete();
            }
        }
      }).listen(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          _log.e('initialization failed', error: error, stackTrace: stackTrace);

          // A failure that arrives *after* [AsyncScopeReady] -- a stream that
          // keeps working once the scope is usable and then raises, or the
          // `already initialized` diagnostic above -- reaches a scope that is
          // initialized: [disposeAsync] will have to release what
          // [initAsync] acquired, and the widgets built for the ready state
          // are the ones on screen. Flipping the model into [AsyncScopeError]
          // now would swap them for `buildOnError` behind the user's back,
          // and completing [_initCompleter] a second time would raise `Bad
          // state: Future already completed` *on top of* the failure being
          // reported -- which is how the real one used to get lost. The
          // failure is reported instead, and the scope is left as it is.
          if (_initSucceeded) {
            FlutterError.reportError(
              FlutterErrorDetails(
                exception: error,
                stack: stackTrace,
                library: 'scopo',
              ),
            );

            return;
          }

          _model.update(
            AsyncScopeError(
              error,
              stackTrace,
              progress: switch (_model.state) {
                AsyncScopeProgress(:final progress) => progress,
                _ => null,
              },
            ),
          );

          if (!_initCompleter.isCompleted) {
            _initCompleter.complete();
          }
        },
        onDone: () {
          if (_initSucceeded) {
            return;
          }

          // A stream that ends without ever yielding [AsyncScopeReady] has
          // initialized nothing and has nothing further coming, and that used
          // to be the quietest way for a scope to fail: the model stayed
          // [AsyncScopeWaiting], the loading branch stayed on screen for good,
          // and the only trace was an `info` line in a logger that is off by
          // default. It is the same silence the synchronous failure below was
          // fixed for -- and the comment there names it in the same words.
          final error = StateError(
            '$W was initialized by a stream that ended without '
            'AsyncScopeReady. That is how an `initAsync` says it is done, so '
            'a stream ending without it leaves the scope nothing to show and '
            'nothing to release.',
          );
          _log.e('not initialized', error: error);

          // Before the model, and before anything that could throw:
          // `_performAsyncDispose` parks on this completer, and a failure on
          // the way to the model would otherwise leave the whole teardown
          // waiting for an initialization that is long over.
          if (!_initCompleter.isCompleted) {
            _initCompleter.complete();
          }

          _model.update(
            AsyncScopeError(
              error,
              StackTrace.current,
              progress: switch (_model.state) {
                AsyncScopeProgress(:final progress) => progress,
                _ => null,
              },
            ),
          );
        },
        cancelOnError: true,
      );
    } on Object catch (error, stackTrace) {
      // `_initSucceeded` stays false: nothing was initialized, so nothing is
      // disposed of either.
      _log.e('initialization failed', error: error, stackTrace: stackTrace);

      // Settled before anything below is attempted. This future is discarded,
      // so nothing retries and nothing else settles the completer, while
      // `_performAsyncDispose` parks on it before it may unregister the scope
      // from its parent: a failure on the way to the model would otherwise
      // leave the whole teardown waiting for an initialization that is long
      // over.
      if (!_initCompleter.isCompleted) {
        _initCompleter.complete();
      }

      // The same state the stream's own failures land in, for the same
      // reason. A failure raised here -- the coordinator lookup, an
      // `initAsync()` that throws while the stream is being built -- is an
      // initialization that failed before it was ready, which is what
      // [AsyncScopeError] means and what `buildOnError` is for. Left out, as
      // it was, the model stayed [AsyncScopeWaiting] and the scope went on
      // showing its loading branch for good: loud in the console, where the
      // re-throw below puts it, and silent on screen, which is the half the
      // user sees.
      //
      // Outside the frame, and that is not a precaution: the failures this
      // catch exists for are raised *before the first `await`*, so it runs
      // inside the very `performRebuild` that started the initialization.
      // Updating the model there marks the element dirty in the middle of its
      // own build, which Flutter refuses -- and the refusal would replace the
      // failure being reported with a second, derived one.
      //
      // The callback is guarded like every other deferred write to the model:
      // by the time it runs the scope may be gone, and a scope closed with
      // `close()` stays mounted while its notifier is disposed of.
      SchedulerBinding.instance.runOutsideFrame(() {
        if (!mounted || _isDisposing) {
          return;
        }

        _model.update(
          AsyncScopeError(
            error,
            stackTrace,
            progress: switch (_model.state) {
              AsyncScopeProgress(:final progress) => progress,
              _ => null,
            },
          ),
        );
      });

      rethrow;
    }

    return _initCompleter.future;
  }

  Future<void> _performAsyncDispose() async {
    _isDisposing = true;

    // First, and synchronously: everything below may take a while, and until
    // this is out the pause is a timer with nobody left to fire for.
    _pauseTimer?.cancel();
    _pauseTimer = null;

    // Four stages, each guarded on its own rather than chained: every one of
    // them reaches user code, and a failure in one is never a reason to skip
    // the ones after it. [unmountScope] drops what must stop reaching the
    // scope at once, preparing gives up on the waits, `disposeAsync()`
    // releases what the scope acquired, and the `finally` gives back what the
    // scope was lent -- its place with the parent, its `scopeKey`, its model.
    // The first failure is passed on once all four are over, so the caller
    // still hears about it.
    AsyncError? failure;

    // Takes what a stage threw. A throw carries one failure, and the first
    // stage to fail has already claimed it, so everything after it goes out
    // the only other way there is. Left to the log line above each call, as
    // it was, the second and third failures reached nobody at all: that log
    // is off by default.
    void take(Object error, StackTrace stackTrace) {
      if (failure == null) {
        failure = AsyncError(error, stackTrace);
      } else {
        _reportFailure(error, stackTrace, 'while disposing of the scope');
      }
    }

    try {
      try {
        // Nothing on a removed element: the framework got here first. On a
        // scope that closed itself this is the only place that ever will.
        unmountScope();
        // ignore: avoid_catching_errors
      } on Object catch (error, stackTrace) {
        _log.e('unmount failed', error: error, stackTrace: stackTrace);
        take(error, stackTrace);
      }

      try {
        await _prepareForDisposal();
        // ignore: avoid_catching_errors
      } on Object catch (error, stackTrace) {
        _log.e(
          'preparation for disposal failed',
          error: error,
          stackTrace: stackTrace,
        );
        take(error, stackTrace);
      }

      try {
        if (_initSucceeded) {
          _log.i('dispose…');
          final result = disposeAsync();
          if (result is Future<void>) {
            // The same bound as the cancellation above, for the same reason:
            // this is user code, the block below gives back what the scope was
            // lent, and a release that never finishes must not be able to keep
            // the key of a scope that is already gone.
            final limit =
                disposeAsyncTimeout ?? ScopeConfig.defaultDisposeAsyncTimeout;

            if (limit == null) {
              await result;
            } else {
              await _awaitBounded(
                result,
                limit,
                'its own teardown',
                onDisposeAsyncTimeout,
              );
            }
          }
        } else {
          _log.d('do not dispose of');
        }

        _log.i('disposed');
        // ignore: avoid_catching_errors
      } on Object catch (error, stackTrace) {
        _log.e('disposal failed', error: error, stackTrace: stackTrace);
        take(error, stackTrace);
      }
    } finally {
      // Cleared, not just unregistered: the element outlives its disposal
      // when it was closed via `close()` rather than removed from the tree,
      // and a stale entry left in the field is one `_registerWithParent()`
      // would try to unregister a second time.
      if (_asyncScopeParentEntry case final asyncScopeParentEntry?) {
        asyncScopeParentEntry.unregister();
        _asyncScopeParentEntry = null;
      }

      if (_asyncScopeEntry case final asyncScopeEntry?) {
        // `_acquiredScopeKey`, not `scopeKey`: what is being released is the
        // key the queue was entered on, whatever the getter says by now.
        _log.d(() => 'exit from [$_acquiredScopeKey]');
        asyncScopeEntry.exit();
        _asyncScopeEntry = null;
      }

      // Nothing is held any more, so [scopeKey] has nothing left to
      // contradict. Set here rather than on `_isDisposing`, so a key that
      // changes while the disposal is still in flight -- with the entry still
      // in its queue -- is reported as loudly as ever.
      _scopeKeySettled = true;

      _model.dispose();

      _widget = null;
    }

    if (failure case final failure?) {
      Error.throwWithStackTrace(failure.error, failure.stackTrace);
    }
  }

  /// Awaits [work], and for no longer than [limit].
  ///
  /// [what] finishes the sentence "couldn't wait for ..." in the reported
  /// expiry, so it reads as a thing this scope was waiting for.
  ///
  /// The limit is measured on real time, by a timer taken from the root zone,
  /// and not on the clock of the zone the teardown happens to run in. Two
  /// reasons, and either one is enough. A teardown that never finishes hangs
  /// on real time -- a mocked clock has nothing true to say about it. And a
  /// scope is usually taken down between frames, with nothing left to advance
  /// a fake clock afterwards: a timer belonging to such a zone would still be
  /// pending when the tree is gone, which is what `flutter_test` ends a test
  /// on. Every widget test with a live scope in it would fail on a timer this
  /// package armed while tidying up after itself.
  ///
  /// Reaches user code through [onExpiry], so its failures are the caller's to
  /// absorb.
  Future<void> _awaitBounded(
    Future<void> work,
    Duration limit,
    String what,
    void Function() onExpiry,
  ) async {
    var finished = false;
    final expired = Completer<void>();
    final timer = Zone.root.createTimer(limit, () {
      if (!expired.isCompleted) {
        expired.complete();
      }
    });

    try {
      // Work that fails still fails here: `Future.any` takes the error of
      // whichever future settles first, and this one settling at all is what
      // the race is about.
      await Future.any([
        work.whenComplete(() => finished = true),
        expired.future,
      ]);
    } finally {
      timer.cancel();
    }

    if (finished) {
      return;
    }

    // Abandoned, not forgotten. The work may still fail long after nobody is
    // waiting for it -- a generator resumed at last, throwing from its
    // `finally` -- and a failure that reaches no listener is one more thing
    // lost in silence.
    unawaited(
      work.catchError((Object error, StackTrace stackTrace) {
        _log.e(
          'an abandoned wait for $what ended in a failure',
          error: error,
          stackTrace: stackTrace,
        );
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'scopo',
          ),
        );
      }),
    );

    _log.e('gave up waiting for $what');
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: TimeoutException(
          '${widget.toStringShort(showHashCode: true)} '
          "couldn't wait for $what",
          limit,
        ),
        stack: StackTrace.current,
        library: 'scopo',
      ),
    );
    onExpiry();
  }

  /// Gives up on everything the disposal has to stop waiting for.
  ///
  /// Reaches user code through [onWaitForChildrenTimeout], so its failures are
  /// the caller's to absorb.
  Future<void> _prepareForDisposal() async {
    _log.d('prepare for disposal');

    // Cancel waiting for access if it has not finished yet.
    if (_asyncScopeEntry case final entry? when entry.isWaiting) {
      _log.d(() => 'cancel waiting for access to [$scopeKey]');
      entry.cancel();
    }

    // Cancel the initialization if it has not finished yet.
    if (_subscription case final subscription?) {
      // A generator runs its `finally` when it is cancelled, and a failure
      // raised there -- or by anything else the cancellation drives -- is
      // delivered through this future. Letting it out would abandon the
      // disposal right here, before any of the releasing below has run: the
      // scope would never unregister from its parent, which then waits out
      // its whole `waitForChildrenTimeout` on a scope that is already gone,
      // and never release its `scopeKey`, so every later scope on that key
      // would queue behind an entry nobody completes. The failure is
      // reported and the disposal goes on -- the same trade the rest of this
      // file makes for the failures it cannot hand to a caller.
      //
      // Waiting forever leads to exactly the same place, and needs no failure
      // to get there. Cancelling an `async*` means resuming its body and
      // letting it run out; a body suspended on a future that never completes
      // is never resumed, so the cancellation never finishes. The wait is
      // therefore bounded: when the limit expires the expiry is reported, the
      // initialization is left where it stands, and the disposal goes on to
      // give back what the scope was holding. What the generator itself holds
      // stays held -- it is parked on somebody else's future, and no scope can
      // complete that one for it.
      try {
        final cancelled = subscription.cancel();
        final limit = initCancellationTimeout ??
            ScopeConfig.defaultInitCancellationTimeout;

        if (limit == null) {
          await cancelled;
        } else {
          await _awaitBounded(
            cancelled,
            limit,
            'its initialization to be cancelled',
            onInitCancellationTimeout,
          );
        }
      } on Object catch (error, stackTrace) {
        _log.e(
          'initialization cancellation failed',
          error: error,
          stackTrace: stackTrace,
        );
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'scopo',
          ),
        );
      }
      if (!_initCompleter.isCompleted) {
        _log.i('initialization cancelled');
        _initCompleter.complete();
      }
    }

    // The completer is settled by [_performAsyncInit], and that never ran when
    // the synchronous [init] failed: there is no initialization to wait for,
    // and nobody left to say so. `close()` reaches this without going through
    // the `unmount` guard, so the wait below would never come back.
    if (!_didStartAsyncInit && !_initCompleter.isCompleted) {
      _initCompleter.complete();
    }

    if (!_initCompleter.isCompleted) {
      _log.d('wait for initialization');
      await _initCompleter.future;
    }

    if (hasChildren) {
      _log.d(() => 'wait for children (count: $childrenCount)');
      await waitForChildren(
        timeout:
            waitForChildrenTimeout ?? ScopeConfig.defaultWaitForChildrenTimeout,
        onTimeout: (error, stackTrace) {
          FlutterError.reportError(
            FlutterErrorDetails(
              // The message the registry builds knows nothing about the widget
              // tree, so the scope puts its own name in front of it.
              exception: TimeoutException(
                '${widget.toStringShort(showHashCode: true)} ${error.message}',
                error.duration,
              ),
              stack: stackTrace,
              library: 'scopo',
            ),
          );
          onWaitForChildrenTimeout();
        },
      );
    }
  }

  @override
  Widget buildChild() => buildOnState(model.state);

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<AsyncScopeState>('state', model.state));
    if (scopeKey case final scopeKey?) {
      properties.add(DiagnosticsProperty<Object?>('scopeKey', scopeKey));
    }
    if (pauseAfterInitialization case final pauseAfterInitialization?) {
      properties.add(
        DiagnosticsProperty<Duration>(
          'pauseAfterInitialization',
          pauseAfterInitialization,
        ),
      );
    }
  }
}
