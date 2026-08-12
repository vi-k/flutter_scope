import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scopo/scopo.dart';

void main() {
  group('looking a scope up', () {
    testWidgets('maybeOf returns null when there is no such scope above', (
      tester,
    ) async {
      Object? found = 'untouched';

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) {
              found = ScopeWidgetCore.maybeOf<_Scope, _ScopeElement>(
                context,
                listen: false,
              );

              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(found, isNull);
    });

    testWidgets('of names the scope it could not find', (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) {
              ScopeWidgetCore.of<_Scope, _ScopeElement>(
                context,
                listen: false,
              );

              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(
        tester.takeException(),
        isA<Exception>().having(
          (e) => '$e',
          'message',
          contains('_Scope not found in the context'),
        ),
      );
    });

    testWidgets('select fails the same way when the scope is missing', (
      tester,
    ) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) {
              ScopeWidgetCore.select<_Scope, _ScopeElement, int>(
                context,
                (element) => element.value,
              );

              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(
        tester.takeException(),
        isA<Exception>().having(
          (e) => '$e',
          'message',
          contains('_Scope not found in the context'),
        ),
      );
    });

    testWidgets(
        'a scope finds itself, and a listener of its own value is '
        'notified', (tester) async {
      await tester.pumpWidget(const _Host());
      await tester.pumpAndSettle();

      final scope = tester.element(find.byType(_Scope)) as _ScopeElement;

      expect(
        ScopeWidgetCore.maybeOf<_Scope, _ScopeElement>(
          scope,
          listen: false,
        ),
        same(scope),
        reason: 'the lookup starts at the element itself',
      );

      // A self-dependency: `InheritedElement` refuses to let an element depend
      // on itself, so the scope keeps those subscriptions apart. The value it
      // selects is its own, and it must still be told when that value changes.
      scope
        ..dependOnSelf()
        ..bump();
      await tester.pump();

      expect(scope.selfNotifications, 1);
    });
  });
}

final class _Host extends StatelessWidget {
  const _Host();

  @override
  Widget build(BuildContext context) => const Directionality(
        textDirection: TextDirection.ltr,
        child: _Scope(),
      );
}

final class _Scope extends ScopeWidgetCore<_Scope, _ScopeElement> {
  const _Scope();

  @override
  _ScopeElement createScopeElement() => _ScopeElement(this);
}

final class _ScopeElement
    extends ScopeWidgetElementBase<_Scope, _ScopeElement> {
  _ScopeElement(super.widget);

  int value = 0;
  int selfNotifications = 0;

  void bump() {
    value++;
    notifyDependents();
  }

  /// Subscribes the scope to a value of its own.
  void dependOnSelf() {
    ScopeWidgetCore.select<_Scope, _ScopeElement, int>(
      this,
      (element) => element.value,
    );
  }

  @override
  void didChangeDependencies() {
    selfNotifications++;
    super.didChangeDependencies();
  }

  @override
  Widget buildChild() => const SizedBox.shrink();
}
