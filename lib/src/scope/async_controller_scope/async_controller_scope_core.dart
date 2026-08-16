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
        await controller.performDispose();
      }
    }
  }

  @override
  void onUnmount() {
    super.onUnmount();
    _controller?.performUnmount();
  }

  @override
  FutureOr<void> disposeAsync() => _controller?.performDispose();
}
