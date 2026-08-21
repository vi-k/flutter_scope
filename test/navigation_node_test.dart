import 'dart:async';

// `ValueListenable` is not exported from `material.dart`; the guard below
// implements it.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scopo/scopo.dart';

void main() {
  group('NavigationNode', () {
    testWidgets('a screen pushed inside the node still sees the scope above it',
        (tester) async {
      await tester.pumpWidget(const _Host(useNode: true));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(
        find.text('pushed: secret'),
        findsOneWidget,
        reason: 'the nested navigator lives below the scope, so the route it '
            'pushes does too',
      );
    });

    testWidgets(
      'control: the same screen pushed on the root navigator does not',
      (tester) async {
        await tester.pumpWidget(const _Host(useNode: false));

        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        expect(
          find.text('pushed: none'),
          findsOneWidget,
          reason: 'the root navigator sits above the scope, and this is the '
              'whole reason NavigationNode exists',
        );
      },
    );

    testWidgets('popping inside the node returns to the node content', (
      tester,
    ) async {
      await tester.pumpWidget(const _Host(useNode: true));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('open'), findsNothing);

      await tester.tap(find.text('back'));
      await tester.pumpAndSettle();

      expect(find.text('open'), findsOneWidget);
      expect(find.text('pushed: secret'), findsNothing);
    });

    testWidgets('system back pops a pushed route inside the node', (
      tester,
    ) async {
      await tester.pumpWidget(const _Host(useNode: true));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('pushed: secret'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('pushed: secret'), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('system back closes a dialog inside the node', (tester) async {
      await tester.pumpWidget(const _Host(useNode: true));

      await tester.tap(find.text('open dialog'));
      await tester.pumpAndSettle();
      expect(find.text('dialog'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('dialog'), findsNothing);
      expect(find.text('open dialog'), findsOneWidget);
    });

    // A drawer is not a route: it puts a local history entry on the route it
    // is on, and nothing tells any navigator its stack has changed. Without a
    // node around it the back gesture closes it, and the node must not be what
    // takes that away.
    testWidgets('system back closes a drawer inside the node', (tester) async {
      await tester.pumpWidget(const _DrawerHost(useNode: true));

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      expect(find.text('drawer'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(
        find.text('drawer'),
        findsNothing,
        reason: 'the press belongs to the drawer, which is what the route the '
            'node sits on would close on its own',
      );
      expect(
        find.text('node content'),
        findsOneWidget,
        reason: 'and the route around the node has to stay: the node must not '
            'take away what works without it',
      );
    });

    // The same press, one layer up: the drawer belongs to the route the node
    // stands on rather than to a route inside it. A node with `onPop` said
    // `doNotPop` unconditionally, so the route never got as far as the local
    // history the drawer had put on it -- and the node was asked "leave this
    // screen?" about a press whose whole job was to close a drawer. Refuse,
    // and the drawer could not be closed with back at all.
    testWidgets(
      'system back closes a drawer above a node with onPop',
      (tester) async {
        final log = <String>[];

        await tester.pumpWidget(_DrawerAboveNodeHost(log: log));

        await tester.tap(find.text('go'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();
        expect(find.text('drawer'), findsOneWidget);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(
          find.text('drawer'),
          findsNothing,
          reason: 'the route would have closed the drawer on its own, and a '
              'node standing on it must not take that away',
        );
        expect(
          log,
          isEmpty,
          reason: 'and the node is not asked about a press that never left '
              'the route it stands on',
        );
        expect(find.text('node content'), findsOneWidget);
      },
    );

    testWidgets(
      'control: the same drawer without a node closes on system back',
      (tester) async {
        await tester.pumpWidget(const _DrawerHost(useNode: false));

        await tester.tap(find.text('go'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();
        expect(find.text('drawer'), findsOneWidget);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(find.text('drawer'), findsNothing);
        expect(find.text('node content'), findsOneWidget);
      },
    );

    // The node's first page is the first route of its own navigator, so
    // nothing about that navigator implies a way back. The node says there is
    // one for the page itself, because pressing it leaves the node.
    testWidgets('an AppBar on the first page of a node draws a back arrow',
        (tester) async {
      await tester.pumpWidget(const _AppBarHost());

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(find.byType(BackButton), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(
        find.text('go'),
        findsOneWidget,
        reason: 'the arrow leaves the node, which is the only thing it could '
            'mean on a page that is the first of its navigator',
      );
    });

    testWidgets('a root node draws no back arrow on its first page', (
      tester,
    ) async {
      await tester.pumpWidget(const _AppBarHost(isRoot: true));

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(
        find.byType(BackButton),
        findsNothing,
        reason: 'a root node keeps a pop to itself, so there is nowhere for '
            'an arrow on its first page to go',
      );
    });

    testWidgets('system back respects a guarded route inside the node', (
      tester,
    ) async {
      await tester.pumpWidget(const _Host(useNode: true));

      await tester.tap(find.text('open guarded'));
      await tester.pumpAndSettle();
      expect(find.text('guarded route'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('guarded route'), findsOneWidget);
    });

    testWidgets('system back stays in a root node while it has an inner route',
        (
      tester,
    ) async {
      await tester.pumpWidget(const _Host(useNode: true, isRoot: true));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('pushed: secret'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('pushed: secret'), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets(
        'system back asks onPop once when the node has nothing to '
        'close', (tester) async {
      var calls = 0;

      await tester.pumpWidget(
        _OnPopHost(
          onPop: (context, result) {
            calls++;
            // A circuit breaker, not part of the contract: a node that keeps
            // asking would otherwise hang the test instead of failing it.
            return calls > 3;
          },
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text('node content'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(
        calls,
        1,
        reason: 'one system back is one question to onPop',
      );
    });

    testWidgets('an onPop that refuses keeps the outer route', (tester) async {
      var calls = 0;

      await tester.pumpWidget(
        _OnPopHost(
          onPop: (context, result) {
            calls++;
            return calls > 3;
          },
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(
        find.text('node content'),
        findsOneWidget,
        reason: 'onPop returned false, so the route it guards must stay',
      );
    });

    testWidgets('an onPop that allows the pop lets the outer route go', (
      tester,
    ) async {
      var calls = 0;

      await tester.pumpWidget(
        _OnPopHost(
          onPop: (context, result) {
            calls++;
            return true;
          },
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(calls, 1);
      expect(
        find.text('go'),
        findsOneWidget,
        reason: 'the screen that pushed the node is back on top',
      );
    });

    // Every test above pushes the node as a second route, so the pop it
    // forwards always has a route to take. On the first route of the
    // application there is none, and the navigator above must be left alone
    // rather than emptied.
    testWidgets('an ordinary node on the first route keeps the application',
        (tester) async {
      var calls = 0;

      await tester.pumpWidget(
        _FirstRouteNodeHost(
          onPop: (context, result) {
            calls++;

            return true;
          },
        ),
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(calls, 1, reason: 'the hook is asked here as anywhere else');
      expect(
        find.text('node content'),
        findsOneWidget,
        reason: 'there is nothing outside the node to let the pop through to, '
            'and taking the only route of the application navigator leaves a '
            'blank screen',
      );
    });

    // An application may guard the route it puts a node on — "are you sure you
    // want to leave this screen". A node hands a pop over; it does not take
    // one, and a guard on the way out is not the node's to overrule.
    testWidgets('an application PopScope over the node keeps its route', (
      tester,
    ) async {
      var refusals = 0;

      await tester.pumpWidget(_AppGuardedHost(onRefused: () => refusals++));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(
        find.text('node content'),
        findsOneWidget,
        reason: 'the application refused the pop, and the node was handing it '
            'over rather than taking it',
      );
      expect(
        refusals,
        1,
        reason: 'and the application hears one press as one: the node asks the '
            'route what a pop would do, which tells nobody anything, where a '
            'maybePop of its own would report a second refusal',
      );
    });

    testWidgets('the only page of a node can guard itself', (tester) async {
      await tester.pumpWidget(const _InnerGuardedHost());

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(
        find.text('node content'),
        findsOneWidget,
        reason: "a PopScope on the node's own page is inside the node, and "
            'the node asks its navigator before it decides anything outside',
      );
    });

    // The two parameters had never been used together. `isRoot` says the node
    // keeps a pop to itself, and `pop()` honours that; the system back path
    // reaches the navigator above by a different line, and nothing checked
    // that the same promise holds there.
    testWidgets('a root node keeps the pop even when onPop allows it',
        (tester) async {
      var calls = 0;

      await tester.pumpWidget(
        _OnPopHost(
          isRoot: true,
          onPop: (context, result) {
            calls++;

            return true;
          },
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(calls, 1, reason: 'the hook is still asked');
      expect(
        find.text('node content'),
        findsOneWidget,
        reason: 'a root node keeps a pop to itself, and an onPop that allows '
            'one answers about the node, not about the route below it',
      );
    });

    // The answer reaches the same decision by the other branch, and the
    // asynchronous one is where the route is popped a whole turn of the event
    // loop after the press.
    testWidgets(
        'a root node keeps the pop when an asynchronous onPop allows it',
        (tester) async {
      var calls = 0;

      await tester.pumpWidget(
        _OnPopHost(
          isRoot: true,
          onPop: (context, result) async {
            calls++;

            return true;
          },
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(calls, 1);
      expect(find.text('node content'), findsOneWidget);
    });

    testWidgets(
        'system back still reaches onPop after an inner route came '
        'and went', (tester) async {
      var calls = 0;

      await tester.pumpWidget(
        _OnPopHost(
          onPop: (context, result) {
            calls++;
            return calls > 3;
          },
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      // Moving the inner stack makes the nested navigator report itself anew,
      // and the forwarding marker must not colour that report.
      await tester.tap(find.text('open inside'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('close inside'));
      await tester.pumpAndSettle();
      expect(find.text('node content'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(
        calls,
        1,
        reason: 'the node has nothing of its own left to close, so the back '
            'belongs to onPop',
      );
      expect(find.text('node content'), findsOneWidget);
    });

    testWidgets('system back inside nested nodes keeps the enclosing route', (
      tester,
    ) async {
      await tester.pumpWidget(const _NestedHost());

      await tester.tap(find.text('open inner'));
      await tester.pumpAndSettle();
      expect(find.text('inner pushed'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('inner pushed'), findsNothing);
      expect(
        find.text('open inner'),
        findsOneWidget,
        reason: 'the innermost node handled the back; nothing above it moved',
      );
    });

    testWidgets('pop() on the only page of a root node keeps the page', (
      tester,
    ) async {
      await tester.pumpWidget(const _Host(useNode: true, isRoot: true));
      expect(find.text('open'), findsOneWidget);

      await tester.tap(find.text('pop the node'));
      await tester.pumpAndSettle();

      expect(
        find.text('open'),
        findsOneWidget,
        reason: 'a root node keeps a pop to itself instead of emptying itself',
      );
    });

    testWidgets(
        'an ordinary node keeps its page when there is nowhere to '
        'forward a pop', (tester) async {
      await tester.pumpWidget(const _Host(useNode: true));

      // The node sits on the first route of the app, so the forwarded pop has
      // nothing to close. Doing it twice is the point: the way outwards must
      // not be a one-shot.
      await tester.tap(find.text('pop the node'));
      await tester.pumpAndSettle();
      expect(find.text('open'), findsOneWidget);

      await tester.tap(find.text('pop the node'));
      await tester.pumpAndSettle();

      expect(
        find.text('open'),
        findsOneWidget,
        reason: 'the node must never be left with an empty stack',
      );
    });

    // The point of the node is that what it opens stands below the scopes the
    // node stands under. `onPop` is where the topic sends a reader to ask a
    // confirmation, and which navigator that confirmation lands on is decided
    // by the context the hook is handed.
    testWidgets('a dialog asked for by onPop belongs to the node', (
      tester,
    ) async {
      await tester.pumpWidget(const _DialogOnPopHost());

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(
        find.text('asking: secret'),
        findsOneWidget,
        reason: 'the dialog was opened with useRootNavigator: false, so it '
            'belongs to the node and reads the scope the node stands under',
      );

      await tester.tap(find.text('stay'));
      await tester.pumpAndSettle();
    });

    testWidgets('an ordinary node forwards a pop it cannot handle', (
      tester,
    ) async {
      await tester.pumpWidget(const _OnPopHost());
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text('node content'), findsOneWidget);

      await tester.tap(find.text('pop the node'));
      await tester.pumpAndSettle();

      expect(
        find.text('go'),
        findsOneWidget,
        reason: 'the pop left the node and closed the route around it',
      );
    });

    testWidgets('a root node does not forward a pop even when it could', (
      tester,
    ) async {
      await tester.pumpWidget(const _OnPopHost(isRoot: true));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('pop the node'));
      await tester.pumpAndSettle();

      expect(
        find.text('node content'),
        findsOneWidget,
        reason: 'there is a navigator above to forward to, and isRoot is '
            'exactly the instruction not to use it',
      );
    });

    testWidgets('the navigatorKey hands the nested navigator to its owner', (
      tester,
    ) async {
      final key = GlobalKey<NodeNavigatorState>();

      await tester.pumpWidget(_Host(useNode: true, navigatorKey: key));

      expect(key.currentState, isNotNull);

      // Not awaited: the future a push returns completes when the route is
      // *popped*, so awaiting it here would wait for a screen nobody closes.
      unawaited(
        key.currentState!.push<void>(
          MaterialPageRoute<void>(builder: (context) => const _Pushed()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('pushed: secret'),
        findsOneWidget,
        reason: 'a route pushed through the key lands in the same node',
      );
    });

    // `NavigatorState.didUpdateWidget` compares the page list it is handed by
    // identity. A fresh list on every build therefore makes the nested
    // navigator diff its stack and report it again -- for a page that has not
    // changed at all -- and every listener above the node hears about it.
    testWidgets('a rebuild of the node hands its navigator the same pages',
        (tester) async {
      await tester.pumpWidget(const _RebuildableNodeHost());
      await tester.pumpAndSettle();

      final pagesBefore = _nodePages(tester);
      final reportsBefore = _RebuildableNodeHostState.instance!.reports;

      _RebuildableNodeHostState.instance!.rebuild();
      await tester.pumpAndSettle();

      expect(
        _nodePages(tester),
        same(pagesBefore),
        reason: 'the child is the same object, so there is nothing new to hand '
            'over',
      );
      expect(
        _RebuildableNodeHostState.instance!.reports,
        reportsBefore,
        reason: 'and the navigator therefore says nothing about its stack',
      );
    });

    testWidgets('a changed child hands its navigator a new page',
        (tester) async {
      await tester.pumpWidget(const _RebuildableNodeHost());
      await tester.pumpAndSettle();

      final pagesBefore = _nodePages(tester);

      _RebuildableNodeHostState.instance!.showOtherChild();
      await tester.pumpAndSettle();

      expect(_nodePages(tester), isNot(same(pagesBefore)));
      expect(
        find.text('the other child'),
        findsOneWidget,
        reason: 'keeping the list must not mean keeping a stale page',
      );
    });

    // An `onPop` that asks before answering leaves a window open, and the
    // system back does not wait politely. A second press used to start a
    // second question, and two `true` answers took two outer routes.
    testWidgets('an asynchronous onPop is asked once, however fast the presses',
        (tester) async {
      final gate = Completer<bool>();
      var calls = 0;

      await tester.pumpWidget(
        _OnPopHost(
          onPop: (context, result) {
            calls++;

            return gate.future;
          },
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(calls, 1, reason: 'the second press met a question already asked');

      gate.complete(true);
      await tester.pumpAndSettle();

      expect(
        find.text('go'),
        findsOneWidget,
        reason: 'and the answer took exactly one route',
      );
    });

    testWidgets('an asynchronous onPop that answers too late takes nothing',
        (tester) async {
      final gate = Completer<bool>();

      await tester.pumpWidget(
        _OnPopHost(onPop: (context, result) => gate.future),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pump();

      // The route the node sits on is closed by something else while the
      // question is still open.
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();

      expect(find.text('go'), findsOneWidget);

      gate.complete(true);
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason: 'an answer about a route that is already gone is not acted on',
      );
      expect(
        find.text('go'),
        findsOneWidget,
        reason: 'and it does not take the screen below with it',
      );
    });

    // The node is still mounted here -- its route only moved down the stack --
    // so `mounted` says nothing and the route itself has to be asked.
    testWidgets(
        'an asynchronous onPop answering under a newer route takes '
        'nothing', (tester) async {
      final gate = Completer<bool>();

      await tester.pumpWidget(
        _OnPopHost(onPop: (context, result) => gate.future),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pump();

      // Something else pushes over the node while the question is open.
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      unawaited(
        navigator.push<void>(
          MaterialPageRoute<void>(
            builder: (context) => const Scaffold(body: Text('on top')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      gate.complete(true);
      await tester.pumpAndSettle();

      expect(
        find.text('on top'),
        findsOneWidget,
        reason: 'the answer was about a route that is no longer the top one',
      );
    });

    // A confirmation dialog is user code, and user code falls over. The chain
    // the answer travels in belongs to nobody, so a failure left in it
    // surfaced far from the widget that raised it -- as an unhandled zone
    // error, in whatever test or frame happened to be running.
    testWidgets('an asynchronous onPop that fails is reported', (tester) async {
      var calls = 0;

      await tester.pumpWidget(
        _OnPopHost(
          onPop: (context, result) {
            calls++;

            return Future<bool>.error(StateError('the dialog fell over'));
          },
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isA<StateError>());
      expect(
        find.text('go'),
        findsNothing,
        reason: 'a question without an answer takes no route',
      );

      // And the node is not left thinking a question is still open.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(calls, 2);
      expect(tester.takeException(), isA<StateError>());
    });

    // The other half of the same chain: the question answered, and what the
    // answer sets off falls over. `then(onValue, onError:)` hands `onError` the
    // failures of the future it is chained to and nothing else, so a raise
    // inside `onValue` -- where the node asks the route about a pop, and where
    // it pops -- went to a chain nobody holds.
    testWidgets('a guard that raises while the node stands aside is reported',
        (tester) async {
      final gate = Completer<bool>();

      await tester.pumpWidget(
        _RaisingGuardHost(onPop: (context, result) => gate.future.then(_arm)),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pump();

      gate.complete(true);
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isA<StateError>(),
        reason: 'asking the route is user code like any other: reported, not '
            'left in a chain nobody holds',
      );
    });

    // And the node does not keep standing aside. It steps aside for the length
    // of one read -- a raise in the middle of that read used to leave it aside
    // for good, and the node then let every later press take the whole route.
    testWidgets('a guard that raises does not leave the node stood aside',
        (tester) async {
      final gate = Completer<bool>();
      var calls = 0;

      await tester.pumpWidget(
        _RaisingGuardHost(
          onPop: (context, result) {
            calls++;

            return gate.future.then(_arm);
          },
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pump();

      gate.complete(true);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isA<StateError>());

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(
        calls,
        2,
        reason: "the press is still the node's to answer -- a node left stood "
            'aside is not asked at all, and the route simply goes',
      );
      expect(
        find.text('go'),
        findsOneWidget,
        reason: 'and this time the route went because the node said so',
      );
    });

    // The node can go without its route going: an app that swaps it out of the
    // route's subtree while a confirmation is on screen leaves the answer with
    // nothing to act through.
    testWidgets(
        'an asynchronous onPop answering after the node is gone takes '
        'nothing', (tester) async {
      final gate = Completer<bool>();

      await tester.pumpWidget(
        _RemovableNodeHost(onPop: (context, result) => gate.future),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pump();

      _RemovableNodeState.instance!.removeNode();
      await tester.pumpAndSettle();

      expect(find.text('without a node'), findsOneWidget);

      gate.complete(true);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.text('without a node'),
        findsOneWidget,
        reason: 'the answer had nothing left to pop through',
      );
    });

    // The key is what the navigator is built with, so a new one would mean a
    // new navigator and an empty stack. Refusing is the only honest answer --
    // and it is what catches a `GlobalKey()` built inline in `build`.
    testWidgets('a changed navigatorKey is refused', (tester) async {
      final first = GlobalKey<NodeNavigatorState>();
      final second = GlobalKey<NodeNavigatorState>();

      await tester.pumpWidget(_Host(useNode: true, navigatorKey: first));
      await tester.pumpAndSettle();

      await tester.pumpWidget(_Host(useNode: true, navigatorKey: second));

      expect(
        tester.takeException(),
        isA<AssertionError>().having(
          (error) => error.message.toString(),
          'message',
          contains('`Widget.key`'),
        ),
      );
    });

    testWidgets('a node route is not on the root navigator', (tester) async {
      await tester.pumpWidget(const _Host(useNode: true));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final rootNavigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );

      expect(
        rootNavigator.canPop(),
        isFalse,
        reason: 'the root navigator still holds a single route',
      );
    });
  });
}

final class _Config {
  final String value;

  const _Config(this.value);
}

final class _Host extends StatelessWidget {
  final bool useNode;
  final GlobalKey<NodeNavigatorState>? navigatorKey;
  final bool isRoot;

  const _Host({
    required this.useNode,
    this.navigatorKey,
    this.isRoot = false,
  });

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: ScopeModel<_Config>(
          create: (context) => const _Config('secret'),
          dispose: (model) {},
          builder: (context) => useNode
              ? NavigationNode(
                  navigatorKey: navigatorKey,
                  isRoot: isRoot,
                  child: const _NodeContent(),
                )
              : const _NodeContent(),
        ),
      );
}

final class _NodeContent extends StatelessWidget {
  const _NodeContent();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: Navigator.of(context).pop,
                child: const Text('pop the node'),
              ),
              TextButton(
                // The future a push returns completes when the route is popped,
                // and nothing here waits for that.
                onPressed: () => unawaited(
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => const _Pushed(),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
              TextButton(
                onPressed: () => unawaited(
                  showDialog<void>(
                    context: context,
                    useRootNavigator: false,
                    builder: (context) => const AlertDialog(
                      content: Text('dialog'),
                    ),
                  ),
                ),
                child: const Text('open dialog'),
              ),
              TextButton(
                onPressed: () => unawaited(
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => const _GuardedPushed(),
                    ),
                  ),
                ),
                child: const Text('open guarded'),
              ),
            ],
          ),
        ),
      );
}

/// Puts a node with an [NavigationNode.onPop] on a route of its own, so a pop
/// that leaves the node has somewhere to land.
final class _OnPopHost extends StatelessWidget {
  final FutureOr<bool> Function(BuildContext context, Object? result)? onPop;
  final bool isRoot;

  const _OnPopHost({this.onPop, this.isRoot = false});

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => unawaited(
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => NavigationNode(
                        onPop: onPop,
                        isRoot: isRoot,
                        child: const _OnPopNodeContent(),
                      ),
                    ),
                  ),
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
}

/// The application guards the route it puts the node on, and refuses.
final class _AppGuardedHost extends StatelessWidget {
  final VoidCallback onRefused;

  const _AppGuardedHost({required this.onRefused});

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => unawaited(
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => PopScope<void>(
                        canPop: false,
                        onPopInvokedWithResult: (didPop, result) {
                          if (!didPop) onRefused();
                        },
                        child: NavigationNode(
                          onPop: (context, result) => true,
                          child: const _OnPopNodeContent(),
                        ),
                      ),
                    ),
                  ),
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
}

/// The node's only page refuses the pop itself.
final class _InnerGuardedHost extends StatelessWidget {
  const _InnerGuardedHost();

  @override
  Widget build(BuildContext context) => const MaterialApp(
        home: NavigationNode(
          child: PopScope<void>(canPop: false, child: _OnPopNodeContent()),
        ),
      );
}

/// A node under a scope, whose `onPop` asks a confirmation the way the `utils`
/// topic recommends asking one.
final class _DialogOnPopHost extends StatelessWidget {
  const _DialogOnPopHost();

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: ScopeModel<_Config>(
          create: (context) => const _Config('secret'),
          dispose: (model) {},
          builder: (context) => NavigationNode(
            onPop: (context, result) async {
              await showDialog<void>(
                context: context,
                useRootNavigator: false,
                builder: (context) {
                  final config = ScopeModel.maybeOf<_Config>(
                    context,
                    listen: false,
                  );

                  return AlertDialog(
                    content: Text('asking: ${config?.value ?? 'none'}'),
                    actions: [
                      TextButton(
                        onPressed: Navigator.of(context).pop,
                        child: const Text('stay'),
                      ),
                    ],
                  );
                },
              );

              return false;
            },
            child: const _NodeContent(),
          ),
        ),
      );
}

/// Puts a node whose first page carries an `AppBar` on a pushed route, so the
/// arrow that `AppBar` draws has somewhere to go.
final class _AppBarHost extends StatelessWidget {
  final bool isRoot;

  const _AppBarHost({this.isRoot = false});

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => unawaited(
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => NavigationNode(
                        isRoot: isRoot,
                        child: Scaffold(
                          appBar: AppBar(title: const Text('node content')),
                          body: const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
}

/// Puts a `Scaffold` with a drawer on a pushed route, with or without a node
/// around it, so the two can be compared on the same press.
final class _DrawerHost extends StatelessWidget {
  final bool useNode;

  const _DrawerHost({required this.useNode});

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => unawaited(
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => useNode
                          ? const NavigationNode(child: _DrawerScreen())
                          : const _DrawerScreen(),
                    ),
                  ),
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
}

final class _DrawerScreen extends StatelessWidget {
  const _DrawerScreen();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('node content')),
        drawer: const Drawer(child: Center(child: Text('drawer'))),
        body: const SizedBox.shrink(),
      );
}

/// Puts the `Scaffold` that owns the drawer *above* the node, on the same
/// pushed route, so the drawer's local history entry belongs to the route the
/// node stands on rather than to one inside it.
final class _DrawerAboveNodeHost extends StatelessWidget {
  final List<String> log;

  const _DrawerAboveNodeHost({required this.log});

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => unawaited(
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => Scaffold(
                        appBar: AppBar(title: const Text('node content')),
                        drawer:
                            const Drawer(child: Center(child: Text('drawer'))),
                        body: NavigationNode(
                          onPop: (context, result) {
                            log.add('onPop');

                            return false;
                          },
                          child: const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
}

/// Puts an ordinary node straight on the first route of the application, where
/// a pop that leaves the node has nowhere to land.
final class _FirstRouteNodeHost extends StatelessWidget {
  final FutureOr<bool> Function(BuildContext context, Object? result)? onPop;

  const _FirstRouteNodeHost({this.onPop});

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: NavigationNode(onPop: onPop, child: const _OnPopNodeContent()),
      );
}

/// A pushed route with a guard of its own that can be made to raise.
///
/// The guard is a [PopEntry], the same thing a `PopScope` registers and the same
/// thing the node registers, and it is read at the moment the route is asked
/// what a pop there would do. The node asks that question itself, from inside
/// the `then` of an asynchronous `onPop` -- so an armed guard raises exactly
/// where the failure the finding is about belongs.
///
/// Armed on demand rather than always: the first press reaches the same guard
/// through the outer navigator's own `maybePop`, and raising there would be the
/// application's callback failing on its own, with no chain of the node's in
/// sight.
final class _RaisingGuardHost extends StatelessWidget {
  final FutureOr<bool> Function(BuildContext context, Object? result) onPop;

  const _RaisingGuardHost({required this.onPop});

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => unawaited(
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => _RaisingGuard(
                        child: NavigationNode(
                          onPop: onPop,
                          child: const _OnPopNodeContent(),
                        ),
                      ),
                    ),
                  ),
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
}

/// Arms the guard as the answer to `onPop` arrives.
///
/// Between this and the node's own read of the route there is nothing but a
/// microtask, so the read that raises is the node's.
bool _arm(bool answer) {
  _RaisingGuardState.instance!.armOnce();

  return answer;
}

/// Registers a [PopEntry] of its own on the route it is built in.
///
/// The same three lines the node's own dispatcher uses, so the guard is asked
/// whenever the route is: [ModalRoute.popDisposition] reads every entry it
/// holds.
final class _RaisingGuard extends StatefulWidget {
  final Widget child;

  const _RaisingGuard({required this.child});

  @override
  State<_RaisingGuard> createState() => _RaisingGuardState();
}

final class _RaisingGuardState extends State<_RaisingGuard>
    implements PopEntry<Object?> {
  static _RaisingGuardState? instance;

  ModalRoute<dynamic>? _route;

  @override
  final _RaisingCanPop canPopNotifier = _RaisingCanPop();

  bool _armedOnce = false;

  /// Arms the guard for the first answer only.
  ///
  /// A later press is answered the same way and would arm it again, and the
  /// point of the second press is what the node does when nothing is wrong.
  void armOnce() {
    if (_armedOnce) {
      return;
    }

    _armedOnce = true;
    canPopNotifier.armed = true;
  }

  @override
  void onPopInvoked(bool didPop) {}

  @override
  void onPopInvokedWithResult(bool didPop, Object? result) {}

  @override
  void initState() {
    super.initState();
    instance = this;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final nextRoute = ModalRoute.of(context);
    if (nextRoute != _route) {
      _route?.unregisterPopEntry(this);
      _route = nextRoute;
      _route?.registerPopEntry(this);
    }
  }

  @override
  void dispose() {
    _route?.unregisterPopEntry(this);
    _route = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Answers `true`, and raises once when armed.
///
/// One shot on purpose: the route is asked what a pop would do from more places
/// than the node's own chain -- the framework asks whenever a navigator's
/// history changes -- and a guard that kept raising would report from all of
/// them. Armed from inside the answer to `onPop`, disarmed by the read itself,
/// it raises in exactly the read the node makes.
///
/// Not a `ValueNotifier`: it never changes its mind, it changes what reading it
/// does. The framework listens to it, so the listener methods are real methods
/// that do nothing rather than throwing ones.
final class _RaisingCanPop implements ValueListenable<bool> {
  bool armed = false;

  @override
  bool get value {
    if (!armed) {
      return true;
    }

    armed = false;

    throw StateError('the guard fell over');
  }

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

/// A pushed route whose subtree can drop the node while the route stays.
final class _RemovableNodeHost extends StatelessWidget {
  final FutureOr<bool> Function(BuildContext context, Object? result) onPop;

  const _RemovableNodeHost({required this.onPop});

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => unawaited(
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => _RemovableNode(onPop: onPop),
                    ),
                  ),
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
}

final class _RemovableNode extends StatefulWidget {
  final FutureOr<bool> Function(BuildContext context, Object? result) onPop;

  const _RemovableNode({required this.onPop});

  @override
  State<_RemovableNode> createState() => _RemovableNodeState();
}

final class _RemovableNodeState extends State<_RemovableNode> {
  static _RemovableNodeState? instance;

  bool _hasNode = true;

  void removeNode() => setState(() => _hasNode = false);

  @override
  void initState() {
    super.initState();
    instance = this;
  }

  @override
  Widget build(BuildContext context) => _hasNode
      ? NavigationNode(
          onPop: widget.onPop,
          child: const _OnPopNodeContent(),
        )
      : const Scaffold(body: Center(child: Text('without a node')));
}

final class _OnPopNodeContent extends StatelessWidget {
  const _OnPopNodeContent();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('node content'),
              TextButton(
                onPressed: Navigator.of(context).pop,
                child: const Text('pop the node'),
              ),
              TextButton(
                onPressed: () => unawaited(
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => Scaffold(
                        body: Center(
                          child: TextButton(
                            onPressed: Navigator.of(context).pop,
                            child: const Text('close inside'),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                child: const Text('open inside'),
              ),
            ],
          ),
        ),
      );
}

/// A node inside another node: the inner one is the only one with a route of
/// its own to close.
final class _NestedHost extends StatelessWidget {
  const _NestedHost();

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: NavigationNode(
          isRoot: true,
          child: NavigationNode(
            child: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => unawaited(
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (context) => const Scaffold(
                            body: Center(child: Text('inner pushed')),
                          ),
                        ),
                      ),
                    ),
                    child: const Text('open inner'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

final class _Pushed extends StatelessWidget {
  const _Pushed();

  @override
  Widget build(BuildContext context) {
    final config = ScopeModel.maybeOf<_Config>(context, listen: false);

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('pushed: ${config?.value ?? 'none'}'),
            TextButton(
              onPressed: Navigator.of(context).pop,
              child: const Text('back'),
            ),
          ],
        ),
      ),
    );
  }
}

final class _GuardedPushed extends StatelessWidget {
  const _GuardedPushed();

  @override
  Widget build(BuildContext context) => const PopScope(
        canPop: false,
        child: Scaffold(
          body: Center(child: Text('guarded route')),
        ),
      );
}

/// The pages the node's own navigator is holding.
///
/// `find.byType` matches an exact runtime type, and the node builds a private
/// subclass of `Navigator`, so the navigators are found by predicate: the outer
/// one is the ancestor, the node's is the last.
List<Page<Object?>> _nodePages(WidgetTester tester) => tester
    .stateList<NavigatorState>(
      find.byWidgetPredicate((widget) => widget is Navigator),
    )
    .last
    .widget
    .pages;

/// A node under a parent that can rebuild without changing anything.
///
/// The child is `const`, so it is the same object on every build -- which is
/// what a node has to notice. Also counts what the nested navigator says about
/// its stack: a `NavigationNotification` is dispatched whenever a navigator's
/// history is flushed, which is what a needless page diff ends in.
final class _RebuildableNodeHost extends StatefulWidget {
  const _RebuildableNodeHost();

  @override
  State<_RebuildableNodeHost> createState() => _RebuildableNodeHostState();
}

final class _RebuildableNodeHostState extends State<_RebuildableNodeHost> {
  static _RebuildableNodeHostState? instance;

  bool _other = false;

  int reports = 0;

  void rebuild() => setState(() {});

  void showOtherChild() => setState(() => _other = true);

  @override
  void initState() {
    super.initState();
    instance = this;
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: NotificationListener<NavigationNotification>(
          onNotification: (notification) {
            reports++;

            return false;
          },
          child: NavigationNode(
            child: _other
                ? const Scaffold(body: Center(child: Text('the other child')))
                : const Scaffold(body: Center(child: Text('the first child'))),
          ),
        ),
      );
}
