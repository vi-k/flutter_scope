import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scopo/scopo.dart';

import 'utils/settle.dart';

/// A scope taken out of the tree while its dependencies are still being built.
///
/// The container promises that whatever a dependency has already taken is given
/// back. Cancellation is the one way in which that promise hangs on a single
/// line: an initialization that never succeeded leaves the scope with
/// `_initSucceeded` false, so the teardown skips `disposeAsync()` — and with it
/// the pass that disposes of the dependencies. The only thing left to release a
/// half-built tree is the `finally` of [ScopeAutoDependencies.init], reached by
/// cancelling the subscription to it.
///
/// The container suite reaches that `finally` by cancelling a subscription it
/// holds itself. Nothing reached it the way an application does — by removing
/// the widget — and the two are not the same path: between them lie the
/// synchronous teardown, the bounded wait for the cancellation to land, and the
/// order the four stages of the disposal run in.
///
/// The second group is the same promise one layer up, where a hand-written
/// `initAsync` guards its own steps instead of handing them to a container.
void main() {
  tearDown(ScopeConfig.reset);

  group('a scope removed while its dependencies are initializing', () {
    testWidgets('releases what the half-built tree had already taken',
        (tester) async {
      final deps = _Deps();

      await tester.pumpWidget(_wrap(_DepScope(deps: deps)));
      await settle(tester, until: () => deps.started.contains('b'));

      expect(
        deps.released,
        isEmpty,
        reason: 'nothing is over yet: the tree is caught mid-walk',
      );

      await tester.pumpWidget(_wrap(const SizedBox.shrink()));

      // A generator suspended on a future nobody completes is never resumed,
      // so cancelling it never returns. The step in flight is let go of here,
      // which is what lets the cancellation land at all.
      deps.gate.complete();
      await settle(tester, until: () => deps.released.isNotEmpty);

      expect(
        deps.released,
        ['a'],
        reason: 'the scope never became ready, so its own disposeAsync is '
            'skipped and this is the only pass that releases the tree',
      );
    });

    testWidgets('does not reach the dependencies below the one it stopped on',
        (tester) async {
      final deps = _Deps();

      await tester.pumpWidget(_wrap(_DepScope(deps: deps)));
      await settle(tester, until: () => deps.started.contains('b'));

      await tester.pumpWidget(_wrap(const SizedBox.shrink()));
      deps.gate.complete();
      await settle(tester, until: () => deps.released.isNotEmpty);

      expect(
        deps.started,
        ['a', 'b'],
        reason: 'the step in flight finishes because nothing can stop it, but '
            'the walk goes no further: a cancelled generator ends at its next '
            'yield rather than building the rest of the tree for a scope that '
            'has already left',
      );
    });

    testWidgets('says of every dependency what became of it', (tester) async {
      final deps = _Deps();

      await tester.pumpWidget(_wrap(_DepScope(deps: deps)));
      await settle(tester, until: () => deps.started.contains('b'));

      await tester.pumpWidget(_wrap(const SizedBox.shrink()));
      deps.gate.complete();
      await settle(tester, until: () => deps.released.isNotEmpty);

      expect(
        deps.flattenDependencies().map((info) => '$info').toList(),
        [
          '[group] disposed',
          '  "a" disposed',
          '  "b" cancelled',
          '  "c" not initialized',
        ],
        reason: 'three different fates under a root that was walked to the '
            'end, and the dump is where a reader finds out which is which: '
            '"c" was never started, "b" was and never finished',
      );
    });

    // The opt-out is documented as keeping the half-built tree for inspection.
    // Through the widget that is a promise about the teardown as much as about
    // the container: the scope is gone, and nothing behind it may release the
    // tree on the user's behalf.
    testWidgets('keeps the half-built tree when asked to keep it',
        (tester) async {
      final deps = _Deps(autoDisposeOnError: false);

      await tester.pumpWidget(_wrap(_DepScope(deps: deps)));
      await settle(tester, until: () => deps.started.contains('b'));

      await tester.pumpWidget(_wrap(const SizedBox.shrink()));
      deps.gate.complete();
      await settle(tester, until: () => false);

      expect(
        deps.released,
        isEmpty,
        reason: 'the container was told to keep what it built, and the scope '
            'leaving the tree does not overrule that',
      );
      expect(
        deps.flattenDependencies().map((info) => '$info').toList(),
        contains('  "a" initialized'),
        reason: 'kept means kept in the state it reached',
      );
    });
  });

  // A hand-written `initAsync` gives back what it took by guarding its own
  // steps, and the topics show how. What shape that guard has to be is the
  // whole of it: a cancellation raises nothing, so the two shapes that look
  // equivalent are not.
  group('an initialization cancelled after it took something', () {
    testWidgets('does not reach a catch, which raising is what would',
        (tester) async {
      final log = <String>[];
      final gate = Completer<void>();

      await tester.pumpWidget(_wrap(_Guarded.withCatch(log: log, gate: gate)));
      await settle(tester, until: () => log.contains('took'));

      await tester.pumpWidget(_wrap(const SizedBox.shrink()));
      gate.complete();
      await settle(tester, until: () => log.length > 1);

      expect(
        log,
        ['took'],
        reason: 'cancelling an `async*` resumes its body and ends it at the '
            'next yield -- nothing is thrown, so the catch never runs; and '
            'the scope never became ready, so `disposeAsync` does not run '
            'either. What the initialization took is held by nobody',
      );
    });

    testWidgets('does reach a finally, which can tell it from a handover',
        (tester) async {
      final log = <String>[];
      final gate = Completer<void>();

      await tester
          .pumpWidget(_wrap(_Guarded.withFinally(log: log, gate: gate)));
      await settle(tester, until: () => log.contains('took'));

      await tester.pumpWidget(_wrap(const SizedBox.shrink()));
      gate.complete();
      await settle(tester, until: () => log.contains('released'));

      expect(
        log,
        ['took', 'released'],
        reason: 'the flag is set after the yield, so a body ended at that '
            'yield leaves it false -- which is exactly the case where what '
            'was taken is still the initialization`s to give back',
      );
    });

    testWidgets('leaves alone what the scope did take over', (tester) async {
      final log = <String>[];
      final gate = Completer<void>()..complete();

      await tester
          .pumpWidget(_wrap(_Guarded.withFinally(log: log, gate: gate)));
      await tester.pumpAndSettle();

      expect(
        log,
        ['took', 'handed over'],
        reason: 'the guard has to keep quiet once the scope is ready, or the '
            'value would be released twice',
      );

      await tester.pumpWidget(_wrap(const SizedBox.shrink()));
      await settle(tester, until: () => log.contains('disposeAsync'));

      expect(
        log,
        ['took', 'handed over', 'disposeAsync'],
        reason: 'and from there it is the scope that releases it',
      );
    });

    // The narrowest state the two can be caught in. `pauseAfterInitialization`
    // holds the ready branch back, so the scope has registered the
    // initialization -- `disposeAsync` will run -- while the screen still shows
    // the loading one. If the flag beside the `yield` could disagree with that,
    // this is where it would: the guard would release what the scope is about to
    // release too.
    //
    // It cannot. The statement after a `yield` runs when the stream asks for the
    // next event, which happens in a microtask after the scope has taken the
    // one it was given -- and a tree can only change in a frame, which is later
    // than any pending microtask.
    testWidgets('says handed over while the ready branch is still held back',
        (tester) async {
      final log = <String>[];
      final gate = Completer<void>()..complete();

      await tester.pumpWidget(
        _wrap(
          _Guarded.withFinally(
            log: log,
            gate: gate,
            pause: const Duration(milliseconds: 100),
          ),
        ),
      );
      await settle(tester, until: () => log.contains('handed over'));

      await tester.pumpWidget(_wrap(const SizedBox.shrink()));
      await settle(tester, until: () => log.contains('disposeAsync'));

      expect(
        log,
        ['took', 'handed over', 'disposeAsync'],
        reason: 'released once, by the scope -- the guard kept quiet, and it '
            'was right to',
      );
    });
  });
}

