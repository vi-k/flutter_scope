import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scopo/scopo.dart';

import 'utils/settle.dart';

void main() {
  // `null` is documented in four places as "wait as long as it takes", and it
  // is the one branch of the four bounded waits that had never been executed:
  // the switches were set here, reset on the next line, and no scope ever ran
  // while one of them was `null`. A teardown that stops waiting is invisible
  // from the outside -- everything is released, just too early -- so the
  // effect asserted below is the one thing that shows it: the key of the
  // scope is not handed over until its own teardown has actually finished.
  group('a removed limit', () {
    testWidgets('really waits for a teardown that takes its time',
        (tester) async {
      addTearDown(ScopeConfig.reset);
      ScopeConfig.defaultDisposeScopeTimeout = null;

      final log = <String>[];
      final slow = Completer<void>();

      Widget build({required bool first, required bool second}) =>
          Directionality(
            textDirection: TextDirection.ltr,
            child: AsyncScopeCoordinator(
              child: Column(
                children: [
                  if (first)
                    AsyncScope(
                      scopeKey: 'shared',
                      initScope: (context, ctx) async {},
                      disposeScope: () async {
                        await slow.future;
                        log.add('disposed');
                      },
                      progressBuilder: (context, progress) =>
                          const SizedBox.shrink(),
                      errorBuilder: (context, error, stackTrace, progress) =>
                          Text('$error'),
                      builder: (context) => const SizedBox.shrink(),
                    ),
                  if (second)
                    AsyncScope(
                      scopeKey: 'shared',
                      scopeKeyTimeout: const Duration(days: 1),
                      initScope: (context, ctx) async {},
                      disposeScope: () {},
                      progressBuilder: (context, progress) =>
                          const SizedBox.shrink(),
                      errorBuilder: (context, error, stackTrace, progress) =>
                          Text('$error'),
                      builder: (context) {
                        log.add('second is in');

                        return const SizedBox.shrink();
                      },
                    ),
                ],
              ),
            ),
          );

      await tester.pumpWidget(build(first: true, second: false));
      await tester.pumpAndSettle();

      await tester.pumpWidget(build(first: false, second: false));
      await settle(tester, until: () => false, rounds: 2);

      await tester.pumpWidget(build(first: false, second: true));
      await settle(tester, until: () => false, rounds: 5);

      expect(
        log,
        isEmpty,
        reason: 'the first teardown has not finished, and with no limit on it '
            'there is nothing else that could let the second scope in',
      );

      slow.complete();
      await settle(tester, until: () => log.length > 1);

      expect(
        log,
        ['disposed', 'second is in'],
        reason: 'the wait ended because the teardown ended, and in that order',
      );

      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: AsyncScopeCoordinator(child: SizedBox.shrink()),
        ),
      );
      await settle(tester, until: () => false, rounds: 5);
    });
  });

  group('ScopeConfig.reset', () {
    // The switches are global and outlive the test that changed them, so a
    // test that forgets to put one back hands the next one a different
    // package. Every suite of this package used to save and restore them by
    // hand, which is a convention rather than a guarantee.
    test('puts every switch back where it started', () {
      addTearDown(ScopeConfig.reset);

      ScopeConfig.pauseAfterInitializationEnabled = false;
      ScopeConfig.defaultScopeKeyTimeout = null;
      ScopeConfig.defaultWaitForChildrenTimeout = Duration.zero;
      ScopeConfig.defaultDisposeScopeTimeout = const Duration(days: 1);
      ScopeConfig.defaultInitCancellationTimeout = null;

      ScopeConfig.reset();

      expect(ScopeConfig.pauseAfterInitializationEnabled, isTrue);
      expect(ScopeConfig.defaultScopeKeyTimeout, const Duration(seconds: 3));
      expect(
        ScopeConfig.defaultWaitForChildrenTimeout,
        const Duration(seconds: 3),
      );
      expect(
        ScopeConfig.defaultDisposeScopeTimeout,
        const Duration(seconds: 3),
      );
      expect(
        ScopeConfig.defaultInitCancellationTimeout,
        const Duration(seconds: 3),
      );
    });
  });
}
