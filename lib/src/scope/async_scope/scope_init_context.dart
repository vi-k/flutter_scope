part of '../scope.dart';

/// Thrown into an initialization body that the scope has given up on.
///
/// Every member of [ScopeInitContext] except [ScopeInitContext.isCancelled]
/// throws it once the scope has stopped waiting. A body is free to let it
/// out — that is how it unwinds — and the scope treats it as the ordinary end
/// of a cancelled initialization rather than as a failure.
final class ScopeInitCancelled implements Exception {
  /// Says that the initialization this was thrown into is no longer wanted.
  const ScopeInitCancelled();

  @override
  String toString() => 'ScopeInitCancelled';
}

/// What an initialization body sees when it is written as a plain `Future`.
///
/// The body reports its progress through [progress] and returns its value,
/// instead of yielding both out of a generator. Unlike a `yield`, a call on
/// the context can be made from a function the body calls, however deep.
///
/// Cancellation is cooperative: Dart cannot interrupt somebody else's `await`.
/// A body learns that the scope gave up the next time it touches this context —
/// every member here except [isCancelled] throws [ScopeInitCancelled] from that
/// moment on. After a bare `await`, call [check]; to wait for something and
/// give up on cancellation at once, wrap it in [wait].
abstract interface class ScopeInitContext {
  /// Reports that the initialization has advanced.
  ///
  /// What it carries is what `buildOnProgress` is given.
  void progress(Object progress);

  /// Whether the scope has given up on this initialization.
  ///
  /// The one member that answers instead of throwing, so that a body can ask
  /// on its way out.
  bool get isCancelled;

  /// Throws [ScopeInitCancelled] if the scope has given up.
  ///
  /// Call after a bare `await`, where nothing else asks.
  void check();

  /// Runs [action] and waits for it, but no longer than the scope wants it.
  ///
  /// Throws [ScopeInitCancelled] up front if the scope has already given up.
  /// If the cancellation arrives while [action] is in flight, the wait ends
  /// there with that exception — and [action] runs on, its result discarded.
  /// It ends the waiting, not the work.
  ///
  /// For anything that must actually stop, hand the cancellation to it through
  /// [onCancel] and wait for it to finish.
  Future<T> wait<T>(FutureOr<T> Function() action);

  /// Registers [callback] to run the moment the scope gives up, and returns a
  /// function that unregisters it.
  ///
  /// This is how a cancellation reaches something that can really stop: an
  /// HTTP client's abort, a subscription, a cancel token of somebody else's.
  void Function() onCancel(void Function() callback);
}

final class _ScopeInitContext implements ScopeInitContext {
  /// Where [progress] goes; set when the stream is listened to.
  void Function(Object progress)? _onProgress;

  final _onCancelCallbacks = <void Function()>[];

  bool _cancelled = false;

  @override
  bool get isCancelled => _cancelled;

  @override
  void check() {
    if (_cancelled) {
      throw const ScopeInitCancelled();
    }
  }

  @override
  void progress(Object progress) {
    check();
    _onProgress?.call(progress);
  }

  @override
  Future<T> wait<T>(FutureOr<T> Function() action) {
    check();

    final completer = Completer<T>();
    final unregister = onCancel(() {
      if (!completer.isCompleted) {
        completer.completeError(const ScopeInitCancelled(), StackTrace.current);
      }
    });

    // The result is routed by hand rather than with `completer.complete(…)` as
    // a callback: by the time [action] comes back the completer may already
    // carry the cancellation, and completing it twice is a `Bad state` on top
    // of whatever the body is already dealing with. An error arriving late is
    // dropped for the same reason, and it is dropped *handled* — this
    // `onError` is what keeps it from becoming an unhandled asynchronous
    // error once nobody is waiting for it any more.
    Future<T>.sync(action).then(
      (value) {
        if (!completer.isCompleted) {
          completer.complete(value);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
    );

    return completer.future.whenComplete(unregister);
  }

  @override
  void Function() onCancel(void Function() callback) {
    check();
    _onCancelCallbacks.add(callback);

    return () => _onCancelCallbacks.remove(callback);
  }

  /// Marks the initialization cancelled and tells everything that registered.
  ///
  /// Runs at most once: the scope cancels its subscription once, and a second
  /// pass would call callbacks that the first one has already taken off.
  void _cancel() {
    if (_cancelled) {
      return;
    }
    _cancelled = true;

    // Over a copy, and the list is emptied first: a callback may unregister
    // itself — [wait]'s does — and every one of them is called exactly once
    // whatever it does to the list underneath.
    final callbacks = List.of(_onCancelCallbacks);
    _onCancelCallbacks.clear();

    for (final callback in callbacks) {
      try {
        callback();
        // ignore: avoid_catching_errors
      } on Object catch (error, stackTrace) {
        // Reported, never re-thrown: this runs inside the scope's teardown,
        // and a callback that throws would abandon the cancellation halfway,
        // leaving the rest of them uncalled.
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'scopo',
            context: ErrorDescription('while cancelling an initialization'),
          ),
        );
      }
    }
  }
}

