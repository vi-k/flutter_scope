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

      await tree.init().drain<void>();
      expect(dependency.initCalls, 1);

      await tree.dispose().drain<void>();
      expect(dependency.disposeCalls, 1);
    });
  });

  // `ScopeDependency` and its `dispose()` are public, and leading a tree by
  // hand is what they are for. A walk the caller stops halfway leaves whatever
  // it never reached still holding what it took, so the tree has to go on
  // saying it needs disposing of -- which is what the `finally` of
  // `ScopeDependencyMixin.dispose` is written to say.
  group('a disposal walk the caller stopped halfway', () {
    test('is still due when the tree is not in Initialized', () async {
      final released = <String>[];
      final parked = Completer<void>();

      // The initialization fails, so the group lands in `Failed` rather than
      // `Initialized` -- one of the four states its `disposalRequired`
      // covers. Both children register a disposer before anything goes
      // wrong: "acquire, register, then carry on".
      final tree = ScopeDependency.sequential('', [
        ScopeDependency('a', (handle) {
          handle.dispose = () async => released.add('a');
        }),
        ScopeDependency('b', (handle) {
          handle.dispose = () async {
            released.add('b');
            await parked.future;
          };
          throw StateError('boom');
        }),
      ]);

      try {
        await tree.init().drain<void>();
      } on Object {
        // The failure is the fixture; the disposal is what is tested.
      }
      expect(tree.state, isA<ScopeDependencyFailed>());

      // Reverse order, so `b` goes first and parks. The walk never reaches
      // `a`.
      final walk = tree.dispose().listen(null);
      await pumpEventQueue();
      expect(released, ['b'], reason: 'parked inside the disposer of b');

      // Asked for, then let go of: cancelling a stream does not interrupt
      // the `await` a generator is parked on, so the cancellation itself
      // only finishes once the disposer of `b` does.
      final cancelled = walk.cancel();
      parked.complete();
      await cancelled;

      expect(
        released,
        ['b'],
        reason: 'the walk stopped where it was, without reaching a',
      );
      expect(
        tree.disposalRequired,
        isTrue,
        reason: 'a is still holding what it took, and nothing has reached it',
      );

      await tree.dispose().drain<void>();

      expect(
        released,
        ['b', 'a'],
        reason: 'the second walk picks up where the cancelled one stopped',
      );
    });

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

      await tree.init().drain<void>();

      final first = tree.dispose().drain<void>();
      await pumpEventQueue();
      expect(log, ['b started'], reason: 'the first walk is parked inside b');

      var secondFinished = false;
      final second = tree.dispose().drain<void>().then((_) {
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

    // Joining is only half an answer. The walk joined can end without having
    // disposed of anything -- a caller stops it -- and the joiner then holds a
    // future that completed, a stream that closed, and a tree that still needs
    // disposing of. Told "done", it goes on to use what it believes it has
    // given back: the very failure the join was written to prevent, moved one
    // caller along.
    test('picks up a walk it joined that was stopped halfway', () async {
      final released = <String>[];
      final parked = Completer<void>();

      final tree = ScopeDependency.sequential('', [
        ScopeDependency('a', (handle) {
          handle.dispose = () async => released.add('a');
        }),
        ScopeDependency('b', (handle) {
          handle.dispose = () async {
            released.add('b');
            await parked.future;
          };
        }),
      ]);

      await tree.init().drain<void>();

      final walk = tree.dispose().listen(null);
      await pumpEventQueue();
      expect(released, ['b']);

      final joined = tree.dispose().drain<void>();
      await pumpEventQueue();

      final cancelled = walk.cancel();
      parked.complete();
      await cancelled;
      await joined;

      expect(
        released,
        ['b', 'a'],
        reason: 'the joiner is the caller who still wants the disposal done',
      );
      expect(tree.disposalRequired, isFalse);
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

      await tree.init().drain<void>();

      final first = tree.dispose().drain<void>();
      await pumpEventQueue();
      final joined = tree.dispose().drain<void>();
      await pumpEventQueue();
      parked.complete();

      await expectLater(first, throwsA(isA<ScopeDependencyException>()));
      await expectLater(joined, throwsA(isA<ScopeDependencyException>()));
    });

    // `_markNothingToDispose` keeps `Initial` on a child that never ran, and
    // says why: "not initialized" is the true thing to say about it. The node
    // the walk itself passes through was saying the opposite.
    test('leaves a tree that never ran saying it never ran', () async {
      final tree = ScopeDependency.sequential('', [
        ScopeDependency('a', (handle) {}),
      ]);

      await tree.dispose().drain<void>();

      expect(tree.state, isA<ScopeDependencyInitial>());
      expect(
        (tree as ScopeDependencyGroup).dependencies.single.state,
        isA<ScopeDependencyInitial>(),
        reason: 'the child already said so; the root disagreed with it',
      );
    });

    // Saying "not initialized" is only half of it: the walk that passed
    // through also wrote down that the disposal was done, and nothing took
    // that back. So the tree could be initialized -- `init()` asserts on
    // `Initial`, and `Initial` is what it now says -- and came up already
    // marked as disposed of, with `disposalRequired` false from the first
    // instant. The teardown after it walked past everything.
    test('can still be initialized and disposed of after that', () async {
      final released = <String>[];
      final tree = ScopeDependency.sequential('', [
        ScopeDependency('a', (handle) {
          handle.dispose = () async => released.add('a');
        }),
      ]);

      await tree.dispose().drain<void>();
      await tree.init().drain<void>();

      expect(
        tree.disposalRequired,
        isTrue,
        reason: 'it holds what the initializer just took',
      );

      await tree.dispose().drain<void>();

      expect(released, ['a']);
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
  Stream<String> init() {
    initCalls++;
    _state = const ScopeDependencyInitialized();

    return Stream.fromFuture(Future.value(name));
  }

  @override
  void onUnmount() {}

  @override
  Stream<String> dispose() {
    disposeCalls++;
    _state = const ScopeDependencyDisposed();

    return Stream.fromFuture(Future.value(name));
  }

  @override
  String get wrappedName => '"$name"';

  @override
  String stateToString() => '$state';
}
