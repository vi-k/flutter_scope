import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scopo/scopo.dart';

import 'utils/settle.dart';

/// The order of the hooks a scope offers, on both ways out and in.
///
/// Everything here is about *when* a hook runs relative to the others, so the
/// assertions are lists, never counts.
void main() {
  group('onMount', () {
    testWidgets('runs before the initialization starts', (tester) async {
      final order = <String>[];

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: AsyncScope(
            mount: (context) => order.add('onMount'),
            init: (context) {
              order.add('init');

              return Stream.value(AsyncScopeReady());
            },
            dispose: () {},
            initBuilder: (context, progress) => const SizedBox.shrink(),
            errorBuilder: (context, error, stackTrace, progress) =>
                const SizedBox.shrink(),
            builder: (context) => const SizedBox.shrink(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        order,
        ['onMount', 'init'],
        reason: 'the hook is documented as the moment before the work begins',
      );
    });

    testWidgets('runs before the initialization of a data scope too',
        (tester) async {
      final order = <String>[];

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: AsyncDataScope<String>(
            mount: (context) => order.add('onMount'),
            init: (context) {
              order.add('init');

              return Stream.value(AsyncDataScopeReady('data'));
            },
            dispose: (data) {},
            initBuilder: (context, progress) => const SizedBox.shrink(),
            errorBuilder: (context, error, stackTrace, progress) =>
                const SizedBox.shrink(),
            builder: (context, data) => const SizedBox.shrink(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(order, ['onMount', 'init']);
    });

    testWidgets('sees the scopes above it', (tester) async {
      String? seen;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: _Ancestor(
            value: 'above',
            child: AsyncScope(
              mount: (context) => seen = _Ancestor.of(context),
              init: (context) => Stream.value(AsyncScopeReady()),
              dispose: () {},
              initBuilder: (context, progress) => const SizedBox.shrink(),
              errorBuilder: (context, error, stackTrace, progress) =>
                  const SizedBox.shrink(),
              builder: (context) => const SizedBox.shrink(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        seen,
        'above',
        reason: 'the element is connected to its ancestors by then',
      );
    });
  });

  // The synchronous half of the teardown -- dropping subscriptions -- and the
  // asynchronous half -- releasing what has to be awaited -- are a pair, and
  // the first has to come first. It used to be wired to `Element.unmount`
  // rather than to the teardown, so `close()`, which keeps the element
  // mounted, skipped it altogether and left whatever it drops holding on.
  group('the synchronous teardown', () {
    setUp(_order.clear);

    testWidgets('runs before the asynchronous one when the scope is removed',
        (tester) async {
      await tester.pumpWidget(const _DepHost());
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester, until: () => _order.contains('dep.dispose'));

      expect(
        _order,
        ['state.onUnmount', 'dep.unmount', 'state.disposeAsync', 'dep.dispose'],
      );
    });

    testWidgets('runs before the asynchronous one when the scope is closed',
        (tester) async {
      await tester.pumpWidget(const _DepHost());
      await tester.pumpAndSettle();

      unawaited(_DepState.instance!.close());
      await settle(tester, until: () => _order.contains('dep.dispose'));

      expect(
        _order,
        ['state.onUnmount', 'dep.unmount', 'state.disposeAsync', 'dep.dispose'],
        reason: 'a closed scope lets go of the same things in the same order',
      );
    });

    testWidgets('runs once, even when a close is followed by a removal',
        (tester) async {
      await tester.pumpWidget(const _DepHost());
      await tester.pumpAndSettle();

      unawaited(_DepState.instance!.close());
      await settle(tester, until: () => _order.contains('dep.dispose'));

      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester, until: () => false);

      expect(
        _order.where((step) => step == 'state.onUnmount'),
        hasLength(1),
      );
      expect(
        _order.where((step) => step == 'dep.unmount'),
        hasLength(1),
      );
    });

    // The two halves of a `Scope` initialize separately -- the container
    // through `initDependencies`, the state through its own `initAsync` --
    // and a failure of each leaves a different amount of the teardown behind.
    // The `full_scope` topic states both as a table; these two pin it.
    testWidgets('drops the state entirely when initDependencies failed',
        (tester) async {
      _Deps.failing = true;
      addTearDown(() => _Deps.failing = false);

      await runZonedGuarded(
        () async {
          await tester.pumpWidget(const _DepHost());
          await tester.pumpAndSettle();
          tester.takeException();

          await tester.pumpWidget(const SizedBox.shrink());
          await settle(tester, until: () => _order.contains('dep.dispose'));
          tester.takeException();
        },
        (_, __) {},
      );

      expect(
        _order,
        ['dep.unmount', 'dep.dispose'],
        reason: 'the ready branch was never built, so `createState()` never '
            'ran and there is no state for `onUnmount`/`disposeAsync` to run '
            'on -- while the dependencies, which did exist, are still given '
            'back, by the container tearing itself down from inside its own '
            'initialization',
      );
    });

    testWidgets(
        'unmounts but does not dispose of a state whose initAsync '
        'failed', (tester) async {
      _DepState.failing = true;
      addTearDown(() => _DepState.failing = false);

      await runZonedGuarded(
        () async {
          await tester.pumpWidget(const _DepHost());
          await tester.pumpAndSettle();
          tester.takeException();

          await tester.pumpWidget(const SizedBox.shrink());
          await settle(tester, until: () => _order.contains('dep.dispose'));
          tester.takeException();
        },
        (_, __) {},
      );

      expect(
        _order,
        ['state.onUnmount', 'dep.unmount', 'dep.dispose'],
        reason: 'the state exists and may already hold a subscription, so the '
            'synchronous half runs; `disposeAsync` is written against a state '
            'that finished initializing and this one did not, so it is '
            'skipped -- the same rule as for the scope itself, one level down',
      );
    });

    testWidgets('of an AsyncScope still precedes its disposal', (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: AsyncScope(
            init: (context) => Stream.value(AsyncScopeReady()),
            unmount: () => _order.add('onUnmount'),
            dispose: () => _order.add('disposeAsync'),
            initBuilder: (context, progress) => const SizedBox.shrink(),
            errorBuilder: (context, error, stackTrace, progress) =>
                const SizedBox.shrink(),
            builder: (context) => const SizedBox.shrink(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester, until: () => _order.contains('disposeAsync'));

      expect(_order, ['onUnmount', 'disposeAsync']);
    });
  });
}

final _order = <String>[];

final class _DepHost extends StatelessWidget {
  const _DepHost();

  @override
  Widget build(BuildContext context) => const Directionality(
        textDirection: TextDirection.ltr,
        child: _DepScope(),
      );
}

final class _DepScope extends Scope<_DepScope, _Deps, _DepState> {
  const _DepScope();

  @override
  Stream<ScopeInitState<Object, _Deps>> initDependencies(
    BuildContext context,
  ) =>
      _Deps().init(context);

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
  _DepState createState() => _DepState();
}

final class _Deps extends ScopeAutoDependencies<_Deps, BuildContext> {
  /// Makes the one dependency fail *after* registering its teardown, which is
  /// the position the promise is about.
  static bool failing = false;

  @override
  ScopeDependency buildDependencies(BuildContext context) => sequential('', [
        dep('a', (dep) {
          dep
            ..unmount = (() => _order.add('dep.unmount'))
            ..dispose = (() => _order.add('dep.dispose'));
          if (failing) {
            throw StateError('dependency a failed');
          }
        }),
      ]);
}

final class _DepState extends ScopeState<_DepScope, _Deps, _DepState> {
  static _DepState? instance;

  /// Makes the state's own asynchronous half fail, which is a different
  /// failure from the container's and has a different answer.
  static bool failing = false;

  @override
  void initState() {
    super.initState();
    instance = this;
  }

  @override
  FutureOr<void> initAsync() {
    if (failing) {
      throw StateError('state initAsync failed');
    }
  }

  @override
  void onUnmount() {
    _order.add('state.onUnmount');
    super.onUnmount();
  }

  @override
  Future<void> disposeAsync() async => _order.add('state.disposeAsync');

  /// Sized, not shrunk: `close()` captures a screenshot of the subtree, and a
  /// zero-sized one cannot be captured.
  @override
  Widget build(BuildContext context) => const SizedBox(width: 8, height: 8);
}

/// A plain inherited widget, to show what the hook can reach.
final class _Ancestor extends InheritedWidget {
  final String value;

  const _Ancestor({required this.value, required super.child});

  static String? of(BuildContext context) => context
      .getElementForInheritedWidgetOfExactType<_Ancestor>()
      ?.widget
      .let((widget) => (widget as _Ancestor).value);

  @override
  bool updateShouldNotify(_Ancestor oldWidget) => value != oldWidget.value;
}

extension<T extends Object> on T {
  R let<R>(R Function(T value) transform) => transform(this);
}
