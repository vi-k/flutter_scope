import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scopo/scopo.dart';

void main() {
  late int originalLevel;
  late ScopeLogTransformer? originalTransformer;
  late ScopeLogPublisher originalDebugPublisher;

  setUp(() {
    originalLevel = ScopeConfig.logger.level;
    originalTransformer = ScopeConfig.logger.transformer;
    originalDebugPublisher = ScopeConfig.logger[ScopeLogLevel.debug].publisher;
  });

  tearDown(() {
    ScopeConfig.logger.level = originalLevel;
    ScopeConfig.logger.transformer = originalTransformer;
    ScopeConfig.logger[ScopeLogLevel.debug].publisher = originalDebugPublisher;
  });

  // The threshold is the first thing every log event meets, and the package
  // ships with it set to `off`. Nothing named it: the suite reached the logger
  // only through code that had already turned it up.
  group('the level', () {
    test('keeps everything out while it is off', () {
      final out = _captureEveryLevel();
      ScopeConfig.logger.level = ScopeLogLevel.off;

      _writeOneOfEach();

      expect(
        out,
        isEmpty,
        reason: 'off is what the package ships with, and it is the whole '
            'reason a release build says nothing',
      );
    });

    test('lets its own level through and keeps the quieter ones out', () {
      final out = _captureEveryLevel();
      ScopeConfig.logger.level = ScopeLogLevel.info;

      _writeOneOfEach();

      expect(
        out,
        ['info', 'error'],
        reason: 'a threshold is a floor: what is louder than it passes, what '
            'is quieter does not',
      );
    });

    test('is read from the root by every sub-logger', () {
      final out = <String>[];
      final level = ScopeConfig.logger[ScopeLogLevel.debug];
      final publisher = level.publisher;
      addTearDown(() => level.publisher = publisher);
      level.publisher = ScopeLogFormatter<String>(
        format: (entry) => entry.path,
        output: out.add,
      );

      // Made before the threshold is set, the way the package makes its own:
      // every scope builds its sub-logger when it is constructed.
      final sub = ScopeConfig.logger.withAddedName('child');

      ScopeConfig.logger.level = ScopeLogLevel.off;
      sub.d('quiet');

      expect(out, isEmpty, reason: 'the root decides for the whole tree');

      ScopeConfig.logger.level = ScopeLogLevel.debug;
      sub.d('loud');

      expect(out, ['scopo | child']);
    });
  });

  // A log always has a message, whatever was passed for it: it is held as a
  // `LazyString`, which renders anything that is not a `String` -- `null`
  // included -- through `toString()`. `ScopeLog.message` used to be declared
  // `String?` all the same, which left a formatter written with `?? '<none>'` a
  // branch that never runs. Two such branches were in this very suite.
  test('a log written with no message reads as null', () {
    final out = <String>[];
    final level = ScopeConfig.logger[ScopeLogLevel.debug];
    final publisher = level.publisher;
    addTearDown(() => level.publisher = publisher);
    level.publisher = ScopeLogFormatter<String>(
      format: (entry) => entry.message,
      output: out.add,
    );
    ScopeConfig.logger.level = ScopeLogLevel.debug;

    ScopeConfig.logger.d(null);

    expect(
      out,
      ['null'],
      reason: 'the fallback of a LazyString is the string, not the absence of '
          'one',
    );
  });

  test('transformer rewrites and drops logs', () {
    final out = <String>[];
    ScopeConfig.logger.level = ScopeLogLevel.debug;
    ScopeConfig.logger[ScopeLogLevel.debug].publisher = ScopeLogFormatter(
      format: (log) => '${log.path}|${log.message}',
      output: out.add,
    );

    // Sub-logger must inherit the transformer.
    final sub = ScopeConfig.logger.withAddedName('child');

    ScopeLog? drop(ScopeLog log) => log.message.contains('noisy') ? null : log;

    expect(drop, isA<ScopeLogTransformer>());
    ScopeConfig.logger.transformer = drop;

    ScopeConfig.logger.d('kept');
    ScopeConfig.logger.d('noisy one');
    sub.d('kept from sub');
    sub.d('noisy from sub');

    expect(out, ['scopo|kept', 'scopo | child|kept from sub']);

    ScopeConfig.logger.transformer = null;
    ScopeConfig.logger.d('noisy again');
    expect(out.last, 'scopo|noisy again');
  });

  // The publisher is the one piece of the logging path a consumer writes, and
  // a throwing one used to come back out of the logging call -- which, inside
  // this package, meant out of a build or out of a teardown. The package now
  // ships a handler on its logger, so a failure of the logging path is
  // reported and the path that was logging goes on.
  group('a publisher that throws', () {
    test('is reported rather than thrown out of the logging call', () {
      final reported = _captureReports();
      _publishByThrowing();
      ScopeConfig.logger.level = ScopeLogLevel.debug;

      expect(
        () => ScopeConfig.logger.d('a line nobody can publish'),
        returnsNormally,
      );
      expect(reported, hasLength(1));
      expect(reported.single.library, 'scopo');
      expect(reported.single.exception, isA<StateError>());
    });

    // `AsyncScope` itself no longer writes a line to this logger at all --
    // its lifecycle reports through `ScopeConfig.observer` now, which has
    // the equivalent protection of its own (`scope_observer_test.dart`,
    // "a throwing observer does not reach the scope"). What is still true,
    // and still worth a scope-shaped test rather than the direct call
    // above: a publisher wired to fail cannot reach into a scope's build or
    // teardown, whether or not that scope happens to log anything.
    testWidgets('does not take the scope down with it', (tester) async {
      _publishByThrowing();
      ScopeConfig.logger.level = ScopeLogLevel.debug;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: AsyncScope(
            initScope: (context) async* {
              yield AsyncScopeReady();
            },
            disposeScope: () {},
            progressBuilder: (context, progress) => const Text('initializing'),
            errorBuilder: (context, error, stackTrace, progress) =>
                const Text('error'),
            builder: (context) => const Text('ready'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('ready'),
        findsOneWidget,
        reason: 'the scope built its ready branch',
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason: 'the teardown survives the broken publisher the same way',
      );
    });

    test('comes back out of the call once the handler is cleared', () {
      _publishByThrowing();
      ScopeConfig.logger.level = ScopeLogLevel.debug;

      final handler = ScopeConfig.logger.onError;
      addTearDown(() => ScopeConfig.logger.onError = handler);
      ScopeConfig.logger.onError = null;

      expect(
        () => ScopeConfig.logger.d('a line nobody can publish'),
        throwsStateError,
        reason: 'clearing the handler is the way back to the old behaviour, '
            'and it has to keep working',
      );
    });
  });
}

/// Every level of the package logger, written into one list by level name.
///
/// The publishers are put back by a tear-down, so a test that fails before its
/// own cleanup does not hand the next one a logger writing into a dead list.
List<String> _captureEveryLevel() {
  final out = <String>[];

  for (final level in const [
    ScopeLogLevel.verbose,
    ScopeLogLevel.debug,
    ScopeLogLevel.info,
    ScopeLogLevel.error,
  ]) {
    final levelLogger = ScopeConfig.logger[level];
    final publisher = levelLogger.publisher;
    addTearDown(() => levelLogger.publisher = publisher);
    levelLogger.publisher = ScopeLogFormatter<String>(
      format: (entry) => entry.levelName,
      output: out.add,
    );
  }

  return out;
}

void _writeOneOfEach() {
  ScopeConfig.logger
    ..v('verbose')
    ..d('debug')
    ..i('info')
    ..e('error');
}

/// Makes every level publish by throwing, and puts the publishers back after.
void _publishByThrowing() {
  for (final level in const [
    ScopeLogLevel.verbose,
    ScopeLogLevel.debug,
    ScopeLogLevel.info,
    ScopeLogLevel.error,
  ]) {
    final levelLogger = ScopeConfig.logger[level];
    final publisher = levelLogger.publisher;
    addTearDown(() => levelLogger.publisher = publisher);
    levelLogger.publisher = const _ThrowingPublisher();
  }
}

/// A publisher of the only kind that matters here: one that fails.
final class _ThrowingPublisher implements ScopeLogPublisher {
  const _ThrowingPublisher();

  @override
  void publish(ScopeLog log) => throw StateError('publisher failed');
}

/// Collects what the package reports, and restores the handler after.
List<FlutterErrorDetails> _captureReports() {
  final reported = <FlutterErrorDetails>[];
  final previous = FlutterError.onError;
  addTearDown(() => FlutterError.onError = previous);
  FlutterError.onError = reported.add;

  return reported;
}
