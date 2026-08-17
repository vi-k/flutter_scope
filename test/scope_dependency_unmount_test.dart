// ignore_for_file: discarded_futures

import 'dart:async';

import 'package:scopo/scopo.dart';
import 'package:test/test.dart';

/// The promise this file is about, written the same way in four dartdocs and
/// in `doc/full_scope.md`:
///
/// > Runs exactly once, **always before [dispose]**, whether the scope was
/// > removed from the tree or closed with `close()`.
///
/// `unmount` is where a dependency lets go of what the asynchronous teardown
/// cannot wait for — an unsubscribe, most often. If `dispose` runs and
/// `unmount` does not, that subscription lives on and keeps writing into a
/// sink the disposer has already closed.
final class _Deps extends ScopeAutoDependencies<_Deps, void> {
  final List<String> log;
  final bool failSecond;

  _Deps(this.log, {required this.failSecond});

  void _both(DepHelper dep) {
    final name = dep.name;

    dep
      ..unmount = () {
        log.add('unmount $name');
      }
      ..dispose = () {
        log.add('dispose $name');
      };
  }

  @override
  ScopeDependency buildDependencies(void context) => sequential('', [
        dep('a', _both),
        dep('b', (dep) {
          _both(dep);
          if (failSecond) {
            throw Exception('b failed to initialize');
          }
        }),
      ]);
}

Future<void> _runInit(_Deps deps) async {
  try {
    await deps.init(null).drain<void>();
  } on Object {
    // The failure is the fixture; what happens to the teardown is the test.
  }
}

/// Every dependency that was released must have been unmounted first.
void _expectUnmountBeforeDispose(List<String> log) {
  for (final entry in log) {
    if (!entry.startsWith('dispose ')) continue;

    final name = entry.substring('dispose '.length);
    final unmount = log.indexOf('unmount $name');

    expect(
      unmount,
      isNonNegative,
      reason: '`$name` was disposed of without ever being unmounted, and the '
          'dartdoc of `unmount` promises it runs whichever way the scope '
          'goes',
    );
    expect(
      unmount,
      lessThan(log.indexOf(entry)),
      reason: 'the promise is not just that `unmount` runs, but that it runs '
          '*before* `dispose`: what it lets go of must be gone before the '
          'disposer closes what it was writing into',
    );
  }
}

void main() {
  group('unmount always runs before dispose', () {
    test('when the initialization succeeded', () async {
      final log = <String>[];
      final deps = _Deps(log, failSecond: false);

      await _runInit(deps);
      deps.onUnmount();
      await deps.dispose();

      expect(
        log,
        ['unmount a', 'unmount b', 'dispose b', 'dispose a'],
        reason: 'the control: unmounts go down the tree, disposals back up',
      );
      _expectUnmountBeforeDispose(log);
    });

    test('when the initialization failed halfway', () async {
      final log = <String>[];
      final deps = _Deps(log, failSecond: true);

      // No `onUnmount()` here on purpose. A scope whose initialization failed
      // never reaches `ScopeReady`, so the element never gets the container
      // and its own `onUnmount()` has nothing to call: the container is torn
      // down from inside the generator instead, by `autoDisposeOnError`. That
      // path is the one the promise has to hold on.
      await _runInit(deps);

      expect(
        log,
        contains('dispose a'),
        reason: 'the disposer of the dependency that did initialize runs -- '
            'this is the established behaviour the promise is measured '
            'against',
      );
      _expectUnmountBeforeDispose(log);
    });
  });

  group('unmount runs exactly once', () {
    test('however many passes reach the container', () async {
      final log = <String>[];
      final deps = _Deps(log, failSecond: false);

      await _runInit(deps);

      // Three passes at the same container. One is what a scope leaving the
      // tree does through its element; the others are what an owner holding
      // the container by hand can do, and what a failed initialization now
      // does from inside the generator. None of them knows about the others,
      // which is why they are written apart rather than as one cascade.
      deps.onUnmount();
      // ignore: cascade_invocations
      deps.onUnmount();
      await deps.dispose();
      deps.onUnmount();

      expect(
        log.where((entry) => entry.startsWith('unmount')),
        ['unmount a', 'unmount b'],
        reason: 'the hook lets go of something -- a subscription, a listener '
            '-- and letting go of it twice is not the same as once',
      );
    });

    test('even for a dependency that has nothing to dispose of', () async {
      final log = <String>[];
      final deps = _UnmountOnly(log);

      await _runInit2(deps);

      deps.onUnmount();
      await deps.dispose();
      deps.onUnmount();

      expect(
        log,
        ['unmount lonely'],
        reason: 'the disposal is what used to drop the helper, and a '
            'dependency with no disposer keeps it: without a guard of its own '
            'the hook would run again on every later pass',
      );
    });
  });
}

/// A dependency that registers `unmount` and nothing else.
final class _UnmountOnly extends ScopeAutoDependencies<_UnmountOnly, void> {
  final List<String> log;

  _UnmountOnly(this.log);

  @override
  ScopeDependency buildDependencies(void context) => dep('lonely', (helper) {
        helper.unmount = () {
          log.add('unmount lonely');
        };
      });
}

Future<void> _runInit2(_UnmountOnly deps) async {
  await deps.init(null).drain<void>();
}
