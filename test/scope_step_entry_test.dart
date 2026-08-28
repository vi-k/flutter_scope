import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scopo/scopo.dart';

import 'utils/observer.dart';

void main() {
  late RecordingObserver observer;

  setUp(() {
    observer = RecordingObserver();
    ScopeConfig.observer = observer;
  });

  tearDown(() {
    ScopeConfig.observer = null;
  });

  group('the entry into a step', () {
    test('is announced before the step is done, in a sequential group',
        () async {
      final dependencies = _Sequential();

      await dependencies.init(null).drain<void>();

      expect(observer.events, [
        'init _Sequential',
        'step _Sequential a',
        'progress _Sequential a (1/2)',
        'step _Sequential b',
        'progress _Sequential b (2/2)',
        'ready _Sequential',
      ]);
    });

    // The promise the whole change is made of: the mark is on the way out
    // before the initializer awaits anything, so a step that never comes back
    // is still the last one announced.
    test('arrives before the initializer awaits anything', () async {
      final parked = Completer<void>();
      final dependencies = _Parked(parked);
      final done = dependencies.init(null).drain<void>();

      await pumpEventQueue();

      expect(
        observer.events,
        ['init _Parked', 'step _Parked parked'],
        reason: 'the step is announced, and nothing says it finished',
      );

      parked.complete();
      await done;

      expect(observer.events.last, 'ready _Parked');
    });

    test(
        'arrives for every arm of a concurrent group before any of them '
        'finishes', () async {
      final first = Completer<void>();
      final second = Completer<void>();
      final dependencies = _Concurrent(first, second);
      final done = dependencies.init(null).drain<void>();

      await pumpEventQueue();

      expect(observer.events, [
        'init _Concurrent',
        'step _Concurrent group/a',
        'step _Concurrent group/b',
      ]);

      second.complete();
      await pumpEventQueue();
      first.complete();
      await done;

      expect(observer.events.sublist(3), [
        'progress _Concurrent group/b (1/2)',
        'progress _Concurrent group/a (2/2)',
        'ready _Concurrent',
      ]);
    });

    // The path of the two halves is assembled by the same `_path` of the same
    // groups, so an anonymous group contributes no segment to either.
    test('carries the path the completed step carries', () async {
      final dependencies = _Nested();

      await dependencies.init(null).drain<void>();

      expect(observer.events, [
        'init _Nested',
        'step _Nested storage/db',
        'progress _Nested storage/db (1/2)',
        'step _Nested storage/cache',
        'progress _Nested storage/cache (2/2)',
        'ready _Nested',
      ]);
    });

    test('is the whole record of a step that failed', () async {
      final dependencies = _Failing();

      await expectLater(
        dependencies.init(null).drain<void>(),
        throwsA(isA<ScopeDependencyException>()),
      );

      // The whole list, not a `contains`: the point of the pair is that
      // nothing follows the entry, and only a full list says so. There is no
      // `onError` among them, and there is not meant to be — the container
      // hands the failure to its caller, which is what `throwsA` above reads,
      // and the scope that owns a container is what reports `onError` with
      // `ScopePhase.initialization`. A container held by hand has no scope.
      expect(observer.events, [
        'init _Failing',
        'step _Failing boom',
        'cancelled _Failing',
        'dispose _Failing',
        'disposed _Failing',
      ]);
    });

    // A dependency of the caller's own making is not a `ScopeDependencyMixin`
    // and has nowhere to take the callback. Its completed step still arrives:
    // that one travels the stream, which is the interface it does implement.
    test('is skipped for a dependency of the caller own making', () async {
      final dependencies = _Foreign();

      await dependencies.init(null).drain<void>();

      expect(observer.events, [
        'init _Foreign',
        'progress _Foreign foreign (1/1)',
        'ready _Foreign',
      ]);
    });
  });

  group('the entry into a step of a disposal', () {
    test('pairs with the release, in reverse declaration order', () async {
      final dependencies = _Disposing();

      await dependencies.init(null).drain<void>();
      await dependencies.dispose();

      expect(observer.events, [
        'init _Disposing',
        'step _Disposing storage/db',
        'progress _Disposing storage/db (1/2)',
        'step _Disposing storage/cache',
        'progress _Disposing storage/cache (2/2)',
        'ready _Disposing',
        'dispose _Disposing',
        'disposal step _Disposing storage/cache',
        'disposal progress _Disposing storage/cache',
        'disposal step _Disposing storage/db',
        'disposal progress _Disposing storage/db',
        'disposed _Disposing',
      ]);
    });

    // `disposalRequired` counts `unmount` as much as `dispose` -- a hook still
    // to run is a thing to hold on to -- so such a dependency is walked. It
    // yields nothing, though, and announcing its entry would have invented a
    // step that never came back: exactly the false positive the pair is read
    // for.
    test('is not announced for a dependency that registered only unmount',
        () async {
      final dependencies = _UnmountOnly();

      await dependencies.init(null).drain<void>();
      dependencies.onUnmount();
      await dependencies.dispose();

      expect(
        observer.events.where((event) => event.contains('listener')),
        ['step _UnmountOnly listener', 'progress _UnmountOnly listener (1/1)'],
        reason: 'the initialization has both halves, the disposal neither',
      );
    });

    // The breaking half of the change: a release used to be reported through
    // `onProgress` as a bare `String`, which made that hook mean two different
    // things at two different points of the lifecycle.
    test('reports the release through onDisposalProgress, not onProgress',
        () async {
      final dependencies = _Disposing();

      await dependencies.init(null).drain<void>();
      observer.events.clear();
      await dependencies.dispose();

      expect(
        observer.events.where((event) => event.startsWith('progress ')),
        isEmpty,
        reason: 'a disposal reports nothing through onProgress any more',
      );
    });
  });

  group('the pairs under strain', () {
    // A release that throws is the one case where a disposal entry is meant
    // to stand alone -- which is exactly what a reader takes for a release
    // that hung, so it had better be the truth and not an accident of the
    // walk giving up early on its siblings.
    test(
        'a release that throws leaves its entry unmatched and the rest of '
        'the walk running', () async {
      final dependencies = _FailingDisposer();

      await dependencies.init(null).drain<void>();
      observer.events.clear();
      await dependencies.dispose();

      expect(observer.events, [
        'dispose _FailingDisposer',
        'disposal step _FailingDisposer storage/cache',
        'disposal step _FailingDisposer storage/db',
        'disposal progress _FailingDisposer storage/db',
        'error _FailingDisposer disposal storage/cache: Bad state: boom',
        'disposed _FailingDisposer',
      ]);
      // Three things at once, and the order is the point of writing the whole
      // list. `storage/cache` was entered and never came back, which is the
      // shape of a release that did not finish. `storage/db` was released all
      // the same -- one dependency that cannot let go is no reason to walk
      // away from the ones below it. And the failure arrives after the walk,
      // not where it happened: both groups collect what their children threw
      // and carry the first one out at the end.
    });

    // The wiring is put on the root by `init`, and `_prepareDependencies` may
    // hand back a tree that was built afresh. A second run has to report as
    // fully as the first.
    test('a second tree reports as fully as the first', () async {
      final dependencies = _Disposing();

      await dependencies.init(null).drain<void>();
      await dependencies.dispose();
      final first = List.of(observer.events);

      observer.events.clear();
      await dependencies.init(null).drain<void>();
      await dependencies.dispose();

      expect(
        observer.events,
        first,
        reason: 'the tree is built anew, and the entry marks come with it',
      );
      expect(
        observer.events.where((event) => event.startsWith('step ')),
        isNotEmpty,
        reason: 'a comparison of two empty recordings would pass for nothing',
      );
    });

    test('a dependency of the caller own making still reports its release',
        () async {
      final dependencies = _Foreign();

      await dependencies.init(null).drain<void>();
      observer.events.clear();
      await dependencies.dispose();

      expect(
        observer.events,
        [
          'dispose _Foreign',
          'disposal progress _Foreign foreign',
          'disposed _Foreign',
        ],
        reason: 'the release arrives, the entry does not: a dependency that '
            'is not a ScopeDependencyMixin has nowhere to take the callback '
            'from, and the release travels the public stream instead',
      );
    });
  });

  test('the composite observer forwards all three new hooks', () {
    final first = RecordingObserver();
    final second = RecordingObserver();
    const target = _FakeObservable('AppDeps(#1a2b)');

    ScopeCompositeObserver([first, second])
      ..onStepStarted(target, 'storage/db')
      ..onDisposalStepStarted(target, 'storage/db')
      ..onDisposalProgress(target, 'storage/db');

    expect(first.events, [
      'step AppDeps storage/db',
      'disposal step AppDeps storage/db',
      'disposal progress AppDeps storage/db',
    ]);
    expect(second.events, first.events, reason: 'both heard the same');
  });

  test('the print observer writes a line for each of the three', () {
    final lines = <String>[];
    const container = _FakeObservable('AppDeps(#1a2b)');

    ScopePrintObserver(output: lines.add)
      ..onStepStarted(container, 'storage/db')
      ..onDisposalStepStarted(container, 'storage/db')
      ..onDisposalProgress(container, 'storage/db');

    expect(lines, [
      'scopo | AppDeps(#1a2b) | initialize storage/db…',
      'scopo | AppDeps(#1a2b) | dispose storage/db…',
      'scopo | AppDeps(#1a2b) | disposed storage/db',
    ]);
  });
}

