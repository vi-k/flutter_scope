import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scopo/scopo.dart';

import 'utils/settle.dart';

void main() {
  group('AsyncDataScope', () {
    testWidgets(
      'reports progress, then hands the data to the builder and to the '
      'descendants',
      (tester) async {
        final gate = Completer<void>();

        await tester.pumpWidget(
          _Host(
            init: (context) async* {
              yield AsyncDataScopeProgress('opening');
              await gate.future;

              yield AsyncDataScopeReady(_Database('main'));
            },
          ),
        );
        await tester.pump();

        expect(
          find.text('initializing: opening'),
          findsOneWidget,
          reason: 'the progress the stream reported is what is shown',
        );

        gate.complete();
        await tester.pumpAndSettle();

        expect(find.text('ready: main'), findsOneWidget);
        expect(
          find.text('descendant: main'),
          findsOneWidget,
          reason: 'a descendant reads the same data through `of`',
        );
      },
    );

    testWidgets('hands the data it produced to dispose', (tester) async {
      final disposed = <_Database>[];
      final database = _Database('main');

      await tester.pumpWidget(
        _Host(
          init: (context) => Stream.value(AsyncDataScopeReady(database)),
          dispose: disposed.add,
        ),
      );
      await tester.pumpAndSettle();

      expect(disposed, isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester, until: () => disposed.isNotEmpty);

      expect(
        disposed,
        [same(database)],
        reason: 'the disposal releases exactly what the initialization opened',
      );
    });

    testWidgets(
      'a failure before the data arrives builds the error branch and keeps '
      'the last progress',
      (tester) async {
        await tester.pumpWidget(
          _Host(
            init: (context) async* {
              yield AsyncDataScopeProgress('opening');

              throw StateError('could not open');
            },
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('error: Bad state: could not open (opening)'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'nothing is disposed of when the data never arrived',
      (tester) async {
        final disposed = <_Database>[];

        await tester.pumpWidget(
          _Host(
            init: (context) async* {
              yield AsyncDataScopeProgress('opening');

              throw StateError('could not open');
            },
            dispose: disposed.add,
          ),
        );
        await tester.pumpAndSettle();

        await tester.pumpWidget(const SizedBox.shrink());
        // Never holds: the point is to give the disposal every chance to run
        // and then show that it had nothing to release.
        await settle(tester, until: () => disposed.isNotEmpty);

        expect(disposed, isEmpty);
      },
    );
  });
}

final class _Database {
  final String name;

  _Database(this.name);
}

final class _Host extends StatelessWidget {
  final Stream<AsyncDataScopeInitState<Object, _Database>> Function(
    BuildContext context,
  ) init;
  final void Function(_Database data)? dispose;

  const _Host({required this.init, this.dispose});

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: AsyncDataScope<_Database>(
          init: init,
          dispose: (data) => dispose?.call(data),
          initBuilder: (context, progress) => Text('initializing: $progress'),
          errorBuilder: (context, error, stackTrace, progress) =>
              Text('error: $error ($progress)'),
          builder: (context, data) => Column(
            children: [Text('ready: ${data.name}'), const _Descendant()],
          ),
        ),
      );
}

final class _Descendant extends StatelessWidget {
  const _Descendant();

  @override
  Widget build(BuildContext context) {
    final data = AsyncDataScope.of<_Database>(context, listen: false).data;

    return Text('descendant: ${data.name}');
  }
}
