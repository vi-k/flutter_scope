import 'dart:async';
import 'dart:collection';

import 'package:fake_async/fake_async.dart';

T myFakeAsync<T>(
  T Function(MyFakeAsync async) callback, {
  DateTime? initialTime,
}) =>
    MyFakeAsync(initialTime: initialTime).run(callback);

final class MyFutureResult<T extends Object?> {
  var _isDone = false;

  T? _result;

  (Object, StackTrace)? _error;

  MyFutureResult();

  bool get isDone => _isDone;

  bool get isFailed => _error != null;

  T get result {
    if (!_isDone) {
      throw StateError('No result');
    }

    if (_error case final error?) {
      Error.throwWithStackTrace(error.$1, error.$2);
    }

    return _result as T;
  }

  Object? get resultOrError =>
      _isDone ? (_error?.$1 ?? _result) : StateError('No result');

  void complete(T value) {
    _result = value;
    _isDone = true;
  }

  void completeError(Object error, StackTrace stackTrace) {
    _error = (error, stackTrace);
    _isDone = true;
  }

  @override
  String toString() => '$MyFutureResult($resultOrError)';
}

final class MyFakeTimer {
  final Duration duration;
  final Duration nextCall;

  MyFakeTimer(FakeAsync fakeAsync, this.duration)
      : nextCall = fakeAsync.elapsed + duration;
}

final class MyFakeAsync {
  final FakeAsync _fakeAsync;
  final List<MyFakeTimer> _pendingTimers = [];

  MyFakeAsync({DateTime? initialTime})
      : _fakeAsync = FakeAsync(initialTime: initialTime);

  /// See [FakeAsync.microtaskCount].
  int get microtaskCount => _fakeAsync.microtaskCount;

  /// See [FakeAsync.nonPeriodicTimerCount].
  int get nonPeriodicTimerCount => _pendingTimers.length;

  /// See [FakeAsync.periodicTimerCount].
  int get periodicTimerCount => _fakeAsync.periodicTimerCount;

  /// [pendingTimers] != [FakeAsync.pendingTimers]
  ///
  /// See also [FakeAsync.pendingTimers].
  List<MyFakeTimer> get pendingTimers => UnmodifiableListView(_pendingTimers);

  /// See [FakeAsync.elapsed].
  Duration get elapsed => _fakeAsync.elapsed;

  /// See also [FakeAsync.run].
  T run<T>(T Function(MyFakeAsync myFakeAsync) callback) => _fakeAsync.run(
        (fakeAsync) => runZoned(
          () => callback(this),
          zoneValues: {'myFakeAsync': this},
          zoneSpecification: ZoneSpecification(
            createTimer: (self, parent, zone, duration, f) {
              final myFakeTimer = MyFakeTimer(fakeAsync, duration);
              _pendingTimers.add(myFakeTimer);

              return parent.createTimer(zone, duration, () {
                _pendingTimers.remove(myFakeTimer);
                f();
              });
            },
          ),
        ),
      );

  /// See [FakeAsync.elapse].
  void elapse(Duration duration) {
    _fakeAsync.elapse(duration);
  }

  /// See [FakeAsync.elapseBlocking].
  void elapseBlocking(Duration duration) {
    _fakeAsync.elapseBlocking(duration);
  }

  /// See [FakeAsync.flushMicrotasks].
  void flushMicrotasks() => _fakeAsync.flushMicrotasks();

  bool flushNextTimer() {
    final nextTimer = _nextTimer();
    if (nextTimer == null) {
      return false;
    }

    _fakeAsync.elapse(nextTimer.nextCall - _fakeAsync.elapsed);

    return true;
  }

  MyFutureResult<T> waitFuture<T extends Object?>(Future<T> future) {
    final result = MyFutureResult<T>();

    // ignore: discarded_futures
    future.then(result.complete, onError: result.completeError);
    flushMicrotasks();
    _waitFutureResult<T>(result);

    return result;
  }

  void _waitFutureResult<T>(MyFutureResult<T> result) {
    while (!result.isDone) {
      if (!flushNextTimer() && !result.isDone) {
        throw StateError(
          'No more timers'
          ' (microtaskCount: $microtaskCount'
          ', nonPeriodicTimerCount: $nonPeriodicTimerCount'
          ', periodicTimerCount: $periodicTimerCount)',
        );
      }
    }
  }

  MyFakeTimer? _nextTimer() {
    if (_pendingTimers.isEmpty) {
      return null;
    }

    MyFakeTimer? timer;
    for (final t in _pendingTimers) {
      if (timer == null || t.nextCall < timer.nextCall) {
        timer = t;
      }
    }

    return timer;
  }
}