final class _Sequential extends ScopeAutoDependencies<_Sequential, void> {
  @override
  ScopeDependency buildDependencies(void context) => sequential('', [
        dep('a', (handle) async {}),
        dep('b', (handle) async {}),
      ]);
}

final class _Parked extends ScopeAutoDependencies<_Parked, void> {
  _Parked(this._parked);

  final Completer<void> _parked;

  @override
  ScopeDependency buildDependencies(void context) =>
      dep('parked', (handle) => _parked.future);
}

final class _Concurrent extends ScopeAutoDependencies<_Concurrent, void> {
  _Concurrent(this._first, this._second);

  final Completer<void> _first;
  final Completer<void> _second;

  @override
  ScopeDependency buildDependencies(void context) => concurrent('group', [
        dep('a', (handle) => _first.future),
        dep('b', (handle) => _second.future),
      ]);
}

final class _Nested extends ScopeAutoDependencies<_Nested, void> {
  @override
  ScopeDependency buildDependencies(void context) => sequential('', [
        sequential('storage', [
          dep('db', (handle) async {}),
          concurrent('', [
            dep('cache', (handle) async {}),
          ]),
        ]),
      ]);
}

final class _Failing extends ScopeAutoDependencies<_Failing, void> {
  @override
  ScopeDependency buildDependencies(void context) =>
      dep('boom', (handle) => throw StateError('boom'));
}

