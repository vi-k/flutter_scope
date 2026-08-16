import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scopo/scopo.dart';

void main() {
  group('lifecycle', () {
    setUp(() {
      _FailingInitScopeElement.initAttempts = 0;
      _FailingInitScopeElement.acquired = 0;
      _FailingInitScopeElement.released = 0;
    });

    testWidgets('init sees ancestors and finishes before the first build', (
      tester,
    ) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: _AncestorScope(
            value: 'ready',
            child: _InitReaderScope(),
          ),
        ),
      );

      expect(find.text('init: ready; completed: true'), findsOneWidget);
    });

    testWidgets('a failed init is not retried and is still cleaned up', (
      tester,
    ) async {
      final scopeKey = GlobalKey();

      Widget buildTree(String label) => Directionality(
            textDirection: TextDirection.ltr,
            child: _FailingInitScope(key: scopeKey, label: label),
          );

      await tester.pumpWidget(buildTree('first'));

      expect(_FailingInitScopeElement.initAttempts, 1);
      expect(_FailingInitScopeElement.acquired, 1);
      expect(
        tester.takeException(),
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'controlled init failure',
        ),
      );

      // A parent rebuild must not run the hook a second time: the failure is
      // terminal, and the resource the first attempt took is still held.
      await tester.pumpWidget(buildTree('second'));

      expect(
        tester.takeException(),
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'controlled init failure',
        ),
        reason: 'the recorded failure is reported again',
      );
      expect(
        _FailingInitScopeElement.initAttempts,
        1,
        reason: 'a failed init is terminal',
      );
      expect(
        _FailingInitScopeElement.acquired,
        1,
        reason: 'nothing is acquired a second time',
      );

      await tester.pumpWidget(const SizedBox.shrink());

      expect(
        _FailingInitScopeElement.released,
        1,
        reason: 'what the failed init took is released on unmount',
      );
    });

    testWidgets('subscribing to a scope from init is rejected', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: _AncestorScope(
            value: 'ready',
            child: _ListeningInitScope(),
          ),
        ),
      );

      expect(
        tester.takeException(),
        isA<AssertionError>().having(
          (error) => error.message.toString(),
          'message',
          contains('listen: false'),
        ),
      );
    });
  });

  group('notifyDependents', () {
    setUp(() {
      _ValueText.buildCount = 0;
      _OtherText.buildCount = 0;
      _SwitchingText.buildCount = 0;
      _BothText.buildCount = 0;
      _PlainText.buildCount = 0;
      _CounterScopeElement.buildChildCount = 0;
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

    // A widget may select a different value from one build to the next. What
    // it selected before is not what it depends on any more, and used to stay
    // registered anyway: the pairs piled up build after build, and a change to
    // any of them — including one nobody reads — rebuilt the widget.
    testWidgets(
      'a dependent that moved to another value is not rebuilt by the old one',
      (tester) async {
        await tester.pumpWidget(const _Host(param: 'a'));
        await tester.pumpAndSettle();

        // The subtree is rebuilt, and the dependent moves from `value` to
        // `other`.
        await tester.pumpWidget(const _Host(param: 'b'));
        await tester.pumpAndSettle();

        final scope =
            tester.element(find.byType(_CounterScope)) as _CounterScopeElement;
        final builds = _SwitchingText.buildCount;

        scope.bump();
        await tester.pump();

        expect(
          _SwitchingText.buildCount,
          builds,
          reason: 'it stopped reading `value` a build ago',
        );

        scope.bumpOther();
        await tester.pump();

        expect(
          _SwitchingText.buildCount,
          builds + 1,
          reason: 'the value it does read still rebuilds it',
        );
      },
    );

    // The other half of the same rule: a build may ask for more than one
    // value, and all of them belong to it. Keeping only the last would be a
    // missed rebuild, which is worse than the extra one above.
    testWidgets(
      'a dependent of two values is rebuilt by either of them',
      (tester) async {
        await tester.pumpWidget(const _Host(param: 'a'));
        await tester.pumpAndSettle();

        final scope =
            tester.element(find.byType(_CounterScope)) as _CounterScopeElement;
        final builds = _BothText.buildCount;

        scope.bump();
        await tester.pump();

        expect(
          _BothText.buildCount,
          builds + 1,
          reason: 'the first of the two changed',
        );

        scope.bumpOther();
        await tester.pump();

        expect(
          _BothText.buildCount,
          builds + 2,
          reason: 'and so did the second',
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

    // A notification runs user code -- every selector of every dependent, and
    // the scope's own -- and it runs it from `performRebuild`, outside any
    // boundary of the framework's. A selector that threw used to take the
    // whole notification with it: every dependent the walk had not reached
    // yet simply never heard about the change, and which ones those were
    // depended on the iteration order of a hash map. The scope's own
    // subscription is first, so a failure there swallowed the notification
    // whole.
    testWidgets(
      'a selector that throws does not swallow the notification',
      (tester) async {
        await tester.pumpWidget(const _Host(param: 'a'));
        await tester.pumpAndSettle();

        final scope =
            tester.element(find.byType(_CounterScope)) as _CounterScopeElement;

        expect(find.text('0'), findsOneWidget);

        scope
          ..explodeOnce = true
          ..bump();
        await tester.pump();

        expect(
          tester.takeException(),
          isA<StateError>(),
          reason: 'what the selector threw is reported, not swallowed',
        );
        expect(
          find.text('1'),
          findsOneWidget,
          reason: 'and the dependents still heard the notification that the '
              'failing selector was only a part of',
        );
      },
    );

    // "Skips rebuilding the whole subtree" was true of the elements and not
    // of the widgets: `ComponentElement.performRebuild` calls `build()`
    // whatever else happens, and only `updateChild` was overridden -- so
    // `buildChild()` ran on every notification and the widget tree it
    // returned was thrown away. On a scope notified every frame that is the
    // whole graph of its subtree, allocated and dropped, once per frame.
    testWidgets('a notification does not rebuild the subtree widgets',
        (tester) async {
      await tester.pumpWidget(const _Host(param: 'a'));
      await tester.pumpAndSettle();

      final scope =
          tester.element(find.byType(_CounterScope)) as _CounterScopeElement;
      final builds = _CounterScopeElement.buildChildCount;

      scope.bump();
      await tester.pump();

      expect(find.text('1'), findsOneWidget, reason: 'the notification landed');
      expect(
        _CounterScopeElement.buildChildCount,
        builds,
        reason: 'and nothing was built for it to land on',
      );

      // A rebuild from above is a different matter: there the subtree really
      // does have to be built again.
      await tester.pumpWidget(const _Host(param: 'b'));

      expect(
        _CounterScopeElement.buildChildCount,
        builds + 1,
        reason: 'a scope updated by its parent still builds its subtree',
      );
    });
  });
}

final class _AncestorScope
    extends ScopeWidgetCore<_AncestorScope, _AncestorScopeElement> {
  final String value;
  @override
  // ignore: overridden_fields
  final Widget child;

  const _AncestorScope({required this.value, required this.child});

  static String valueOf(BuildContext context) =>
      ScopeWidgetCore.of<_AncestorScope, _AncestorScopeElement>(
        context,
        listen: false,
      ).widget.value;

  @override
  _AncestorScopeElement createScopeElement() => _AncestorScopeElement(this);
}

final class _AncestorScopeElement
    extends ScopeWidgetElementBase<_AncestorScope, _AncestorScopeElement> {
  _AncestorScopeElement(super.widget);

  @override
  Widget buildChild() => widget.child;
}

final class _InitReaderScope
    extends ScopeWidgetCore<_InitReaderScope, _InitReaderScopeElement> {
  const _InitReaderScope();

  @override
  _InitReaderScopeElement createScopeElement() => _InitReaderScopeElement(this);
}

final class _InitReaderScopeElement
    extends ScopeWidgetElementBase<_InitReaderScope, _InitReaderScopeElement> {
  _InitReaderScopeElement(super.widget);

  String? _ancestorValue;
  bool _initCompleted = false;

  @override
  void init() {
    _ancestorValue = _AncestorScope.valueOf(this);
    _initCompleted = true;
    super.init();
  }

  @override
  Widget buildChild() =>
      Text('init: $_ancestorValue; completed: $_initCompleted');
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

  /// A second changeable value, so that a dependent can move from one to the
  /// other between builds.
  int other = 0;

  /// A value no test ever changes, so a dependent on it must never be
  /// rebuilt by a notification.
  int get constant => 42;

  /// Makes the next call of the scope's own selector fail, once.
  ///
  /// One shot on purpose: the throw belongs to the notification, and the
  /// build that follows has to be able to succeed, so that what the test sees
  /// afterwards is the state of the scope and not a widget stuck on an error
  /// of its own.
  bool explodeOnce = false;

  bool _takeExplode() {
    if (!explodeOnce) {
      return false;
    }
    explodeOnce = false;

    return true;
  }

  void bump() {
    value++;
    notifyDependents();
  }

  void bumpOther() {
    other++;
    notifyDependents();
  }

  /// Builds a *fresh* subtree every time, so that a rebuild that reaches
  /// `updateChild` really rebuilds the children. Handing out one stored
  /// instance would let the framework skip them on identity alone, and the
  /// notify-only path would look like it worked even when it did not.
  /// How many times the scope itself built its subtree.
  static int buildChildCount = 0;

  @override
  Widget buildChild() {
    buildChildCount++;
    // A subscription of the scope to itself. `notifyClients` runs it before
    // any dependent, so whatever it does to a notification it does to all of
    // them -- which is what makes the test below deterministic, where the
    // order of the dependents is not.
    //
    // It reads `constant`, so it never fires by itself and the other tests in
    // this file see the notify-only path they were written for.
    ScopeWidgetCore.select<_CounterScope, _CounterScopeElement, int>(
      this,
      (element) {
        if (element._takeExplode()) {
          throw StateError('the selector failed');
        }

        return element.constant;
      },
    );

    return Column(
      children: [
        const _ValueText(),
        const _OtherText(),
        const _ParamText(),
        _SwitchingText(useValue: widget.param == 'a'),
        const _BothText(),
        _PlainText(param: widget.param),
      ],
    );
  }
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

/// Selects one of two changeable values, whichever the scope's parameter says.
///
/// Which one it reads is a property of the build it is in, and nothing else
/// about the widget changes with it — so a rebuild caused by the value it
/// stopped reading is visible in [buildCount] alone.
final class _SwitchingText extends StatelessWidget {
  static int buildCount = 0;

  final bool useValue;

  const _SwitchingText({required this.useValue});

  @override
  Widget build(BuildContext context) {
    buildCount++;
    final value =
        ScopeWidgetCore.select<_CounterScope, _CounterScopeElement, int>(
      context,
      useValue ? (element) => element.value : (element) => element.other,
    );

    return Text('switching: $value');
  }
}

/// Selects both changeable values in one build.
final class _BothText extends StatelessWidget {
  static int buildCount = 0;

  const _BothText();

  @override
  Widget build(BuildContext context) {
    buildCount++;
    final value =
        ScopeWidgetCore.select<_CounterScope, _CounterScopeElement, int>(
      context,
      (element) => element.value,
    );
    final other =
        ScopeWidgetCore.select<_CounterScope, _CounterScopeElement, int>(
      context,
      (element) => element.other,
    );

    return Text('both: $value/$other');
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

/// A scope whose `init()` takes a resource and then fails.
///
/// The counters are static because the element is rebuilt from a fresh widget
/// on every pump, and the test has to watch the hook across those rebuilds.
final class _FailingInitScope
    extends ScopeWidgetCore<_FailingInitScope, _FailingInitScopeElement> {
  final String label;

  const _FailingInitScope({super.key, required this.label});

  @override
  _FailingInitScopeElement createScopeElement() =>
      _FailingInitScopeElement(this);
}

final class _FailingInitScopeElement extends ScopeWidgetElementBase<
    _FailingInitScope, _FailingInitScopeElement> {
  static int initAttempts = 0;
  static int acquired = 0;
  static int released = 0;

  _FailingInitScopeElement(super.widget);

  @override
  void init() {
    initAttempts++;
    acquired++; // the resource is taken…

    throw StateError('controlled init failure'); // …and then the hook fails
  }

  @override
  void dispose() {
    released++;
    super.dispose();
  }

  @override
  Widget buildChild() => Text('label: ${widget.label}');
}

/// A scope whose `init()` asks for an ancestor *with* a subscription.
final class _ListeningInitScope
    extends ScopeWidgetCore<_ListeningInitScope, _ListeningInitScopeElement> {
  const _ListeningInitScope();

  @override
  _ListeningInitScopeElement createScopeElement() =>
      _ListeningInitScopeElement(this);
}

final class _ListeningInitScopeElement extends ScopeWidgetElementBase<
    _ListeningInitScope, _ListeningInitScopeElement> {
  _ListeningInitScopeElement(super.widget);

  @override
  void init() {
    ScopeWidgetCore.of<_AncestorScope, _AncestorScopeElement>(
      this,
      listen: true,
    );
    super.init();
  }

  @override
  Widget buildChild() => const SizedBox.shrink();
}
