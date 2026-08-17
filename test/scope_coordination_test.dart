import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:scopo/src/scope/async_scope/scope_coordination.dart';
import 'package:test/test.dart';

/// Lets pending microtasks and zero-duration timers run.
Future<void> pumpEvents() => Future<void>.delayed(Duration.zero);

/// How long the timeouts below are given, in real time.
///
/// Real, because the limits of both waits are timers of the root zone, and a
/// fake clock cannot reach those -- which is the whole point of putting them
/// there. Short, because every test that waits one out pays for it.
const _limit = Duration(milliseconds: 20);

/// Waits past [_limit] in real time.
Future<void> waitOutTheLimit() => Future<void>.delayed(_limit * 5);

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

    test('a timeout reports and lets the entry in anyway', () async {
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
              timeout: _limit,
              onTimeout: (error, _) => reported = error,
            )
            .then((_) => secondIsIn = true),
      );

      await pumpEvents();
      expect(secondIsIn, isFalse);

      await waitOutTheLimit();
      expect(secondIsIn, isTrue);
      expect(reported, isNotNull);
      expect(reported!.message, contains('second'));
      expect(reported!.message, contains('key'));

      expect(
        second.isCompleted,
        isFalse,
        reason: 'being let in is not leaving',
      );
      expect(
        queues.length,
        1,
        reason: 'a timed-out entry keeps its slot, so exit() is still'
            ' required',
      );
    });

    // The limit is a timer of the root zone, and this is what says so. A hang
    // of the kind these limits exist for outlives frames, and a scope is
    // usually taken down between them: a timer of the zone the wait runs in
    // would still be pending when the tree is gone, which is what
    // `flutter_test` ends a test on -- somebody's own widget test failing for
    // no reason of theirs. `Future.timeout` put the timer exactly there.
    test('the limit does not run on the clock of the zone that waits', () {
      fakeAsync((async) {
        final queues = KeyedAccessQueues();
        var expired = false;

        unawaited(queues.enter('key', AccessEntry('first')));
        unawaited(
          queues.enter(
            'key',
            AccessEntry('second'),
            timeout: const Duration(seconds: 3),
            onTimeout: (_, __) => expired = true,
          ),
        );

        async.elapse(const Duration(minutes: 1));

        expect(
          expired,
          isFalse,
          reason: 'a fake clock reaches no timer of the root zone, and this '
              'limit is one',
        );
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
  });

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

    // A scope can be handed the same entry to release twice -- its disposal
    // clears the field, but an element that stays mounted through `close()`
    // can still be moved in the tree and try to re-register. Raising on the
    // second release would turn that into a crash for a caller with nothing
    // left to fix, and in release builds -- where the asserts are gone --
    // into `Future already completed`.
    test('unregistering a second time is a no-op', () async {
      final registry = ChildRegistry();
      final child = registry.registerChild('child');
      expect(registry.hasChildren, isTrue);

      child.unregister();
      expect(registry.hasChildren, isFalse);

      child.unregister();

      var done = false;
      unawaited(registry.waitForChildren().then((_) => done = true));
      await pumpEvents();

      expect(done, isTrue);
      expect(registry.childrenCount, 0);
    });

    test('a timeout reports and gives up on the children left', () async {
      final registry = ChildRegistry()..registerChild('slow');
      TimeoutException? reported;

      var done = false;
      unawaited(
        registry
            .waitForChildren(
              timeout: _limit,
              onTimeout: (error, _) => reported = error,
            )
            .then((_) => done = true),
      );

      await waitOutTheLimit();

      expect(done, isTrue, reason: 'the wait must not hang');
      expect(reported, isNotNull);
      expect(reported!.message, contains('slow'));
      expect(
        registry.hasChildren,
        isFalse,
        reason: 'the children left behind are dropped',
      );
    });

    // The same question as for the queue above, and the same answer: the limit
    // of this wait is a timer of the root zone, so a fake clock cannot reach
    // it. Both waits used `Future.timeout`, and both had to change.
    test('the limit does not run on the clock of the zone that waits', () {
      fakeAsync((async) {
        final registry = ChildRegistry()..registerChild('slow');
        var expired = false;

        unawaited(
          registry.waitForChildren(
            timeout: const Duration(seconds: 3),
            onTimeout: (_, __) => expired = true,
          ),
        );

        async.elapse(const Duration(minutes: 1));

        expect(
          expired,
          isFalse,
          reason: 'a fake clock reaches no timer of the root zone, and this '
              'limit is one',
        );
      });
    });

    test('a timeout drops only the children the wait was awaiting', () async {
      final registry = ChildRegistry()..registerChild('slow');
      TimeoutException? reported;

      var done = false;
      unawaited(
        registry
            .waitForChildren(
              timeout: _limit,
              onTimeout: (error, _) => reported = error,
            )
            .then((_) => done = true),
      );

      // Registered while the wait is already running, so it is excluded from
      // that wait by design -- but it never unregistered, so the registry
      // must still know about it once the wait has given up.
      final laterChild = registry.registerChild('later');

      await waitOutTheLimit();

      expect(done, isTrue, reason: 'the wait must not hang');
      expect(reported, isNotNull);
      expect(
        reported!.message,
        contains('slow'),
        reason: 'the child that held the wait up is named',
      );
      expect(
        reported!.message,
        isNot(contains('later')),
        reason: 'a child this wait never awaited did not hold it up',
      );
      expect(
        registry.childrenCount,
        1,
        reason: 'only the children of the expired wait are dropped',
      );

      var secondDone = false;
      unawaited(registry.waitForChildren().then((_) => secondDone = true));
      await pumpEvents();

      expect(
        secondDone,
        isFalse,
        reason: 'a later wait must still await the child that is live',
      );

      laterChild.unregister();
      await pumpEvents();

      expect(secondDone, isTrue);
      expect(registry.hasChildren, isFalse);
    });

    test('an onTimeout that throws still gives up on the children left',
        () async {
      final registry = ChildRegistry()..registerChild('slow');
      Object? escaped;

      unawaited(
        registry
            .waitForChildren(
          timeout: _limit,
          onTimeout: (_, __) => throw StateError('reporting failed'),
        )
            .catchError((Object error) {
          escaped = error;
        }),
      );

      await waitOutTheLimit();

      expect(escaped, isA<StateError>(), reason: 'the failure is not hidden');
      expect(
        registry.hasChildren,
        isFalse,
        reason: 'a reporter that throws must not leave the registry holding '
            'entries the expired wait already gave up on',
      );
    });
  });
}
