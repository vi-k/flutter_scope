import 'package:flutter_test/flutter_test.dart';
import 'package:scopo/scopo.dart';

void main() {
  group('ScopeConfig.reset', () {
    // The switches are global and outlive the test that changed them, so a
    // test that forgets to put one back hands the next one a different
    // package. Every suite of this package used to save and restore them by
    // hand, which is a convention rather than a guarantee.
    test('puts every switch back where it started', () {
      addTearDown(ScopeConfig.reset);

      ScopeConfig.pauseAfterInitializationEnabled = false;
      ScopeConfig.defaultScopeKeysTimeout = null;
      ScopeConfig.defaultWaitForChildrenTimeout = Duration.zero;
      ScopeConfig.defaultDisposeAsyncTimeout = const Duration(days: 1);
      ScopeConfig.defaultInitCancellationTimeout = null;

      ScopeConfig.reset();

      expect(ScopeConfig.pauseAfterInitializationEnabled, isTrue);
      expect(ScopeConfig.defaultScopeKeysTimeout, const Duration(seconds: 3));
      expect(
        ScopeConfig.defaultWaitForChildrenTimeout,
        const Duration(seconds: 3),
      );
      expect(
        ScopeConfig.defaultDisposeAsyncTimeout,
        const Duration(seconds: 3),
      );
      expect(
        ScopeConfig.defaultInitCancellationTimeout,
        const Duration(seconds: 3),
      );
    });

    test('leaves the logger alone', () {
      final level = ScopeConfig.logger.level;
      addTearDown(() => ScopeConfig.logger.level = level);

      ScopeConfig.logger.level = ScopeLogLevel.debug;
      ScopeConfig.reset();

      expect(
        ScopeConfig.logger.level,
        ScopeLogLevel.debug,
        reason: 'the logger is an object with publishers and a transformer of '
            'its own, not a switch this can put back',
      );
    });
  });
}
