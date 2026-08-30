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
        'error _FailingDisposer disposal storage/cache: Bad state: boom',
        'disposal step _FailingDisposer storage/db',
        'disposal progress _FailingDisposer storage/db',
        'disposed _FailingDisposer',
      ]);
      // Three things at once, and the order is the point of writing the whole
      // list. `storage/cache` was entered and never came back, which is the
      // shape of a release that did not finish -- and the failure that ended
      // it arrives immediately behind it, so the two are read together and
      // the entry never looks like a step that hung. `storage/db` was
      // released all the same: one dependency that cannot let go is no reason
      // to walk away from the ones below it.
      //
      // The failure used to arrive at the end of the walk instead, carried
      // out by the groups that collected it. That was fine while the
      // container was the only thing that could drive a disposal; it is not,
      // and a walk driven by hand never reached that listener at all.
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

  // R5: the pair used to hold only while the container drove the walk. The
  // entry travels a channel pointed at the container from the moment the tree
  // is built; the exit used to travel the stream, which belongs to whoever
  // subscribed. Anyone else driving -- and the walk is public -- left the
  // container hearing entries and nothing behind them.
  group('the pair holds whoever drives the walk', () {
    test('when the walk is driven by hand and the container is never asked',
        () async {
      final dependencies = _TwoDisposers();

      await dependencies.init(null).drain<void>();
      observer.events.clear();

      final byHand = <String>[];
      await dependencies.root.dispose().forEach(byHand.add);

      expect(
        observer.events,
        [
          'disposal step _TwoDisposers b',
          'disposal progress _TwoDisposers b',
          'disposal step _TwoDisposers a',
          'disposal progress _TwoDisposers a',
        ],
        reason: 'both halves arrive, outside any onDispose/onDisposed',
      );
      expect(byHand, ['b', 'a'], reason: 'the driver still gets the paths');
    });

    test('when the container joins a walk driven by hand', () async {
      final parked = Completer<void>();
      final dependencies = _ParkedDisposer(parked);

      await dependencies.init(null).drain<void>();
      observer.events.clear();

      final byHand = <String>[];
      dependencies.root.dispose().listen(byHand.add);
      await pumpEventQueue();

      final joined = dependencies.dispose();
      await pumpEventQueue();

      parked.complete();
      await joined;

      expect(observer.events, [
        'disposal step _ParkedDisposer b',
        'dispose _ParkedDisposer',
        'disposal progress _ParkedDisposer b',
        'disposal step _ParkedDisposer a',
        'disposal progress _ParkedDisposer a',
        'disposed _ParkedDisposer',
      ]);
      expect(byHand, ['b', 'a']);
    });

    // The mark is sent before the `yield`, and this is the test that holds it
    // there: a cancelled `async*` resumes past its `await` and runs up to the
    // next `yield`, but never past it. Sent after the `yield`, the exit of a
    // disposer that actually finished would be lost for ever -- an entry with
    // no exit over a resource that is already released.
    test('when the walk is cancelled on a parked disposer', () async {
      final parked = Completer<void>();
      final dependencies = _ParkedDisposer(parked);

      await dependencies.init(null).drain<void>();
      observer.events.clear();

      final byHand = <String>[];
      final subscription = dependencies.root.dispose().listen(byHand.add);
      await pumpEventQueue();

      unawaited(subscription.cancel());
      parked.complete();
      await pumpEventQueue();

      expect(
        observer.events,
        [
          'disposal step _ParkedDisposer b',
          'disposal progress _ParkedDisposer b',
        ],
        reason: 'the disposer finished, so its exit is due even though the '
            'walk that started it was cancelled',
      );

      await dependencies.dispose();

      expect(
        observer.events,
        [
          'disposal step _ParkedDisposer b',
          'disposal progress _ParkedDisposer b',
          'dispose _ParkedDisposer',
          'disposal step _ParkedDisposer a',
          'disposal progress _ParkedDisposer a',
          'disposed _ParkedDisposer',
        ],
        reason: 'the container picks up what is left, and b is not released '
            'a second time',
      );
    });

    test('is announced for a foreign child by the group above it', () async {
      final dependencies = _ForeignChild();

      await dependencies.init(null).drain<void>();
      observer.events.clear();
      await dependencies.dispose();

      expect(
        observer.events,
        [
          'dispose _ForeignChild',
          'disposal progress _ForeignChild outer/foreign',
          'disposal step _ForeignChild outer/own',
          'disposal progress _ForeignChild outer/own',
          'disposed _ForeignChild',
        ],
        reason: 'the foreign child has no channel of its own, so the group '
            'speaks its exit; its entry stays unannounced, as it always was',
      );
    });

    test('holds for a package root with no group above it', () async {
      final dependencies = _RootLeaf();

      await dependencies.init(null).drain<void>();
      observer.events.clear();
      await dependencies.dispose();

      expect(observer.events, [
        'dispose _RootLeaf',
        'disposal step _RootLeaf solo',
        'disposal progress _RootLeaf solo',
        'disposed _RootLeaf',
      ]);
    });

    test('holds for every arm of a concurrent group', () async {
      final dependencies = _ConcurrentDisposers();

      await dependencies.init(null).drain<void>();
      observer.events.clear();
      await dependencies.dispose();

      final walk =
          observer.events.where((e) => e.startsWith('disposal ')).toList();

      expect(walk, hasLength(4), reason: 'two arms, two halves each');
      for (final arm in ['a', 'b']) {
        final entry = walk.indexOf('disposal step _ConcurrentDisposers $arm');
        final exit =
            walk.indexOf('disposal progress _ConcurrentDisposers $arm');
        expect(entry, isNonNegative, reason: '$arm was announced');
        expect(
          exit,
          greaterThan(entry),
          reason: "$arm's exit follows its entry",
        );
      }
    });

    // The bridge has a branch of its own in each group, and the test above
    // walks only the sequential one: a concurrent group of package leaves
    // announces from their own channels and never reaches the bridge at all.
    test('is announced for a foreign child of a concurrent group', () async {
      final dependencies = _ForeignInConcurrent();

      await dependencies.init(null).drain<void>();
      observer.events.clear();
      await dependencies.dispose();

      final walk =
          observer.events.where((e) => e.startsWith('disposal ')).toList();

      expect(
        walk,
        containsAll([
          'disposal progress _ForeignInConcurrent g/foreign',
          'disposal step _ForeignInConcurrent g/own',
          'disposal progress _ForeignInConcurrent g/own',
        ]),
      );
      expect(
        walk.where((e) => e.contains('foreign')),
        ['disposal progress _ForeignInConcurrent g/foreign'],
        reason: 'the foreign arm has an exit and, as ever, no entry',
      );
    });

    test('says nothing on a second dispose after the walk is over', () async {
      final dependencies = _TwoDisposers();

      await dependencies.init(null).drain<void>();
      await dependencies.dispose();
      observer.events.clear();
      await dependencies.dispose();

      expect(
        observer.events.where((e) => e.startsWith('disposal ')),
        isEmpty,
        reason: 'everything was released the first time round',
      );
    });

    // The entry is sent on the container's behalf however the walk was
    // started, so the failure that ends that step has to reach the container
    // too. Driven by hand, the error used to go only to the driver: the
    // observer saw an entry with no exit and nothing to say it had failed,
    // which is indistinguishable from a release that hung.
    test('carries the failure of a walk driven by hand', () async {
      final dependencies = _FailingDisposer();

      await dependencies.init(null).drain<void>();
      observer.events.clear();

      await dependencies.root.dispose().drain<void>().onError((_, __) {});

      expect(observer.events, [
        'disposal step _FailingDisposer storage/cache',
        'error _FailingDisposer disposal storage/cache: Bad state: boom',
        'disposal step _FailingDisposer storage/db',
        'disposal progress _FailingDisposer storage/db',
      ]);
    });

    // Not the design's "a tree built and then disposed of before `init`":
    // that one is unreachable through a container, because `init` is an
    // `async*` and `_prepareDependencies` — the only thing that ever builds
    // the tree — does not run until the stream is listened to. A container
    // that was never initialized has no tree at all, and this is what that
    // looks like from outside.
    test('says nothing for a container with no tree behind it', () async {
      final dependencies = _TwoDisposers();

      await dependencies.dispose();

      expect(observer.events, isEmpty);
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

final class _TwoDisposers extends ScopeAutoDependencies<_TwoDisposers, void> {
  @override
  ScopeDependency buildDependencies(void context) => sequential('', [
        dep('a', (handle) async {
          handle.dispose = () async {};
        }),
        dep('b', (handle) async {
          handle.dispose = () async {};
        }),
      ]);
}

final class _ParkedDisposer
    extends ScopeAutoDependencies<_ParkedDisposer, void> {
  _ParkedDisposer(this._parked);

  final Completer<void> _parked;

  @override
  ScopeDependency buildDependencies(void context) => sequential('', [
        dep('a', (handle) async {
          handle.dispose = () async {};
        }),
        dep('b', (handle) async {
          handle.dispose = () => _parked.future;
        }),
      ]);
}

final class _ForeignChild extends ScopeAutoDependencies<_ForeignChild, void> {
  @override
  ScopeDependency buildDependencies(void context) => sequential('outer', [
        dep('own', (handle) async {
          handle.dispose = () async {};
        }),
        _ForeignDependency(),
      ]);
}

final class _RootLeaf extends ScopeAutoDependencies<_RootLeaf, void> {
  @override
  ScopeDependency buildDependencies(void context) =>
      dep('solo', (handle) async {
        handle.dispose = () async {};
      });
}

final class _ConcurrentDisposers
    extends ScopeAutoDependencies<_ConcurrentDisposers, void> {
  @override
  ScopeDependency buildDependencies(void context) => concurrent('', [
        dep('a', (handle) async {
          handle.dispose = () async {};
        }),
        dep('b', (handle) async {
          handle.dispose = () async {};
        }),
      ]);
}

final class _ForeignInConcurrent
    extends ScopeAutoDependencies<_ForeignInConcurrent, void> {
  @override
  ScopeDependency buildDependencies(void context) => concurrent('g', [
        dep('own', (handle) async {
          handle.dispose = () async {};
        }),
        _ForeignDependency(),
      ]);
}
