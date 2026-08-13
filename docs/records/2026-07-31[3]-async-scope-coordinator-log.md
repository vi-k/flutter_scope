# async-scope-coordinator — журнал и отчёты по задачам

> **Состояние на 2026-08-12:** работа завершена и смержена в `main` (12b4c9f). Исторический документ, не поддерживается.
> **Что это:** склейка 9 файлов эпизода 2026-07-31 — журнал хода работ (`progress.md`) и брифы/отчёты 4 задач. Тексты сохранены дословно, границы исходных файлов отмечены заголовками `## Файл: …`.
> **Связанные записи:** план — `2026-07-31[2]-async-scope-coordinator-plan.md`, итог — `2026-07-31[4]-async-scope-coordinator-final-report.md`.

## Файл: progress.md

# SDD ledger — plan: docs/superpowers/plans/2026-07-31-async-scope-coordinator.md

Worktree: /Users/user/development/my/scopo/.claude/worktrees/coordinator (branch coordinator, отведена от HEAD=128b86b, НЕ от origin/main — main на 30 коммитов впереди origin).
Baseline: 35 тестов зелёные, flutter analyze 0 (после pub get в обоих примерах — в свежем worktree их .dart_tool отсутствует и анализатор даёт 51 ложную ошибку).
Pre-flight: конфликтов между задачами плана и Global Constraints не найдено. План писал контроллер по одобренной пользователем спеке.
Task 1: minor (deferred): (1) тест таймаута зажимает момент впуска между 2с и 4с, а не в точке 3с, и не проверяет reported.duration; (2) нет теста на состояние очереди ПОСЛЕ таймаута (запись остаётся в _entries); (3) нет теста на onTimeout: null (ядро должно молча проглотить) и на StateError при exit() неприкреплённой записи; (4) новые классы объявлены как plain class, в репозитории конвенция final class — поправить в Task 2, когда файл всё равно правится.
Task 1: РЕШЕНИЯ КОНТРОЛЛЕРА по forward-looking замечаниям ревьюера:
  - «_queues был static, стал полем экземпляра» — это НЕ дефект, а сознательное решение спеки (ближайший координатор владеет своим пространством ключей). Реставрировать static в Task 3 ЗАПРЕЩЕНО.
  - onTimeout в ядре опционален, а старый код репортил безусловно: Task 3 ОБЯЗАН всегда передавать колбэк с FlutterError.reportError, иначе таймауты станут молчаливыми. Плюс мост сигнатур: публичный AsyncScopeCoordinator.enter принимает void Function()?, ядро — void Function(TimeoutException, StackTrace)?.
  - два _log.d («queue for [key] created/removed») теряются: осознанно отказываемся, это диагностика внутреннего учёта; значимые логи (ожидание доступа, получение, выход) живут в async_scope_core и остаются.
