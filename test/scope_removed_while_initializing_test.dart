import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scopo/scopo.dart';

import 'utils/observer.dart';
import 'utils/settle.dart';

/// A scope taken out of the tree while its dependencies are still being built.
///
/// The container promises that whatever a dependency has already taken is given
/// back. Cancellation is the one way in which that promise hangs on a single
/// line: an initialization that never succeeded leaves the scope with
/// `_initSucceeded` false, so the teardown skips `disposeScope()` — and with it
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
/// `initScope` guards its own steps instead of handing them to a container.
///
/// The third is the phase after both of them: the asynchronous initialization
/// of the *state*, which starts only once the ready branch has built the state
/// and can therefore still be running when the scope is taken away.
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
        reason: 'the scope never became ready, so its own disposeScope is '
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

  // A hand-written `initScope` gives back what it took, and there are two
  // ways it happens. A body that waits through the context is thrown into and
  // gives the thing back itself; a body that waits on a bare `await` is told
  // nothing, runs to its end, and what it produced is released by the scope.
  // Which of the two it is decides what the guard has to look like.
  group('an initialization cancelled after it took something', () {
    testWidgets('is thrown into when it waits through the context',
        (tester) async {
      final log = <String>[];
      final gate = Completer<void>();

      await tester.pumpWidget(
        _wrap(
          _Guarded.withCatch(log: log, gate: gate, waitsThroughContext: true),
        ),
      );
      await settle(tester, until: () => log.contains('took'));

      await tester.pumpWidget(_wrap(const SizedBox.shrink()));
      await settle(tester, until: () => log.contains('released'));

      expect(
        log,
        ['took', 'released'],
        reason: 'the cancellation arrives as a throw from `ctx.wait`, so the '
            'catch runs and the body gives back what it had taken',
      );
      expect(
        gate.isCompleted,
        isFalse,
        reason: 'the wait ended without the step it was waiting for',
      );
    });

    testWidgets(
        'is not thrown into when it waits on a bare await, and the '
        'scope releases what it produced instead', (tester) async {
      final log = <String>[];
      final gate = Completer<void>();

      await tester.pumpWidget(_wrap(_Guarded.withCatch(log: log, gate: gate)));
      await settle(tester, until: () => log.contains('took'));

      await tester.pumpWidget(_wrap(const SizedBox.shrink()));
      gate.complete();
      await settle(tester, until: () => log.contains('disposeScope'));

      expect(
        log,
        ['took', 'disposeScope'],
        reason: 'a body that asks the context nothing cannot be told '
            'anything, so its catch never runs -- and the value it finished '
            'producing for a scope that had gone is handed to `disposeScope` '
            'rather than left with nobody, which is where a generator left it',
      );
    });

    testWidgets('does reach a finally, which can tell it from a handover',
        (tester) async {
      final log = <String>[];
      final gate = Completer<void>();

      await tester.pumpWidget(
        _wrap(
          _Guarded.withFinally(log: log, gate: gate, waitsThroughContext: true),
        ),
      );
      await settle(tester, until: () => log.contains('took'));

      await tester.pumpWidget(_wrap(const SizedBox.shrink()));
      await settle(tester, until: () => log.contains('released'));

      expect(
        log,
        ['took', 'released'],
        reason: 'the flag is set after the step, so a body thrown into at '
            'that step leaves it false -- which is exactly the case where '
            'what was taken is still the initialization`s to give back',
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
      await settle(tester, until: () => log.contains('disposeScope'));

      expect(
        log,
        ['took', 'handed over', 'disposeScope'],
        reason: 'and from there it is the scope that releases it',
      );
    });

    // The narrowest state the two can be caught in. `pauseAfterInitialization`
    // holds the ready branch back, so the scope has registered the
    // initialization -- `disposeScope` will run -- while the screen still shows
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
      await settle(tester, until: () => log.contains('disposeScope'));

      expect(
        log,
        ['took', 'handed over', 'disposeScope'],
        reason: 'released once, by the scope -- the guard kept quiet, and it '
            'was right to',
      );
    });
  });

  // The last of the three initializations a `Scope` runs, and the only one
  // that starts after the scope is on screen: `initStateAsync()` is called
  // from `initState()` of the state, and the state is what the ready branch
  // builds. A scope taken off the tree while it is still running leaves a
  // state Flutter has already disposed of -- and the hook that follows the
  // initialization reaches user code. `onInitialized()` on a dead state has no
  // `context` to work with, and the `notifyDependents()` beside it would raise
  // an assertion of the framework's own.
  //
  // The guard that covers this was there, and nothing covered the guard:
  // removing it left the whole suite green.
  group('a scope removed while its state is initializing', () {
    testWidgets('does not call onInitialized on a state that is gone',
        (tester) async {
      final gate = Completer<void>();
      final initialized = <String>[];
      addTearDown(() {
        if (!gate.isCompleted) {
          gate.complete();
        }
      });

      await tester.pumpWidget(
        _wrap(_StateScope(gate: gate, initialized: initialized)),
      );
      await tester.pumpAndSettle();

      expect(
        initialized,
        isEmpty,
        reason: 'the ready branch is on screen while initStateAsync runs, '
            'which is the whole reason this window exists',
      );

      await tester.pumpWidget(_wrap(const SizedBox.shrink()));
      await settle(tester, until: () => false);

      gate.complete();
      await settle(tester, until: () => initialized.isNotEmpty);

      expect(
        initialized,
        isEmpty,
        reason: 'the state is gone, so the hook that would hand it to user '
            'code is not called at all',
      );
      expect(tester.takeException(), isNull);
    });

    // Both tests above hand the gate over in the end, which is the case where
    // the initialization comes back on its own. When it does not, the teardown
    // has nothing to come back to: it parks on the completer the initialization
    // settles, and that wait carries no limit of its own -- deliberately, since
    // on the scope layer the package is what settles it. Here the user is, so
    // what ends the wait is the limit around the step above it.
    testWidgets('gives up on a state that never finishes initializing',
        (tester) async {
      final observer = RecordingObserver();
      ScopeConfig.observer = observer;
      addTearDown(() => ScopeConfig.observer = null);

      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) {
          gate.complete();
        }
      });

      // Grows only if `onInitialized` runs, which is the thing this scope
      // never gets to. A modifiable list, so a day when it does run says so by
      // failing the expectation rather than by raising out of the hook.
      final initialized = <String>[];

      await tester.pumpWidget(
        _wrap(
          _StateScope(
            gate: gate,
            initialized: initialized,
            disposeScopeTimeout: const Duration(milliseconds: 50),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // What the mount reported is not what this test is about, and the
      // teardown is what the list below has to read as.
      observer.events.clear();

      await tester.pumpWidget(_wrap(const SizedBox.shrink()));
      await settle(
        tester,
        until: () => observer.events.contains('disposed _StateScope'),
      );

      expect(
        observer.events,
        [
          'dispose _StateScope',
          'timeout _StateScope its own teardown',
          'disposed _StateScope',
        ],
        reason: 'a `LiteScope` has no second half below the state to protect, '
            'so the limit sits around the whole step and the expiry is '
            'reported as the teardown of the scope itself -- and the teardown '
            'ends, which is the point: without it the scope would hold its '
            'place with the parent for as long as the initialization runs',
      );
      expect(
        tester.takeException(),
        isA<TimeoutException>(),
        reason: 'giving up is said out loud, not only to an observer',
      );
      expect(
        initialized,
        isEmpty,
        reason: 'giving up on the wait is not the same as the wait coming '
            'back: the initialization is still running, and the hook that '
            'follows it has not been reached',
      );
    });

    // The other half of the same guard: while the scope is still there, the
    // hook does run, and on a state that is still on the tree.
    testWidgets('does call it on a state that is still there', (tester) async {
      final gate = Completer<void>();
      final initialized = <String>[];

      await tester.pumpWidget(
        _wrap(_StateScope(gate: gate, initialized: initialized)),
      );
      await tester.pumpAndSettle();

      gate.complete();
      await settle(tester, until: () => initialized.isNotEmpty);

      expect(initialized, ['mounted']);
    });
  });
}

