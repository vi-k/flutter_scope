## Task 1: Ядро — очереди по ключам

**Files:**
- Create: `lib/src/scope/e_async_scope/scope_coordination.dart`
- Test: `test/scope_coordination_test.dart`

**Interfaces:**
- Produces: `KeyedAccessQueues` (`enter`, `length`, `containsKey`), `AccessEntry` (`isCompleted`, `isWaiting`, `isCancelled`, `exit`, `cancel`). Задача 3 подставляет их вместо `_AsyncScopeCoordinatorQueue` и `AsyncScopeCoordinatorEntry`.

- [ ] **Step 1: Написать падающий тест**

Создать `test/scope_coordination_test.dart`:

```dart
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:scopo/src/scope/e_async_scope/scope_coordination.dart';
import 'package:test/test.dart';

/// Lets pending microtasks and zero-duration timers run.
Future<void> pumpEvents() => Future<void>.delayed(Duration.zero);

void main() {
  group('KeyedAccessQueues', () {
    test('the first entry gets in immediately', () async {
      final queues = KeyedAccessQueues();
      final first = AccessEntry('first');

      await queues.enter('key', first).timeout(const Duration(seconds: 1));

      expect(first.isWaiting, isFalse);
      expect(queues.containsKey('key'), isTrue);
    });

    test('the second entry waits for the first to exit', () async {
      final queues = KeyedAccessQueues();
      final first = AccessEntry('first');
      final second = AccessEntry('second');

      await queues.enter('key', first);

      var secondIsIn = false;
      unawaited(queues.enter('key', second).then((_) => secondIsIn = true));
      await pumpEvents();

      expect(secondIsIn, isFalse, reason: 'the key is still held');
      expect(second.isWaiting, isTrue);

      first.exit();
      await pumpEvents();

      expect(secondIsIn, isTrue);
      expect(second.isWaiting, isFalse);
    });

    test('the queue is removed once the last entry exits', () async {
      final queues = KeyedAccessQueues();
      final entry = AccessEntry('only');

      await queues.enter('key', entry);
      expect(queues.length, 1);

      entry.exit();

      expect(queues.length, 0);
      expect(queues.containsKey('key'), isFalse);
    });
  });
}
```

- [ ] **Step 2: Убедиться, что тест падает**

Run: `flutter test test/scope_coordination_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:scopo/src/scope/e_async_scope/scope_coordination.dart'`.

- [ ] **Step 3: Написать ядро очередей**

Создать `lib/src/scope/e_async_scope/scope_coordination.dart`. Логика переносится из нынешнего `_AsyncScopeCoordinatorQueue` (`async_scope_coordinator.dart:109-208`) без изменения семантики:

```dart
import 'dart:async';

/// A FIFO mutex keyed by an arbitrary object.
///
/// An [AccessEntry] entering a free key is let in at once; entering a held key
/// waits until every entry that came before it has left. The queue of a key is
/// discarded as soon as its last entry leaves, so a key costs nothing while
/// nobody holds it.
class KeyedAccessQueues {
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
class AccessEntry {
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

class _AccessQueue {
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
          '${entry._debugName} couldn\'t wait to get access to [$key]:'
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
    assert(identical(entry._queue, this), 'Entry is not attached to this queue');
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
```

- [ ] **Step 4: Убедиться, что тесты проходят**

Run: `flutter test test/scope_coordination_test.dart`
Expected: PASS (3 теста).

- [ ] **Step 5: Дописать остальные тесты очередей**

Добавить в группу `KeyedAccessQueues`:

```dart
    test('entries are let in in the order they arrived', () async {
      final queues = KeyedAccessQueues();
      final order = <String>[];
      final first = AccessEntry('first');
      final second = AccessEntry('second');
      final third = AccessEntry('third');

      await queues.enter('key', first);
      unawaited(queues.enter('key', second).then((_) => order.add('second')));
      unawaited(queues.enter('key', third).then((_) => order.add('third')));
      await pumpEvents();

      expect(order, isEmpty);

      first.exit();
      await pumpEvents();
      expect(order, ['second'], reason: 'third still waits for second');

      second.exit();
      await pumpEvents();
      expect(order, ['second', 'third']);

      third.exit();
    });

    test('cancelling stops the wait but keeps the place in the queue',
        () async {
      final queues = KeyedAccessQueues();
      final first = AccessEntry('first');
      final second = AccessEntry('second');

      await queues.enter('key', first);
      final secondEntered = queues.enter('key', second);
      await pumpEvents();

      second.cancel();
      await secondEntered.timeout(const Duration(seconds: 1));

      expect(second.isCancelled, isTrue);
      expect(second.isWaiting, isFalse);
      expect(second.isCompleted, isFalse, reason: 'exit() is still required');
      expect(queues.length, 1);

      first.exit();
      second.exit();
      expect(queues.length, 0);
    });

    test('a timeout reports and lets the entry in anyway', () {
      fakeAsync((async) {
        final queues = KeyedAccessQueues();
        final first = AccessEntry('first');
        final second = AccessEntry('second');
        TimeoutException? reported;

        unawaited(queues.enter('key', first));
        var secondIsIn = false;
        unawaited(
          queues
              .enter(
                'key',
                second,
                timeout: const Duration(seconds: 3),
                onTimeout: (error, _) => reported = error,
              )
              .then((_) => secondIsIn = true),
        );

        async.elapse(const Duration(seconds: 2));
        expect(secondIsIn, isFalse);

        async.elapse(const Duration(seconds: 2));
        expect(secondIsIn, isTrue);
        expect(reported, isNotNull);
        expect(reported!.message, contains('second'));
        expect(reported!.message, contains('key'));
      });
    });

    test('a key can be taken again after it was released', () async {
      final queues = KeyedAccessQueues();
      final first = AccessEntry('first');

      await queues.enter('key', first);
      first.exit();
      expect(queues.containsKey('key'), isFalse);

      final second = AccessEntry('second');
      await queues.enter('key', second).timeout(const Duration(seconds: 1));

      expect(queues.containsKey('key'), isTrue);
      expect(second.isWaiting, isFalse);
    });

    test('different keys do not block each other', () async {
      final queues = KeyedAccessQueues();
      final a = AccessEntry('a');
      final b = AccessEntry('b');

      await queues.enter('a', a);
      await queues.enter('b', b).timeout(const Duration(seconds: 1));

      expect(queues.length, 2);
    });
```

- [ ] **Step 6: Прогнать и убедиться в чистоте**

Run: `flutter test test/scope_coordination_test.dart` → PASS (8 тестов).
Run: `grep -c "package:flutter" lib/src/scope/e_async_scope/scope_coordination.dart` → `0`.
Run: `flutter analyze` → `No issues found!`

- [ ] **Step 7: Коммит**

```bash
git add lib/src/scope/e_async_scope/scope_coordination.dart test/scope_coordination_test.dart
git commit -m "feat: add a Flutter-free keyed access queue for scope coordination"
```

---

