import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scopo/scopo.dart';

import 'utils/settle.dart';

/// The initialization written as a plain `Future`: the progress and the
/// cancellation reach the body through a context instead of through the
/// mechanics of a generator.
void main() {
  group('ScopeInitContext', () {
    testWidgets('reports progress and finishes by returning', (tester) async {
      final gate = Completer<void>();

      await tester.pumpWidget(
        _Host(
          init: (context, ctx) async {
            ctx.progress('connecting');
            await gate.future;
          },
        ),
      );
      await tester.pump();

      expect(
        find.text('initializing: connecting'),
        findsOneWidget,
        reason: 'what `ctx.progress` reported is what is shown',
      );

      gate.complete();
      await tester.pumpAndSettle();

      expect(
        find.text('ready'),
        findsOneWidget,
        reason: 'the body returning is how the scope is told it is ready',
      );
    });

    // The point of the whole exercise. `yield` works in the body of the
    // generator and nowhere else, so reporting a step from a helper meant
    // making the helper a `Stream` too, and its caller, and so on up. A call
    // on the context can be made from anywhere.
    testWidgets('reports progress from a nested function', (tester) async {
      Future<void> openStorage(ScopeInitContext ctx) async {
        ctx.progress('opening storage');
        await Future<void>.delayed(Duration.zero);
      }

      await tester.pumpWidget(
        _Host(init: (context, ctx) => openStorage(ctx)),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('initializing: opening storage'), findsOneWidget);

      await tester.pumpAndSettle();

      expect(find.text('ready'), findsOneWidget);
    });

    testWidgets(
      'a scope that leaves the tree cancels the body where it waits',
      (tester) async {
        final log = <String>[];
        final gate = Completer<void>();

        await tester.pumpWidget(
          _Host(
            init: (context, ctx) async {
              try {
                await ctx.wait(() => gate.future);
                log.add('past the wait');
              } finally {
                log.add('finally');
              }
            },
          ),
        );
        await tester.pump();

        expect(log, isEmpty, reason: 'the body is parked on the gate');

        await tester.pumpWidget(const SizedBox.shrink());
        await settle(tester, until: () => log.contains('finally'));

        expect(
          log,
          ['finally'],
          reason: 'the wait ends the moment the scope leaves the tree, and '
              'the body unwinds instead of running on',
        );
        expect(gate.isCompleted, isFalse, reason: 'nobody completed the gate');
      },
    );

    testWidgets('check throws once the scope has given up', (tester) async {
      final log = <String>[];
      final gate = Completer<void>();

      await tester.pumpWidget(
        _Host(
          init: (context, ctx) async {
            await gate.future;
            log.add('past the await');
            ctx.check();
            log.add('past the check');
          },
        ),
      );
      await tester.pump();

      await tester.pumpWidget(const SizedBox.shrink());
      gate.complete();
      await settle(tester, until: () => log.contains('past the await'));

      expect(
        log,
        ['past the await'],
        reason: 'a bare await does not notice the cancellation, and `check` '
            'right after it is what does',
      );
    });

    testWidgets(
      'a body that throws builds the error branch and keeps the last progress',
      (tester) async {
        await tester.pumpWidget(
          _Host(
            init: (context, ctx) async {
              ctx.progress('connecting');
              await Future<void>.delayed(Duration.zero);

              throw StateError('no connection');
            },
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('error: Bad state: no connection (connecting)'),
          findsOneWidget,
          reason: 'the failure reaches the error branch with the progress it '
              'had reached',
        );
      },
    );

    testWidgets(
      'a scope cancelled after the body finished still releases it',
      (tester) async {
        final log = <String>[];
        final gate = Completer<void>();

        await tester.pumpWidget(
          _Host(
            init: (context, ctx) async {
              // A bare `await`: this body never asks whether it is still
              // wanted, so it runs to its end for a scope that is already
              // gone.
              await gate.future;
              log.add('acquired');
            },
            dispose: () => log.add('released'),
          ),
        );
        await tester.pump();

        await tester.pumpWidget(const SizedBox.shrink());
        gate.complete();
        await settle(tester, until: () => log.contains('released'));

        expect(
          log,
          ['acquired', 'released'],
          reason: 'what a body took after the cancellation is still given back',
        );
      },
    );
  });

  // A concurrent group hands its arms a context of their own: the first arm
  // that fails cancels its siblings, and that has to happen without touching
  // the initialization the group itself belongs to.
  group('a child context', () {
    test('is cancelled with its parent', () {
      final parent = ScopeInitHandle();
      final child = ScopeInitHandle.childOf(parent.context);

      expect(child.isCancelled, isFalse);

      parent.cancel();

      expect(child.isCancelled, isTrue, reason: 'the parent takes it with it');
    });

    test('is cancelled on its own without touching the parent', () {
      final parent = ScopeInitHandle();
      final child = ScopeInitHandle.childOf(parent.context)..cancel();

      expect(child.isCancelled, isTrue);
      expect(
        parent.isCancelled,
        isFalse,
        reason: 'one arm giving up is not the whole initialization giving up',
      );
    });

    test('tells its own body, and the parent body separately', () {
      final parent = ScopeInitHandle();
      final child = ScopeInitHandle.childOf(parent.context);
      final told = <String>[];

      parent.context.onCancel(() => told.add('parent'));
      child.context.onCancel(() => told.add('child'));

      child.cancel();
      expect(told, ['child']);

      parent.cancel();
      expect(told, ['child', 'parent']);
    });

    test('made under a cancelled parent is already cancelled', () {
      final parent = ScopeInitHandle()..cancel();

      expect(ScopeInitHandle.childOf(parent.context).isCancelled, isTrue);
    });
  });
}

final class _Host extends StatelessWidget {
  final Future<void> Function(BuildContext context, ScopeInitContext ctx) init;
  final void Function()? dispose;

  const _Host({required this.init, this.dispose});

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: AsyncScope(
          initScope: init,
          disposeScope: () => dispose?.call(),
          progressBuilder: (context, progress) =>
              Text('initializing: $progress'),
          errorBuilder: (context, error, stackTrace, progress) =>
              Text('error: $error ($progress)'),
          builder: (context) => const Text('ready'),
        ),
      );
}
