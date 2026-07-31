import 'dart:async';

/// A FIFO mutex keyed by an arbitrary object.
///
/// An [AccessEntry] entering a free key is let in at once; entering a held key
/// waits until every entry that came before it has left. The queue of a key is
/// discarded as soon as its last entry leaves, so a key costs nothing while
/// nobody holds it.
final class KeyedAccessQueues {
  final _queues = <Object, _AccessQueue>{};

  /// The number of keys currently held.
  int get length => _queues.length;

  bool containsKey(Object key) => _queues.containsKey(key);

  /// Takes [entry] into the queue of [key] and completes once it has access.
  ///
  /// Completes at once when the key is free. When [timeout] elapses before
  /// access is granted, [onTimeout] is called and the entry is let in anyway:
  /// holding the caller back forever would freeze the widget tree, and a
  /// missing release is a bug in the holder, not in its successor.
  Future<void> enter(
    Object key,
    AccessEntry entry, {
    Duration? timeout,
    void Function(TimeoutException error, StackTrace stackTrace)? onTimeout,
  }) {
    final queue = _queues.putIfAbsent(
      key,
      () => _AccessQueue(key, onEmpty: () => _queues.remove(key)),
    );

    return queue.enter(entry, timeout: timeout, onTimeout: onTimeout);
  }
}

/// A place in the queue of one key.
final class AccessEntry {
  final String _debugName;
  _AccessQueue? _queue;
  final _completer = Completer<void>();
  final _cancelCompleter = Completer<void>();
  bool _isWaiting = false;

  AccessEntry(this._debugName);

  bool get isCompleted => _completer.isCompleted;

  bool get isWaiting => _isWaiting;

  bool get isCancelled => _cancelCompleter.isCompleted;

  /// Releases the key.
  void exit() {
    final queue = _queue;
    if (queue == null) {
      throw StateError('$AccessEntry is not attached');
    }
    queue._exit(this);
  }

  /// Gives up waiting for access.
  ///
  /// The entry stays in the queue until [exit], so a cancelled entry still has
  /// to be released.
  void cancel() {
    assert(isWaiting, 'Entry is not waiting');
    if (!_cancelCompleter.isCompleted) {
      _cancelCompleter.complete();
    }
  }

  @override
  String toString() => '$_debugName'
      ' ${isCompleted ? 'completed' : //
          isWaiting ? 'waiting' : //
              isCancelled ? 'cancelled' : 'not completed'}';
}

final class _AccessQueue {
  final Object key;
  void Function()? onEmpty;

  final _entries = <AccessEntry>{};

  _AccessQueue(this.key, {this.onEmpty});

  Future<void> enter(
    AccessEntry entry, {
    Duration? timeout,
    void Function(TimeoutException error, StackTrace stackTrace)? onTimeout,
  }) async {
    assert(entry._queue == null, 'Entry is already attached');
    assert(!entry._completer.isCompleted, 'Entry is already completed');

    final previous = List.of(_entries);

    entry._queue = this;
    _entries.add(entry);

    if (previous.isEmpty) {
      return;
    }

    entry._isWaiting = true;
    var future = Future.any([
      previous.map((entry) => entry._completer.future).wait,
      entry._completer.future,
      entry._cancelCompleter.future,
    ]);
    if (timeout != null) {
      future = future.timeout(timeout);
    }

    try {
      await future;
    } on TimeoutException catch (_, stackTrace) {
      onTimeout?.call(
        TimeoutException(
          "${entry._debugName} couldn't wait to get access to [$key]:"
          ' $previous',
          timeout,
        ),
        stackTrace,
      );
    } finally {
      entry._isWaiting = false;
    }
  }

  void _exit(AccessEntry entry) {
    assert(
      identical(entry._queue, this),
      'Entry is not attached to this queue',
    );
    assert(!entry._completer.isCompleted, 'Entry is already completed');

    _entries.remove(entry);
    entry._completer.complete();
    entry._queue = null;

    if (_entries.isEmpty) {
      onEmpty?.call();
      onEmpty = null;
    }
  }

  @override
  String toString() => 'queue[$key]';
}

/// The children one parent waits for before disposing of itself.
final class ChildRegistry {
  final _children = <ChildEntry>[];

  bool get hasChildren => _children.isNotEmpty;

  int get childrenCount => _children.length;

  ChildEntry registerChild(String debugName) {
    final entry = ChildEntry._(debugName, this);
    _children.add(entry);

    return entry;
  }

  /// Completes once the children registered at the time of the call have
  /// unregistered.
  ///
  /// The children are snapshotted when the wait starts, so one that registers
  /// while the wait is already running is not awaited by it.
  ///
  /// Completes at once when there are no children. When [timeout] elapses,
  /// [onTimeout] is called, the awaited children that never finished are
  /// dropped and the future completes normally: a child that never finishes
  /// must not keep its parent from being disposed of. A child that registered
  /// after the wait started is kept — this wait never awaited it, so it is not
  /// this wait's to give up on.
  Future<void> waitForChildren({
    Duration? timeout,
    void Function(TimeoutException error, StackTrace stackTrace)? onTimeout,
  }) async {
    if (_children.isEmpty) {
      return;
    }

    // The snapshot this wait is responsible for. The live list may grow while
    // the wait is running, and those late arrivals belong to a later wait, not
    // to this one -- neither to await, nor to give up on.
    final awaited = List.of(_children);

    var future = awaited.map((e) => e._completer.future).wait;
    if (timeout != null) {
      future = future.timeout(timeout);
    }

    try {
      await future;
    } on TimeoutException catch (_, stackTrace) {
      final unfinished =
          awaited.where((e) => !e._completer.isCompleted).toList();

      try {
        onTimeout?.call(
          TimeoutException(
            "couldn't wait for the children to complete: $unfinished",
            timeout,
          ),
          stackTrace,
        );
      } finally {
        // Dropping the children this wait gave up on keeps a second wait from
        // hanging on entries nobody will complete. It happens even when the
        // report above throws, so a failing reporter cannot leave the registry
        // wedged. The children registered after this wait started stay.
        _children.removeWhere(unfinished.contains);
      }
    }
  }
}

/// A child registered in a [ChildRegistry].
final class ChildEntry {
  final String _debugName;
  ChildRegistry? _registry;
  final _completer = Completer<void>();

  ChildEntry._(this._debugName, this._registry);

  void unregister() {
    assert(_registry != null, 'Entry is already unregistered');
    assert(!_completer.isCompleted, 'Entry is already completed');

    _completer.complete();
    _registry?._children.remove(this);
    _registry = null;
  }

  @override
  String toString() => '$_debugName'
      ' ${_completer.isCompleted ? 'completed' : 'not completed'}';
}
