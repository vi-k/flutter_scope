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
  await deps.init(null, ScopeInitHandle().context);
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
///
/// It parks on a gate the test opens rather than on a delay it waits out.
/// A real timer made the window a matter of wall-clock -- the assertion
/// between the two halves was true only while the continuation had not been
/// held up longer than the delay, which on a loaded machine is not a promise
/// -- and cost a fifth of a second of every run for a window that is opened
/// and closed by the test anyway.
final class _SlowController extends ScopeController {
  final List<String> calls;
  final Completer<void> gate;

  _SlowController(this.calls, this.gate);

  @override
  Future<void> init() async {
    calls.add('init');
    await gate.future;
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

  _SlowDeps(this.calls, this.gate);

  final Completer<void> gate;

  @override
  ScopeDependency buildDependencies(void context) => sequential('', [
        controllerDep('player', () => player = _SlowController(calls, gate)),
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

      await expectLater(
        deps.init(null, ScopeInitHandle().context),
        throwsException,
      );

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
        final gate = Completer<void>();
        final deps = _SlowDeps(calls, gate);

        final handle = ScopeInitHandle();
        // The caller drives the tree itself, so the cancellation it asks for
        // comes back to it as a throw. Caught here because it is the answer,
        // not a failure.
        final walk = () async {
          try {
            await deps.init(null, handle.context);
          } on ScopeInitCancelled {
            calls.add('cancelled');
          }
        }();
        await pumpEventQueue();

        expect(
          calls,
          ['init'],
          reason: 'the walk is parked inside `performInit` -- this is the '
              'window the whole registration order is about',
        );

        // Asked for, then let through: the cancellation reaches the walk at
        // once, but the initializer it is parked inside is not interrupted --
        // Dart cannot interrupt somebody else's `await` -- so the walk ends
        // only once `init` does.
        handle.cancel();
        gate.complete();
        await walk;

        expect(
          calls,
          ['init', 'init finished', 'onUnmount', 'dispose', 'cancelled'],
          reason: 'cancelling the walk does not abandon the initializer that '
              'is already running: it finishes, and only then does the '
              'teardown of the walk unmount and dispose of what was '
              'registered. So a controller half-way through `init` is never '
              'left holding what it took -- it finishes, then it is released',
        );
        expect(deps.player.mounted, isFalse);
      },
      // A hang, not a failure, is what a lost cancellation looks like here.
      timeout: const Timeout(Duration(seconds: 10)),
    );
  });
}
