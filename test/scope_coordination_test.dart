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

    test('a timeout reports and gives up on the children left', () {
      fakeAsync((async) {
        final registry = ChildRegistry()..registerChild('slow');
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

    test('a timeout drops only the children the wait was awaiting', () {
      fakeAsync((async) {
        final registry = ChildRegistry()..registerChild('slow');
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

        // Registered while the wait is already running, so it is excluded from
        // that wait by design -- but it never unregistered, so the registry
        // must still know about it once the wait has given up.
        final laterChild = registry.registerChild('later');

        async.elapse(const Duration(seconds: 4));

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
        async.elapse(Duration.zero);

        expect(
          secondDone,
          isFalse,
          reason: 'a later wait must still await the child that is live',
        );

        laterChild.unregister();
        async.elapse(Duration.zero);

        expect(secondDone, isTrue);
        expect(registry.hasChildren, isFalse);
      });
    });

    test('an onTimeout that throws still gives up on the children left', () {
      fakeAsync((async) {
        final registry = ChildRegistry()..registerChild('slow');
        Object? escaped;

        unawaited(
          registry
              .waitForChildren(
            timeout: const Duration(seconds: 3),
            onTimeout: (_, __) => throw StateError('reporting failed'),
          )
              .catchError((Object error) {
            escaped = error;
          }),
        );

        async.elapse(const Duration(seconds: 4));

        expect(escaped, isA<StateError>(), reason: 'the failure is not hidden');
        expect(
          registry.hasChildren,
          isFalse,
          reason: 'a reporter that throws must not leave the registry holding '
              'entries the expired wait already gave up on',
        );
      });
    });
  });
}
