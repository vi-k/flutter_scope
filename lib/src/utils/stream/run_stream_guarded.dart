import 'dart:async';

import '../../environment/scope_config.dart';

/// Runs a stream in a guarded environment until its first error.
///
/// - If [streamFactory] throws, the exception is passed to the resulting
///   stream: the function returns a [Stream.error].
/// - An error coming from the stream ends the processing: the subscription is
///   cancelled and the resulting stream is closed.
/// - [onPostCancelError] receives what the cancellation of the source itself
///   raises, and nothing else. It is the one failure with nowhere to go: the
///   resulting stream is already closed by then, so an error from
///   `subscription.cancel()` would otherwise be lost.
///
/// The cancellation runs when the stream ends with an error and when the
/// subscription to the resulting stream is cancelled, so [onPostCancelError]
/// may be called on either path — but never when the source simply closes.
///
/// [observable] tells [ScopeObserver.onTrace] who this run belongs to. This
/// function has no [ScopeObservable] of its own — it is a function, not an
/// object — so its two callers each pass their own; left `null`, the run
/// traces nothing.
Stream<T> runStreamGuarded<T>(
  Stream<T> Function() streamFactory,
  void Function(Object, StackTrace) onPostCancelError, {
  String? debugName,
  ScopeObservable? observable,
}) {
  final Stream<T> stream;

  try {
    stream = streamFactory();
  } on Object catch (error, stackTrace) {
    return Stream.error(error, stackTrace);
  }

  final controller = StreamController<T>();
  StreamSubscription<T>? subscription;
  Completer<void>? cancelCompleter;

  final label = debugName == null ? '' : '($debugName) ';

  void pause() {
    subscription?.pause();
  }

  void resume() {
    subscription?.resume();
  }

  /// Cancels every subscription, waits for them to finish and forwards the
  /// errors that occur.
  Future<void> cancel() async {
    if (observable case final observable?) {
      notifyObserver(
        (observer) => observer.onTrace(observable, '${label}cancel'),
      );
    }

    var innerCompleter = cancelCompleter;
    if (innerCompleter == null) {
      controller.close(); // ignore: unawaited_futures

      innerCompleter = Completer<void>();
      cancelCompleter = innerCompleter;

      try {
        if (observable case final observable?) {
          notifyObserver(
            (observer) => observer.onTrace(
              observable,
              '${label}await subscription.cancel()',
            ),
          );
        }
        await subscription?.cancel();
        if (observable case final observable?) {
          notifyObserver(
            (observer) => observer.onTrace(
              observable,
              '${label}await subscription.cancel() done',
            ),
          );
        }
        // ignore: avoid_catching_errors
      } on Object catch (error, stackTrace) {
        if (observable case final observable?) {
          notifyObserver(
            (observer) => observer.onTrace(
              observable,
              '${label}onPostCancelError($error)',
            ),
          );
        }
        onPostCancelError(error, stackTrace);
      } finally {
        subscription = null;
        innerCompleter.complete();
      }
    }

    await innerCompleter.future;
    if (observable case final observable?) {
      notifyObserver(
        (observer) => observer.onTrace(observable, '${label}cancel done'),
      );
    }
  }

  controller
    ..onPause = pause
    ..onResume = resume
    ..onCancel = cancel
    ..onListen = () {
      subscription = stream.listen(
        controller.add,
        onError: (Object error, StackTrace stacktrace) {
          if (observable case final observable?) {
            notifyObserver(
              (observer) => observer.onTrace(
                observable,
                '${label}controller.addError($error)',
              ),
            );
          }
          controller.addError(error, stacktrace);

          if (subscription == null) {
            // Reported from inside `listen()` itself, before the subscription
            // this cancels has been handed back -- so cancelling right here
            // finds nothing to cancel and leaves the source running. One
            // microtask later it is assigned. Only this branch waits: on every
            // ordinary path the cancel stays where it was, synchronous and
            // immediately after the error.
            // ignore: discarded_futures
            scheduleMicrotask(cancel);
          } else {
            cancel(); // ignore: discarded_futures
          }
        },
        onDone: () {
          if (observable case final observable?) {
            notifyObserver(
              (observer) => observer.onTrace(
                observable,
                '${label}subscription.onDone',
              ),
            );
          }
          subscription = null;
          controller.close(); // ignore: discarded_futures
        },
      );
    };

  return controller.stream;
}
