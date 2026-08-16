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

    // The type arguments read scope-first, value-last, the way they do
    // everywhere else in the package -- including this family's own base,
    // `AsyncDataScopeBase.select<W, T, V>`.
    testWidgets('select reads one part of the value', (tester) async {
      await tester.pumpWidget(
        _Host(
          init: (context) =>
              Stream.value(AsyncDataScopeReady(_Database('main'))),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('selected: main'), findsOneWidget);
    });

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

  // `null` is a value like any other when `T` is nullable, and the getter used
  // to read the value itself as the answer to "is there one yet?". Before the
  // initialization finished it therefore handed out `null` — a value the scope
  // never produced — instead of saying there was nothing to hand out.
  group('AsyncDataScope with a nullable value', () {
    testWidgets('data throws before the value arrives', (tester) async {
      final gate = Completer<void>();
      Object? seen;

      await tester.pumpWidget(
        _NullableHost(
          init: (context) async* {
            await gate.future;

            yield AsyncDataScopeReady(null);
          },
          onInitializing: (data) => seen = data,
        ),
      );
      await tester.pump();

      expect(
        seen,
        isA<StateError>(),
        reason: 'the scope has produced nothing yet, and `null` is not a way '
            'to say so',
      );

      gate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('data returns the null the initialization produced',
        (tester) async {
      Object? seen = 'not read';

      await tester.pumpWidget(
        _NullableHost(
          init: (context) => Stream.value(AsyncDataScopeReady(null)),
          onReady: (data) => seen = data,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        seen,
        isNull,
        reason: 'the value is there, and it is `null`',
      );
    });
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
            children: [
              Text('ready: ${data.name}'),
              const _Descendant(),
              const _Selector(),
            ],
          ),
        ),
      );
}

/// A scope over a nullable value, with a reader on each branch.
///
/// Both readers ask for `data` through a descendant, which is the only place
/// the scope can be looked up from — the builders are called with the scope's
/// own element, and a lookup walks the ancestors.
final class _NullableHost extends StatelessWidget {
  final Stream<AsyncDataScopeInitState<Object, String?>> Function(
    BuildContext context,
  ) init;
  final void Function(Object? data)? onInitializing;
  final void Function(Object? data)? onReady;

  const _NullableHost({required this.init, this.onInitializing, this.onReady});

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: AsyncDataScope<String?>(
          init: init,
          dispose: (data) {},
          initBuilder: (context, progress) => _NullableReader(onInitializing),
          errorBuilder: (context, error, stackTrace, progress) =>
              const SizedBox.shrink(),
          builder: (context, data) => _NullableReader(onReady),
        ),
      );
}

/// Reports what `data` gave it: the value, or whatever it threw.
final class _NullableReader extends StatelessWidget {
  final void Function(Object? data)? report;

  const _NullableReader(this.report);

  @override
  Widget build(BuildContext context) {
    try {
      report?.call(AsyncDataScope.of<String?>(context, listen: false).data);
      // ignore: avoid_catching_errors
    } on Object catch (error) {
      report?.call(error);
    }

    return const SizedBox.shrink();
  }
}

final class _Selector extends StatelessWidget {
  const _Selector();

  @override
  Widget build(BuildContext context) {
    final name = AsyncDataScope.select<_Database, String>(
      context,
      (scope) => scope.data.name,
    );

    return Text('selected: $name');
  }
}

final class _Descendant extends StatelessWidget {
  const _Descendant();

  @override
  Widget build(BuildContext context) {
    final data = AsyncDataScope.of<_Database>(context, listen: false).data;

    return Text('descendant: ${data.name}');
  }
}
