import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scopo/scopo.dart';
import 'package:scopo/src/utils/stream/run_stream_guarded.dart';

import 'utils/observer.dart';

void main() {
  group('runStreamGuarded', () {
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

    test(
        'reports the steps of a cancellation through onTrace, one caller '
        'told apart from another by debugName', () async {
      final observer = RecordingObserver(trace: true);
      ScopeConfig.observer = observer;
      addTearDown(() => ScopeConfig.observer = null);

      final source = StreamController<int>();
      addTearDown(source.close);

      final guarded = runStreamGuarded(
        () => source.stream,
        _ignore,
        debugName: 'db',
        observable: const _FakeObservable(),
      );

      final received = <int>[];
      final subscription = guarded.listen(received.add);

      source.add(1);
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      expect(received, [1]);
      expect(observer.events, [
        'trace _FakeObservable (db) cancel',
        'trace _FakeObservable (db) await subscription.cancel()',
        'trace _FakeObservable (db) await subscription.cancel() done',
        'trace _FakeObservable (db) cancel done',
      ]);
    });

    test(
        'reports nothing through onTrace when the observer does not record '
        'traces', () async {
      final observer = RecordingObserver();
      ScopeConfig.observer = observer;
      addTearDown(() => ScopeConfig.observer = null);

      final source = StreamController<int>();
      addTearDown(source.close);

      final guarded = runStreamGuarded(
        () => source.stream,
        _ignore,
        debugName: 'db',
        observable: const _FakeObservable(),
      );

      final subscription = guarded.listen((_) {});
      await subscription.cancel();

      expect(observer.events, isEmpty);
    });
  });
}

void _ignore(Object error, StackTrace stackTrace) {}

/// A [ScopeObservable] with no scope behind it, for a test that calls
/// [runStreamGuarded] directly rather than through a dependency.
final class _FakeObservable implements ScopeObservable {
  const _FakeObservable();

  @override
  String get debugLabel => '_FakeObservable';
}
