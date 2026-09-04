// ignore_for_file: discarded_futures

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:scopo/scopo.dart';
import 'package:test/test.dart';

/// A container whose single dependency takes something and then goes wrong.
///
/// This is the shape the contract is about: an initializer that has already
/// acquired a resource and registered its disposer does not get to keep it just
/// because it failed afterwards.
final class _Deps extends ScopeAutoDependencies<_Deps, void> {
  final List<String> released;
  final FutureOr<void> Function(ScopeDependencyHandle dep) _init;

  _Deps(this.released, this._init);

  @override
  bool get autoDisposeOnError => false;

  @override
  ScopeDependency buildDependencies(void context) =>
      sequential('', [dep('holder', _init)]);
}

Future<void> _init(_Deps deps) async {
  try {
    await deps.init(null, ScopeInitHandle().context);
  } on Object {
    // The failure is the point of the fixture; the disposal is what is tested.
  }
}

void main() {
  group('a dependency that failed after taking something', () {
    test('still releases it when the initializer throws', () async {
      final released = <String>[];
      final deps = _Deps(released, (dep) {
        dep.dispose = () => released.add(dep.name);

        throw Exception('boom');
      });

      await _init(deps);
      await deps.dispose();

      expect(
        released,
        ['holder'],
        reason: 'the disposer was registered before the failure, so whatever '
            'it releases was already taken',
      );
    });

    test('still releases it when the initializer fails asynchronously',
        () async {
      final released = <String>[];
      final deps = _Deps(released, (dep) async {
        dep.dispose = () async => released.add(dep.name);
        await Future<void>.delayed(Duration.zero);

        throw Exception('boom');
      });

      await _init(deps);
      await deps.dispose();

      expect(released, ['holder']);
    });

    test('releases nothing when the initializer took nothing', () async {
      final released = <String>[];
      final deps = _Deps(released, (dep) {
        throw Exception('boom');
      });

      await _init(deps);
      await deps.dispose();

      expect(
        released,
        isEmpty,
        reason: 'no disposer was registered, so there is nothing to release',
      );
    });

    test('releases what it took exactly once', () async {
      final released = <String>[];
      final deps = _Deps(released, (dep) {
        dep.dispose = () => released.add(dep.name);

        throw Exception('boom');
      });

      await _init(deps);
      await deps.dispose();
      await deps.dispose();

      expect(released, ['holder']);
    });
  });

  _sequentialDisposalGroup();
  _concurrentDisposalGroup();
  _diagnosticsGroup();
}

/// A container of three named dependencies, disposed of in reverse order.
final class _Three extends ScopeAutoDependencies<_Three, void> {
  final List<String> released;
  final Set<String> failOnDispose;

  _Three(this.released, {this.failOnDispose = const {}});

  @override
  bool get autoDisposeOnError => false;

  FutureOr<void> Function(ScopeDependencyHandle dep) _init(String name) =>
      (dep) {
        dep.dispose = () {
          released.add(name);
          if (failOnDispose.contains(name)) {
            throw Exception('$name failed to release');
          }
        };
      };

  @override
  ScopeDependency buildDependencies(void context) => sequential('', [
        dep('a', _init('a')),
        dep('b', _init('b')),
        dep('c', _init('c')),
      ]);
}

void _sequentialDisposalGroup() {
  group('a disposer that throws', () {
    test('does not keep the dependencies below it from being released',
        () async {
      final released = <String>[];
      final deps = _Three(released, failOnDispose: {'b'});

      await deps.init(null, ScopeInitHandle().context);
      await deps.dispose();

      expect(
        released,
        ['c', 'b', 'a'],
        reason: 'disposal runs in reverse order, and one failure is not a '
            'reason to abandon whatever is left holding resources',
      );
    });

    test('is still reported', () async {
      final deps = _Three(<String>[], failOnDispose: {'b'});

      await deps.init(null, ScopeInitHandle().context);
      await deps.dispose();

      expect(
        deps.flattenDependenciesWithErrors().map((i) => i.dependency.name),
        contains('b'),
        reason: 'the failure is recorded on the dependency that failed',
      );
    });
  });
}

