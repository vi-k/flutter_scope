// ignore_for_file: discarded_futures

import 'dart:async';

import 'package:scopo/scopo.dart';
import 'package:test/test.dart';

/// A container whose single dependency takes something and then goes wrong.
///
/// This is the shape the contract is about: an initializer that has already
/// acquired a resource and registered its disposer does not get to keep it just
/// because it failed afterwards.
final class _Deps extends ScopeAutoDependencies<_Deps, void> {
  final List<String> released;
  final FutureOr<void> Function(DepHelper dep) _init;

  _Deps(this.released, this._init);

  @override
  bool get autoDisposeOnError => false;

  @override
  ScopeDependency buildDependencies(void context) =>
      sequential('', [dep('holder', _init)]);
}

Future<void> _runInit(_Deps deps) async {
  try {
    await deps.init(null).drain<void>();
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

      await _runInit(deps);
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

      await _runInit(deps);
      await deps.dispose();

      expect(released, ['holder']);
    });

    test('releases nothing when the initializer took nothing', () async {
      final released = <String>[];
      final deps = _Deps(released, (dep) {
        throw Exception('boom');
      });

      await _runInit(deps);
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

      await _runInit(deps);
      await deps.dispose();
      await deps.dispose();

      expect(released, ['holder']);
    });
  });
}
