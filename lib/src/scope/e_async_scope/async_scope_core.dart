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
    // Register again when the widget is moved in the tree with a GlobalKey.
    _registerWithParent();
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
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
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
        final entry = AccessEntry(
          widget.toStringShort(showHashCode: true),
        );
        _asyncScopeEntry = entry;
        _log.d(() => 'wait for access to [$scopeKey]');
        try {
          await AsyncScopeCoordinator._enter(
            this,
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
        } on Object {
          // The entry never made it into a queue -- the lookup of the
          // coordinator that owns the queues is what failed -- so there is
          // nothing to release, and the `exit()` in `_performAsyncDispose`
          // would throw on an entry that was never attached.
          _asyncScopeEntry = null;
          rethrow;
        }
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
      _asyncScopeParentEntry?.unregister();

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
