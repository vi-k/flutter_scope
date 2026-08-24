// ignore_for_file: discarded_futures

import 'dart:async';

import 'package:scopo/scopo.dart';
import 'package:test/test.dart';

/// Logs its three hooks, the same shape `async_controller_scope_test.dart`
/// uses to watch `ScopeController` on its own.
final class _TestController extends ScopeController {
  final List<String> calls;

  _TestController(this.calls);

  @override
  Future<void> init() async => calls.add('init');

  @override
  void onUnmount() => calls.add('onUnmount');

  @override
  Future<void> dispose() async => calls.add('dispose');
}

final class _Deps extends ScopeAutoDependencies<_Deps, void> {
  final List<String> calls;
  late final _TestController player;

  _Deps(this.calls);

  @override
  ScopeDependency buildDependencies(void context) => sequential('', [
        controllerDep('player', () => player = _TestController(calls)),
      ]);
}

Future<void> _init(_Deps deps) async {
  await deps.init(null).drain<void>();
}

/// Its `init` logs and then throws, the way a real controller's would if
/// whatever it awaits fails.
final class _FailingController extends ScopeController {
  final List<String> calls;

  _FailingController(this.calls);

  @override
  Future<void> init() async {
    calls.add('init');
    throw Exception('boom');
  }

  @override
  void onUnmount() => calls.add('onUnmount');

  @override
  Future<void> dispose() async => calls.add('dispose');
}

/// Its `init` suspends, so the walk can be cancelled while `performInit` is
/// still in flight -- the path a scope takes when it leaves the tree before
/// its dependencies are up.
final class _SlowController extends ScopeController {
  static const step = Duration(milliseconds: 200);

  final List<String> calls;

  _SlowController(this.calls);

  @override
  Future<void> init() async {
    calls.add('init');
    await Future<void>.delayed(step);
    calls.add('init finished');
  }

  @override
  void onUnmount() => calls.add('onUnmount');

  @override
  Future<void> dispose() async => calls.add('dispose');
}

final class _SlowDeps extends ScopeAutoDependencies<_SlowDeps, void> {
  final List<String> calls;
  late final _SlowController player;

  _SlowDeps(this.calls);

  @override
  ScopeDependency buildDependencies(void context) => sequential('', [
        controllerDep('player', () => player = _SlowController(calls)),
      ]);
}

final class _FailingDeps extends ScopeAutoDependencies<_FailingDeps, void> {
  final List<String> calls;
  late final _FailingController player;

  _FailingDeps(this.calls);

  @override
  ScopeDependency buildDependencies(void context) => sequential('', [
        controllerDep('player', () => player = _FailingController(calls)),
      ]);
}

void main() {
  group('ScopeAutoDependencies.controllerDep', () {
    test('runs create, performInit, performUnmount and performDispose',
        () async {
      final calls = <String>[];
      final deps = _Deps(calls);

      await _init(deps);

      expect(calls, ['init']);
      expect(deps.player.mounted, isTrue);

      deps.onUnmount();
      await deps.dispose();

      expect(calls, ['init', 'onUnmount', 'dispose']);
      expect(deps.player.mounted, isFalse);
    });

    test('releases the controller when its init fails, like any dep()',
        () async {
      final calls = <String>[];
      final deps = _FailingDeps(calls);

      await expectLater(deps.init(null).drain<void>(), throwsException);

      expect(
        calls,
        ['init', 'onUnmount', 'dispose'],
        reason: 'the handle was registered before `performInit` was '
            'awaited, so `autoDisposeOnError` finds it and releases the '
            'controller even though `init` never returned',
      );
    });

    test(
      'releases the controller when the walk is cancelled mid-init',
      () async {
        final calls = <String>[];
        final deps = _SlowDeps(calls);

        final subscription = deps.init(null).listen(null);
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(
          calls,
          ['init'],
          reason: 'the walk is parked inside `performInit` -- this is the '
              'window the whole registration order is about',
        );

        await subscription.cancel();

        expect(
          calls,
          ['init', 'init finished', 'onUnmount', 'dispose'],
          reason: 'cancelling the walk does not abandon the initializer that '
              'is already running: `cancel()` waits for it, and only then '
              'does the `finally` of the generator unmount and dispose of '
              'what was registered. So a controller half-way through `init` '
              'is never left holding what it took -- it finishes, then it is '
              'released',
        );
        expect(deps.player.mounted, isFalse);
      },
      // A hang, not a failure, is what a lost cancellation looks like here.
      timeout: const Timeout(Duration(seconds: 10)),
    );
  });
}
