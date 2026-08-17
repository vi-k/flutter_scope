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

  test('transformer rewrites and drops logs', () {
    final out = <String>[];
    ScopeConfig.logger.level = ScopeLogLevel.debug;
    ScopeConfig.logger[ScopeLogLevel.debug].publisher = ScopeLogFormatter(
      format: (log) => '${log.path}|${log.message}',
      output: out.add,
    );

    // Sub-logger must inherit the transformer.
    final sub = ScopeConfig.logger.withAddedName('child');

    ScopeLog? drop(ScopeLog log) =>
        (log.message ?? '').contains('noisy') ? null : log;

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
