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
}
