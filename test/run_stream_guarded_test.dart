import 'package:flutter_test/flutter_test.dart';
import 'package:scopo/scopo.dart';
import 'package:scopo/src/utils/stream/run_stream_guarded.dart';

void main() {
  group('runStreamGuarded', () {
    test('does not build a sub-logger for every call', () async {
      // Warm the one logger the function keeps, so what is counted below is
      // the steady state rather than the very first call.
      await runStreamGuarded(Stream<int>.empty, _ignore).drain<Object?>();

      ScopeConfig.logger.pruneSubloggers();
      final before = ScopeConfig.logger.subLoggersCount;

      // Held on purpose: the root keeps its sub-loggers weakly, and a count
      // taken over collectable objects would prove nothing.
      final streams = [
        for (var i = 0; i < 5; i++)
          runStreamGuarded(Stream<int>.empty, _ignore, debugName: 'dep$i'),
      ];
      for (final stream in streams) {
        await stream.drain<Object?>();
      }

      ScopeConfig.logger.pruneSubloggers();
      expect(
        ScopeConfig.logger.subLoggersCount,
        before,
        reason: 'this runs twice for every dependency of every scope',
      );
      expect(streams, hasLength(5));
    });

    // A factory that throws before there is a stream at all has nowhere to
    // raise: the caller is holding a `Stream`, not a future. So the failure
    // is handed back as the stream, and a caller that subscribes hears it
    // through `onError` like any other. Without the guard it is thrown at
    // whoever called `runStreamGuarded` — one line up from where a scope
    // would have caught it.
    test('hands back a failing factory as a stream, not a throw', () async {
      final failure = StateError('the factory fell over');
      final Stream<int> stream;

      // Deliberately outside `expect`: the point is that this line does not
      // throw at all.
      stream = runStreamGuarded<int>(() => throw failure, _ignore);

      await expectLater(stream, emitsError(same(failure)));
    });

    test('tells its callers apart in the message', () async {
      final lines = <String>[];
      final logger = ScopeConfig.logger;
      final level = logger.level;
      final publisher = logger[ScopeLogLevel.verbose].publisher;

      addTearDown(() {
        logger.level = level;
        logger[ScopeLogLevel.verbose].publisher = publisher;
      });

      logger.level = ScopeLogLevel.verbose;
      logger[ScopeLogLevel.verbose].publisher = ScopeLogFormatter<String>(
        format: (entry) => '${entry.message}',
        output: lines.add,
      );

      await runStreamGuarded(Stream<int>.empty, _ignore, debugName: 'db')
          .drain<Object?>();

      expect(lines, isNotEmpty);
      expect(lines.every((line) => line.contains('(db)')), isTrue);
    });
  });
}

void _ignore(Object error, StackTrace stackTrace) {}