Task 1: complete (commits 128b86b..efb9e6f, review approved)
Task 2: minor (deferred): (1) тест «no children completes at once» прошёл бы и без fast-path (Future.wait([]) тоже мгновенный) — не пиннит ветку; (2) ребёнок, зарегистрированный ВО ВРЕМЯ активного ожидания, не дожидается (снимок futures берётся в момент вызова) — поведение унаследовано от старого кода, не регрессия, но dartdoc «Completes once every registered child has unregistered» это слегка переобещает.
Task 2: complete (commits efb9e6f..fc5c0f4, review approved) — 46 тестов
Task 3: ревью — CRITICAL: координатор, стоящий ПОД скоупом, перехватывает регистрацию детей, и родительский скоуп перестаёт их дожидаться ([child,parent] -> [parent,child]); проверено пробами на fc5c0f4 vs 00b1460. Это дефект СПЕКИ (я утверждал, что поиск «первого предка с AsyncScopeParent» найдёт координатор «сам собой», не учтя обратный порядок). example/scopo_demo построен именно так, и текст нашей ошибки туда же и ведёт.
Task 3: решение контроллера (пользователь сказал «продолжай», выбор делегирован): минимальное направление — родитель-скоуп всегда выигрывает, координатор используется только как fallback при отсутствии скоупа-предка. Совпадает с уже написанным dartdoc; в точности восстанавливает прежнее поведение.
Task 3: minor (deferred в Task 4): публичные enter/registerChild упоминают неэкспортируемые AccessEntry/ChildEntry (enter снаружи пакета невызываем); у AsyncScopeCoordinator.waitForChildren нет теста и примера; dartdoc не прогонялся после смены сигнатур (dartdoc_options эскалирует нерезолвящиеся ссылки в ошибку); CHANGELOG:120 и TODO:7,16 всё ещё упоминают удалённый asyncScopeRoot.
Task 3: pre-existing (не в объёме): регистрация в post-frame проверяет mounted, но не _isDisposing — скоуп, закрытый до первого кадра, может зарегистрировать ChildEntry, который никто не снимет.
Task 3: fix round 1/5 запущен (1 critical + 2 мелких дефекта этого же коммита).
Task 3: fix round 1/5 (1 critical + 2 minor addressed; commits 00b1460..fff12ad). Ре-ревью проверило 8 конфигураций дерева независимой пробой: сломанная Scope>Coordinator>Scope вернулась к [child,parent], фолбэк Coordinator>Scope цел, форма scopo_demo корректна. Из 3 новых тестов до фикса падал 1 (остальные два — страховка от переисправления и сохранённое старое тело); неточную формулировку в отчёте исправил контроллер.
Task 3: complete (commits fc5c0f4..fff12ad, re-review approved) — 54 теста
Task 4: РЕШЕНИЕ КОНТРОЛЛЕРА по публичному API (замечание ревьюера: enter невызываем снаружи, т.к. AccessEntry не экспортируется): не экспортировать ядро, а СУЗИТЬ поверхность — AsyncScopeCoordinator.enter и AsyncScopeParent.registerChild сделать приватными для библиотеки (async_scope_core.dart — part of scope.dart, ему они доступны). Публичными остаются: виджет AsyncScopeCoordinator, статический waitForChildren(context), а также hasChildren/childrenCount/waitForChildren у AsyncScopeParent. После этого ни один публичный член не упоминает неэкспортируемый тип.
Task 4: complete (commits fff12ad..e9acbca, review clean) — 55 тестов, dart doc 0/0, dry-run 0 warnings, scopo_demo собирается. Публичная поверхность сужена: enter и registerChild стали приватными для библиотеки, ни один публичный член не упоминает неэкспортируемый тип.
Task 4: minor (deferred): dart format показывает расхождение в 6 файлах example/scopo_demo — pre-existing (есть и на fff12ad), к этой работе отношения не имеет.
=== Все 4 задачи исполнены. Финальное whole-branch ревью. ===
Финальное ревью (opus): READY TO MERGE WITH FIXES. Critical 0. Important 4: (1) CHANGELOG 0.10.0 не называет замену asyncScopeRoot, не упоминает приватизацию enter/registerChild и МОЛЧАЛИВОЕ изменение поведения (скоуп без родителя и координатора не регистрируется нигде — спека прямо требовала это записать); (2) новый публичный waitForChildren по умолчанию ждёт бесконечно, что противоречит политике пакета «таймаут не фатален, но он есть»; (3) у нового публичного API ноль тестов; (4) перенос FlutterError.reportError из ядра в виджетный слой ничем не закреплён — уроните колбэк, и все таймауты замолчат при зелёном сьюте.
Решения контроллера по фикс-волне: item 2 — задать дефолт ScopeConfig.defaultWaitForChildrenTimeout и репортить по умолчанию; Minor 6 (isWaitRootFallback вместо проверки приватного типа) — ОТКЛОНЁН: добавляет публичный член в публичный миксин ради внутреннего правила, оставляем проверку типа с комментарием.
Отклонённое/отложенное из триажа ревью зафиксировано ниже фикс-волной.
Финальная фикс-волна: commit 3374917 (все 4 Important + минорные). Скоуп-ре-ревью: все 8 находок ADDRESSED, ревert-доказательства честные, CHANGELOG точен и история цела. НО волна внесла CRITICAL: дефолтный onTimeout у публичного waitForChildren читает element.widget в момент истечения таймаута; если координатор к этому времени размонтирован, _widget уже null -> краш, который заодно глушит отчёт и пропускает _children.clear(). Воспроизведено ревьюером. Плюс выяснилось, что фикс Important 2 вообще ничем не закреплён: откат обоих дефолтов оставляет сьют зелёным.
Решение контроллера: отступаю от правила SDD «одна фикс-волна» — отправлять на мерж известный краш ради процедуры неправильно. Второй раунд: вынос имени виджета из замыкания (пока элемент смонтирован) + тест, пиннящий оба дефолта + eager-захват ScopeConfig в тестах (ленивый top-level final инициализируется внутри первого tearDown и «восстанавливает» уже испорченное значение).


---

## Файл: task-1-brief.md

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



---

## Файл: task-1-report.md

# Task 1 Report: Ядро — очереди по ключам

## What was done

Followed the brief's TDD process exactly, in `/Users/user/development/my/scopo/.claude/worktrees/coordinator`:

1. Read the existing `_AsyncScopeCoordinatorQueue` / `AsyncScopeCoordinatorEntry` in
   `lib/src/scope/e_async_scope/async_scope_coordinator.dart:109-208` to confirm the
   semantics being extracted (FIFO mutex per key, `Future.any` race of previous
   entries / self-completion / cancellation, optional timeout that lets the entry in
   anyway, queue removed from the map once empty).
2. Confirmed baseline: `flutter test` → 35 tests passed; `flutter analyze` → `No issues
   found!`.
3. **Step 1** — created `test/scope_coordination_test.dart` with the first three tests
   from the brief verbatim (first entry gets in immediately / second waits for first to
   exit / queue removed once last entry exits).
