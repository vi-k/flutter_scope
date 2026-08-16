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
  late final Duration? defaultScopeKeysTimeout;
  late final Duration? defaultWaitForChildrenTimeout;
  late final Duration? defaultInitCancellationTimeout;
  late final Duration? defaultDisposeAsyncTimeout;

  setUpAll(() {
    defaultScopeKeysTimeout = ScopeConfig.defaultScopeKeysTimeout;
    defaultWaitForChildrenTimeout = ScopeConfig.defaultWaitForChildrenTimeout;
    defaultInitCancellationTimeout = ScopeConfig.defaultInitCancellationTimeout;
    defaultDisposeAsyncTimeout = ScopeConfig.defaultDisposeAsyncTimeout;
  });

  tearDown(() {
    ScopeConfig.defaultScopeKeysTimeout = defaultScopeKeysTimeout;
    ScopeConfig.defaultWaitForChildrenTimeout = defaultWaitForChildrenTimeout;
    ScopeConfig.defaultInitCancellationTimeout = defaultInitCancellationTimeout;
    ScopeConfig.defaultDisposeAsyncTimeout = defaultDisposeAsyncTimeout;
  });

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
  final List<String> disposed;

  /// Holds [disposeAsync] open, so this scope can keep its parent waiting.
  final Completer<void>? disposeGate;

  /// Parks [initAsync] on this, so this scope cannot be cancelled.
  final Completer<void>? initGate;

  const _Async({
    required this.label,
    required this.disposed,
    this.failOnUnmount = false,
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
