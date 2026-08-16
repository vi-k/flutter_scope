import 'dart:async';

import '../../environment/scope_config.dart';

/// The logger of every call, made once for the library.
///
/// Not one per call: creating a sub-logger walks the live sub-loggers of the
/// root and relinks four levels against it, and this function runs twice for
/// every dependency of every scope — all of it wasted with the level at its
/// default of `off`. The call is told apart by [runStreamGuarded]'s
/// `debugName` in the message instead of by a name of its own in the path.
final _log = log.withAddedName('runStreamGuarded');

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
Stream<T> runStreamGuarded<T>(
  Stream<T> Function() streamFactory,
  void Function(Object, StackTrace) onPostCancelError, {
  String? debugName,
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
    _log.v(() => '${label}cancel');

    var innerCompleter = cancelCompleter;
    if (innerCompleter == null) {
      controller.close(); // ignore: unawaited_futures

      innerCompleter = Completer<void>();
      cancelCompleter = innerCompleter;

      try {
        _log.v(() => '${label}await subscription.cancel()');
        await subscription?.cancel();
        _log.v(() => '${label}await subscription.cancel() done');
        // ignore: avoid_catching_errors
      } on Object catch (error, stackTrace) {
        _log.v(() => '${label}onPostCancelError($error)');
        onPostCancelError(error, stackTrace);
      } finally {
        subscription = null;
        innerCompleter.complete();
      }
    }

    await innerCompleter.future;
    _log.v(() => '${label}cancel done');
  }

  controller
    ..onPause = pause
    ..onResume = resume
    ..onCancel = cancel
    ..onListen = () {
      subscription = stream.listen(
        controller.add,
        onError: (Object error, StackTrace stacktrace) {
          _log.v(() => '${label}controller.addError($error)');
          controller.addError(error, stacktrace);
          cancel(); // ignore: discarded_futures
        },
        onDone: () {
          _log.v(() => '${label}subscription.onDone');
          subscription = null;
          controller.close(); // ignore: discarded_futures
        },
      );
    };

  return controller.stream;
}