Widget _wrap(Widget child) => Directionality(
      textDirection: TextDirection.ltr,
      child: child,
    );

/// Dependencies whose middle step can be held open, so the tree can be caught
/// half-built.
///
/// `a` takes something and registers its disposer, `b` parks on [gate], and `c`
/// is never reached — one dependency for each of the three fates a cancelled
/// walk leaves behind.
final class _Deps extends ScopeAutoDependencies<_Deps, BuildContext> {
  /// The dependencies whose initializer started, in order.
  final started = <String>[];

  /// The dependencies whose disposer ran, in order.
  final released = <String>[];

  /// Holds `b` open, so the cancellation arrives while the walk is mid-tree.
  final gate = Completer<void>();

  final bool _autoDisposeOnError;

  _Deps({bool autoDisposeOnError = true})
      : _autoDisposeOnError = autoDisposeOnError;

  @override
  bool get autoDisposeOnError => _autoDisposeOnError;

  @override
  ScopeDependency buildDependencies(BuildContext context) => sequential('', [
        dep('a', (dep) {
          started.add('a');
          dep.dispose = () => released.add('a');
        }),
        dep('b', (dep) async {
          started.add('b');
          await gate.future;
        }),
        dep('c', (dep) {
          started.add('c');
          dep.dispose = () => released.add('c');
        }),
      ]);
}

