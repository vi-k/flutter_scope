## Task 2: Ядро — реестр детей

**Files:**
- Modify: `lib/src/scope/e_async_scope/scope_coordination.dart`
- Test: `test/scope_coordination_test.dart`

**Interfaces:**
- Consumes: файл ядра из Задачи 1.
- Produces: `ChildRegistry` (`hasChildren`, `childrenCount`, `registerChild`, `waitForChildren({timeout, onTimeout})`), `ChildEntry` (`unregister`). Задача 3 подставляет их в `AsyncScopeParent`.

- [ ] **Step 1: Написать падающие тесты**

Добавить в `test/scope_coordination_test.dart` новую группу:

```dart
  group('ChildRegistry', () {
    test('waiting with no children completes at once', () async {
      final registry = ChildRegistry();

      await registry.waitForChildren().timeout(const Duration(seconds: 1));

      expect(registry.hasChildren, isFalse);
    });

    test('waiting completes when every child has unregistered', () async {
      final registry = ChildRegistry();
      final first = registry.registerChild('first');
      final second = registry.registerChild('second');

      expect(registry.childrenCount, 2);

      var done = false;
      unawaited(registry.waitForChildren().then((_) => done = true));
      await pumpEvents();
      expect(done, isFalse);

      first.unregister();
      await pumpEvents();
      expect(done, isFalse, reason: 'the second child is still registered');

      second.unregister();
      await pumpEvents();
      expect(done, isTrue);
      expect(registry.hasChildren, isFalse);
    });

    test('a timeout reports and gives up on the children left', () {
      fakeAsync((async) {
        final registry = ChildRegistry();
        registry.registerChild('slow');
        TimeoutException? reported;

        var done = false;
        unawaited(
          registry
              .waitForChildren(
                timeout: const Duration(seconds: 3),
                onTimeout: (error, _) => reported = error,
              )
              .then((_) => done = true),
        );

        async.elapse(const Duration(seconds: 4));

        expect(done, isTrue, reason: 'the wait must not hang');
        expect(reported, isNotNull);
        expect(reported!.message, contains('slow'));
        expect(
          registry.hasChildren,
          isFalse,
          reason: 'the children left behind are dropped',
        );
      });
    });
  });
```

- [ ] **Step 2: Убедиться, что тесты падают**

Run: `flutter test test/scope_coordination_test.dart --name ChildRegistry`
Expected: FAIL — `Undefined name 'ChildRegistry'`.

- [ ] **Step 3: Написать реестр**

Дописать в `lib/src/scope/e_async_scope/scope_coordination.dart`:

```dart
/// The children one parent waits for before disposing of itself.
class ChildRegistry {
  final _children = <ChildEntry>[];

  bool get hasChildren => _children.isNotEmpty;

  int get childrenCount => _children.length;

  ChildEntry registerChild(String debugName) {
    final entry = ChildEntry._(debugName, this);
    _children.add(entry);

    return entry;
  }

  /// Completes once every registered child has unregistered.
  ///
  /// Completes at once when there are no children. When [timeout] elapses,
  /// [onTimeout] is called, the children left behind are dropped and the
  /// future completes normally: a child that never finishes must not keep its
  /// parent from being disposed of.
  Future<void> waitForChildren({
    Duration? timeout,
    void Function(TimeoutException error, StackTrace stackTrace)? onTimeout,
  }) async {
    if (_children.isEmpty) {
      return;
    }

    var future = _children.map((e) => e._completer.future).wait;
    if (timeout != null) {
      future = future.timeout(timeout);
    }

    try {
      await future;
    } on TimeoutException catch (_, stackTrace) {
      onTimeout?.call(
        TimeoutException(
          "couldn't wait for the children to complete: $_children",
          timeout,
        ),
        stackTrace,
      );
      // Only the children that never finished are still here; dropping them
      // keeps a second wait from hanging on entries nobody will complete.
      _children.clear();
    }
  }
}

/// A child registered in a [ChildRegistry].
class ChildEntry {
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
```

Обратить внимание: `_children.map(...).wait` — расширение `dart:async` над `Iterable<Future>`; оно уже используется в текущем `async_scope_parent.dart:33`.

- [ ] **Step 4: Убедиться, что тесты проходят**

Run: `flutter test test/scope_coordination_test.dart` → PASS (11 тестов).

- [ ] **Step 5: Коммит**

```bash
git add lib/src/scope/e_async_scope/scope_coordination.dart test/scope_coordination_test.dart
git commit -m "feat: add a child registry that owns its wait timeout"
```

---