/// A concurrent group holding a sequential branch beside a plain dependency.
///
/// The shape matters: the failure is raised by the dependency standing *next
/// to* a group, so what a lost cancellation takes with it is not one sibling
/// but a whole branch, part-way through its own reverse walk.
final class _Nested extends ScopeAutoDependencies<_Nested, void> {
  final List<String> released;
  final Set<String> failOnDispose;

  _Nested(this.released, {this.failOnDispose = const {}});

  @override
  bool get autoDisposeOnError => false;

  FutureOr<void> Function(ScopeDependencyHandle dep) _init(String name) =>
      (dep) {
        dep.dispose = () async {
          // Asynchronous on purpose: a synchronous branch would be over
          // before the sibling had a chance to fail, and the cancellation
          // this tests for would have nothing left to reach.
          await Future<void>.delayed(Duration.zero);
          released.add(name);
          if (failOnDispose.contains(name)) {
            throw Exception('$name failed to release');
          }
        };
      };

  @override
  ScopeDependency buildDependencies(void context) => concurrent('', [
        sequential('branch', [
          dep('a', _init('a')),
          dep('b', _init('b')),
        ]),
        dep('x', _init('x')),
      ]);
}

void _concurrentDisposalGroup() {
  group('a disposer that throws in a concurrent group', () {
    test('does not take the branch beside it with it', () async {
      final released = <String>[];
      final deps = _Nested(released, failOnDispose: {'x'});

      await deps.init(null, ScopeInitHandle().context);
      await deps.dispose();

      expect(
        released,
        containsAll(['x', 'b', 'a']),
        reason: 'a failure in one arm of a concurrent group is no reason to '
            'cancel the others, which are still holding resources of their '
            'own -- and nothing comes back for them: the walk marks itself '
            'done either way',
      );
      expect(
        released.indexOf('b') < released.indexOf('a'),
        isTrue,
        reason: 'the branch finished its own reverse walk rather than '
            'stopping wherever the cancellation found it',
      );
    });

    test('is still reported', () async {
      final deps = _Nested(<String>[], failOnDispose: {'x'});

      await deps.init(null, ScopeInitHandle().context);
      await deps.dispose();

      expect(
        deps.flattenDependenciesWithErrors().map((i) => i.dependency.name),
        contains('x'),
        reason: 'the failure is recorded on the dependency that failed',
      );
    });
  });
}

/// A container whose single dependency refuses to let go.
final class _FailingDispose
    extends ScopeAutoDependencies<_FailingDispose, void> {
  _FailingDispose();

  @override
  bool get autoDisposeOnError => false;

  @override
  ScopeDependency buildDependencies(void context) => sequential('', [
        dep('holder', (dep) {
          dep.dispose = () => throw Exception('holder refuses to let go');
        }),
      ]);
}

