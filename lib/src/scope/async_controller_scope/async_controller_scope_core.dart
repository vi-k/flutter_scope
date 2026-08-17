part of '../scope.dart';

/// {@category AsyncControllerScope}
abstract base class AsyncControllerScopeCore<
    W extends AsyncControllerScopeCore<W, E, C>,
    E extends AsyncControllerScopeElementBase<W, E, C>,
    C extends ScopeController> extends AsyncDataScopeCore<W, E, C> {
  /// Creates the widget half of a scope owning a controller.
  const AsyncControllerScopeCore({
    super.key,
    super.tag,
    super.child, // Not used by default. You can use it at your own discretion.
  });
}

/// {@category AsyncControllerScope}
abstract base class AsyncControllerScopeElementBase<
    W extends AsyncControllerScopeCore<W, E, C>,
    E extends AsyncControllerScopeElementBase<W, E, C>,
    C extends ScopeController> extends AsyncDataScopeElementBase<W, E, C> {
  /// Creates the element of a scope owning a controller.
  AsyncControllerScopeElementBase(super.widget);

  /// Kept from the moment it is created, so the synchronous half of the
  /// teardown can reach it even when the initialization never finished.
  C? _controller;

  //
  // Overriding block
  //

  /// Creates the controller this scope owns.
  ///
  /// Called once, at the start of the asynchronous phase. The context is the
  /// scope's own element: reading another scope with `listen: false` is fine
  /// here, subscribing to one is not.
  C createController(BuildContext context);

  //
  // End of overriding block
  //

  /// Sealed: this is the whole of what the family promises -- a controller
  /// created, initialized and released on every path, including the two a
  /// hand-written version loses it on. Overriding it would take all of that
  /// away silently. The hook to write is [createController].
  @nonVirtual
  @override
  Stream<AsyncDataScopeInitState<Object, C>> initDataAsync() async* {
    final controller = _controller = createController(this);

    try {
      await controller.performInit();

      yield AsyncDataScopeReady(controller);
    } finally {
      // The criterion is the one `_performAsyncDispose` uses to decide whether
      // to call `disposeAsync`, and it has to be: a flag set beside the `yield`
      // above would lie. The event travels from there through the `map` that
      // stores the value to the `asyncMap` callback that sets
      // `_initSucceeded` -- and a cancellation landing in between drops it,
      // because nothing is delivered after `cancel()`. The scope would then
      // never call `disposeAsync`, while a local flag would be saying the
      // controller had been handed over.
      if (!_initSucceeded) {
        await _releaseController(controller);
      }
    }
  }

  /// Releases [controller] when the initialization never handed it over.
  ///
  /// Two guards, and neither of them is a precaution.
  ///
  /// A failure raised from the `finally` above would replace the failure the
  /// `finally` was entered for -- the one that actually broke the scope, and
  /// the only one worth showing. It is reported instead. And `dispose()` is
  /// documented to run on the path where `init()` failed halfway, which makes
  /// that the path it is most likely to fail on.
  ///
  /// The wait is bounded for the same reason the rest of the teardown is: a
  /// release that never finishes never lets the generator finish either, so
  /// the failure of `init()` would never reach the model and the scope would
  /// show its loading branch for ever. `disposeAsyncTimeout` is the limit the
  /// `AsyncControllerScope` topic names for the wait on `dispose()`, and this
  /// is a wait on `dispose()`.
  Future<void> _releaseController(C controller) async {
    try {
      final released = controller.performDispose();

      // A teardown that gave up on this initialization has since run to the
      // end, and the release is happening on a generator it abandoned. There
      // is nothing left for a limit to protect -- nobody is waiting for this,
      // the model is disposed of and the `scopeKey` is back -- and there is
      // nothing left to read a limit from either: `disposeAsyncTimeout` goes
      // through `widget`, which the element cleared on its way out, so asking
      // raised a `_TypeError` where a release belonged. The wait goes on
      // unbounded, which is what an abandoned release deserves: it can hold
      // nothing up.
      if (_disposalIsOver) {
        await released;

        return;
      }

      final limit =
          disposeAsyncTimeout ?? ScopeConfig.defaultDisposeAsyncTimeout;

      if (limit == null) {
        await released;
      } else {
        await _awaitBounded(
          released,
          limit,
          'its controller to be released',
          onDisposeAsyncTimeout,
        );
      }
      // ignore: avoid_catching_errors
    } on Object catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'scopo',
          context: ErrorDescription(
            'while releasing the controller of a scope whose initialization '
            'had already failed',
          ),
        ),
      );
    }
  }

  @override
  void onUnmount() {
    super.onUnmount();
    _controller?.performUnmount();
  }

  /// Releases the controller on the ordinary path.
  ///
  /// A subclass that adds a teardown of its own has to chain to this one:
  /// it is the only place the controller is released when the scope reached
  /// its ready state, and forgetting it leaks exactly what this family
  /// exists to keep hold of.
  @mustCallSuper
  @override
  FutureOr<void> disposeAsync() => _controller?.performDispose();
}
