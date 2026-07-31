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

    AsyncScopeParent? parent;
    visitAncestorElements((e) {
      if (e case final AsyncScopeParent e) {
        parent = e;
        return false;
      }
      return true;
    });

    _asyncScopeParentEntry = parent?.registerChild(
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

    // Wait for access.
    if (scopeKey case final scopeKey?) {
      final entry = AccessEntry(
        widget.toStringShort(showHashCode: true),
      );
      _asyncScopeEntry = entry;
      _log.d(() => 'wait for access to [$scopeKey]');
      await AsyncScopeCoordinator.enter(
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
      switch (_model.state) {
        case AsyncScopeWaiting():
        case AsyncScopeProgress():
          break;
        case AsyncScopeReady():
          throw StateError('$W already initialized');
        case AsyncScopeError():
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
          _initCompleter.complete();
      }
    }).listen(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        _log.e('initialization failed', error: error, stackTrace: stackTrace);

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

        _initCompleter.complete();
      },
      onDone: () {
        if (!_initCompleter.isCompleted) {
          _log.i('not initialized');
          _initCompleter.complete();
        }
      },
      cancelOnError: true,
    );

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