/// Turns an initialization written as a `Future` into the stream the scope
/// engine consumes.
///
/// [progressState] and [readyState] build the two events of the family this
/// runs for; [releaseLateValue] is given a value that arrived after the scope
/// had already given up — the body could not be stopped, and what it produced
/// still has to be let go of.
Stream<S> _runScopeInit<S extends Object, T>({
  required Future<T> Function(ScopeInitContext ctx) body,
  required S Function(Object progress) progressState,
  required S Function(T value) readyState,
  required FutureOr<void> Function(T value) releaseLateValue,
}) {
  final ctx = _ScopeInitContext();
  late final StreamController<S> controller;

  /// The body, while it runs. What a cancellation waits for.
  Future<void>? running;

  void report(Object error, StackTrace stackTrace, String what) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'scopo',
        context: ErrorDescription(what),
      ),
    );
  }

  Future<void> run() async {
    try {
      final value = await body(ctx);

      // The half a generator cannot do at all. A body that never asks the
      // context anything cannot be stopped, so its value can arrive for a
      // scope that is already gone -- and inside a generator that value is
      // simply lost, held by a body nobody will resume. Here it is still in
      // hand, and the only thing left to do with it is to release it.
      if (ctx.isCancelled) {
        try {
          await releaseLateValue(value);
          // ignore: avoid_catching_errors
        } on Object catch (error, stackTrace) {
          report(
              error,
              stackTrace,
              'while releasing a value that the '
              'initialization produced after it had been cancelled');
        }

        return;
      }

      controller.add(readyState(value));
      // Closed and not waited for, and this is load-bearing. `close()` comes
      // back only once `done` has been delivered, and delivering `done` takes
      // the listener off -- which calls `onCancel` below, which waits for this
      // very body. Awaiting the close here is therefore a deadlock with
      // itself: the body waits for the close, the close waits for the
      // cancellation, and the cancellation waits for the body. Nothing else
      // announces it, either: the scope goes on showing its loading branch,
      // and the teardown gives up on the initialization only when
      // `initCancellationTimeout` expires.
      unawaited(controller.close());
    } on ScopeInitCancelled {
      // How a cancelled body unwinds, and the expected way out: the scope
      // asked for the cancellation and is waiting for exactly this.
      // ignore: avoid_catching_errors
    } on Object catch (error, stackTrace) {
      // A failure that arrives after the cancellation has nowhere to go: the
      // subscription is gone, and `addError` on a controller nobody listens to
      // is dropped in silence. Reported instead, the way the engine reports
      // the failures it cannot hand to a caller.
      if (ctx.isCancelled) {
        report(error, stackTrace, 'in an initialization that was cancelled');

        return;
      }

      controller.addError(error, stackTrace);
      // Not waited for, for the reason the successful close above is not.
      unawaited(controller.close());
    }
  }

  controller = StreamController<S>(
    onListen: () {
      // Set here rather than at construction: the body starts on subscription,
      // so there is nothing to report before this point.
      ctx._onProgress = (progress) {
        // A progress call can outlive the body -- a helper it left running
        // still holds the context -- and `add` after `close` throws. The
        // stream is over by then and there is nothing to report to.
        if (!controller.isClosed) {
          controller.add(progressState(progress));
        }
      };
      // Not discarded: it is kept in `running`, which is what the
      // cancellation below waits for. The lint reads the call and not where
      // its future goes.
      // ignore: discarded_futures
      running = run();
    },
    // Synchronous, and that is what makes this work: the body is told the
    // moment `cancel()` is called, rather than when it next reaches a `yield`.
    // The future returned here is what `cancel()` waits for, so the scope's
    // `initCancellationTimeout` bounds the body itself.
    onCancel: () {
      ctx._cancel();

      return running;
    },
  );

  return controller.stream;
}
