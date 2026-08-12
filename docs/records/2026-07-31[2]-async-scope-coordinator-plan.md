# AsyncScope Coordinator Redesign Implementation Plan

> **Состояние на 2026-08-12:** выполнен полностью, смержен в `main` (12b4c9f). Исторический документ, не поддерживается.
> **Что это:** план реализации редизайна координации из 4 задач.
> **Связанные записи:** спецификация — `2026-07-31[1]-async-scope-coordinator-design.md`, отчёты по задачам — `2026-07-31[3]-async-scope-coordinator-tasks.md`, предмержевое ревью — `2026-07-31[4]-async-scope-coordinator-final-report.md`.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Сделать `AsyncScopeCoordinator` единственным владельцем координации асинхронных скоупов — очередей по `scopeKey` и корня ожиданий, — вынеся саму координацию в тестируемое ядро без Flutter.

**Architecture:** Новая самостоятельная библиотека `lib/src/scope/e_async_scope/scope_coordination.dart` (не `part` от `scope.dart`, не экспортируется из `lib/scopo.dart`) содержит `KeyedAccessQueues`/`AccessEntry` и `ChildRegistry`/`ChildEntry`. Элемент координатора владеет `KeyedAccessQueues` как полем экземпляра и подмешивает `AsyncScopeParent`, поэтому существующий поиск «первого предка с `AsyncScopeParent`» находит его сам собой. Глобальный `asyncScopeRoot` удаляется.

**Tech Stack:** Dart 3 / Flutter, `flutter_test`, `fake_async` (через `test/utils/my_fake_async.dart`).

**Spec:** `docs/superpowers/specs/2026-07-31-async-scope-coordinator-design.md` — читать перед началом.

## Global Constraints

- Ядро (`scope_coordination.dart`) не импортирует Flutter — только `dart:async`. Проверяется грепом в Задаче 1.
- Ядро не бросает по таймауту: зовёт `onTimeout(TimeoutException, StackTrace)` и завершается нормально. Политику «сообщить через `FlutterError.reportError` и продолжить» задаёт виджетный слой.
- Целевой релиз — **0.10.0** (не опубликован). Удаления чистые, без `@Deprecated`.
- После каждой задачи: `flutter analyze` — 0 замечаний в корне и обоих примерах; `flutter test` — все зелёные; `dart format` — без изменений.
- Базовая линия на старте: 35 тестов, analyze 0, `dart doc` 0/0, `pub publish --dry-run` 0 warnings.
- Сообщения коммитов — с префиксом типа: `feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`.
- Русские комментарии в `lib/` не заводить — весь новый dartdoc и комментарии на английском.

---

## File Structure

| Файл | Что делает |
|---|---|
| `lib/src/scope/e_async_scope/scope_coordination.dart` | **создаётся.** Ядро: `KeyedAccessQueues`, `AccessEntry`, `ChildRegistry`, `ChildEntry`. Без Flutter. |
| `lib/src/scope/e_async_scope/async_scope_coordinator.dart` | виджет и элемент; элемент получает `AsyncScopeParent` и поле `_queues`; удаляются `AsyncScopeCoordinatorEntry` и `_AsyncScopeCoordinatorQueue` |
| `lib/src/scope/e_async_scope/async_scope_parent.dart` | миксин делегирует в `ChildRegistry`; `ScopeChildEntry` удаляется |
| `lib/src/scope/e_async_scope/async_scope_root.dart` | **удаляется целиком** |
| `lib/src/scope/scope.dart` | убирается `part 'e_async_scope/async_scope_root.dart';`, добавляется `import '../e_async_scope/scope_coordination.dart';` (путь — от `lib/src/scope/`) |
| `lib/src/scope/e_async_scope/async_scope_core.dart` | регистрация у родителя без фолбэка; ожидание детей одним вызовом; тип записи `AccessEntry` |
| `test/scope_coordination_test.dart` | **создаётся.** Юнит-тесты ядра. |
| `test/async_scope_coordinator_test.dart` | **создаётся.** Widget-тесты виджетного слоя. |

---

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

## Task 3: Координатор владеет очередями и корнем

Самая содержательная задача: виджетный слой переключается на ядро, `asyncScopeRoot` исчезает.

**Files:**
- Modify: `lib/src/scope/e_async_scope/async_scope_coordinator.dart`
- Modify: `lib/src/scope/e_async_scope/async_scope_parent.dart`
- Delete: `lib/src/scope/e_async_scope/async_scope_root.dart`
- Modify: `lib/src/scope/scope.dart`
- Modify: `lib/src/scope/e_async_scope/async_scope_core.dart`
- Test: `test/async_scope_coordinator_test.dart`

