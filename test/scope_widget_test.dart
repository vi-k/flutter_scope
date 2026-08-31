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

    // And what the failure costs the subscription it belongs to: a selector
    // that could not answer counts as *changed*, so its dependent is rebuilt
    // and asks it again from inside its own build — where the framework's
    // error boundary turns a second failure into an `ErrorWidget` for that
    // one widget. Counting it as unchanged instead would be the quiet
    // opposite: the dependent keeps a value nobody could confirm.
    testWidgets(
      'a selector that could not answer counts as changed',
      (tester) async {
        await tester.pumpWidget(const _Host(param: 'a'));
        await tester.pumpAndSettle();

        final scope =
            tester.element(find.byType(_CounterScope)) as _CounterScopeElement;
        final before = _CounterScopeElement.buildChildCount;

        // Control: the scope's own selector reads a value that never changes,
        // so an ordinary notification leaves its subtree alone.
        scope.bump();
        await tester.pump();

        expect(
          _CounterScopeElement.buildChildCount,
          before,
          reason: 'the selector answered, and answered the same as before',
        );

        scope
          ..explodeOnce = true
          ..bump();
        await tester.pump();

        expect(tester.takeException(), isA<StateError>());
        expect(
          _CounterScopeElement.buildChildCount,
          before + 1,
          reason: 'the selector could not answer, so the subtree is rebuilt '
              'rather than left standing on an answer nobody gave',
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

    // The guard that defers a notification asked about *this* element's own
    // rebuild, and a notification does not have to come from there. A model
    // touched from the build of a descendant -- a lazy load, a default filled
    // in on first read, the same ordinary user code the guard exists for --
    // arrives while the scope itself is not rebuilding, so the bare
    // `markNeedsBuild()` was called and the framework refused it: "setState()
    // or markNeedsBuild() called during build". In release the check lives in
    // an assert and the same code works, which made this a difference between
    // debug and release rather than a rule.
    testWidgets('a notification made from a descendant build is not refused',
        (tester) async {
      final key = GlobalKey<_BumperState>();

      await tester.pumpWidget(_Host(param: 'a', extra: _Bumper(key: key)));
      await tester.pumpAndSettle();

      // Its own rebuild, so the scope above it is not the one building.
      key.currentState!.armAndRebuild();
      await tester.pump();
      // The notification is deferred to the end of that frame, so the rebuild
      // it asks for lands on the next one.
      await tester.pump();

      expect(
        tester.takeException(),
        isNull,
        reason: 'the notification is deferred to after the frame, not refused',
      );
      expect(
        find.text('1'),
        findsOneWidget,
        reason: 'and it lands, a frame late rather than never',
      );
    });

    // `_notifyPending` says a notification is waiting, and `performRebuild`
    // takes it down as it acts on it. Left standing, *every* later rebuild
    // that does not come from the parent -- a `MediaQuery`, a `Theme`, a
    // locale -- is treated as notify-only, and the subtree freezes for good.
    testWidgets('a notification is spent by the rebuild that acts on it',
        (tester) async {
      await tester.pumpWidget(const _Host(param: 'a'));
      await tester.pumpAndSettle();

      final scope = tester.element(find.byType(_CounterScope))
          as _CounterScopeElement
        ..bump();
      await tester.pump();

      final builds = _CounterScopeElement.buildChildCount;

      // Not from the parent: `update()` is what raises `_forceRebuild`, and
      // this is the other way an element is rebuilt.
      scope.markNeedsBuild();
      await tester.pump();

      expect(
        _CounterScopeElement.buildChildCount,
        builds + 1,
        reason: 'the notification was spent by the rebuild before it, so this '
            'one is an ordinary rebuild and builds the subtree',
      );
    });

    // The same rule met from the other side, and the side that was missing:
    // a rebuild the scope did not ask for and the parent did not cause. An
    // inherited dependency of the scope's *own* element -- which is what a
    // user's builder subscribes to the moment it calls `Theme.of(context)`,
    // the context there being this element -- arrives as
    // `didChangeDependencies()` and a bare `markNeedsBuild()`. No new widget
    // comes down, so `update()` never runs and `_forceRebuild` is never
    // raised. Landing in the same frame as a pending notification, that
    // rebuild was taken for a notify-only one and the change was lost for
    // good: the framework had already delivered it and does not deliver it
    // twice.
    testWidgets(
      'an inherited change that lands with a notification is not eaten',
      (tester) async {
        Future<void> pumpShade(int level) => tester.pumpWidget(
              Directionality(
                textDirection: TextDirection.ltr,
                child: _Shade(level: level, child: const _ShadeScope()),
              ),
            );

        await pumpShade(1);
        expect(find.text('shade:1'), findsOneWidget);

        // Control: the dependency change alone arrives.
        await pumpShade(2);
        expect(
          find.text('shade:2'),
          findsOneWidget,
          reason: 'a dependency change on its own has always arrived',
        );

        // The collision: a notification is pending when the dependency
        // changes in the same frame.
        (tester.element(find.byType(_ShadeScope)) as _ShadeScopeElement).bump();
        await pumpShade(3);

        expect(
          find.text('shade:3'),
          findsOneWidget,
          reason: 'the notification must not swallow the dependency change: '
              'the framework delivered it once and will not do so again',
        );

        // And it stays lost without a second chance, so a later frame is not
        // what makes this pass.
        await tester.pump();
        expect(find.text('shade:3'), findsOneWidget);
      },
    );

    // The other side of the same rule. A notify-only rebuild hands back what
    // the last real build made and leaves the child element alone -- which
    // needs there to have been a real build. When the first one threw, the
    // boundary above put an `ErrorWidget` in the subtree's place and the cache
    // stayed empty; every notification after that built a fresh subtree,
    // handed it to an `updateChild` that kept the `ErrorWidget` instead, and
    // filled the cache with what it had just thrown away -- so the second
    // notification did not even build. The scope was frozen on the error for
    // the rest of its life, and only a rebuild from above could bring it back.
    testWidgets('a notification rebuilds a subtree the first build never made',
        (tester) async {
      await tester.pumpWidget(
        const _Host(param: 'a', failFirstBuild: true),
      );

      expect(
        tester.takeException(),
        isA<StateError>(),
        reason: 'the first build failed, and the boundary above showed it',
      );
      expect(find.byType(ErrorWidget), findsOneWidget);

      (tester.element(find.byType(_CounterScope)) as _CounterScopeElement)
          .bump();
      await tester.pump();

      expect(
        find.text('1'),
        findsOneWidget,
        reason: 'with nothing cached there is nothing to hand back, so the '
            'rebuild cannot be notify-only',
      );
      expect(
        find.byType(ErrorWidget),
        findsNothing,
        reason: 'and the error branch is gone rather than there for good',
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
  final bool failFirstBuild;
  final Widget? extra;

  const _Host({required this.param, this.failFirstBuild = false, this.extra});

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: _CounterScope(
          param: param,
          failFirstBuild: failFirstBuild,
          extra: extra,
        ),
      );
}

final class _CounterScope
    extends ScopeWidgetCore<_CounterScope, _CounterScopeElement> {
  final String param;

  /// Makes the very first `buildChild()` fail, the way a builder reading a
  /// field the scope has not filled in yet does.
  final bool failFirstBuild;

  /// Put into the subtree beside the ordinary dependents, so a test can hand
  /// the scope a descendant of its own.
  final Widget? extra;

  const _CounterScope({
    required this.param,
    this.failFirstBuild = false,
    this.extra,
  });

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

  /// Whether the one failure [_CounterScope.failFirstBuild] asks for is spent.
  bool _firstBuildFailed = false;

  @override
  Widget buildChild() {
    buildChildCount++;
    if (widget.failFirstBuild && !_firstBuildFailed) {
      _firstBuildFailed = true;
      throw StateError('the first build failed');
    }
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
        if (widget.extra case final extra?) extra,
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

/// A descendant that pokes the scope from its own build.
final class _Bumper extends StatefulWidget {
  const _Bumper({super.key});

  @override
  State<_Bumper> createState() => _BumperState();
}

final class _BumperState extends State<_Bumper> {
  bool _armed = false;

  /// Rebuilds this widget alone, with the poke armed for that build.
  void armAndRebuild() => setState(() => _armed = true);

  @override
  Widget build(BuildContext context) {
    if (_armed) {
      _armed = false;
      ScopeWidgetCore.of<_CounterScope, _CounterScopeElement>(
        context,
        listen: false,
      ).bump();
    }

    return const SizedBox.shrink();
  }
}

/// An inherited widget the scope reads from `buildChild()` -- the way a user's
/// builder reads `Theme.of(context)`, where the context handed to it is the
/// scope's own element.
final class _Shade extends InheritedWidget {
  const _Shade({required this.level, required super.child});

  final int level;

  static int of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_Shade>()!.level;

  @override
  bool updateShouldNotify(_Shade oldWidget) => oldWidget.level != level;
}

/// Const and parameterless, so the same instance comes down every frame and
/// `update()` is never the reason this element rebuilds.
final class _ShadeScope
    extends ScopeWidgetCore<_ShadeScope, _ShadeScopeElement> {
  const _ShadeScope();

  @override
  _ShadeScopeElement createScopeElement() => _ShadeScopeElement(this);
}

final class _ShadeScopeElement
    extends ScopeWidgetElementBase<_ShadeScope, _ShadeScopeElement> {
  _ShadeScopeElement(super.widget);

  int value = 0;

  void bump() {
    value++;
    notifyDependents();
  }

  @override
  Widget buildChild() => Text('shade:${_Shade.of(this)}');
}
