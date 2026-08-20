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

  /// The element of the nearest scope [W] above [context], or `null`.
  ///
  /// Statics are not inherited in Dart, so a family built on this layer needs
  /// these three here rather than on the layer below: the same lookups exist on
  /// [AsyncDataScopeCore] and [AsyncScopeCore], and going through one of those
  /// with this family's type arguments works but is not something to have to
  /// find out.
  static E? maybeOf<
          W extends AsyncControllerScopeCore<W, E, C>,
          E extends AsyncControllerScopeElementBase<W, E, C>,
          C extends ScopeController>(
    BuildContext context, {
    required bool listen,
  }) =>
      ScopeContext.maybeOf<W, E>(context, listen: listen);

  /// The element of the nearest scope [W] above [context].
  ///
  /// Throws when there is none.
  static E of<
          W extends AsyncControllerScopeCore<W, E, C>,
          E extends AsyncControllerScopeElementBase<W, E, C>,
          C extends ScopeController>(
    BuildContext context, {
    required bool listen,
  }) =>
      ScopeContext.of<W, E>(context, listen: listen);

  /// Subscribes to one value of the scope and returns it.
  static V select<
          W extends AsyncControllerScopeCore<W, E, C>,
          E extends AsyncControllerScopeElementBase<W, E, C>,
          C extends ScopeController,
          V extends Object?>(
    BuildContext context,
    V Function(E element) selector,
  ) =>
      ScopeContext.select<W, E, V>(context, selector);
}

/// {@category AsyncControllerScope}
abstract base class AsyncControllerScopeElementBase<
        W extends AsyncControllerScopeCore<W, E, C>,
        E extends AsyncControllerScopeElementBase<W, E, C>,
        C extends ScopeController> extends AsyncDataScopeElementBase<W, E, C>
    implements AsyncControllerScopeContext<W, C> {
  /// Creates the element of a scope owning a controller.
  AsyncControllerScopeElementBase(super.widget);

  @override
  C get controller => data;

  @override
  C? get controllerOrNull => dataOrNull;

  @override
  bool get hasController => hasData;

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
      // to call `disposeScope`, and it is that one on purpose: the controller
      // has to be released exactly once, so the flag that releases it here and
      // the flag that releases it there must be the same fact rather than two
      // facts that agree.
      //
      // A flag set beside the `yield` above -- what the `AsyncScope`,
      // `AsyncDataScope` and `Scope` topics teach for an initialization written
      // by hand -- would agree today, and that is not a coincidence worth
      // relying on twice over: the statement after a `yield` runs when the
      // stream asks for the next event, which is after the scope has taken the
      // one it was given, and a cancellation at the `yield` ends the body
      // without running it. The suite stands in the narrowest state where the
      // two could disagree -- registered, but with the ready branch still held
      // back by `pauseAfterInitialization` -- and they do not
      // (`scope_removed_while_initializing_test.dart`).
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
  /// show its loading branch for ever. `disposeScopeTimeout` is the limit the
  /// `AsyncControllerScope` topic names for the wait on `dispose()`, and this
  /// is a wait on `dispose()`.
  Future<void> _releaseController(C controller) async {
    try {
      final released = controller.performDispose();

      // A teardown that gave up on this initialization has since run to the
      // end, and the release is happening on a generator it abandoned. There
      // is nothing left for a limit to protect -- nobody is waiting for this,
      // the model is disposed of and the `scopeKey` is back -- and there is
      // nothing left to read a limit from either: `disposeScopeTimeout` goes
      // through `widget`, which the element cleared on its way out, so asking
      // raised a `_TypeError` where a release belonged. The wait goes on
      // unbounded, which is what an abandoned release deserves: it can hold
      // nothing up.
      if (_disposalFinished) {
        await released;

        return;
      }

      final limit =
          disposeScopeTimeout ?? ScopeConfig.defaultDisposeScopeTimeout;

      if (limit == null) {
        await released;
      } else {
        await _awaitBounded(
          released,
          limit,
          'its controller to be released',
          onDisposeScopeTimeout,
        );
      }
      // ignore: avoid_catching_errors
    } on Object catch (error, stackTrace) {
      // Reported to the observer as well as through `FlutterError`, and for
      // the same reason the ordinary teardown does it: this is a `dispose()`
      // that failed, and the fact that nobody is left to be handed the
      // failure is exactly why an observer is the one thing that can still
      // hear it. The expiry of the very same wait already arrives as
      // `onTimeout`, so without this an observer heard about a release that
      // ran too long and nothing at all about one that failed.
      notifyObserver(
        (observer) =>
            observer.onError(this, ScopePhase.disposal, error, stackTrace),
      );
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
  FutureOr<void> disposeScope() => _controller?.performDispose();
}