**Interfaces:**
- Consumes: `KeyedAccessQueues`, `AccessEntry`, `ChildRegistry`, `ChildEntry` из Задач 1-2.
- Produces: `AsyncScopeCoordinator.enter(context, key, entry, {timeout, onTimeout})` — сигнатура прежняя, но тип записи теперь `AccessEntry`; новый `AsyncScopeCoordinator.waitForChildren(context, {timeout, onTimeout})`; `AsyncScopeParent` с тем же набором членов, но `waitForChildren` принимает `timeout`/`onTimeout`.

- [ ] **Step 1: Написать падающие widget-тесты**

Создать `test/async_scope_coordinator_test.dart`. Фикстура одна на все тесты; сигнатуры `scopeKey`, `initAsync`, `disposeAsync`, `buildOnState` взяты из `AsyncScopeCore`, стиль объявления — из `test/async_scope_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scopo/scopo.dart';

void main() {
  setUp(_TestScopeElement.reset);

  testWidgets('two coordinators do not share a key', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: [
            AsyncScopeCoordinator(child: _TestScope(testKey: 'shared')),
            AsyncScopeCoordinator(child: _TestScope(testKey: 'shared')),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(_TestScopeElement.initialized, 2);
    expect(
      tester.takeException(),
      isNull,
      reason: 'neither scope waited for the one in the other coordinator',
    );
  });

  testWidgets('the nearest coordinator serves the key', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: AsyncScopeCoordinator(
          child: Column(
            children: [
              _TestScope(testKey: 'shared'),
              AsyncScopeCoordinator(child: _TestScope(testKey: 'shared')),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(_TestScopeElement.initialized, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a scopeKey without a coordinator is an error', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: _TestScope(testKey: 'shared'),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isA<FlutterError>());
  });

  testWidgets('a parent scope waits for the scope below it', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: AsyncScopeCoordinator(
          child: _TestScope(
            disposeLabel: 'parent',
            child: _TestScope(
              disposeLabel: 'child',
              disposeDelay: Duration(milliseconds: 50),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox.shrink(),
      ),
    );
    await tester.pumpAndSettle();

    expect(_TestScopeElement.disposalOrder, ['child', 'parent']);
  });

  testWidgets('a scope with no parent and no coordinator disposes cleanly',
      (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: _TestScope(disposeLabel: 'lonely'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox.shrink(),
      ),
    );
    await tester.pumpAndSettle();

    expect(_TestScopeElement.disposalOrder, ['lonely']);
    expect(tester.takeException(), isNull);
  });
}

final class _TestScope extends AsyncScopeCore<_TestScope, _TestScopeElement> {
  final Object? testKey;
  final String? disposeLabel;
  final Duration disposeDelay;
  final Widget child;

  const _TestScope({
    this.testKey,
    this.disposeLabel,
    this.disposeDelay = Duration.zero,
    this.child = const SizedBox.shrink(),
  });

  @override
  _TestScopeElement createScopeElement() => _TestScopeElement(this);
}

final class _TestScopeElement
    extends AsyncScopeElementBase<_TestScope, _TestScopeElement> {
  _TestScopeElement(super.widget);

  static int initialized = 0;
  static final disposalOrder = <String>[];

  static void reset() {
    initialized = 0;
    disposalOrder.clear();
  }

  @override
  Object? get scopeKey => widget.testKey;

  @override
  Stream<AsyncScopeInitState> initAsync() async* {
    initialized++;
    yield AsyncScopeReady();
  }

  @override
  FutureOr<void> disposeAsync() async {
    if (widget.disposeDelay > Duration.zero) {
      await Future<void>.delayed(widget.disposeDelay);
    }
    if (widget.disposeLabel case final label?) {
      disposalOrder.add(label);
    }
  }

  @override
  Widget buildOnState(AsyncScopeState state) => widget.child;
}
```

- [ ] **Step 2: Убедиться, что тесты падают**

Run: `flutter test test/async_scope_coordinator_test.dart`

Ожидаемое до правок `lib/`: первые два теста падают — статическая карта делает ключ общим, второй скоуп ждёт три секунды, ловит таймаут и `takeException()` возвращает отчёт об ошибке. Остальные три проходят и до правок: они страхуют от регресса (ошибка без координатора, ожидание родителем ребёнка, чистая утилизация одинокого скоупа — последний сейчас держится на `asyncScopeRoot`, который мы удаляем).

