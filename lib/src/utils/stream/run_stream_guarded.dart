import 'dart:async';

import '../../environment/scope_config.dart';

/// Runs a stream in a guarded environment until its first error.
///
/// - If [streamFactory] throws, the exception is passed to the resulting
///   stream: the function returns a [Stream.error].
/// - An error coming from the stream ends the processing: the subscription is
///   cancelled and the resulting stream is closed.
/// - Every error received after that - after an error, or after the
///   subscription to the resulting stream is cancelled - is passed to
///   [onPostCancelError].
///
/// [onPostCancelError] is not called when the stream closes without an error,
/// and is called when the stream closes with one or is cancelled.
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

  final l = log.withAddedName(
    () => 'runStreamGuarded${debugName == null ? '' : '($debugName)'}',
  );

  void pause() {
    subscription?.pause();
  }

  void resume() {
    subscription?.resume();
  }

  /// Cancels every subscription, waits for them to finish and forwards the
  /// errors that occur.
  Future<void> cancel() async {
    l.v('cancel');

    var innerCompleter = cancelCompleter;
    if (innerCompleter == null) {
      controller.close(); // ignore: unawaited_futures

      innerCompleter = Completer<void>();
      cancelCompleter = innerCompleter;

      try {
        l.v('await subscription.cancel()');
        await subscription?.cancel();
        l.v('await subscription.cancel() done');
        // ignore: avoid_catching_errors
      } on Object catch (error, stackTrace) {
        l.v(() => 'onPostCancelError($error)');
        onPostCancelError(error, stackTrace);
      } finally {
        subscription = null;
        innerCompleter.complete();
      }
    }

    await innerCompleter.future;
    l.v('cancel done');
  }

  controller
    ..onPause = pause
    ..onResume = resume
    ..onCancel = cancel
    ..onListen = () {
      subscription = stream.listen(
        controller.add,
        onError: (Object error, StackTrace stacktrace) {
          l.v(() => 'controller.addError($error)');
          controller.addError(error, stacktrace);
          cancel(); // ignore: discarded_futures
        },
        onDone: () {
          l.v('subscription.onDone');
          subscription = null;
          controller.close(); // ignore: discarded_futures
        },
      );
    };

  return controller.stream;
}
