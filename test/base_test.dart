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
      // A build first, so the subscription is taken where subscriptions are
      // taken; then the change it is meant to hear about.
      scope
        ..dependOnSelf = true
        ..markNeedsBuild();
      await tester.pump();

      scope.bump();
      await tester.pump();

      expect(scope.selfNotifications, 1);
    });

    // Flutter remembers a lookup that found nothing, so that a widget moved
    // under a matching ancestor later is told about it. The lookup here went
    // through `getElementForInheritedWidgetOfExactType`, which records
    // nothing, so a `GlobalKey` widget carried under a scope was never
    // notified: it went on showing what it read when there was no scope.
    testWidgets('a lookup that found nothing is remembered as a dependency', (
      tester,
    ) async {
      final key = GlobalKey();
      final seeker = _Seeker(key: key);

      await tester.pumpWidget(
        Directionality(textDirection: TextDirection.ltr, child: seeker),
      );

      final state = tester.state<_SeekerState>(find.byType(_Seeker));

      expect(state.found, isFalse);
      expect(state.dependencyChanges, 1, reason: 'the one after initState');

      // The same element, carried under a scope by its key.
      await tester.pumpWidget(_Host(builder: (context) => seeker));

      expect(
        tester.state<_SeekerState>(find.byType(_Seeker)),
        same(state),
        reason: 'the key kept the element, so this is a move and not a rebuild',
      );
      expect(state.found, isTrue);
      expect(state.dependencyChanges, 2);
    });
  });

  group('where a subscription may be taken', () {
    // What a dependent asked for is remembered per build, and the boundary
    // between one build and the next is taken from the frame. A registration
    // made outside a build therefore belongs to whichever build shares its
    // frame -- `didChangeDependencies` runs in the same frame as the build
    // that follows it, so the subscription looks like it works -- and is
    // dropped by the first build that does not share it, which is any rebuild
    // coming from the parent rather than from a change. Nothing could honour
    // it, so it is refused instead of quietly forgotten.
    testWidgets('subscribing from didChangeDependencies is rejected',
        (tester) async {
      await tester.pumpWidget(
        _Host(builder: (context) => const _SubscribesTooEarly()),
      );

      expect(
        tester.takeException(),
        isA<AssertionError>().having(
          (error) => error.message.toString(),
          'message',
          contains('only be subscribed to from a build'),
        ),
      );
    });
  });

  group('what a dependent subscribes to', () {
    testWidgets('a selector is the only thing that wakes a dependent up', (
      tester,
    ) async {
      var builds = 0;

      await tester.pumpWidget(
        _Host(
          builder: (context) {
            builds++;
            ScopeWidgetCore.select<_Scope, _ScopeElement, int>(
              context,
              (element) => element.value,
            );

            return const SizedBox.shrink();
          },
        ),
      );
      final scope = tester.element(find.byType(_Scope)) as _ScopeElement;

      expect(builds, 1);

      scope.bumpOther();
      await tester.pump();
      expect(
        builds,
        1,
        reason: 'a change of a value nobody selected reaches nobody',
      );

      scope.bump();
      await tester.pump();
      expect(builds, 2, reason: 'the selected value did change');
    });

    testWidgets('listening to the scope subsumes any selector on it', (
      tester,
    ) async {
      var builds = 0;

      await tester.pumpWidget(
        _Host(
          builder: (context) {
            builds++;
            ScopeWidgetCore.select<_Scope, _ScopeElement, int>(
              context,
              (element) => element.value,
            );
            ScopeWidgetCore.of<_Scope, _ScopeElement>(context, listen: true);

            return const SizedBox.shrink();
          },
        ),
      );
      final scope = tester.element(find.byType(_Scope)) as _ScopeElement;

      expect(builds, 1);

      scope.bumpOther();
      await tester.pump();
      expect(
        builds,
        2,
        reason: 'a subscription to everything cannot be narrowed by a selector',
      );
    });
  });
}

final class _Host extends StatelessWidget {
  final WidgetBuilder? builder;

  const _Host({this.builder});

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: _Scope(builder: builder),
      );
}

/// Looks the scope up with `listen: true` and counts how often Flutter tells
/// it its dependencies changed.
final class _Seeker extends StatefulWidget {
  const _Seeker({super.key});

  @override
  State<_Seeker> createState() => _SeekerState();
}

final class _SeekerState extends State<_Seeker> {
  int dependencyChanges = 0;
  bool found = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    dependencyChanges++;
  }

  @override
  Widget build(BuildContext context) {
    found = ScopeWidgetCore.maybeOf<_Scope, _ScopeElement>(
          context,
          listen: true,
        ) !=
        null;

    return const SizedBox.shrink();
  }
}

/// Subscribes from `didChangeDependencies`, which is a frame too early.
final class _SubscribesTooEarly extends StatefulWidget {
  const _SubscribesTooEarly();

  @override
  State<_SubscribesTooEarly> createState() => _SubscribesTooEarlyState();
}

final class _SubscribesTooEarlyState extends State<_SubscribesTooEarly> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    ScopeWidgetCore.select<_Scope, _ScopeElement, int>(
      context,
      (element) => element.value,
    );
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

final class _Scope extends ScopeWidgetCore<_Scope, _ScopeElement> {
  final WidgetBuilder? builder;

  const _Scope({this.builder});

  @override
  _ScopeElement createScopeElement() => _ScopeElement(this);
}

final class _ScopeElement
    extends ScopeWidgetElementBase<_Scope, _ScopeElement> {
  _ScopeElement(super.widget);

  int value = 0;
  int other = 0;
  int selfNotifications = 0;

  void bump() {
    value++;
    notifyDependents();
  }

  /// Changes a value nobody selects.
  void bumpOther() {
    other++;
    notifyDependents();
  }

  /// Whether [buildChild] subscribes the scope to a value of its own.
  ///
  /// From the build, because that is the only place a subscription can be
  /// taken -- see the assertion in `ScopeContext._find`. Called straight from
  /// a test it would be exactly the mistake that assertion is about.
  bool dependOnSelf = false;

  @override
  void didChangeDependencies() {
    selfNotifications++;
    super.didChangeDependencies();
  }

  @override
  Widget buildChild() {
    if (dependOnSelf) {
      ScopeWidgetCore.select<_Scope, _ScopeElement, int>(
        this,
        (element) => element.value,
      );
    }

    return Builder(
      builder: widget.builder ?? (_) => const SizedBox.shrink(),
    );
  }
}