final class _DepScope extends Scope<_DepScope, _Deps, _DepScopeState> {
  final _Deps deps;

  const _DepScope({required this.deps}) : super(child: const SizedBox.shrink());

  @override
  Stream<ScopeInitState<Object, _Deps>> initDependencies(
    BuildContext context,
  ) =>
      deps.init(context);

  @override
  Widget buildOnInitializing(BuildContext context, Object? progress) =>
      const SizedBox.shrink();

  @override
  Widget buildOnError(
    BuildContext context,
    Object error,
    StackTrace stackTrace,
    Object? progress,
  ) =>
      const SizedBox.shrink();

  @override
  _DepScopeState createState() => _DepScopeState();
}

final class _DepScopeState
    extends ScopeState<_DepScope, _Deps, _DepScopeState> {
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// A scope whose initialization takes something and guards it — in one of the
/// two shapes the topics could show.
///
/// [gate] stands for the step that follows the acquisition, so the scope can
/// be caught between having taken something and having handed it over.
final class _Guarded extends AsyncScopeBase<_Guarded> {
  final List<String> log;
  final Completer<void> gate;

  /// Whether the guard is a `finally` rather than a `catch`.
  final bool guardIsFinally;

  /// Holds the ready branch back, so the scope can be caught having registered
  /// the initialization while the screen still shows the loading one.
  final Duration? pause;

  const _Guarded.withCatch({required this.log, required this.gate})
      : guardIsFinally = false,
        pause = null,
        super(child: const SizedBox.shrink());

  const _Guarded.withFinally({
    required this.log,
    required this.gate,
    this.pause,
  })  : guardIsFinally = true,
        super(child: const SizedBox.shrink());

  @override
  Duration? get pauseAfterInitialization => pause;

  @override
  Stream<AsyncScopeInitState> initAsync(BuildContext context) async* {
    log.add('took');

    if (!guardIsFinally) {
      try {
        await gate.future;
        // ignore: avoid_catching_errors
      } on Object {
        log.add('released');
        rethrow;
      }

      yield AsyncScopeReady();

      return;
    }

    var handedOver = false;

    try {
      await gate.future;

      yield AsyncScopeReady();
      handedOver = true;
      log.add('handed over');
    } finally {
      if (!handedOver) {
        log.add('released');
      }
    }
  }

  @override
  Future<void> disposeAsync() async => log.add('disposeAsync');

  @override
  Widget buildOnInitializing(BuildContext context, Object? progress) =>
      const SizedBox.shrink();

  @override
  Widget buildOnError(
    BuildContext context,
    Object error,
    StackTrace stackTrace,
    Object? progress,
  ) =>
      const SizedBox.shrink();

  @override
  Widget buildOnReady(BuildContext context) => child;
}
