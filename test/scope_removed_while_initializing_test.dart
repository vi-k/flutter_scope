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
