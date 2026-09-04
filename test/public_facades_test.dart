import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scopo/scopo.dart';

import 'utils/settle.dart';

/// The facades a user actually extends, which nothing in the suite had built.
///
/// The behaviour lives one layer below, in the `*Core` classes, and that is
/// where the suite works. What is left untried in between is the wiring: the
/// facade element forwards every hook and every parameter to the widget, one
/// line each, and a line that forwards the wrong thing — or forwards nothing —
/// reads exactly like its neighbours.
void main() {
  group('LiteScope', () {
    testWidgets('drives the hooks of the widget and of the state it makes',
        (tester) async {
      final log = <String>[];

      await tester.pumpWidget(_wrap(_Lite(log: log)));
      await tester.pumpAndSettle();

      expect(
        log,
        [
          'buildOnWaiting',
          'init',
          'buildOnProgress: half',
          'state.initStateAsync',
          'state.build',
        ],
        reason: 'every one of these is a separate line of forwarding in the '
            'facade element, and the branches are shown in the order the '
            'states arrive -- the waiting branch first of all, because the '
            'asynchronous phase starts only after the build that would show '
            'it',
      );

      await tester.pumpWidget(_wrap(const SizedBox.shrink()));
      await settle(
        tester,
        until: () => log.contains('state.disposeStateAsync'),
      );

      expect(
        log.sublist(5),
        ['state.onUnmount', 'state.disposeStateAsync'],
        reason: 'the teardown reaches the state through the facade too, and '
            'the synchronous half comes first',
      );
    });

    testWidgets('wraps the ready branch with what wrapState returns',
        (tester) async {
      final log = <String>[];

      await tester.pumpWidget(_wrap(_Lite(log: log)));
      await tester.pumpAndSettle();

      expect(
        find.byType(_Wrapper),
        findsOneWidget,
        reason: 'wrapState is the documented way to put a widget around the '
            'ready branch alone, and a facade that never calls it leaves a '
            'public hook that quietly does nothing',
      );
      expect(
        find.descendant(of: find.byType(_Wrapper), matching: find.text('body')),
        findsOneWidget,
        reason: 'and what it wraps is the state, not something beside it',
      );

      await tester.pumpWidget(_wrap(const SizedBox.shrink()));
      await settle(
        tester,
        until: () => log.contains('state.disposeStateAsync'),
      );
    });

    testWidgets('is found from below, by state and by parameters',
        (tester) async {
      final seen = <String, Object?>{};
      final log = <String>[];

      await tester.pumpWidget(
        _wrap(
          _Lite(
            log: log,
            label: 'named',
            body: Builder(
              builder: (context) {
                seen['of'] = LiteScope.of<_Lite, _LiteState>(context).answer;
                seen['maybeOf'] =
                    LiteScope.maybeOf<_Lite, _LiteState>(context)?.answer;
                seen['paramsOf'] = LiteScope.paramsOf<_Lite, _LiteState>(
                  context,
                  listen: false,
                ).label;
                seen['select'] = LiteScope.select<_Lite, _LiteState, String>(
                  context,
                  (scope) => scope.answer,
                );
                seen['selectParam'] =
                    LiteScope.selectParam<_Lite, _LiteState, String>(
                  context,
                  (widget) => widget.label,
                );

                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(seen, {
        'of': 'answer',
        'maybeOf': 'answer',
        'paramsOf': 'named',
        'select': 'answer',
        'selectParam': 'named',
      });

      await tester.pumpWidget(_wrap(const SizedBox.shrink()));
      await settle(
        tester,
        until: () => log.contains('state.disposeStateAsync'),
      );
    });

    testWidgets('answers null from maybeOf where there is no such scope',
        (tester) async {
      _LiteState? seen;
      var asked = false;

      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) {
              asked = true;
              seen = LiteScope.maybeOf<_Lite, _LiteState>(context);

              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(asked, isTrue, reason: 'the builder did run');
      expect(seen, isNull);
    });

    // `buildOnProgress` and `buildOnError` are optional here, and rightly
    // so: a `LiteScope` initializes nothing of its own, so most of them have
    // no progress branch to build. Overriding `initScope()` is what gives them
    // one, and the defaults left behind then throw rather than show a blank
    // screen. What they throw has to say which method is missing — a bare
    // `UnimplementedError` names neither the method nor the scope — and it has
    // to name the method by the name it actually has.
    testWidgets('says which builder is missing when initScope() is overridden',
        (tester) async {
      await tester.pumpWidget(_wrap(const _HalfWritten()));
      await tester.pump();

      expect(
        tester.takeException(),
        isA<UnimplementedError>().having(
          (error) => error.message,
          'message',
          allOf(
            contains('buildOnProgress'),
            contains('initScope()'),
            contains('_HalfWritten'),
          ),
        ),
      );

      // The scope is still on the tree, and its teardown is asynchronous:
      // ending here would leave the notifier undisposed, which the leak
      // tracker reports as a leak of the package rather than of the test.
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester, until: () => false, rounds: 5);
    });

    // The same for the error branch, with one thing more to carry: the
    // failure the scope was about to show. Left out, it is lost — the screen
    // gets the missing-builder error and the reason the scope failed at all
    // goes with it.
    testWidgets('says which builder is missing, and why it was needed',
        (tester) async {
      await tester.pumpWidget(_wrap(const _HalfWritten(failing: true)));
      await tester.pump();

      expect(
        tester.takeException(),
        isA<UnimplementedError>().having(
          (error) => error.message,
          'message',
          allOf(
            contains('buildOnError'),
            contains('the initialization it never wrote'),
          ),
        ),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester, until: () => false, rounds: 5);
    });
  });

  // The largest topic in the documentation, and the one surface the suite
  // never called: `of`, `maybeOf`, `select`, `paramsOf` and `selectParam` on
  // `Scope` had zero callers in the whole run. Two of the review's unnoticed
  // mutations lived right here.
  group('Scope', () {
    testWidgets('is found from below, by state, dependencies and parameters',
        (tester) async {
      final seen = <String, Object?>{};
      final log = <String>[];

      await tester.pumpWidget(
        _wrap(
          _Full(
            log: log,
            label: 'named',
            body: Builder(
              builder: (context) {
                seen['of'] = Scope.of<_Full, _FullDeps, _FullState>(
                  context,
                ).answer;
                seen['maybeOf'] = Scope.maybeOf<_Full, _FullDeps, _FullState>(
                  context,
                )?.answer;
                seen['dependencies'] =
                    Scope.of<_Full, _FullDeps, _FullState>(context)
                        .dependencies
                        .value;
                seen['paramsOf'] = Scope.paramsOf<_Full, _FullDeps, _FullState>(
                  context,
                  listen: false,
                ).label;
                seen['select'] =
                    Scope.select<_Full, _FullDeps, _FullState, String>(
                  context,
                  (state) => state.answer,
                );
                seen['selectParam'] =
                    Scope.selectParam<_Full, _FullDeps, _FullState, String>(
                  context,
                  (widget) => widget.label,
                );

                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(seen, {
        'of': 'answer',
        'maybeOf': 'answer',
        'dependencies': 'built',
        'paramsOf': 'named',
        'select': 'answer',
        'selectParam': 'named',
      });

      await tester.pumpWidget(_wrap(const SizedBox.shrink()));
      await settle(
        tester,
        until: () => log.contains('state.disposeStateAsync'),
      );
    });

    // `listen: true` is the whole difference between the two branches of
    // `paramsOf`, and a branch that ignores it reads like the other one. The
    // readers below are `const`, so they are the same widget on every pump:
    // anything that rebuilds one came from the scope rather than from a
    // parent handing it a new instance. Written the other way -- a `Builder`
    // rebuilt by its parent along with everything else -- the test passes
    // whether the subscription exists or not, which was checked by running it
    // against a `paramsOf` that ignores `listen`.
    testWidgets('paramsOf with listen: true hears a scope rebuilt above it',
        (tester) async {
      final log = <String>[];
      _ParamsReader.builds = 0;

      Widget build(String label, String other) => _wrap(
            _Full(
              log: log,
              label: label,
              other: other,
              body: const _ParamsReader(),
            ),
          );

      await tester.pumpWidget(build('first', 'x'));
      await tester.pumpAndSettle();
      expect(_ParamsReader.builds, 1);

      await tester.pumpWidget(build('second', 'x'));
      await tester.pumpAndSettle();

      expect(
        _ParamsReader.builds,
        2,
        reason: 'the reader asked to listen, so a scope rebuilt with other '
            'parameters has to reach it',
      );

      await tester.pumpWidget(_wrap(const SizedBox.shrink()));
      await settle(
        tester,
        until: () => log.contains('state.disposeStateAsync'),
      );
    });

    // `selectParam` is the narrow form: it subscribes to one parameter, and a
    // change to any other is none of its business.
    testWidgets('selectParam hears the parameter it selected, and no other',
        (tester) async {
      final log = <String>[];
      _SelectParamReader.builds = 0;

      Widget build(String label, String other) => _wrap(
            _Full(
              log: log,
              label: label,
              other: other,
              body: const _SelectParamReader(),
            ),
          );

      await tester.pumpWidget(build('first', 'x'));
      await tester.pumpAndSettle();
      expect(_SelectParamReader.builds, 1);

      await tester.pumpWidget(build('first', 'y'));
      await tester.pumpAndSettle();
      expect(
        _SelectParamReader.builds,
        1,
        reason: 'the parameter it selected did not change',
      );

      await tester.pumpWidget(build('second', 'y'));
      await tester.pumpAndSettle();
      expect(_SelectParamReader.builds, 2, reason: 'and this one did');

      await tester.pumpWidget(_wrap(const SizedBox.shrink()));
      await settle(
        tester,
        until: () => log.contains('state.disposeStateAsync'),
      );
    });

    testWidgets('answers null from maybeOf where there is no such scope',
        (tester) async {
      _FullState? seen;
      var asked = false;

      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) {
              asked = true;
              seen = Scope.maybeOf<_Full, _FullDeps, _FullState>(context);

              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(asked, isTrue, reason: 'the builder did run');
      expect(seen, isNull);
    });
  });

  group('ScopeWidgetBase', () {
    testWidgets('hands its own parameters down', (tester) async {
      String? seen;

      await tester.pumpWidget(
        _wrap(
          _Params(
            value: 'above',
            child: Builder(
              builder: (context) {
                seen =
                    ScopeWidgetBase.of<_Params>(context, listen: false).value;

                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(seen, 'above');
    });

    testWidgets('rebuilds a dependent when the parameter it selected changes',
        (tester) async {
      _Reader.builds = 0;

      // The dependent is `const`, so it is the same widget on every pump:
      // anything that rebuilds it came from the scope rather than from a
      // parent handing it a new instance of itself.
      Widget build(String value, String other) => _wrap(
            _Params(
              value: value,
              other: other,
              child: const _Reader(),
            ),
          );

      await tester.pumpWidget(build('a', 'x'));
      expect(_Reader.builds, 1);

      await tester.pumpWidget(build('a', 'y'));
      expect(
        _Reader.builds,
        1,
        reason: 'the parameter the dependent selected did not change',
      );

      await tester.pumpWidget(build('b', 'y'));
      expect(_Reader.builds, 2, reason: 'and this one did');
    });
  });
}

Widget _wrap(Widget child) => Directionality(
      textDirection: TextDirection.ltr,
      child: child,
    );

/// A scope built on the public facade, reporting every hook it is asked for.
final class _Lite extends LiteScope<_Lite, _LiteState> {
  final List<String> log;
  final String label;
  final Widget body;

  const _Lite({
    required this.log,
    this.label = 'lite',
    this.body = const Text('body'),
  }) : super(child: const SizedBox.shrink());

  @override
  Future<void> initScope(ScopeInitContext ctx) async {
    log.add('init');
    ctx.progress('half');
  }

  @override
  Widget? buildOnWaiting(BuildContext context) {
    log.add('buildOnWaiting');

    return const Text('waiting');
  }

  @override
  Widget buildOnProgress(BuildContext context, Object? progress) {
    log.add('buildOnProgress: $progress');

    return Text('initializing: $progress');
  }

  @override
  Widget buildOnError(
    BuildContext context,
    Object error,
    StackTrace stackTrace,
    Object? progress,
  ) =>
      Text('error: $error');

  @override
  Widget wrapState(BuildContext context, Widget child) =>
      _Wrapper(child: child);

  @override
  _LiteState createState() => _LiteState();
}

final class _LiteState extends LiteScopeState<_Lite, _LiteState> {
  /// What a lookup from below reads off the state.
  String get answer => 'answer';

  @override
  FutureOr<void> initStateAsync() {
    params.log.add('state.initStateAsync');
  }

  @override
  void onUnmount() {
    super.onUnmount();
    params.log.add('state.onUnmount');
  }

  @override
  FutureOr<void> disposeStateAsync() {
    params.log.add('state.disposeStateAsync');
  }

  @override
  Widget build(BuildContext context) {
    params.log.add('state.build');

    return params.body;
  }
}

/// A scope that took the half of the bargain it wanted: it overrides `init()`
/// and leaves the two builders that go with it to their defaults.
final class _HalfWritten extends LiteScope<_HalfWritten, _HalfWrittenState> {
  final bool failing;

  const _HalfWritten({this.failing = false})
      : super(child: const SizedBox.shrink());

  @override
  Future<void> initScope(ScopeInitContext ctx) async {
    if (failing) {
      throw StateError('the pre-initialization fell over');
    }

    ctx.progress('half');
  }

  @override
  Widget? buildOnWaiting(BuildContext context) => const Text('waiting');

  @override
  _HalfWrittenState createState() => _HalfWrittenState();
}

final class _HalfWrittenState
    extends LiteScopeState<_HalfWritten, _HalfWrittenState> {
  @override
  Widget build(BuildContext context) => const Text('ready');
}

/// The `Scope` facade: a container in front of a state, and the five lookups
/// that reach them from below.
final class _Full extends Scope<_Full, _FullDeps, _FullState> {
  final List<String> log;
  final String label;

  /// A second parameter, so that "heard the one it selected" can be told from
  /// "heard everything".
  final String other;
  final Widget body;

  const _Full({
    required this.log,
    this.label = 'full',
    this.other = 'other',
    this.body = const SizedBox.shrink(),
  }) : super(child: const SizedBox.shrink());

  @override
  Stream<ScopeInitState<Object, _FullDeps>> initDependencies(
    BuildContext context,
  ) =>
      _FullDeps().asStream();

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
      Text('$error');

  @override
  _FullState createState() => _FullState();
}

final class _FullDeps implements ScopeDependencies {
  final String value = 'built';

  @override
  void onUnmount() {}

  @override
  FutureOr<void> dispose() {}
}

final class _FullState extends ScopeState<_Full, _FullDeps, _FullState> {
  /// What a lookup from below reads off the state.
  String get answer => 'answer';

  @override
  FutureOr<void> disposeStateAsync() {
    params.log.add('state.disposeStateAsync');
  }

  @override
  Widget build(BuildContext context) => params.body;
}

/// Marks what [_Lite.wrapState] put around the ready branch.
final class _Wrapper extends StatelessWidget {
  final Widget child;

  const _Wrapper({required this.child});

  @override
  Widget build(BuildContext context) => child;
}

/// Subscribes to the whole scope widget through `paramsOf`, and counts.
final class _ParamsReader extends StatelessWidget {
  static int builds = 0;

  const _ParamsReader();

  @override
  Widget build(BuildContext context) {
    builds++;
    Scope.paramsOf<_Full, _FullDeps, _FullState>(context, listen: true);

    return const SizedBox.shrink();
  }
}

/// Subscribes to one parameter of [_Full] through `selectParam`, and counts.
final class _SelectParamReader extends StatelessWidget {
  static int builds = 0;

  const _SelectParamReader();

  @override
  Widget build(BuildContext context) {
    builds++;
    Scope.selectParam<_Full, _FullDeps, _FullState, String>(
      context,
      (widget) => widget.label,
    );

    return const SizedBox.shrink();
  }
}

/// Subscribes to one parameter of [_Params] and counts what it cost.
final class _Reader extends StatelessWidget {
  static int builds = 0;

  const _Reader();

  @override
  Widget build(BuildContext context) {
    builds++;
    ScopeWidgetBase.select<_Params, String>(context, (widget) => widget.value);

    return const SizedBox.shrink();
  }
}

/// A scope over its own parameters, on the public facade.
final class _Params extends ScopeWidgetBase<_Params> {
  final String value;
  final String other;

  const _Params({
    required this.value,
    required super.child,
    this.other = '',
  });

  @override
  Widget build(BuildContext context) => child;
}
