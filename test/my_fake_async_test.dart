import 'dart:async';

import 'package:test/test.dart';

import 'utils/my_fake_async.dart';

/// The bookkeeping of the fake async helper itself.
///
/// It is a test helper, and testing a test helper is worth it only where
/// getting it wrong is silent: every count it keeps is read by
/// `waitFuture`, which decides from them whether there is any work left to
/// run. A count that is too high does not fail — it hangs, or it reports "No
/// more timers" about a timer nobody is waiting for.
void main() {
  group('MyFakeAsync', () {
    test('forgets a timer that was cancelled', () {
      myFakeAsync((async) {
        final timer = Timer(const Duration(seconds: 1), () {});
        expect(async.nonPeriodicTimerCount, 1);

        timer.cancel();

        expect(
          async.nonPeriodicTimerCount,
          0,
          reason: 'a cancelled timer is not pending; the count is what '
              'waitFuture reads to decide there is nothing left to run',
        );
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('forgets a timer that fired', () {
      myFakeAsync((async) {
        var fired = false;
        Timer(const Duration(seconds: 1), () => fired = true);

        async.elapse(const Duration(seconds: 1));

        expect(fired, isTrue);
        expect(async.nonPeriodicTimerCount, 0);
      });
    });

    // The shape the wrapper exists for, and the one a bounded wait produces:
    // a race where the timer loses and is cancelled in a `finally`.
    test('a bounded wait whose timer loses leaves nothing pending', () {
      myFakeAsync((async) {
        final completer = Completer<String>();
        final timer = Timer(const Duration(seconds: 3), () {});
        completer.complete('done');

        final result = async.waitFuture(completer.future);
        timer.cancel();

        expect(result.result, 'done');
        expect(async.nonPeriodicTimerCount, 0);
      });
    });
  });
}