final class _Disposing extends ScopeAutoDependencies<_Disposing, void> {
  @override
  ScopeDependency buildDependencies(void context) => sequential('storage', [
        dep('db', (handle) async {
          handle.dispose = () async {};
        }),
        dep('cache', (handle) async {
          handle.dispose = () async {};
        }),
      ]);
}

final class _UnmountOnly extends ScopeAutoDependencies<_UnmountOnly, void> {
  @override
  ScopeDependency buildDependencies(void context) =>
      dep('listener', (handle) async {
        handle.unmount = () {};
      });
}

final class _FailingDisposer
    extends ScopeAutoDependencies<_FailingDisposer, void> {
  @override
  ScopeDependency buildDependencies(void context) => sequential('storage', [
        dep('db', (handle) async {
          handle.dispose = () async {};
        }),
        dep('cache', (handle) async {
          handle.dispose = () async => throw StateError('boom');
        }),
      ]);
}

final class _Foreign extends ScopeAutoDependencies<_Foreign, void> {
  @override
  ScopeDependency buildDependencies(void context) => _ForeignDependency();
}

/// A [ScopeDependency] written outside the package, as the interface allows.
final class _ForeignDependency implements ScopeDependency {
  @override
  final String name = 'foreign';

  @override
  final int count = 1;

  @override
  ScopeDependencyState get state => _state;
  ScopeDependencyState _state = const ScopeDependencyInitial();

  @override
  bool get disposalRequired =>
      !_disposalDone && _state is ScopeDependencyInitialized;
  bool _disposalDone = false;

  @override
  Stream<String> init() async* {
    _state = const ScopeDependencyInitialized();
    yield name;
  }

  @override
  void onUnmount() {}

  @override
  Stream<String> dispose() async* {
    _disposalDone = true;
    _state = const ScopeDependencyDisposed();
    yield name;
  }

  @override
  String get wrappedName => '"$name"';

  @override
  String stateToString() => '$state';
}

final class _FakeObservable implements ScopeObservable {
  const _FakeObservable(this.debugLabel);

  @override
  final String debugLabel;
}