void _diagnosticsGroup() {
  group('a failure of a dependency', () {
    test('carries the stack trace of what it wraps', () async {
      final deps = _Deps(<String>[], (dep) => throw Exception('boom'));

      Object? error;
      StackTrace? stackTrace;
      try {
        await deps.init(null, ScopeInitHandle().context);
      } on Object catch (e, s) {
        error = e;
        stackTrace = s;
      }

      expect(error, isA<ScopeDependencyException>());
      expect(
        stackTrace,
        isNot(StackTrace.empty),
        reason: 'this is the trace that reaches `buildOnError`, and a crash '
            'reporter given an empty one has nothing to work from -- the '
            'original is inside the exception, but nothing says so',
      );
    });

    test('is reported when the disposal is the part that failed', () async {
      final reported = <Object>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (details) => reported.add(details.exception);
      addTearDown(() => FlutterError.onError = previous);

      final deps = _FailingDispose();
      await deps.init(null, ScopeInitHandle().context);
      await deps.dispose();

      expect(
        reported.map((error) => '$error'),
        contains(contains('refuses to let go')),
        reason: 'the container never re-throws what its disposal failed with, '
            'so a report is the only way out; the log it used to go to alone '
            'is off by default',
      );
    });
  });

  // A group hands its children's streams to `_mergeStreams`, which used to ask
  // the iterable whether it was empty before walking it. On a lazy `map` that
  // question is not free: it calls the mapping function for the first element
  // -- `dep.init()`, `dep.dispose()` -- and throws the answer away, and the
  // walk then calls it again. The package's own leaves are `async*`, whose
  // bodies wait to be listened to, so the discarded stream did nothing; a
  // stream that starts its work when it is made does not have that manner.
  group('a concurrent group', () {
    test('asks each child for its stream exactly once', () async {
      final dependency = _CountingDependency();
      final tree = ScopeDependency.concurrent('', [dependency]);

      await tree.init(ScopeInitHandle().context, (_) {});
      expect(dependency.initCalls, 1);

      await tree.dispose((_) {});
      expect(dependency.disposeCalls, 1);
    });
  });

  // Two callers can ask one tree for the same disposal, and the second is
  // owed the truth about the first: that it is not over, and how it ended.
  group('a second disposal', () {
    // A group promises reverse order, and the promise was kept only as long as
    // one walk was running. A second `dispose()` arriving while the first was
    // parked found the child it was parked in already stripped of its hook --
    // taken off before the `await`, so that a disposer runs once -- decided it
    // had nothing to do there, and walked on to the child below, which the
    // parked one is built on top of.
    test('is not started a second time while one is running', () async {
      final log = <String>[];
      final parked = Completer<void>();

      final tree = ScopeDependency.sequential('', [
        ScopeDependency('a', (handle) {
          handle.dispose = () async => log.add('a released');
        }),
        ScopeDependency('b', (handle) {
          handle.dispose = () async {
            log.add('b started');
            await parked.future;
            log.add('b released');
          };
        }),
      ]);

      await tree.init(ScopeInitHandle().context, (_) {});

      final first = tree.dispose((_) {});
      await pumpEventQueue();
      expect(log, ['b started'], reason: 'the first walk is parked inside b');

      var secondFinished = false;
      final second = tree.dispose((_) {}).then((_) {
        secondFinished = true;
      });
      await pumpEventQueue();

      expect(
        log,
        ['b started'],
        reason: 'a is below b and is released after it, never beside it',
      );
      expect(
        secondFinished,
        isFalse,
        reason: 'a caller told the disposal is over while it is still running '
            'goes on to use what it thinks it has given back',
      );

      parked.complete();
      await Future.wait([first, second]);

      expect(log, ['b started', 'b released', 'a released']);
    });

    // The other half of what a joiner is owed. A walk that ended by failing
    // ended, and both callers asked for the same disposal: telling the second
    // that it went well is the same lie in a different place.
    test('carries the failure of the walk it joined', () async {
      final parked = Completer<void>();

      final tree = ScopeDependency.sequential('', [
        ScopeDependency('a', (handle) {
          handle.dispose = () async {
            await parked.future;
            throw StateError('boom');
          };
        }),
      ]);

      await tree.init(ScopeInitHandle().context, (_) {});

      final first = tree.dispose((_) {});
      await pumpEventQueue();
      final joined = tree.dispose((_) {});
      await pumpEventQueue();
      parked.complete();

      await expectLater(first, throwsA(isA<ScopeDependencyException>()));
      await expectLater(joined, throwsA(isA<ScopeDependencyException>()));
    });
  });
}

/// A dependency of the caller's own making that counts how often it is asked
/// for a stream, and starts its work when it is made rather than when it is
/// listened to -- `Stream.fromFuture` is the shape that does it.
final class _CountingDependency implements ScopeDependency {
  int initCalls = 0;
  int disposeCalls = 0;

  @override
  final String name = 'counted';

  @override
  final int count = 1;

  @override
  ScopeDependencyState get state => _state;
  ScopeDependencyState _state = const ScopeDependencyInitial();

  @override
  bool get disposalRequired => _state is ScopeDependencyInitialized;

  @override
  Future<void> init(ScopeInitContext ctx, void Function(String path) onStep) {
    initCalls++;
    _state = const ScopeDependencyInitialized();
    onStep(name);

    return Future<void>.value();
  }

  @override
  void onUnmount() {}

  @override
  Future<void> dispose(void Function(String path) onStep) {
    disposeCalls++;
    _state = const ScopeDependencyDisposed();
    onStep(name);

    return Future<void>.value();
  }

  @override
  String get wrappedName => '"$name"';

  @override
  String stateToString() => '$state';
}
