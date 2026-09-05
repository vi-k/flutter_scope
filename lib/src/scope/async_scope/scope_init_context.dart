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
/// moment on.
///
/// What must not be wrapped is an acquisition. [wait] gives up on waiting
/// rather than on the work, so the value it was waiting for never reaches the
/// body — and a connection, a database or a container the body never received
/// is one nobody can release. Call those directly and let the body return what
/// it built: what a body produced for a scope that had already given up is
/// handed to the release rather than lost. [wait] is for a call that owns
/// nothing and whose result nobody needs any more; after a bare `await` that
/// must not be walked away from, [check] is what says the rest is not worth
/// doing.
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
  /// Which is what it is for: a call that owns nothing and whose result nobody
  /// needs any more — a read, a warm-up, a pause. An acquisition does not go
  /// in here. Its value comes back to a wait that is already over, so the body
  /// never receives it, and what nobody receives, nobody closes:
  ///
  /// ```dart
  /// final database = await ctx.wait(Database.open);  // lost on cancellation
  /// final database = await Database.open();          // released by the scope
  /// ```
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

/// Drives an initialization written for a [ScopeInitContext] from outside a
/// scope.
///
/// A scope makes its own context and cancels it when it gives up, so nothing
/// that lives inside a scope needs this. It is for code that owns an
/// initialization itself — a `ScopeAutoDependencies` tree driven by hand, a
/// container initialized before any widget exists, a test:
///
/// ```dart
/// final handle = ScopeInitHandle(onProgress: print);
/// final dependencies = await deps.init(context, handle.context);
/// // …and, if the caller changes its mind while that is still running:
/// handle.cancel();
/// ```
///
/// [cancel] is the counterpart of a scope leaving the tree: the body is told
/// at its next touch of the context, and whatever it registered through
/// [ScopeInitContext.onCancel] runs at once. It does not wait for the body —
/// the caller has the future for that.
final class ScopeInitHandle {
  final _ScopeInitContext _context;

  /// Creates a handle over a fresh context.
  ///
  /// [onProgress] is given whatever the initialization reports.
  ScopeInitHandle({void Function(Object progress)? onProgress})
      : _context = _ScopeInitContext() {
    _context._onProgress = onProgress;
  }

  /// A handle over a context that [parent] takes with it when it is
  /// cancelled, and that can be cancelled on its own without touching
  /// [parent].
  ///
  /// This is what a group of concurrent branches gives its arms: the first arm
  /// to fail gives up on its siblings without giving up on the initialization
  /// they all belong to.
  ///
  /// A child made under a context that is already cancelled is cancelled from
  /// the start — there is nothing for it to run. Cancelling a child takes it
  /// off [parent], so a group that ends does not leave its arm behind on a
  /// context that outlives it.
  factory ScopeInitHandle.childOf(
    ScopeInitContext parent, {
    void Function(Object progress)? onProgress,
  }) {
    final child = ScopeInitHandle(onProgress: onProgress);
    if (parent.isCancelled) {
      child.cancel();

      return child;
    }

    child._detachFromParent = parent.onCancel(child.cancel);

    return child;
  }

  /// Takes this handle off its parent; `null` for a handle with no parent.
  void Function()? _detachFromParent;

  /// The context to hand to the initialization.
  ScopeInitContext get context => _context;

  /// Whether [cancel] has been called.
  bool get isCancelled => _context.isCancelled;

  /// Gives up on the initialization.
  ///
  /// Every member of [context] throws [ScopeInitCancelled] from here on, and
  /// the callbacks registered through [ScopeInitContext.onCancel] run now.
  /// Calling it twice does nothing the second time.
  void cancel() {
    final detach = _detachFromParent;
    _detachFromParent = null;
    detach?.call();

    _context._cancel();
  }
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
    //
    // `unawaited`, and that is the point rather than a formality: this future
    // is deliberately not the one the caller gets back — [completer] is —
    // and an analyzer newer than the floor says so out loud
    // (`discarded_futures`).
    unawaited(
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
      ),
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
