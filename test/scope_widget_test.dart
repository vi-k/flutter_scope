import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scopo/scopo.dart';

void main() {
  group('notifyDependents', () {
    setUp(() {
      _ValueText.buildCount = 0;
      _OtherText.buildCount = 0;
      _PlainText.buildCount = 0;
    });

    testWidgets(
      'notifies the dependents without rebuilding the scope subtree',
      (tester) async {
        await tester.pumpWidget(const _Host(param: 'a'));
        await tester.pumpAndSettle();

        final scope =
            tester.element(find.byType(_CounterScope)) as _CounterScopeElement;
        final subtreeBuilds = _PlainText.buildCount;
        final dependentBuilds = _ValueText.buildCount;

        scope.bump();
        await tester.pump();

        expect(find.text('1'), findsOneWidget);
        expect(
          _ValueText.buildCount,
          dependentBuilds + 1,
          reason: 'the dependent of the changed value was rebuilt once',
        );
        expect(
          _PlainText.buildCount,
          subtreeBuilds,
          reason: 'the subtree was not rebuilt: `updateChild` kept the old '
              'child',
        );
      },
    );

    testWidgets(
      'a rebuild from above in the same frame keeps both the notification and '
      'the subtree',
      (tester) async {
        await tester.pumpWidget(const _Host(param: 'a'));
        await tester.pumpAndSettle();

        final scope =
            tester.element(find.byType(_CounterScope)) as _CounterScopeElement;
        final subtreeBuilds = _PlainText.buildCount;
        final dependentBuilds = _ValueText.buildCount;

        // The notification is pending — `_shouldOnlyNotify` is set and the
        // element is dirty — when the parent rebuilds the scope with a new
        // widget. `update()` sets `_forceRebuild`, so this frame has to do
        // both: notify the dependents *and* rebuild the subtree. Doing only
        // the first is what throws the new subtree away, which is how a
        // closing `LiteScope` once lost the frame that mounts its screenshot.
        scope.bump();
        await tester.pumpWidget(const _Host(param: 'b'));

        expect(find.text('1'), findsOneWidget);
        expect(
          _ValueText.buildCount,
          dependentBuilds + 1,
          reason: 'the pending notification was not lost',
        );
        expect(
          _PlainText.buildCount,
          subtreeBuilds + 1,
          reason: 'the subtree of the updated scope was rebuilt',
        );
        expect(
          find.text('param: b'),
          findsOneWidget,
          reason: 'the subtree shows what the new widget carries',
        );
      },
    );

    testWidgets(
      'a dependent of an unchanged value is not rebuilt',
      (tester) async {
        await tester.pumpWidget(const _Host(param: 'a'));
        await tester.pumpAndSettle();

        final scope =
            tester.element(find.byType(_CounterScope)) as _CounterScopeElement;
        final otherBuilds = _OtherText.buildCount;

        scope.bump();
        await tester.pump();

        expect(
          _OtherText.buildCount,
          otherBuilds,
          reason: 'its selected value did not change',
        );
      },
    );
  });
}

/// The tree under test: a scope whose parameter can be changed from above.
///
/// The scope builds four descendants — one depending on a value it changes,
/// one on a value it does not, one on its own parameter, and one subscribed to
/// nothing at all, which is how the tests tell a rebuilt subtree from a bare
/// notification.
final class _Host extends StatelessWidget {
  final String param;

  const _Host({required this.param});

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: _CounterScope(param: param),
      );
}

final class _CounterScope
    extends ScopeWidgetCore<_CounterScope, _CounterScopeElement> {
  final String param;

  const _CounterScope({required this.param});

  @override
  _CounterScopeElement createScopeElement() => _CounterScopeElement(this);
}

final class _CounterScopeElement
    extends ScopeWidgetElementBase<_CounterScope, _CounterScopeElement> {
  _CounterScopeElement(super.widget);

  /// The value the dependents select, changed only through [bump].
  int value = 0;

  /// A value no test ever changes, so a dependent on it must never be
  /// rebuilt by a notification.
  int get constant => 42;

  void bump() {
    value++;
    notifyDependents();
  }

  /// Builds a *fresh* subtree every time, so that a rebuild that reaches
  /// `updateChild` really rebuilds the children. Handing out one stored
  /// instance would let the framework skip them on identity alone, and the
  /// notify-only path would look like it worked even when it did not.
  @override
  Widget buildChild() => Column(
        children: [
          const _ValueText(),
          const _OtherText(),
          const _ParamText(),
          _PlainText(param: widget.param),
        ],
      );
}

final class _ValueText extends StatelessWidget {
  static int buildCount = 0;

  const _ValueText();

  @override
  Widget build(BuildContext context) {
    buildCount++;
    final value =
        ScopeWidgetCore.select<_CounterScope, _CounterScopeElement, int>(
      context,
      (element) => element.value,
    );

    return Text('$value');
  }
}

final class _OtherText extends StatelessWidget {
  static int buildCount = 0;

  const _OtherText();

  @override
  Widget build(BuildContext context) {
    buildCount++;
    final value =
        ScopeWidgetCore.select<_CounterScope, _CounterScopeElement, int>(
      context,
      (element) => element.constant,
    );

    return Text('constant: $value');
  }
}

final class _ParamText extends StatelessWidget {
  const _ParamText();

  @override
  Widget build(BuildContext context) {
    final param =
        ScopeWidgetCore.select<_CounterScope, _CounterScopeElement, String>(
      context,
      (element) => element.widget.param,
    );

    return Text('param: $param');
  }
}

/// Subscribes to nothing: it is rebuilt only when the subtree itself is.
///
/// Deliberately not `const`: the scope builds a new instance on every
/// `buildChild()`, so an actual rebuild of the subtree reaches it, while a
/// notify-only frame never does.
final class _PlainText extends StatelessWidget {
  static int buildCount = 0;

  final String param;

  const _PlainText({required this.param});

  @override
  Widget build(BuildContext context) {
    buildCount++;

    return Text('plain: $param');
  }
}