- [ ] **Step 3: Переключить `AsyncScopeParent` на `ChildRegistry`**

`lib/src/scope/e_async_scope/async_scope_parent.dart` целиком:

```dart
part of '../scope.dart';

/// A scope that waits for the scopes below it before disposing of itself.
///
/// The nearest ancestor with this mixin — a parent scope, or the
/// [AsyncScopeCoordinator] when there is no parent scope — is what a scope
/// registers with. A scope with neither above it registers nowhere and nobody
/// waits for it.
///
/// {@category AsyncScope}
mixin AsyncScopeParent on Diagnosticable {
  final _childRegistry = ChildRegistry();

  bool get hasChildren => _childRegistry.hasChildren;

  int get childrenCount => _childRegistry.childrenCount;

  /// Completes once every child registered with this parent has finished.
  ///
  /// On [timeout] the children left behind are dropped and [onTimeout] is
  /// called; the future completes normally either way.
  Future<void> waitForChildren({
    Duration? timeout,
    void Function(TimeoutException error, StackTrace stackTrace)? onTimeout,
  }) =>
      _childRegistry.waitForChildren(timeout: timeout, onTimeout: onTimeout);

  ChildEntry registerChild(String debugName) =>
      _childRegistry.registerChild(debugName);
}
```

`ScopeChildEntry` удаляется — его роль исполняет `ChildEntry` из ядра.

- [ ] **Step 4: Переключить координатор на ядро**

В `lib/src/scope/e_async_scope/async_scope_coordinator.dart`:

1. Элемент подмешивает `AsyncScopeParent` и владеет очередями:

```dart
final class _AsyncScopeCoordinatorElement extends ScopeWidgetElementBase<
    AsyncScopeCoordinator,
    _AsyncScopeCoordinatorElement> with AsyncScopeParent {
  _AsyncScopeCoordinatorElement(super.widget);

  final _queues = KeyedAccessQueues();

  @override
  Widget buildChild() => widget.child;

  Future<void> enter(
    Object key,
    AccessEntry entry, {
    Duration? timeout,
    void Function(TimeoutException error, StackTrace stackTrace)? onTimeout,
  }) =>
      _queues.enter(key, entry, timeout: timeout, onTimeout: onTimeout);
}
```

2. Статический `enter` меняет только тип записи и сигнатуру `onTimeout`; текст `FlutterError` при отсутствии координатора не трогать.

3. Добавить статический хелпер и общий поиск элемента:

```dart
  /// Waits for the scopes that registered with this coordinator.
  ///
  /// These are the scopes that have no parent scope above them; a scope with a
  /// parent scope is awaited by that parent instead.
  static Future<void> waitForChildren(
    BuildContext context, {
    Duration? timeout,
    void Function(TimeoutException error, StackTrace stackTrace)? onTimeout,
  }) =>
      _elementOf(context).waitForChildren(timeout: timeout, onTimeout: onTimeout);
```

где `_elementOf(BuildContext)` — приватная статика, содержащая нынешний `maybeOf(...) ?? (throw FlutterError(...))`; оба публичных метода зовут её, чтобы текст ошибки был один.

4. Удалить `AsyncScopeCoordinatorEntry` и `_AsyncScopeCoordinatorQueue` целиком.

- [ ] **Step 5: Удалить корень и подключить ядро**

```bash
git rm lib/src/scope/e_async_scope/async_scope_root.dart
```

В `lib/src/scope/scope.dart` убрать строку `part 'e_async_scope/async_scope_root.dart';` и добавить к импортам:

```dart
import 'e_async_scope/scope_coordination.dart';
```

(путь относительно `lib/src/scope/scope.dart`).

- [ ] **Step 6: Переключить `async_scope_core.dart`**

1. Поля (`:107-109`):

```dart
  AccessEntry? _asyncScopeEntry;

  ChildEntry? _asyncScopeParentEntry;
```

2. Регистрация у родителя (`:184`) — без глобального фолбэка:

```dart
    _asyncScopeParentEntry = parent?.registerChild(
      widget.toStringShort(showHashCode: true),
    );
```

3. Создание записи (`:202`): `AsyncScopeCoordinatorEntry(...)` → `AccessEntry(...)`.

4. Вызов `AsyncScopeCoordinator.enter` (`:207-213`) — подставить новую сигнатуру `onTimeout`:

