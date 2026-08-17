import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scopo/scopo.dart';

import 'utils/settle.dart';

/// Cleanup is a promise, and a hook the user wrote is not part of it.
///
/// Every scope family hands control to user code on its way out — `onUnmount`,
/// the expiry callbacks, the state's own `disposeAsync`, a dependency's
/// `unmount`. A failure there used to take the mandatory teardown with it: the
/// registration with the parent, the `scopeKey`, the model and the dependencies
/// all stayed alive, and the failure was the only trace left.
///
/// The assertions below are about effects, never about timings: what proves the
/// teardown ran is that the resources it releases came back.
void main() {
  tearDown(ScopeConfig.reset);

  group('AsyncScope', () {
    testWidgets('disposes of itself after a failing onUnmount', (tester) async {
      final disposed = <String>[];

      await tester.pumpWidget(
        _wrap(_Async(label: 'holder', failOnUnmount: true, disposed: disposed)),
      );
      await tester.pumpAndSettle();

      await tester.pumpWidget(_wrap(const SizedBox.shrink()));
      await settle(tester, until: () => disposed.isNotEmpty);

      expect(
        tester.takeException(),
        isA<StateError>(),
        reason: 'the failure is still reported',
      );
      expect(
        disposed,
        ['holder'],
        reason: 'the hook is user code; the teardown behind it is not',
      );
    });

    // The `scopeKey` is what the leak costs someone else: an entry nobody
    // releases parks every later scope on that key behind it. The successor's
    // own limit is set beyond anything this test can advance, so an expiry
    // cannot be what let it in.
    testWidgets('releases its scopeKey after a failing onUnmount',
        (tester) async {
      final disposed = <String>[];

      Widget build({required bool holder, required bool successor}) => _wrap(
            Column(
              children: [
                if (holder)
                  _Async(
                    label: 'holder',
                    scopeKey: 'shared',
                    failOnUnmount: true,
                    disposed: disposed,
                  ),
                if (successor)
                  _Async(
                    label: 'successor',
                    scopeKey: 'shared',
                    scopeKeyTimeout: const Duration(days: 1),
                    disposed: disposed,
                  ),
              ],
            ),
          );

      await tester.pumpWidget(build(holder: true, successor: false));
      await tester.pumpAndSettle();

      await tester.pumpWidget(build(holder: false, successor: false));
      await settle(tester, until: () => disposed.isNotEmpty);
      expect(tester.takeException(), isA<StateError>());

      await tester.pumpWidget(build(holder: false, successor: true));
      await settle(tester, until: () => _readyCount(tester) == 1);

      expect(
        _readyCount(tester),
        1,
        reason: 'the key was released, so the next scope got in at once',
      );
      expect(tester.takeException(), isNull);
    });

    // An initialization parked on a future that never completes cannot be
    // cancelled at all, so the teardown gives up on it after
    // `initCancellationTimeout` -- and the expiry runs user code one step
    // before the block that gives the key back, exactly like the two other
    // expiries do.
    testWidgets(
        'releases its scopeKey after a failing '
        'onInitCancellationTimeout', (tester) async {
      final disposed = <String>[];

      // Never completed: the holder can only leave by the limit expiring.
      final hang = Completer<void>();

      // Two failures are reported here, one after the other -- the expiry, and
      // then the hook it calls -- and `takeException` collapses several of
      // them into one summary string. Captured directly, so both can be seen.
      final reported = <FlutterErrorDetails>[];
      final previousOnError = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = previousOnError);

      Widget build({required bool holder, required bool successor}) => _wrap(
            Column(
              children: [
                if (holder)
                  _Async(
                    label: 'holder',
                    scopeKey: 'shared',
                    initGate: hang,
                    initCancellationTimeout: const Duration(milliseconds: 50),
                    onInitCancellationTimeout: () =>
                        throw StateError('onInitCancellationTimeout failed'),
                    disposed: disposed,
                  ),
                if (successor)
                  _Async(
                    label: 'successor',
                    scopeKey: 'shared',
                    scopeKeyTimeout: const Duration(days: 1),
                    disposed: disposed,
                  ),
              ],
            ),
          );

      await tester.pumpWidget(build(holder: true, successor: false));
      await tester.pumpAndSettle();

      // Nothing marks the moment the teardown gives up -- `disposeAsync` is
      // skipped on a scope that never initialized -- so the settle runs its
      // whole budget.
      await tester.pumpWidget(build(holder: false, successor: false));
      await settle(tester, until: () => false);

      // Put back before the assertions, and not only by the tear-down: while
      // it is in place a failing `expect` is reported through it and
      // collected instead of ending the test, which leaves the run hanging
      // rather than red. The test three blocks below says the same and does
      // it; this one only said it.
      FlutterError.onError = previousOnError;

      expect(
        reported.map((details) => details.exception),
        [
          isA<TimeoutException>(),
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'onInitCancellationTimeout failed',
          ),
        ],
        reason: 'the expiry is reported, and so is what the hook made of it',
      );

      await tester.pumpWidget(build(holder: false, successor: true));
      await settle(tester, until: () => _readyCount(tester) == 1);

      expect(
        _readyCount(tester),
        1,
        reason: 'the hook is user code; the teardown behind it is not',
      );
    });

    // `disposeAsync` is the scope's own release, and it is user code twice
    // over: it can hang, and the expiry of the wait for it can fail. Neither
    // may keep the key of a scope that has already left the tree.
    testWidgets('releases its scopeKey after a failing onDisposeAsyncTimeout',
        (tester) async {
      final disposed = <String>[];
      final errors = <Object>[];

      // Never completed: the holder's own teardown never finishes.
      final hang = Completer<void>();

      Widget build({required bool holder, required bool successor}) => _wrap(
            Column(
              children: [
                if (holder)
                  _Async(
                    label: 'holder',
                    scopeKey: 'shared',
                    disposeGate: hang,
                    disposeAsyncTimeout: const Duration(milliseconds: 50),
                    onDisposeAsyncTimeout: () =>
                        throw StateError('onDisposeAsyncTimeout failed'),
                    disposed: disposed,
                  ),
                if (successor)
                  _Async(
                    label: 'successor',
                    scopeKey: 'shared',
                    scopeKeyTimeout: const Duration(days: 1),
                    disposed: disposed,
                  ),
              ],
            ),
          );

      // What the hook throws is re-thrown at the end of the disposal, which
      // runs on a discarded future: a guarded child zone catches it before
      // `flutter_test` ends the test on it.
      await runZonedGuarded(
        () async {
          await tester.pumpWidget(build(holder: true, successor: false));
          await tester.pumpAndSettle();

          await tester.pumpWidget(build(holder: false, successor: false));
          await settle(tester, until: () => false);
        },
        (error, stackTrace) => errors.add(error),
      );

      expect(
        tester.takeException(),
        isA<TimeoutException>(),
        reason: 'the expiry itself is reported',
      );
      expect(
        errors.single,
        isA<StateError>(),
        reason: 'and so is what the callback made of it',
      );
      expect(
        disposed,
        isEmpty,
        reason: 'the teardown is still parked; it was given up on, not run',
      );

      await tester.pumpWidget(build(holder: false, successor: true));
      await settle(tester, until: () => _readyCount(tester) == 1);

      expect(
        _readyCount(tester),
        1,
        reason: 'the key came back even though the teardown never finished',
      );
    });

    // A wait that expired is abandoned, not forgotten. The teardown behind it
    // goes on running with nobody holding its future, and a failure it reaches
    // long afterwards has no caller left to raise at -- so the one way out it
    // has is a report. Without it the failure would be lost in silence, which
    // is the one outcome this whole file exists to prevent.
    testWidgets('reports a teardown that fails after it was given up on',
        (tester) async {
      final disposed = <String>[];
      final hang = Completer<void>();
      final reported = <FlutterErrorDetails>[];
      final previousOnError = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = previousOnError);

      await tester.pumpWidget(
        _wrap(
          _Async(
            label: 'holder',
            disposeGate: hang,
            disposeAsyncTimeout: const Duration(milliseconds: 50),
            disposed: disposed,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.pumpWidget(_wrap(const SizedBox.shrink()));
      await settle(tester, until: () => reported.isNotEmpty);

      expect(
        reported.map((details) => details.exception),
        [isA<TimeoutException>()],
        reason: 'the expiry itself, and nothing else yet',
      );

      // Long after the disposal stopped waiting for it.
      hang.completeError(StateError('the teardown fell over at last'));
      await settle(tester, until: () => reported.length > 1);

      // Put back before the assertions below, and not only by the tear-down:
      // while it is in place, a failing `expect` is reported through it and
      // collected instead of ending the test, which leaves the run hanging
      // rather than red.
      FlutterError.onError = previousOnError;

      expect(
        reported.map((details) => details.exception),
        [
          isA<TimeoutException>(),
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'the teardown fell over at last',
          ),
        ],
        reason: 'nobody is waiting for this future any more, so a report is '
            'the only way the failure reaches anyone at all',
      );
      expect(disposed, isEmpty, reason: 'it never got as far as releasing');
    });

    // The expiry callback runs while the scope still holds everything: its
    // entry with the parent, its key, its model. It is reached from the
    // disposal itself, one step before the block that gives all of that back.
    testWidgets('disposes of itself after a failing onWaitForChildrenTimeout',
        (tester) async {
      final disposed = <String>[];
      final childGate = Completer<void>();
      final errors = <Object>[];

      // The disposal runs on a discarded future, so what it re-throws is an
      // uncaught error of the zone the teardown ran in: a guarded child zone
      // catches it before `flutter_test` ends the test on it. Nothing inside
      // that zone may throw, so every `expect` is made once it is gone.
      await runZonedGuarded(
        () async {
          await tester.pumpWidget(
            _wrap(
              _Async(
                label: 'parent',
                disposed: disposed,
                waitForChildrenTimeout: const Duration(milliseconds: 50),
                onWaitForChildrenTimeout: () =>
                    throw StateError('onWaitForChildrenTimeout failed'),
                child: _Async(
                  label: 'child',
                  disposed: disposed,
                  disposeGate: childGate,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // The child's disposal is held open, so the parent's wait for it
          // runs out and the expiry callback fails.
          await tester.pumpWidget(_wrap(const SizedBox.shrink()));
          await tester.pump(const Duration(milliseconds: 100));
          await settle(tester, until: () => disposed.contains('parent'));
        },
        (error, stackTrace) => errors.add(error),
      );

      expect(
        tester.takeException(),
        isA<TimeoutException>(),
        reason: 'the expiry itself is still reported',
      );
      expect(
        errors.single,
        isA<StateError>(),
        reason: 'and so is what the callback made of it',
      );
      expect(
        disposed,
        contains('parent'),
        reason: 'the wait was given up on, not the disposal',
      );

      childGate.complete();
      await settle(tester, until: () => disposed.contains('child'));
      expect(disposed, containsAll(['parent', 'child']));
    });

    // The disposal runs in four stages, each guarded on its own, and only the
    // first failure has a caller left to raise at -- the others used to end in
    // a log line that is off by default. Two of the four failing is an
    // ordinary path, not a contrived one: the wait for the children expired,
    // and the scope's own release fell over behind it.
    testWidgets('reports the second failure of a disposal that failed twice',
        (tester) async {
      final disposed = <String>[];
      final childGate = Completer<void>();
      final errors = <Object>[];
      final reported = <FlutterErrorDetails>[];
      final previousOnError = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = previousOnError);

      await runZonedGuarded(
        () async {
          await tester.pumpWidget(
            _wrap(
              _Async(
                label: 'parent',
                disposed: disposed,
                failOnDispose: true,
                waitForChildrenTimeout: const Duration(milliseconds: 50),
                onWaitForChildrenTimeout: () =>
                    throw StateError('onWaitForChildrenTimeout failed'),
                child: _Async(
                  label: 'child',
                  disposed: disposed,
                  disposeGate: childGate,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          await tester.pumpWidget(_wrap(const SizedBox.shrink()));
          await tester.pump(const Duration(milliseconds: 100));
          // The re-throw is the last thing the disposal does, after the block
          // that gives back what the scope was lent.
          await settle(tester, until: () => errors.isNotEmpty);
        },
        (error, stackTrace) => errors.add(error),
      );

      // Put back before the assertions, and not only by the tear-down: a
      // failing `expect` reported through it is collected instead of ending
      // the test, which leaves the run hanging rather than red.
      FlutterError.onError = previousOnError;

      expect(
        errors.single,
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'onWaitForChildrenTimeout failed',
        ),
        reason: 'the first failure is the one the caller hears',
      );
      expect(
        reported
            .map((details) => details.exception)
            .whereType<StateError>()
            .map((error) => error.message),
        contains('disposeAsync of parent failed'),
        reason: 'the second has no caller left to raise at, so a report is '
            'the only way out it has',
      );

      childGate.complete();
      await settle(tester, until: () => disposed.contains('child'));
    });
  });

  group('AsyncDataScope', () {
    testWidgets('disposes of itself after a failing onUnmount', (tester) async {
      final disposed = <String>[];

      await tester.pumpWidget(_wrap(_AsyncData(disposed: disposed)));
      await tester.pumpAndSettle();

      await tester.pumpWidget(_wrap(const SizedBox.shrink()));
      await settle(tester, until: () => disposed.isNotEmpty);

      expect(tester.takeException(), isA<StateError>());
      expect(
        disposed,
        ['data'],
        reason: 'the value the scope produced is released either way',
      );
    });
  });

  // The family whose whole point is that the controller is released on every
  // path. The path where `init()` failed and the release failed behind it is
  // covered by its own suite; these two are the ordinary one -- a controller
  // that was handed over, used, and then failed on its way out.
  group('AsyncControllerScope', () {
    testWidgets('releases its controller after a failing onUnmount',
        (tester) async {
      final controller = _Controller(failOnUnmount: true);

      await tester.pumpWidget(_wrap(_Controlled(controller: controller)));
      await tester.pumpAndSettle();

      await tester.pumpWidget(_wrap(const SizedBox.shrink()));
      await settle(tester, until: () => controller.calls.contains('dispose'));

      expect(
        tester.takeException(),
        isA<StateError>(),
        reason: 'the failure is still reported',
      );
      expect(
        controller.calls,
        ['init', 'onUnmount', 'dispose'],
        reason: 'the hook is user code; releasing the controller behind it is '
            'the whole promise of the family, and a synchronous half that '
            'threw is no reason to break it',
      );
    });

    // The other half: a release that fails is still a scope that has to give
    // back what it was lent. `dispose()` is the last thing the controller is
    // asked for, and the key is handed back after it.
    testWidgets('releases its scopeKey after a failing controller dispose',
        (tester) async {
      final controller = _Controller(failOnDispose: true);
      final disposed = <String>[];
      final errors = <Object>[];

      Widget build({required bool holder, required bool successor}) => _wrap(
            Column(
              children: [
                if (holder)
                  _Controlled(controller: controller, scopeKey: 'shared'),
                if (successor)
                  _Async(
                    label: 'successor',
                    scopeKey: 'shared',
                    scopeKeyTimeout: const Duration(days: 1),
                    disposed: disposed,
                  ),
              ],
            ),
          );

      // See the `onWaitForChildrenTimeout` test: a disposal that re-throws
      // does so on a discarded future.
      await runZonedGuarded(
        () async {
          await tester.pumpWidget(build(holder: true, successor: false));
          await tester.pumpAndSettle();

          await tester.pumpWidget(build(holder: false, successor: false));
          await settle(
            tester,
            until: () => controller.calls.contains('dispose'),
          );
        },
        (error, stackTrace) => errors.add(error),
      );

      expect(
        errors.single,
        isA<StateError>(),
        reason: 'the failure is still reported',
      );

      await tester.pumpWidget(build(holder: false, successor: true));
      await settle(tester, until: () => _readyCount(tester) == 1);

      expect(
        _readyCount(tester),
        1,
        reason: 'the key came back even though the controller refused to go',
      );
    });
  });

  group('Scope', () {
    // `unmount` on a dependency is the one hook that runs synchronously, in
    // the middle of the element leaving the tree. A failure there used to stop
    // the walk over the siblings and skip the base teardown behind it, so
    // nothing was ever disposed of.
    testWidgets('unmounts and disposes of every dependency after a failing one',
        (tester) async {
      final log = <String>[];

      await tester.pumpWidget(_wrap(_DepScope(log: log, failOnUnmount: 'a')));
      await tester.pumpAndSettle();

      await tester.pumpWidget(_wrap(const SizedBox.shrink()));
      await settle(tester, until: () => log.contains('dispose a'));

      expect(tester.takeException(), isA<StateError>());
      expect(
        log,
        containsAll(['unmount a', 'unmount b', 'dispose b', 'dispose a']),
        reason: 'one hook that failed is no reason to keep the rest of the '
            'dependencies holding what they took',
      );
    });

    // The synchronous half of the teardown, and the same rule as the
    // asynchronous half below: a state that failed to drop what it holds is
    // still a state whose dependencies are holding theirs, and `onUnmount` is
    // the only place they are dropped -- it runs once, and a scope that got
    // this far never comes back for a second attempt.
    testWidgets('unmounts its dependencies after a failing state unmount',
        (tester) async {
      final log = <String>[];

      await tester.pumpWidget(
        _wrap(_DepScope(log: log, failOnStateUnmount: true)),
      );
      await tester.pumpAndSettle();

      await tester.pumpWidget(_wrap(const SizedBox.shrink()));
      await settle(tester, until: () => log.contains('dispose a'));

      expect(
        tester.takeException(),
        isA<StateError>(),
        reason: 'the failure is still reported',
      );
      expect(
        log,
        containsAll(['unmount b', 'unmount a']),
        reason: 'the state failed to let go of its own synchronously; the '
            'dependencies still have to let go of theirs, and this is the '
            'only pass that does it',
      );
    });

    testWidgets('disposes of its dependencies after a failing state disposal',
        (tester) async {
      final log = <String>[];
      final errors = <Object>[];

      // See the `onWaitForChildrenTimeout` test: a disposal that re-throws
      // does so on a discarded future.
      await runZonedGuarded(
        () async {
          await tester.pumpWidget(
            _wrap(_DepScope(log: log, failOnStateDispose: true)),
          );
          await tester.pumpAndSettle();

          await tester.pumpWidget(_wrap(const SizedBox.shrink()));
          await settle(tester, until: () => log.contains('dispose a'));
        },
        (error, stackTrace) => errors.add(error),
      );

      expect(
        errors.single,
        isA<StateError>(),
        reason: 'the failure is still reported',
      );
      expect(
        log,
        containsAll(['dispose b', 'dispose a']),
        reason: 'the state failed to let go of its own; the dependencies '
            'still have to let go of theirs',
      );
    });

    // Both halves of the teardown can fail, and each half is the other's
    // equal: the second is run whatever the first did. Only one of the two
    // failures has a caller to be raised at, though, and it must be the first
    // -- the state let go before the dependencies did, so its failure is the
    // one that explains the other.
    //
    // The container is written by hand here rather than built by
    // `ScopeAutoDependencies`, and that is the point: the automatic one
    // absorbs what its own children throw on the way out, so the only
    // container that can hand a failure to the state above it is a
    // hand-written one.
    testWidgets(
        'keeps the failure of the state when the dependencies fail to unmount '
        'behind it', (tester) async {
      final log = <String>[];
      final reported = <FlutterErrorDetails>[];
      final previousOnError = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = previousOnError);

      await tester.pumpWidget(
        _wrap(
          _PlainDepScope(
            log: log,
            failOnStateUnmount: true,
            failOnDepsUnmount: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.pumpWidget(_wrap(const SizedBox.shrink()));
      await settle(tester, until: () => log.contains('dispose deps'));

      // See the test above: put back before the assertions, or a failing
      // `expect` is collected instead of ending the test.
      FlutterError.onError = previousOnError;

      expect(
        reported
            .where((details) => details.library != 'scopo')
            .map((details) => details.exception)
            .whereType<StateError>()
            .map((error) => error.message),
        contains('the state failed to unmount itself'),
        reason: 'the first failure leaves the way it always has -- through '
            'the caller, which here is the framework unmounting the element',
      );
      expect(
        reported
            .where((details) => details.library == 'scopo')
            .map((details) => details.exception)
            .whereType<StateError>()
            .map((error) => error.message),
        contains('the dependencies failed to unmount'),
        reason: 'and the second leaves through a report, since the throw is '
            'taken by the first',
      );
    });

    // The same rule in the asynchronous half, where the two failures are told
    // apart by where they end up: the first on the discarded future the
    // disposal runs on, the second in a report.
    testWidgets(
        'keeps the failure of the state when the dependencies fail to dispose '
        'behind it', (tester) async {
      final log = <String>[];
      final errors = <Object>[];
      final reported = <FlutterErrorDetails>[];
      final previousOnError = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = previousOnError);

      await runZonedGuarded(
        () async {
          await tester.pumpWidget(
            _wrap(
              _PlainDepScope(
                log: log,
                failOnStateDispose: true,
                failOnDepsDispose: true,
              ),
            ),
          );
          await tester.pumpAndSettle();

          // The re-throw is the last thing the disposal does, after the block
          // that gives back what the scope was lent: waiting for it is waiting
          // for the whole teardown, model included.
          await tester.pumpWidget(_wrap(const SizedBox.shrink()));
          await settle(tester, until: () => errors.isNotEmpty);
        },
        (error, stackTrace) => errors.add(error),
      );

      FlutterError.onError = previousOnError;

      expect(
        errors.single,
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'the state failed to dispose of itself',
        ),
        reason: 'the first failure is the one the caller hears',
      );
      expect(
        reported
            .map((details) => details.exception)
            .whereType<StateError>()
            .map((error) => error.message),
        contains('the dependencies failed to dispose'),
        reason: 'and the second is reported rather than lost',
      );
      expect(
        log,
        ['unmount deps', 'dispose deps'],
        reason: 'a failing state is no reason to skip either half',
      );
    });
  });
}

Widget _wrap(Widget child) => Directionality(
      textDirection: TextDirection.ltr,
      child: AsyncScopeCoordinator(child: child),
    );

/// How many [_Async] scopes have finished initializing.
int _readyCount(WidgetTester tester) => tester
    .elementList(find.byType(_Async))
    .whereType<AsyncScopeContext<_Async>>()
    .where((element) => element.state is AsyncScopeReady)
    .length;

/// An asynchronous scope whose hooks can be made to fail one at a time.
final class _Async extends AsyncScopeBase<_Async> {
  final String label;
  final bool failOnUnmount;
  final bool failOnDispose;
  final List<String> disposed;

  /// Holds [disposeAsync] open, so this scope can keep its parent waiting.
  final Completer<void>? disposeGate;

  /// Parks [initAsync] on this, so this scope cannot be cancelled.
  final Completer<void>? initGate;

  const _Async({
    required this.label,
    required this.disposed,
    this.failOnUnmount = false,
    this.failOnDispose = false,
    this.disposeGate,
    this.initGate,
    super.scopeKey,
    super.scopeKeyTimeout,
    super.initCancellationTimeout,
    super.onInitCancellationTimeout,
    super.disposeAsyncTimeout,
    super.onDisposeAsyncTimeout,
    super.waitForChildrenTimeout,
    super.onWaitForChildrenTimeout,
    Widget? child,
  }) : super(child: child ?? const SizedBox.shrink());

  @override
  Stream<AsyncScopeInitState> initAsync(BuildContext context) async* {
    if (initGate case final gate?) {
      await gate.future;
    }
    yield AsyncScopeReady();
  }

  @override
  void onUnmount() {
    if (failOnUnmount) {
      throw StateError('onUnmount failed');
    }
  }

  @override
  Future<void> disposeAsync() async {
    if (disposeGate case final gate?) {
      await gate.future;
    }
    disposed.add(label);
    if (failOnDispose) {
      throw StateError('disposeAsync of $label failed');
    }
  }

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

/// An asynchronous scope producing a value, with a failing `onUnmount`.
final class _AsyncData extends AsyncDataScopeBase<_AsyncData, String> {
  final List<String> disposed;

  const _AsyncData({required this.disposed})
      : super(child: const SizedBox.shrink());

  @override
  Stream<AsyncDataScopeInitState<Object, String>> initData(
    BuildContext context,
  ) async* {
    yield AsyncDataScopeReady('data');
  }

  @override
  void onUnmount(String? data) => throw StateError('onUnmount failed');

  @override
  FutureOr<void> disposeData(String data) {
    disposed.add(data);
  }

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
  Widget buildOnReady(BuildContext context, String data) => child;
}

/// A scope owning a controller, handed one made outside so the test can read
/// what it was asked for.
final class _Controlled
    extends AsyncControllerScopeBase<_Controlled, _Controller> {
  final _Controller controller;

  const _Controlled({required this.controller, super.scopeKey})
      : super(child: const SizedBox.shrink());

  @override
  _Controller createController(BuildContext context) => controller;

  @override
  Widget buildOnInitializing(BuildContext context) => const SizedBox.shrink();

  @override
  Widget buildOnError(
    BuildContext context,
    Object error,
    StackTrace stackTrace,
  ) =>
      const SizedBox.shrink();

  @override
  Widget buildOnReady(BuildContext context, _Controller controller) => child;
}

/// A controller that records what it was asked for, and can refuse one step.
final class _Controller extends ScopeController {
  final calls = <String>[];
  final bool failOnUnmount;
  final bool failOnDispose;

  _Controller({this.failOnUnmount = false, this.failOnDispose = false});

  @override
  Future<void> init() async => calls.add('init');

  @override
  void onUnmount() {
    calls.add('onUnmount');
    if (failOnUnmount) {
      throw StateError('onUnmount failed');
    }
  }

  @override
  FutureOr<void> dispose() {
    calls.add('dispose');
    if (failOnDispose) {
      throw StateError('dispose failed');
    }
  }
}

/// A scope with two dependencies, either of whose hooks can be made to fail.
final class _DepScope extends Scope<_DepScope, _Deps, _DepScopeState> {
  final List<String> log;
  final String? failOnUnmount;
  final bool failOnStateUnmount;
  final bool failOnStateDispose;

  const _DepScope({
    required this.log,
    this.failOnUnmount,
    this.failOnStateUnmount = false,
    this.failOnStateDispose = false,
  }) : super(child: const SizedBox.shrink());

  @override
  Stream<ScopeInitState<Object, _Deps>> initDependencies(
    BuildContext context,
  ) =>
      _Deps(log: log, failOnUnmount: failOnUnmount).init(context);

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

final class _Deps extends ScopeAutoDependencies<_Deps, BuildContext> {
  final List<String> log;
  final String? failOnUnmount;

  _Deps({required this.log, this.failOnUnmount});

  FutureOr<void> Function(DepHelper dep) _init(String name) => (dep) {
        dep
          ..unmount = () {
            log.add('unmount $name');
            if (failOnUnmount == name) {
              throw StateError('unmount of $name failed');
            }
          }
          ..dispose = () => log.add('dispose $name');
      };

  @override
  ScopeDependency buildDependencies(BuildContext context) => sequential('', [
        dep('a', _init('a')),
        dep('b', _init('b')),
      ]);
}

final class _DepScopeState
    extends ScopeState<_DepScope, _Deps, _DepScopeState> {
  @override
  void onUnmount() {
    super.onUnmount();
    if (params.failOnStateUnmount) {
      throw StateError('the state failed to unmount itself');
    }
  }

  @override
  FutureOr<void> disposeAsync() {
    if (params.failOnStateDispose) {
      throw StateError('the state failed to dispose of itself');
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// A scope over a hand-written container, so that both halves of the teardown
/// can be made to fail on both sides at once.
///
/// [ScopeAutoDependencies] never hands a failure up: what its children throw
/// on the way out it reports itself. A container written against the interface
/// is the one that can, which is what the two halves of [ScopeCoreState] are
/// written for.
final class _PlainDepScope
    extends Scope<_PlainDepScope, _PlainDeps, _PlainDepScopeState> {
  final List<String> log;
  final bool failOnDepsUnmount;
  final bool failOnDepsDispose;
  final bool failOnStateUnmount;
  final bool failOnStateDispose;

  const _PlainDepScope({
    required this.log,
    this.failOnDepsUnmount = false,
    this.failOnDepsDispose = false,
    this.failOnStateUnmount = false,
    this.failOnStateDispose = false,
  }) : super(child: const SizedBox.shrink());

  @override
  Stream<ScopeInitState<Object, _PlainDeps>> initDependencies(
    BuildContext context,
  ) =>
      _PlainDeps(
        log: log,
        failOnUnmount: failOnDepsUnmount,
        failOnDispose: failOnDepsDispose,
      ).asStream();

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
  _PlainDepScopeState createState() => _PlainDepScopeState();
}

final class _PlainDeps implements ScopeDependencies {
  final List<String> log;
  final bool failOnUnmount;
  final bool failOnDispose;

  _PlainDeps({
    required this.log,
    this.failOnUnmount = false,
    this.failOnDispose = false,
  });

  @override
  void onUnmount() {
    log.add('unmount deps');
    if (failOnUnmount) {
      throw StateError('the dependencies failed to unmount');
    }
  }

  @override
  FutureOr<void> dispose() {
    log.add('dispose deps');
    if (failOnDispose) {
      throw StateError('the dependencies failed to dispose');
    }
  }
}

final class _PlainDepScopeState
    extends ScopeState<_PlainDepScope, _PlainDeps, _PlainDepScopeState> {
  @override
  void onUnmount() {
    super.onUnmount();
    if (params.failOnStateUnmount) {
      throw StateError('the state failed to unmount itself');
    }
  }

  @override
  FutureOr<void> disposeAsync() {
    if (params.failOnStateDispose) {
      throw StateError('the state failed to dispose of itself');
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