/// A scope whose *state* parks its asynchronous initialization on [gate].
final class _StateScope extends LiteScope<_StateScope, _StateScopeState> {
  final Completer<void> gate;
  final List<String> initialized;

  const _StateScope({
    required this.gate,
    required this.initialized,
    super.disposeScopeTimeout,
  });

  @override
  Widget? buildOnWaiting(BuildContext context) => const SizedBox.shrink();

  @override
  _StateScopeState createState() => _StateScopeState();
}

final class _StateScopeState
    extends LiteScopeState<_StateScope, _StateScopeState> {
  @override
  Future<void> initStateAsync() => params.gate.future;

  @override
  void onInitialized() {
    super.onInitialized();
    params.initialized.add(mounted ? 'mounted' : 'unmounted');
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
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
  Widget buildOnProgress(BuildContext context, Object? progress) =>
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

  /// Whether the body waits through the context rather than on a bare
  /// `await`.
  ///
  /// This is what decides whether the cancellation reaches the body at all:
  /// it arrives as a throw from [ScopeInitContext], and a body that asks the
  /// context nothing is told nothing.
  final bool waitsThroughContext;

  /// Holds the ready branch back, so the scope can be caught having registered
  /// the initialization while the screen still shows the loading one.
  final Duration? pause;

  const _Guarded.withCatch({
    required this.log,
    required this.gate,
    this.waitsThroughContext = false,
  })  : guardIsFinally = false,
        pause = null,
        super(child: const SizedBox.shrink());

  const _Guarded.withFinally({
    required this.log,
    required this.gate,
    this.pause,
    this.waitsThroughContext = false,
  })  : guardIsFinally = true,
        super(child: const SizedBox.shrink());

  @override
  Duration? get pauseAfterInitialization => pause;

  /// The step that follows the acquisition, waited for in one of the two ways
  /// a body can wait.
  Future<void> _step(ScopeInitContext ctx) =>
      waitsThroughContext ? ctx.wait(() => gate.future) : gate.future;

  @override
  Future<void> initScope(BuildContext context, ScopeInitContext ctx) async {
    log.add('took');

    if (!guardIsFinally) {
      try {
        await _step(ctx);
        // ignore: avoid_catching_errors
      } on Object {
        log.add('released');
        rethrow;
      }

      return;
    }

    var handedOver = false;

    try {
      await _step(ctx);
      handedOver = true;
      log.add('handed over');
    } finally {
      if (!handedOver) {
        log.add('released');
      }
    }
  }

  @override
  Future<void> disposeScope() async => log.add('disposeScope');

  @override
  Widget buildOnProgress(BuildContext context, Object? progress) =>
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
