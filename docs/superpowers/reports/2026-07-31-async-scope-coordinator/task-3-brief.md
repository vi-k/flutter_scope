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