```dart
      await AsyncScopeCoordinator.enter(
        this,
        scopeKey,
        entry,
        timeout: scopeKeyTimeout ?? ScopeConfig.defaultScopeKeysTimeout,
        onTimeout: (error, stackTrace) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stackTrace,
              library: 'scopo',
            ),
          );
          onScopeKeyTimeout();
        },
      );
```

(отчёт об ошибке переезжает из ядра сюда; в `_AccessQueue` его больше нет).

5. Ожидание детей (`:320-347`) — весь блок с `future.timeout`, `try/on TimeoutException` и `_children.clear()` заменить на:

```dart
    if (hasChildren) {
      _log.d(() => 'wait for children (count: $childrenCount)');
      await waitForChildren(
        timeout:
            waitForChildrenTimeout ?? ScopeConfig.defaultWaitForChildrenTimeout,
        onTimeout: (error, stackTrace) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stackTrace,
              library: 'scopo',
            ),
          );
          onWaitForChildrenTimeout();
        },
      );
    }
```

Текст исключения теперь формирует ядро; проверить, что `_children` больше нигде в файле не упоминается.

- [ ] **Step 7: Прогнать и починить**

Run: `flutter analyze` → 0. Run: `flutter test` → все зелёные, включая новые widget-тесты.
Если анализатор жалуется на `ScopeChildEntry`/`AsyncScopeCoordinatorEntry` — значит осталась ссылка; заменить на типы ядра.

- [ ] **Step 8: Коммит**

```bash
git add -A lib test
git commit -m "refactor: make the coordinator own the queues and the wait root"
```

---

## Task 4: Публичная поверхность, документация, релизные заметки

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`
- Modify: `TODO.md`
- Modify: `lib/src/scope/e_async_scope/async_scope_coordinator.dart` (dartdoc)

- [ ] **Step 1: Дописать dartdoc координатора**

У `AsyncScopeCoordinator` сейчас только `{@category AsyncScope}`. Добавить описание: что он владеет очередями `scopeKey` в пределах своего поддерева, что ближайший выигрывает, и что он же ждёт скоупы без родителя. Ссылки писать в квадратных скобках только на существующие символы — `dart doc` эскалирует нерезолвящиеся ссылки в ошибку.

- [ ] **Step 2: README**

В разделе про `scopeKey` (около `README.md:408`) добавить абзац: координатор ограничивает область действия ключей своим поддеревом, а `AsyncScopeCoordinator.waitForChildren(context)` позволяет дождаться верхнеуровневых скоупов. Сниппет проверить компиляцией в scratch-пакете вне репозитория.

- [ ] **Step 3: CHANGELOG**

В секцию `## 0.10.0` добавить:

```markdown
* [breaking changes] `AsyncScopeCoordinator` now owns the `scopeKey` queues of
  its own subtree instead of a process-wide map, and is what scopes without a
  parent scope register with. The global `asyncScopeRoot`, `AsyncScopeRoot`,
  `AsyncScopeCoordinatorEntry` and `ScopeChildEntry` are gone, and
  `AsyncScopeParent.waitForChildren` takes `timeout` and `onTimeout`.
```

- [ ] **Step 4: TODO.md**

Удалить пункты, закрытые этой работой: строку про `AsyncScopeCoordinator` в «Известные проблемы» и пункт `waitForChildren, asyncScopeRoot - переделать…` в верхнем списке.

- [ ] **Step 5: Полная верификация**

```bash
flutter analyze                    # 0
(cd example/minimal && flutter analyze)      # 0
(cd example/scopo_demo && flutter analyze)   # 0
flutter test                       # все зелёные
dart doc --output <scratch>/dartdoc-coord    # 0 warnings, 0 errors
flutter pub publish --dry-run      # 0 warnings
(cd example/scopo_demo && flutter build macos --debug)  # собирается
```

- [ ] **Step 6: Коммит**

```bash
git add -A
git commit -m "docs: describe coordinator-owned scopeKey scoping"
```

---

## Verification

1. `flutter test` — 35 прежних тестов плюс 11 юнит-тестов ядра и 5 widget-тестов координатора, все зелёные.
2. `flutter analyze` — 0 в корне и обоих примерах.
3. `grep -rn "asyncScopeRoot\|AsyncScopeRoot\|AsyncScopeCoordinatorEntry\|ScopeChildEntry" lib test example` — пусто.
4. `grep -c "package:flutter" lib/src/scope/e_async_scope/scope_coordination.dart` — `0`.
5. `dart doc` — 0 warnings, 0 errors.
6. `flutter pub publish --dry-run` — 0 warnings.
7. `example/scopo_demo` собирается под macOS (демо использует координатор).
