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
        controller('player', () => player = _TestController(calls)),
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

final class _FailingDeps extends ScopeAutoDependencies<_FailingDeps, void> {
  final List<String> calls;
  late final _FailingController player;

  _FailingDeps(this.calls);

  @override
  ScopeDependency buildDependencies(void context) => sequential('', [
        controller('player', () => player = _FailingController(calls)),
      ]);
}

void main() {
  group('ScopeAutoDependencies.controller', () {
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
  });
}
