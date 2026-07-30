part of '../scope.dart';

/// {@category AsyncScope}
final class AsyncScopeCoordinator extends ScopeWidgetCore<AsyncScopeCoordinator,
    _AsyncScopeCoordinatorElement> {
  const AsyncScopeCoordinator({
    super.key,
    super.tag,
    required super.child,
  });

  @override
  // ignore: library_private_types_in_public_api
  _AsyncScopeCoordinatorElement createScopeElement() =>
      _AsyncScopeCoordinatorElement(this);

  static Future<void> enter(
    BuildContext context,
    Object key,
    AsyncScopeCoordinatorEntry entry, {
    Duration? timeout,
    void Function()? onTimeout,
  }) =>
      ScopeWidgetCore.maybeOf<AsyncScopeCoordinator,
          _AsyncScopeCoordinatorElement>(
        context,
        listen: false,
      )?.enter(key, entry, timeout: timeout, onTimeout: onTimeout) ??
      (throw FlutterError(
        'No `$AsyncScopeCoordinator`.\n'
        'You are trying to use `scopeKey`, but the `$AsyncScopeCoordinator`'
        ' is missing in the context. Add it to the widget tree so that'
        ' all your scopes that need coordination by `scopeKey` can access'
        ' it. The most universal solution is to place it above'
        ' `$MaterialApp`.',
      ));
}

final class _AsyncScopeCoordinatorElement extends ScopeWidgetElementBase<
    AsyncScopeCoordinator, _AsyncScopeCoordinatorElement> {
  _AsyncScopeCoordinatorElement(super.widget);

  static final _queues = <Object, _AsyncScopeCoordinatorQueue>{};

  @override
  Widget buildChild() => widget.child;

  Future<void> enter(
    Object key,
    AsyncScopeCoordinatorEntry entry, {
    Duration? timeout,
    void Function()? onTimeout,
  }) {
    final queue = _queues.putIfAbsent(key, () {
      final q = _AsyncScopeCoordinatorQueue(
        key,
        remove: () {
          _queues.remove(key);
          _log.d(() => 'queue for [$key] removed');
        },
      );
      _log.d(() => 'queue for [$key] created');
      return q;
    });

    return queue.enter(entry, timeout: timeout, onTimeout: onTimeout);
  }
}

final class AsyncScopeCoordinatorEntry {
  final String _debugName;
  _AsyncScopeCoordinatorQueue? _queue;
  final _completer = Completer<void>();
  final _cancelCompleter = Completer<void>();
  bool _isWaiting = false;

  AsyncScopeCoordinatorEntry(this._debugName);

  bool get isCompleted => _completer.isCompleted;

  bool get isWaiting => _isWaiting;

  bool get isCancelled => _cancelCompleter.isCompleted;

  /// Leaves the queue.
  void exit() {
    _checkQueue()._exit(this);
  }

  /// Cancels waiting for access.
  void cancel() {
    assert(isWaiting, 'Entry is not waiting');
    if (!_cancelCompleter.isCompleted) {
      _cancelCompleter.complete();
    }
  }

  _AsyncScopeCoordinatorQueue _checkQueue() =>
      _queue ??
      (throw StateError('$AsyncScopeCoordinatorEntry is not attached'));

  @override
  String toString() => '$_debugName'
      ' ${isCompleted ? 'completed' : //
          isWaiting ? 'waiting' : //
              isCancelled ? 'cancelled' : 'not completed'}';
}

final class _AsyncScopeCoordinatorQueue {
  final Object key;
  void Function()? remove;

  final _entries = <AsyncScopeCoordinatorEntry>{};

  _AsyncScopeCoordinatorQueue(this.key, {this.remove});

  bool get isEmpty => _entries.isEmpty;

  bool get isNotEmpty => _entries.isNotEmpty;

  int get length => _entries.length;

  void close() {
    final errors = <AsyncError>[];
    for (final entry in List.of(_entries)) {
      try {
        _exit(entry);
      } on Object catch (error, stackTrace) {
        errors.add(AsyncError(error, stackTrace));
      }
    }

    if (errors.isNotEmpty) {
      throw ParallelWaitError(<void>[], errors);
    }
  }

  Future<void> enter(
    AsyncScopeCoordinatorEntry entry, {
    Duration? timeout,
    void Function()? onTimeout,
  }) async {
    assert(entry._queue == null, 'Entry is already attached');
    assert(!entry._completer.isCompleted, 'Entry is already completed');

    final previous = List.of(_entries);

    entry._queue = this;
    _entries.add(entry);

    if (previous.isEmpty) {
      return;
    }

    // Wait until every previous owner releases the controller,
    // OR until this entry is cancelled.
    entry._isWaiting = true;
    var future = Future.any([
      previous.map((entry) => entry._completer.future).wait,
      entry._completer.future,
      entry._cancelCompleter.future,
    ]);
    if (timeout != null) {
      future = future.timeout(timeout);
    }

    // On timeout, report the error and let the owner in anyway.
    try {
      await future;
    } on TimeoutException catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: TimeoutException(
            '${entry._debugName}'
            " couldn't wait to get access to [$key]:"
            ' $previous',
            timeout,
          ),
          stack: stackTrace,
          library: 'scopo',
        ),
      );
      onTimeout?.call();
    } finally {
      entry._isWaiting = false;
    }
  }

  void _exit(AsyncScopeCoordinatorEntry entry) {
    assert(
      identical(entry._queue, this),
      'Entry is not attached to this queue',
    );
    assert(!entry._completer.isCompleted, 'Entry is already completed');

    _entries.remove(entry);
    entry._completer.complete();
    entry._queue = null;

    if (_entries.isEmpty) {
      remove?.call();
      remove = null;
    }
  }

  @override
  String toString() => '$AsyncScopeCoordinator:queue[$key]';
}
