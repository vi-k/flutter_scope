part of '../scope.dart';

/// {@category AsyncScope}
abstract base class AsyncScopeCore<W extends AsyncScopeCore<W, E>,
        E extends AsyncScopeElementBase<W, E>>
    extends ScopeModelCore<W, E, AsyncScopeModel> {
  const AsyncScopeCore({
    super.key,
    super.tag,
    super.child, // Not used by default. You can use it at your own discretion.
  });

  static E? maybeOf<W extends AsyncScopeCore<W, E>,
          E extends AsyncScopeElementBase<W, E>>(
    BuildContext context, {
    required bool listen,
  }) =>
      ScopeContext.maybeOf<W, E>(context, listen: listen);

  static E
      of<W extends AsyncScopeCore<W, E>, E extends AsyncScopeElementBase<W, E>>(
    BuildContext context, {
    required bool listen,
  }) =>
          ScopeContext.of<W, E>(context, listen: listen);

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
  /// **The key, together with the coordinator above the scope, is fixed for
  /// the lifetime of the element.** The place in the queue is taken once, and
  /// it cannot be moved: a key that starts returning something else -- or a
  /// scope moved with a [GlobalKey] under a different coordinator -- leaves the
  /// entry parked where it was, so the old key is held by a scope that no
  /// longer claims it while the new key excludes nobody. A change is reported
  /// in debug builds; there is no re-acquisition, because releasing and taking
  /// a key again is asynchronous and a rebuild is not.
  ///
  /// To switch a scope to another key, or to move it under another
  /// coordinator, give the widget a different [Widget.key] instead: the
  /// framework then builds a new element, which takes the new key from scratch
  /// and releases the old one on its way out.
  Object? get scopeKey => null;

  Duration? get pauseAfterInitialization => null;

  Duration? get scopeKeyTimeout => null;

  void onScopeKeyTimeout() {}

  Duration? get waitForChildrenTimeout => null;

  void onWaitForChildrenTimeout() {}

  Stream<AsyncScopeInitState> initAsync() => Stream.value(AsyncScopeReady());

  FutureOr<void> disposeAsync() {}

  Widget buildOnState(AsyncScopeState state);

  //
  // End of overriding block
  //

  @override
  AsyncScopeModel get model => _model.asUnmodifiable();
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

  AccessEntry? _asyncScopeEntry;

  /// The [scopeKey] and the [AsyncScopeCoordinator] element [_asyncScopeEntry]
  /// took its place on.
  ///
  /// An entry lives in the queue of one key of one coordinator and there is no
  /// way to move it, so the pair is fixed once the entry exists. It is
  /// remembered here to be able to say so out loud when it changes, instead of
  /// letting the mutual exclusion the key exists for quietly stop working.
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

  AsyncScopeElementBase(super.widget);

  @override
  void mount(Element? parent, Object? newSlot) {
    super.mount(parent, newSlot);
    _performAsyncInit(); // ignore: discarded_futures
  }

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
  }

  /// Fails when the (`scopeKey`, coordinator) pair this element took its place
  /// on is no longer the pair it would ask for now.
  ///
  /// Called from an `assert`, so it costs nothing in release builds -- which
  /// is also why it raises rather than returning `false`: the message is worth
  /// more than the line number.
  bool _debugCheckScopeKeyOwnership() {
    if (_asyncScopeEntry == null) {
      return true;
    }

    final currentScopeKey = scopeKey;
    final currentCoordinator = ScopeWidgetCore.maybeOf<AsyncScopeCoordinator,
        _AsyncScopeCoordinatorElement>(this, listen: false);

    if (currentScopeKey == _acquiredScopeKey &&
        identical(currentCoordinator, _acquiredCoordinator)) {
      return true;
    }

    final acquiredCoordinator =
        _acquiredCoordinator?.toStringShort() ?? 'no $AsyncScopeCoordinator';
    final coordinator =
        currentCoordinator?.toStringShort() ?? 'no $AsyncScopeCoordinator';

    throw FlutterError.fromParts([
      ErrorSummary(
        'The `scopeKey` of ${widget.toStringShort()} changed while it was'
        ' holding one.',
      ),
      ErrorDescription(
        'It took its place in the queue of [$_acquiredScopeKey] of'
        ' $acquiredCoordinator, and is now asking for the queue of'
        ' [$currentScopeKey] of $coordinator.',
      ),
      ErrorDescription(
        'The entry it is holding cannot follow it: it stays where it was, so'
        ' the key it still holds is never released for the scope it was meant'
        ' to keep out, and the key it appears to hold now keeps nobody out.'
        ' Releasing a key and taking another one is asynchronous, and a'
        ' rebuild is not, so there is nothing to do about it here.',
      ),
      ErrorHint(
        'A `scopeKey` and the `$AsyncScopeCoordinator` above the scope are'
        ' fixed for the lifetime of the element. To use another key, or to'
        ' move the scope under another coordinator, give the widget a'
        ' different `key`: the framework then builds a new element, which'
        ' takes the new key from scratch and releases the old one on its way'
        ' out.',
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
      // Wait for access.
      if (scopeKey case final scopeKey?) {
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
        _acquiredScopeKey = scopeKey;
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

        if (entry.isCancelled || !mounted) {
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
              Future<void>.delayed(pauseAfterInitialization, () {
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
          if (!_initCompleter.isCompleted) {
            _log.i('not initialized');
            _initCompleter.complete();
          }
        },
        cancelOnError: true,
      );
    } on Object catch (error, stackTrace) {
      // `_initSucceeded` stays false: nothing was initialized, so nothing is
      // disposed of either.
      _log.e('initialization failed', error: error, stackTrace: stackTrace);
      if (!_initCompleter.isCompleted) {
        _initCompleter.complete();
      }
      rethrow;
    }

    return _initCompleter.future;
  }

  Future<void> _performAsyncDispose() async {
    _isDisposing = true;

    _log.d('prepare for disposal');

    // Cancel waiting for access if it has not finished yet.
    if (_asyncScopeEntry case final entry? when entry.isWaiting) {
      _log.d(() => 'cancel waiting for access to [$scopeKey]');
      entry.cancel();
    }

    // Cancel the initialization if it has not finished yet.
    if (_subscription case final subscription?) {
      // TODO(nashol): errors raised after the cancellation land here
      await subscription.cancel();
      if (!_initCompleter.isCompleted) {
        _log.i('initialization cancelled');
        _initCompleter.complete();
      }
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

    try {
      if (_initSucceeded) {
        _log.i('dispose…');
        final result = disposeAsync();
        if (result is Future<void>) {
          await result;
        }
      } else {
        _log.d('do not dispose of');
      }

      _log.i('disposed');
    } on Object catch (error, stackTrace) {
      _log.e('disposal failed', error: error, stackTrace: stackTrace);
      rethrow;
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
        _log.d(() => 'exit from [$scopeKey]');
        asyncScopeEntry.exit();
        _asyncScopeEntry = null;
      }

      _model.dispose();

      _widget = null;
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
