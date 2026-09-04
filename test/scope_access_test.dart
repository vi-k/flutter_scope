import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scopo/scopo.dart';

/// The accessor objects hold nothing and decide nothing: each method is the
/// static of the same name with the type arguments already filled in. So what
/// is worth testing is exactly that — **the accessor and the static answer the
/// same thing** — and the tests below read the same value twice, once each way,
/// in one tree.
///
/// Written this way on purpose. A test that only asserted the value would pass
/// for an accessor wired to the wrong static as long as both happened to return
/// the same type; comparing against the static it stands for cannot.
void main() {
  tearDown(ScopeConfig.reset);

  group('ScopeAccess', () {
    testWidgets('answers what the five statics of Scope answer',
        (tester) async {
      late final List<Object?> pairs;

      await tester.pumpWidget(
        _wrap(
          _FullScope(
            title: 'full',
            child: Builder(
              builder: (context) {
                pairs = [
                  // of
                  _FullScope.access.of(context),
                  Scope.of<_FullScope, _Deps, _FullScopeState>(context),
                  // maybeOf
                  _FullScope.access.maybeOf(context),
                  Scope.maybeOf<_FullScope, _Deps, _FullScopeState>(context),
                  // select
                  _FullScope.access.select(context, (s) => s.counter),
                  Scope.select<_FullScope, _Deps, _FullScopeState, int>(
                    context,
                    (s) => s.counter,
                  ),
                  // paramsOf
                  _FullScope.access.paramsOf(context, listen: false),
                  Scope.paramsOf<_FullScope, _Deps, _FullScopeState>(
                    context,
                    listen: false,
                  ),
                  // selectParam
                  _FullScope.access.selectParam(context, (w) => w.title),
                  Scope.selectParam<_FullScope, _Deps, _FullScopeState, String>(
                    context,
                    (w) => w.title,
                  ),
                ];

                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(pairs, hasLength(10));
      for (var i = 0; i < pairs.length; i += 2) {
        expect(
          pairs[i],
          same(pairs[i + 1]),
          reason: 'accessor and static number ${i ~/ 2} disagree',
        );
      }
      expect(pairs[4], 7, reason: 'and the value is the state, not a default');
      expect(pairs[8], 'full');

      await tester.pumpWidget(_wrap(const SizedBox.shrink()));
      await _settle(tester);
    });
  });

  group('LiteScopeAccess', () {
    testWidgets('answers what the five statics of LiteScope answer',
        (tester) async {
      late final List<Object?> pairs;

      await tester.pumpWidget(
        _wrap(
          _Lite(
            label: 'lite',
            child: Builder(
              builder: (context) {
                pairs = [
                  _Lite.access.of(context),
                  LiteScope.of<_Lite, _LiteState>(context),
                  _Lite.access.maybeOf(context),
                  LiteScope.maybeOf<_Lite, _LiteState>(context),
                  _Lite.access.select(context, (s) => s.value),
                  LiteScope.select<_Lite, _LiteState, int>(
                    context,
                    (s) => s.value,
                  ),
                  _Lite.access.paramsOf(context, listen: false),
                  LiteScope.paramsOf<_Lite, _LiteState>(context, listen: false),
                  _Lite.access.selectParam(context, (w) => w.label),
                  LiteScope.selectParam<_Lite, _LiteState, String>(
                    context,
                    (w) => w.label,
                  ),
                ];

                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (var i = 0; i < pairs.length; i += 2) {
        expect(pairs[i], same(pairs[i + 1]));
      }
      expect(pairs[4], 3);
      expect(pairs[8], 'lite');

      await tester.pumpWidget(_wrap(const SizedBox.shrink()));
      await _settle(tester);
    });
  });

  group('ScopeWidgetAccess', () {
    testWidgets('answers what the three statics of ScopeWidgetBase answer',
        (tester) async {
      late final List<Object?> pairs;

      await tester.pumpWidget(
        _wrap(
          _Config(
            apiKey: 'key',
            child: Builder(
              builder: (context) {
                pairs = [
                  _Config.access.of(context, listen: false),
                  ScopeWidgetBase.of<_Config>(context, listen: false),
                  _Config.access.maybeOf(context, listen: false),
                  ScopeWidgetBase.maybeOf<_Config>(context, listen: false),
                  _Config.access.select(context, (w) => w.apiKey),
                  ScopeWidgetBase.select<_Config, String>(
                    context,
                    (w) => w.apiKey,
                  ),
                ];

                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (var i = 0; i < pairs.length; i += 2) {
        expect(pairs[i], same(pairs[i + 1]));
      }
      expect(pairs[4], 'key');
    });

    // The `listen` an accessor takes has to reach the static it stands for,
    // and nothing above proves that: both sides of every pair pass the same
    // value, so an accessor that hard-coded one would still agree with the
    // static. Checked by the only thing that tells the two apart — whether the
    // reader is rebuilt when the scope changes.
    //
    // The reader is `const` on purpose: one rebuilt by its parent would count
    // rebuilds it never subscribed to, and the test would pass for an accessor
    // that ignores `listen` entirely.
    testWidgets('passes listen through rather than fixing it', (tester) async {
      _CountingReader.builds = 0;

      Widget build(String key) => _wrap(
            _Config(apiKey: key, child: const _CountingReader(listen: true)),
          );

      await tester.pumpWidget(build('one'));
      expect(_CountingReader.builds, 1);

      await tester.pumpWidget(build('two'));
      expect(
        _CountingReader.builds,
        2,
        reason: 'listen: true subscribes, so a changed scope rebuilds it',
      );

      _CountingReader.builds = 0;

      Widget quiet(String key) => _wrap(
            _Config(apiKey: key, child: const _CountingReader(listen: false)),
          );

      await tester.pumpWidget(quiet('one'));
      expect(_CountingReader.builds, 1);

      await tester.pumpWidget(quiet('two'));
      expect(
        _CountingReader.builds,
        1,
        reason: 'listen: false does not, and an accessor that fixed the flag '
            'to true would be caught right here',
      );
    });
  });
}

/// Counts its own builds, and is `const` so that only a subscription can cause
/// one.
final class _CountingReader extends StatelessWidget {
  static int builds = 0;

  final bool listen;

  const _CountingReader({required this.listen});

  @override
  Widget build(BuildContext context) {
    builds++;
    _Config.access.of(context, listen: listen);

    return const SizedBox.shrink();
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }
}

Widget _wrap(Widget child) => Directionality(
      textDirection: TextDirection.ltr,
      child: child,
    );

//
// Scope
//

final class _Deps implements ScopeDependencies {
  static Future<_Deps> init(ScopeInitContext ctx) async => _Deps();

  @override
  void onUnmount() {}

  @override
  FutureOr<void> dispose() {}
}

final class _FullScope extends Scope<_FullScope, _Deps, _FullScopeState> {
  final String title;

  const _FullScope({required this.title, required super.child});

  static const access = ScopeAccess<_FullScope, _Deps, _FullScopeState>();

  @override
  Future<_Deps> initDependencies(
    BuildContext context,
    ScopeInitContext ctx,
  ) =>
      _Deps.init(ctx);

  @override
  _FullScopeState createState() => _FullScopeState();

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
      const SizedBox.shrink();
}

final class _FullScopeState
    extends ScopeState<_FullScope, _Deps, _FullScopeState> {
  final counter = 7;

  @override
  Widget build(BuildContext context) => params.child;
}

//
// LiteScope
//

final class _Lite extends LiteScope<_Lite, _LiteState> {
  final String label;

  const _Lite({required this.label, required super.child});

  static const access = LiteScopeAccess<_Lite, _LiteState>();

  @override
  Widget? buildOnWaiting(BuildContext context) => const SizedBox.shrink();

  @override
  _LiteState createState() => _LiteState();
}

final class _LiteState extends LiteScopeState<_Lite, _LiteState> {
  final value = 3;

  @override
  Widget build(BuildContext context) => params.child;
}

//
// ScopeWidgetBase
//

final class _Config extends ScopeWidgetBase<_Config> {
  final String apiKey;

  const _Config({required this.apiKey, required super.child});

  static const access = ScopeWidgetAccess<_Config>();

  @override
  Widget build(BuildContext context) => child;
}