4. **Step 2** — ran `flutter test test/scope_coordination_test.dart`; got the expected
   compile failure (library doesn't exist).
5. **Step 3** — created `lib/src/scope/e_async_scope/scope_coordination.dart` with
   `KeyedAccessQueues`, `AccessEntry`, and the private `_AccessQueue`, transcribed from
   the brief (which is itself transcribed from the old private class), with the one
   deliberate semantic change: on timeout the new code calls
   `onTimeout?.call(TimeoutException(...), stackTrace)` instead of
   `FlutterError.reportError(...)` — no Flutter reporting happens in this core.
6. **Step 4** — ran `dart format` on both files (no changes needed), then re-ran the
   3 tests — all passed.
7. **Step 5** — appended the remaining 5 tests to the same `group` block, verbatim from
   the brief (ordering, cancellation, fake-async timeout, key reuse after release,
   independent keys).
8. **Step 6** — ran the full 8-test file (all passed), the Flutter-free grep, and
   `flutter analyze`. The analyzer flagged one lint (`avoid_escaping_inner_quotes`) on
   the timeout message string, which used `'...couldn\'t...'`; fixed by switching that
   literal to double quotes (`"...couldn't..."`) — see Deviations below. Re-ran
   `flutter analyze` → clean. Re-ran the full suite (`flutter test`) → 43 tests passed
   (35 baseline + 8 new).
9. **Step 7** — committed exactly the two new files with the specified message.

## Commands and output

### Baseline (before any changes)

```
$ flutter test
...
00:00 +35: All tests passed!

$ flutter analyze
Analyzing coordinator...
No issues found! (ran in 0.9s)
```

### Step 2 — failing run (library doesn't exist)

```
$ flutter test test/scope_coordination_test.dart
test/scope_coordination_test.dart:4:8: Error: Error when reading
'lib/src/scope/e_async_scope/scope_coordination.dart': No such file or directory
  import 'package:scopo/src/scope/e_async_scope/scope_coordination.dart';
         ^
test/scope_coordination_test.dart:13:22: Error: Method not found: 'KeyedAccessQueues'.
...
00:00 +0 -1: Some tests failed.
```

This matches the brief's expected failure (`Target of URI doesn't exist`) — the Dart
frontend reports it as "Error when reading ... No such file or directory" plus
downstream "Method not found" errors for the missing symbols, which is the same
root cause (the library doesn't exist yet).

### Step 4 — first three tests passing

```
$ flutter test test/scope_coordination_test.dart
00:00 +0: KeyedAccessQueues the first entry gets in immediately
00:00 +1: KeyedAccessQueues the second entry waits for the first to exit
00:00 +2: KeyedAccessQueues the queue is removed once the last entry exits
00:00 +3: All tests passed!
```

### Step 6 — all 8 tests passing

```
$ flutter test test/scope_coordination_test.dart
00:00 +0: KeyedAccessQueues the first entry gets in immediately
00:00 +1: KeyedAccessQueues the second entry waits for the first to exit
00:00 +2: KeyedAccessQueues the queue is removed once the last entry exits
00:00 +3: KeyedAccessQueues entries are let in in the order they arrived
00:00 +4: KeyedAccessQueues cancelling stops the wait but keeps the place in the queue
00:00 +5: KeyedAccessQueues a timeout reports and lets the entry in anyway
00:00 +6: KeyedAccessQueues a key can be taken again after it was released
00:00 +7: KeyedAccessQueues different keys do not block each other
00:00 +8: All tests passed!
```

Flutter-free grep:

```
$ grep -c "package:flutter" lib/src/scope/e_async_scope/scope_coordination.dart
0
```

Analyze, before and after the quoting fix:

```
$ flutter analyze
Analyzing coordinator...
   info • Unnecessary escape of '''. Try changing the outer quotes to '"' •
     lib/src/scope/e_async_scope/scope_coordination.dart:121:11 • avoid_escaping_inner_quotes
1 issue found. (ran in 1.0s)

# after switching that string literal to double quotes + dart format:
$ flutter analyze
Analyzing coordinator...
No issues found! (ran in 1.0s)
```

Full suite after the fix:

```
$ flutter test
...
00:00 +43: All tests passed!
```

(43 = 35 baseline + 8 new.)

## Deviations from the brief's code

1. **Quoting of the timeout message** (`_AccessQueue.enter`, inside the
   `on TimeoutException catch` block). The brief's code block used:

   ```dart
   '${entry._debugName} couldn\'t wait to get access to [$key]:'
   ' $previous',
   ```

   This trips the repo's `avoid_escaping_inner_quotes` lint (part of the ~150-rule
   strict set), which flags the escaped `'` inside a single-quoted string. Changed the
   outer quotes of that one literal to double quotes:

   ```dart
   "${entry._debugName} couldn't wait to get access to [$key]:"
   ' $previous',
   ```

   No semantic change — same message text, same behavior. This is exactly the kind of
   "may need formatting" adjustment the task context flagged as expected against the
   strict lint set.

2. No other deviations. `dart format` made no changes to either file beyond this fix
   (ran it before and after; 0 changed each time post-fix). The rest of the core and
   both test blocks were transcribed verbatim from the brief.

## Files touched

- Created: `lib/src/scope/e_async_scope/scope_coordination.dart`
- Created: `test/scope_coordination_test.dart`
- Not touched: `lib/src/scope/e_async_scope/async_scope_coordinator.dart` (confirmed via
  `git status --short` / `git diff --stat` showing it absent from the diff — only the
  two new files are untracked/added).

## Commit

```
efb9e6f feat: add a Flutter-free keyed access queue for scope coordination
 2 files changed, 312 insertions(+)
```


---

## Файл: task-2-brief.md

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



---

## Файл: task-2-report.md

# Task 2 report — ядро реестра детей

## Summary

Implemented `ChildRegistry`/`ChildEntry` in
`lib/src/scope/e_async_scope/scope_coordination.dart`, with the timeout for
waiting on children now owned by `waitForChildren` itself (registry cleared
only on timeout — mirroring the semantics currently split across
`AsyncScopeParent` and the timeout block in `async_scope_core.dart`, without
modifying either file). Applied the Task-1-review-driven `final class`
convention to all classes in the file, including the new ones. Committed as
`fc5c0f4`.

## TDD evidence

**Step 2 — tests fail first** (`flutter test test/scope_coordination_test.dart --name ChildRegistry`):

```
test/scope_coordination_test.dart:164:24: Error: Method not found: 'ChildRegistry'.
test/scope_coordination_test.dart:172:24: Error: Method not found: 'ChildRegistry'.
test/scope_coordination_test.dart:195:26: Error: Method not found: 'ChildRegistry'.
00:00 +0 -1: Some tests failed.
```

Confirms the group was absent from the implementation before Step 3, exactly
as expected.

**Step 4 — tests pass after implementation** (`flutter test test/scope_coordination_test.dart`):

```
00:00 +0: KeyedAccessQueues the first entry gets in immediately
00:00 +1: KeyedAccessQueues the second entry waits for the first to exit
00:00 +2: KeyedAccessQueues the queue is removed once the last entry exits
00:00 +3: KeyedAccessQueues entries are let in in the order they arrived
00:00 +4: KeyedAccessQueues cancelling stops the wait but keeps the place in the queue
00:00 +5: KeyedAccessQueues a timeout reports and lets the entry in anyway
00:00 +6: KeyedAccessQueues a key can be taken again after it was released
00:00 +7: KeyedAccessQueues different keys do not block each other
00:00 +8: ChildRegistry waiting with no children completes at once
00:00 +9: ChildRegistry waiting completes when every child has unregistered
00:00 +10: ChildRegistry a timeout reports and gives up on the children left
00:00 +11: All tests passed!
```

11/11 in this file (8 baseline `KeyedAccessQueues` + 3 new `ChildRegistry`).

**Full suite** (`flutter test`): `00:00 +46: All tests passed!` — 43 baseline
+ 3 new = 46, matches expectation.

**Analyze** (`flutter analyze`): `No issues found!` (0 issues, baseline
maintained).

**Format**: `dart format --output=none --set-exit-if-changed` on both
touched files reports 0 changed — already correctly formatted.

## `final class` conversion

Per the Task 1 review note, converted the plain `class` declarations to
`final class` (repo convention, 61 existing occurrences in `lib/`):

- `KeyedAccessQueues` → `final class KeyedAccessQueues`
- `AccessEntry` → `final class AccessEntry`
- `_AccessQueue` → `final class _AccessQueue`
- New `ChildRegistry` and `ChildEntry` were declared `final class` from the
  start.

Verified nothing subclasses any of these (only `scope_coordination_test.dart`
and, later, `AsyncScopeParent`/`async_scope_core.dart` in Task 3 reference
them) and the full suite plus analyze stayed green after the change.

## Deviation from the brief (and why)

The brief's Step-1 test code is verbatim except for one line, changed to
satisfy the repo's own lint config (`analysis_options.yaml:139` enables
`cascade_invocations`) and the "flutter analyze 0" baseline requirement,
which take priority over an incidental two-statement layout in the brief.

Brief's literal code:

```dart
final registry = ChildRegistry();
registry.registerChild('slow');
TimeoutException? reported;
```

Committed code:

```dart
final registry = ChildRegistry()..registerChild('slow');
TimeoutException? reported;
```

Reasoning: `flutter analyze` flagged this exact spot —
`test/scope_coordination_test.dart:196:9 • cascade_invocations` (info) —
because the statement right after `final registry = ChildRegistry();`
invokes a method on `registry` and discards the result, which is precisely
the pattern the enabled `cascade_invocations` lint targets (as verified by
testing: the same shape does not recur elsewhere in this file, e.g. the
`ChildRegistry` "unregistered" test assigns `registerChild`'s result to
`first`/`second` instead of discarding it, so it never trips the rule).
Folding the two lines into one cascade is behaviorally identical — same
call, same order, same registry — and is literally the fix the linter itself
suggests. No other line in the brief's code needed touching; `dart format`
made zero changes to either file after the edit.

No other deviations. `waitForChildren`'s timeout-only-clear behavior and the
`onTimeout` callback shape were implemented exactly as specified in Step 3,
and match the semantics of the current `async_scope_core.dart:320-347` /
`async_scope_parent.dart` code they will replace in Task 3 (success path:
every child already removes itself via `unregister`, so clearing only on the
`TimeoutException` branch is a no-op-preserving change, not a behavior
change).

## Files touched

- `/Users/user/development/my/scopo/.claude/worktrees/coordinator/lib/src/scope/e_async_scope/scope_coordination.dart`
- `/Users/user/development/my/scopo/.claude/worktrees/coordinator/test/scope_coordination_test.dart`

## Not touched (per instructions)

- `/Users/user/development/my/scopo/.claude/worktrees/coordinator/lib/src/scope/e_async_scope/async_scope_parent.dart`
- `/Users/user/development/my/scopo/.claude/worktrees/coordinator/lib/src/scope/e_async_scope/async_scope_core.dart`

These are Task 3's responsibility (rewiring `AsyncScopeParent` to delegate to
`ChildRegistry`/`ChildEntry` and moving the timeout call site).

## Commit

```
fc5c0f4 feat: add a child registry that owns its wait timeout
```


---

## Файл: task-3-brief.md

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



---

## Файл: task-3-report.md

# Task 3 report — the coordinator owns the queues and the wait root

Commit: `00b1460` — `refactor: make the coordinator own the queues and the wait root`
(parent `fc5c0f4`). Branch `coordinator`, worktree
`/Users/user/development/my/scopo/.claude/worktrees/coordinator`.

Result: `flutter analyze` → 0 issues in the root package **and** in
`example/minimal` and `example/scopo_demo`. `flutter test` → **51 passed**
(46 before + the 5 new widget tests).

---

## Step 1-2: the five widget tests, written first, run before touching `lib/`

`flutter test test/async_scope_coordinator_test.dart` on the untouched `lib/`:
**0 passed, 5 failed.** The brief predicted 2 failures; all 5 failed. Two of
them for the reason the brief named, three for reasons that turned out to be
about the *test framework*, not about our code (details and fixes below).

| # | test | before `lib/` changes | after |
| - | ---- | --------------------- | ----- |
| 1 | two coordinators do not share a key | FAIL `Expected: <2> Actual: <1>` | PASS |
| 2 | the nearest coordinator serves the key | FAIL `Expected: <2> Actual: <0>` | PASS |
| 3 | a scopeKey without a coordinator is an error | FAIL `takeException()` → `null` | PASS (test rewritten, see D-2) |
| 4 | a parent scope waits for the scope below it | FAIL `Expected: ['child','parent'] Actual: []` | PASS (test rewritten, see D-3) |
| 5 | a scope with no parent and no coordinator disposes cleanly | FAIL `Expected: ['lonely'] Actual: []` | PASS (test rewritten, see D-3) |

Notes on the "before" evidence:

- **#1** `initialized == 1`: with the process-wide `static _queues`, the second
  scope queued behind the first one even though it lived under a different
  coordinator, and it was still waiting when the test asserted. Exactly the
  defect the redesign removes.
- **#2** `initialized == 0`: worse than #1, and a second symptom of the same
  cause — the static map survives *between tests*, so the entry test #1 left
  behind (its scope was never disposed of before the test ended) kept the key
  `'shared'` held, and even the *first* scope of test #2 was made to wait.
  After the fix each `_AsyncScopeCoordinatorElement` owns its own
  `KeyedAccessQueues`, which dies with the element, and the tests are
  independent.

---

## Steps 3-6: the rewiring (as specified)

- **`lib/src/scope/e_async_scope/async_scope_parent.dart`** — rewritten verbatim
  from the brief. `ScopeChildEntry` deleted; the mixin now delegates to
  `ChildRegistry` and `waitForChildren` takes `timeout`/`onTimeout`.
- **`lib/src/scope/e_async_scope/async_scope_coordinator.dart`** —
  `_AsyncScopeCoordinatorElement` mixes in `AsyncScopeParent` and holds
  `final _queues = KeyedAccessQueues()` (per-instance, **not** static — binding
  controller decision 1). `AsyncScopeCoordinatorEntry` and
  `_AsyncScopeCoordinatorQueue` deleted wholesale (including the dead
  `close()`). New private static `_elementOf(BuildContext)` holds the single
  copy of the `maybeOf(...) ?? throw FlutterError(...)` lookup; the `FlutterError`
  text is byte-identical to the old one. `enter` now takes an `AccessEntry` and
  the richer `onTimeout` signature; new static `waitForChildren(context, …)`.
- **`lib/src/scope/e_async_scope/async_scope_root.dart`** — `git rm`'d.
- **`lib/src/scope/scope.dart`** — `part 'e_async_scope/async_scope_root.dart';`
  removed, `import 'e_async_scope/scope_coordination.dart';` added.
- **`lib/src/scope/e_async_scope/async_scope_core.dart`** — fields retyped to
  `AccessEntry`/`ChildEntry`; `(parent ?? asyncScopeRoot).registerChild(…)` →
  `parent?.registerChild(…)`; both timeout call sites now always pass a
  reporting callback (controller decision 2); the manual
  `future.timeout` / `try` / `on TimeoutException` / `_children.clear()` block is
  gone. `_children` no longer appears anywhere outside `scope_coordination.dart`
  (verified by grep over `lib/`).

The two `_log.d('queue for [key] created/removed')` diagnostics were **not**
re-added, as instructed.

---

## Deviations

### D-1 — `waitForChildren` timeout message keeps the widget prefix (controller decision 4)

The brief's Step 6.5 snippet reports `error` as the core built it. The core's
message is `"couldn't wait for the children to complete: <children>"`, with no
widget context, whereas the old code prefixed
`widget.toStringShort(showHashCode: true)`. Per the binding controller decision,
the callback rebuilds the exception:

```dart
exception: TimeoutException(
  '${widget.toStringShort(showHashCode: true)} ${error.message}',
  error.duration,
),
```

`prefix + ' ' + core message` reproduces the old string exactly
(`_Widget(#abc) couldn't wait for the children to complete: [...]`), and
`error.duration` carries the timeout through unchanged. The `scopeKey` path
needs no such treatment: the `AccessEntry` debug name already *is* the widget's
short string, so the core's message is self-identifying and `error` is reported
as-is.

### D-2 — test #3 rewritten: the "no coordinator" error is an *uncaught zone error*, not a framework-reported one

**This is the framework being different from the brief's assumption, not our
code being wrong. The assertion was not weakened.**

`AsyncScopeCoordinator.enter` throws `FlutterError` synchronously inside the
`async` body of `_performAsyncInit`, which `mount()` starts and *discards*
(`// ignore: discarded_futures`). The error therefore never reaches the
framework's `_debugReportException`; it becomes an unhandled error of the zone
the mount ran in. `flutter_test`'s zone `handleUncaughtError`
(`packages/flutter_test/lib/src/binding.dart:1814-1910`) does **not** park it in
`_pendingExceptionDetails` — it reports it and immediately ends the test through
`testCompletionHandler`. Consequently `tester.takeException()` can never return
it: the observed run showed the test failing at `pumpWidget` and then a second
failure at the `expect` line marked *"running a test (but after the test had
completed)"*, with `takeException()` → `null`.

Rewrite: the mount runs inside `runZonedGuarded`, whose handler catches the
error first, and the test asserts on what was caught:

```dart
expect(errors, hasLength(1));
expect(errors.single, isA<FlutterError>());
```

That is strictly stronger than the original (it also pins that there is exactly
one error). Verified against the *unmodified* `lib/` in a scratch probe: the
guarded zone receives the "No `AsyncScopeCoordinator`" `FlutterError` while
`takeException()` returns `null`.

### D-3 — tests #4/#5 rewritten: `pumpAndSettle()` cannot drive the async disposal chain

**Also framework behavior, already documented in this repo. Assertions
unchanged.**

`_performAsyncDispose` awaits `subscription.cancel()` on the `async*` stream
returned by `initAsync()`. That future only completes on the *real* event loop;
`FakeAsync` microtask flushing and elapsing never complete it. Minimal repro
with no scopo code at all (scratch probe, since deleted):

```dart
final sub = gen().asyncMap((e) {}).listen((_) {}, cancelOnError: true);
unawaited(chain(sub));               // logs 'before cancel' / 'after cancel'
for (var i = 0; i < 5; i++) { await tester.pump(); }
// → [before cancel]                 (5 pumps change nothing)
await tester.runAsync(() => Future<void>.delayed(Duration.zero));
// → [before cancel, after cancel]
```

With scopo, the probe showed the log stopping at `prepare for disposal` through
`pumpWidget` + `pumpAndSettle`, and only reaching `dispose…` / `disposed` after
a `runAsync`. `pumpAndSettle` makes this worse than an ordinary pump loop: with
no frame scheduled it performs exactly **one** pump and returns.

This is a known constraint of this codebase, already written down in
`test/async_scope_test.dart:124-133` and `test/lite_scope_test.dart:364-383`
(which carries a `_settle` helper for precisely this). Both tests now use a
local `_settle` of the same shape, interleaving real time with fake time so the
`Duration(milliseconds: 50)` `disposeDelay` (a *fake* timer, created inside the
fake zone) also fires:

```dart
for (var i = 0; i < 20 && !until(); i++) {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
  await tester.pump(const Duration(milliseconds: 10));
}
```

The assertions are untouched — still the exact
`expect(disposalOrder, ['child', 'parent'])` and
`expect(disposalOrder, ['lonely'])`, plus `expect(tester.takeException(), isNull)`.

### D-4 — the test fixture uses `super.child` instead of declaring its own `child`

The brief's fixture declares `final Widget child;` on `_TestScope`. `ProxyWidget`
(via `InheritedWidget` → `ScopeInheritedWidget`) already declares `child`, so the
analyzer flagged `overridden_fields` + `annotate_overrides`. Fixed by taking the
inherited one, whose default `ScopeInheritedWidget` sets to `_NullWidget()`:

```dart
const _TestScope({
  this.testKey,
  this.disposeLabel,
  this.disposeDelay = Duration.zero,
  super.child = const SizedBox.shrink(),
});
```

`buildOnState` still returns `widget.child` and the widget stays `const`.
No behavioral difference.

---

## Observations for Task 4 (not acted on here)

1. **`AccessEntry` / `ChildEntry` are no longer part of the package's public
   API.** `scope_coordination.dart` is `import`ed by `scope.dart`, not exported
   from `lib/scopo.dart` — which is what the design doc calls for
   (`docs/superpowers/specs/2026-07-31-async-scope-coordinator-design.md:50,181,182`:
   "из публичного API уходит"). The consequence is that the still-public
   `AsyncScopeCoordinator.enter(context, key, entry, …)` cannot be *called* by a
   package consumer any more, because they cannot name or construct an
   `AccessEntry`. It remains reachable from inside the package
   (`async_scope_core.dart`), which is its only real caller. If that is not the
   intent, Task 4 should either export the coordination library or mark `enter`
   as internal.
2. **`AsyncScopeCoordinator.waitForChildren` has no caller yet.** It is the
   replacement for what `asyncScopeRoot` existed for (an app awaiting its
   top-level scopes) and is only exercised indirectly, through the mixin, by
   test #4. Worth a documented example.
3. **Stale docs mentioning the removed API**: `CHANGELOG.md:120` mentions
   `asyncScopeRoot`; `TODO.md:7-8,16` still lists this task's items as pending.

---

# Fix round — review of `00b1460`

Commit: `fff12ad` — `fix: keep a parent scope as the wait root when a coordinator sits below it`.

`flutter analyze` → 0 issues in the root package and in `example/minimal` and
`example/scopo_demo`. `flutter test` → **54 passed** (51 → 54; the
coordinator file went from 5 tests to 8).

## Critical — a coordinator below a scope shadowed that scope as the wait root

`_registerWithParent` stopped at the nearest ancestor carrying
`AsyncScopeParent`. Since `00b1460` gave the coordinator element that mixin, a
coordinator sitting *between* two scopes captured the child, and the parent
scope stopped waiting for it. This is the package's own demo shape
(`example/scopo_demo/lib/app/app.dart:65-79` wraps `MaterialApp` in a
coordinator *inside* the root `App` scope), and the "place it above
`MaterialApp`" advice in our error text pushes users straight into it.

Fixed as directed: walk past coordinators, remember the nearest one, keep
looking for a real scope, and fall back to the remembered coordinator only when
no scope ancestor exists (`async_scope_core.dart:175-196`). The dartdoc on
`AsyncScopeParent` already described exactly this, so it needed no change.

### Before / after, all four arrangements

Measured with a scratch probe (since deleted) that mounts each tree, reads the
coordinator's `childrenCount`, then unmounts and records the order in which
`disposeAsync()` completed. The child scope carries a 50 ms `disposeDelay`, so
a parent that fails to wait finishes first and the order inverts.

| # | arrangement | metric | at `00b1460` | after the fix | expected |
| - | ----------- | ------ | ------------ | ------------- | -------- |
| 1 | `Coordinator > Scope` | coordinator `childrenCount` | 1 | 1 | 1 |
| 1 | | disposal order | `[only]` | `[only]` | `[only]` |
| 2 | `Scope(parent) > Scope(child)` | disposal order | `[child, parent]` | `[child, parent]` | `[child, parent]` |
| 3 | `Scope(parent) > Coordinator > Scope(child)` | coordinator `childrenCount` | **1** | **0** | 0 |
| 3 | | disposal order | **`[parent, child]`** | **`[child, parent]`** | `[child, parent]` |
| 4 | bare `Scope`, no coordinator | disposal order / exception | `[lonely]` / `null` | `[lonely]` / `null` | `[lonely]` / `null` |

Only row 3 changed, and it changed in the intended direction. Rows 1, 2 and 4
are unchanged, which is the point: the fallback to the coordinator and the
"registers nowhere" case both survive.

### Regression tests added (3 new, 1 of 3 failing before the `lib/` fix)

- **`a coordinator between two scopes does not take the place of the parent`** —
  arrangement 3. Asserts both halves: `coordinator.childrenCount == 0` *and*
  `disposalOrder == ['child', 'parent']`. Before the fix it failed on the first
  assertion with `Expected: <0> Actual: <1>`.
- **`a scope with no parent scope registers with the coordinator`** —
  arrangement 1, the `asyncScopeRoot` replacement, now asserted directly
  (`coordinator.childrenCount == 1`) instead of only implied.
- **`a coordinator above a parent scope leaves the pair alone`** — the old
  `a parent scope waits for the scope below it` body, kept as-is under a name
  that says what it actually covers.

`a parent scope waits for the scope below it` was retargeted to arrangement 2
(the bare `Scope(parent) > Scope(child)` pair, no coordinator anywhere), which
no test covered before.

The coordinator's element is reached through the public part of its role:

```dart
AsyncScopeParent _coordinatorOf(WidgetTester tester) =>
    tester.element(find.byType(AsyncScopeCoordinator)) as AsyncScopeParent;
```

`_AsyncScopeCoordinatorElement` stays private; `AsyncScopeParent.childrenCount`
is already public.

## Defect 1 — the shared `_elementOf` error text assumed `scopeKey`

`_elementOf` is now also the lookup for `AsyncScopeCoordinator.waitForChildren`,
where `scopeKey` is irrelevant, so the leading sentence was made neutral and the
`scopeKey` note moved to the end, where it stays true for both entry points:

```
No `AsyncScopeCoordinator`.
The `AsyncScopeCoordinator` is missing in the context. Add it to the widget
tree so that all your scopes that need it can access it. The most universal
solution is to place it above `MaterialApp`. A scope with a `scopeKey` needs
it to be coordinated with the other scopes that share the key.
```

The first line is unchanged, so the test's `contains('No `AsyncScopeCoordinator`')`
assertion pins a stable prefix.

## Defect 2 — test #3 accepted any `FlutterError`

`a scopeKey without a coordinator is an error` now also asserts
`expect(errors.single.toString(), contains('No `AsyncScopeCoordinator`'))`,
so an unrelated `FlutterError` can no longer keep it green.

## Notes

- The "place it above `MaterialApp`" advice was kept. With this fix that shape
  is correct again: a coordinator above `MaterialApp` but below a root scope no
  longer steals the root scope's children.
- No change was needed in `example/scopo_demo`; it analyzes clean and its
  arrangement is now the one covered by the new regression test.


---

## Файл: task-4-brief.md

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


---

## Файл: task-4-report.md

# Task 4 report — public surface, documentation, release notes

Commit: `e9acbca` — `docs: describe coordinator-owned scopeKey scoping`
(parent `fff12ad`). Branch `coordinator`, worktree
`/Users/user/development/my/scopo/.claude/worktrees/coordinator`.

Result: `flutter analyze` → 0 issues in the root package and in
`example/minimal` and `example/scopo_demo`. `flutter test` → **55 passed**
(54 before + 1 new nested-coordinator test). `dart doc` → **0 warnings, 0
errors**. `flutter pub publish --dry-run` → **0 warnings**.
`example/scopo_demo` builds for macOS debug.

---

## Item 1 — shrink the public surface

`AsyncScopeCoordinator.enter` → `AsyncScopeCoordinator._enter` (static method,
`lib/src/scope/e_async_scope/async_scope_coordinator.dart`).
`AsyncScopeParent.registerChild` → `AsyncScopeParent._registerChild`
(`lib/src/scope/e_async_scope/async_scope_parent.dart`). Both were public
methods whose signatures named `AccessEntry` / `ChildEntry` —
types defined in `scope_coordination.dart`, which `scope.dart` only
`import`s (not `export`s), so they were never part of the package's public
API and the methods were already uncallable from outside. Renaming just makes
that explicit.

Call sites updated in `async_scope_core.dart` (both are `part of
'../scope.dart'`, so the rename is invisible to them beyond the identifier):
`AsyncScopeCoordinator.enter(...)` → `AsyncScopeCoordinator._enter(...)`, and
`(parentScope ?? coordinator)?.registerChild(...)` →
`?._registerChild(...)`.

Kept public, as instructed: the `AsyncScopeCoordinator` widget, the static
`AsyncScopeCoordinator.waitForChildren(context, ...)`, and
`AsyncScopeParent.hasChildren` / `childrenCount` / `waitForChildren`.

Verified two ways:
- `grep -rn "AccessEntry\|ChildEntry" lib` — the only remaining hits are
  inside `scope_coordination.dart` itself (that library's own public API,
  out of scope for this item) and on now-private members/fields.
- Generated dartdoc: `AsyncScopeCoordinator-class.html` no longer mentions
  `enter` at all; `AsyncScopeParent-mixin.html`'s member-id list is exactly
  `childrenCount, debugFillProperties, hasChildren, hashCode, noSuchMethod,
  runtimeType, toDiagnosticsNode, toString, toStringShort, waitForChildren`
  plus Diagnosticable operators — no `registerChild`.

## Item 2 — `dart doc`

Added a full class-level dartdoc comment to `AsyncScopeCoordinator` (previously
just `{@category AsyncScope}`) covering: it owns the `scopeKey` queues of its
own subtree, the nearest coordinator above a scope always serves it, and it is
independently the wait root for scopes with no parent scope above them, with
`[waitForChildren]` linked. Ran:

```
dart doc --output <scratch>/dartdoc-task4
```

→ `Found 0 warnings and 0 errors.` Confirmed by inspecting the rendered HTML:
both `[AsyncScopeCoordinator]` and `[AsyncScopeParent]` self/cross-references
and `[waitForChildren]` resolved to real anchors, no dangling links.

## Item 3 — CHANGELOG

Added exactly the bullet given in the brief to the top of `## 0.10.0` (nothing
else in that section reordered). Left every historical section — including
`## 0.6.1`'s `asyncScopeRoot` entry and `## 0.6.2`'s `AsyncScopeCoordinator`
entry — untouched; confirmed via `git diff CHANGELOG.md` showing only an
insertion at the top.

## Item 4 — nested-coordinator test

Added `'a scope under nested coordinators registers with the nearest one'` to
`test/async_scope_coordinator_test.dart`, right after the existing
`'a scope with no parent scope registers with the coordinator'` arrangement
test. Pumps `Coordinator > Coordinator > _TestScope()`, reads both
coordinator elements via `tester.elementList(find.byType(AsyncScopeCoordinator))`
(document order → `[outer, inner]`) cast to `AsyncScopeParent`, and asserts
`inner.childrenCount == 1` / `outer.childrenCount == 0`. Passes; also verified
it fails without the fix by temporarily reading only `.first` — not needed
here since the underlying behavior already shipped in task 3, this test just
closes the coverage gap the reviewer flagged.

## README — `scopeKey` section / `waitForChildren`

Added two paragraphs after the existing `AsyncScopeCoordinator(child:
MaterialApp(...))` snippet: one on coordinators scoping `scopeKey` to their
own subtree (nearest wins), one on `AsyncScopeCoordinator.waitForChildren
(context)` being the way to await top-level scopes — the direct replacement
for the removed `asyncScopeRoot`.

Both Dart snippets (`AsyncScopeCoordinator(child: MaterialApp(home:
HomeScreen()))` and `await AsyncScopeCoordinator.waitForChildren(context);`)
were verified by compiling them in a throwaway package outside the repo
(`<scratch>/readme_check`, `scopo` pulled in via a `path:` dependency pointing
at this worktree) — `flutter analyze` on that package reported "No issues
found!". The scratch package was deleted afterward; it never touched the
repo.

## TODO.md

Removed the two items closed by this work: the `waitForChildren`/
`asyncScopeRoot` redesign line under the top-level list, and the
`AsyncScopeCoordinator: глобальный static _queues без очистки...` line under
"Известные проблемы (0.10.x)". Left the unrelated test-coverage line that
merely *mentions* `AsyncScopeCoordinator` in passing (`e_async_scope
(особенно AsyncScopeCoordinator)`), since that's about missing tests in
general, not the bug this task fixed — and task 3/4 together did add
`AsyncScopeCoordinator` test coverage, but the line covers the whole
`e_async_scope` group, not just that class.

---

## Full verification

| Check | Result |
| ----- | ------ |
| `flutter analyze` (root) | 0 issues |
| `flutter analyze` (`example/minimal`) | 0 issues |
| `flutter analyze` (`example/scopo_demo`) | 0 issues |
| `flutter test` (root) | 55 passed |
| `dart format` on the 4 files this task touched in `lib`/`test` | 0 changes |
| `dart doc --output <scratch>/dartdoc-task4` | 0 warnings, 0 errors |
| `flutter pub publish --dry-run` | 0 warnings |
| `cd example/scopo_demo && flutter build macos --debug` | succeeds (`Built .../scopo_demo.app`) |
| `grep -rn "asyncScopeRoot\|AsyncScopeRoot\|AsyncScopeCoordinatorEntry\|ScopeChildEntry" lib test example` | empty |
| `grep -c "package:flutter" lib/src/scope/e_async_scope/scope_coordination.dart` | `0` |

### Note on `dart format` scope

Repo-wide `dart format --set-exit-if-changed .` reports 6 files it would
reformat, all in `example/scopo_demo/lib/**` (e.g. `box.dart`,
`code_block.dart`). This is **pre-existing** — confirmed by stashing this
task's changes and re-running the same command against `fff12ad` (the task 3
tip): identical 6 files, identical diffs (a Dart-formatter "tall style" line-
break difference, e.g. `color:\n    borderColor ??` vs `color: borderColor
??`). None of these files were touched by task 4, so they're left alone;
formatting them would mix an unrelated cosmetic change into a docs commit.
The 4 files this task actually edited under `lib/`/`test/` format clean.

### Note on the macOS build command

`flutter build macos --debug` triggered a one-time "Adding Swift Package
Manager integration" migration that modified
`example/scopo_demo/macos/Podfile.lock`,
`Runner.xcodeproj/project.pbxproj`, and `Runner.xcscheme`. These were reverted
with `git checkout --` after the build succeeded, since they're a local
tooling side effect unrelated to this task, not something requested by the
brief.

## Concerns

None blocking. The pre-existing `dart format` drift in `example/scopo_demo`
(noted above) is worth a follow-up if the team wants the whole repo
format-clean under the current Dart SDK, but it predates this task and isn't
part of its scope.

