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
            init: (context, ctx) async {
              ctx.progress('opening');
              await gate.future;

              return _Database('main');
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
          init: (context, ctx) async => _Database('main'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('selected: main'), findsOneWidget);
    });

    // The half a generator cannot do at all: a body that asks the context
    // nothing cannot be stopped, so its value arrives for a scope that is
    // already gone. Inside a generator that value stayed with a body nobody
    // would resume; here the scope still has it, and the only thing left to
    // do with it is to release it.
    testWidgets(
      'a value that arrives after the cancellation is handed to dispose',
      (tester) async {
        final disposed = <_Database>[];
        final database = _Database('main');
        final gate = Completer<void>();

        await tester.pumpWidget(
          _Host(
            init: (context, ctx) async {
              await gate.future;

              return database;
            },
            dispose: disposed.add,
          ),
        );
        await tester.pump();

        await tester.pumpWidget(const SizedBox.shrink());
        gate.complete();
        await settle(tester, until: () => disposed.isNotEmpty);

        expect(
          disposed,
          [same(database)],
          reason: 'the value the body produced too late is still released',
        );
      },
    );

    testWidgets('hands the data it produced to dispose', (tester) async {
      final disposed = <_Database>[];
      final database = _Database('main');

      await tester.pumpWidget(
        _Host(
          init: (context, ctx) async => database,
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
            init: (context, ctx) async {
              ctx.progress('opening');

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

    // The value is caught in the `map` the family wraps the initialization
    // in, one step ahead of the "already initialized" check in the layer
    // above: `map` runs as the event goes past, `asyncMap` only after. A
    // second `ready` therefore replaced the value before anything could refuse
    // it -- the model stayed as it was, the dependents heard nothing, and the
    // first value was left with nobody to release it.

    testWidgets(
      'nothing is disposed of when the data never arrived',
      (tester) async {
        final disposed = <_Database>[];

        await tester.pumpWidget(
          _Host(
            init: (context, ctx) async {
              ctx.progress('opening');

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
          init: (context, ctx) async {
            await gate.future;

            return null;
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
          init: (context, ctx) async => null,
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

    // `dataOrNull` cannot answer this one: it is `null` on both sides of the
    // moment the value arrives. `_hasData` was kept for exactly this and was
    // only ever consulted by `data`.
    testWidgets('hasData tells "nothing yet" from "the value is null"',
        (tester) async {
      final gate = Completer<void>();
      final seen = <bool>[];

      await tester.pumpWidget(
        _NullableHost(
          init: (context, ctx) async {
            await gate.future;

            return null;
          },
          onInitializingHasData: seen.add,
          onReadyHasData: seen.add,
        ),
      );
      await tester.pump();

      expect(seen, [false], reason: 'nothing has been produced yet');

      gate.complete();
      await tester.pumpAndSettle();

      expect(seen, [false, true]);
    });
  });
}

final class _Database {
  final String name;

  _Database(this.name);
}

final class _Host extends StatelessWidget {
  final Future<_Database> Function(
    BuildContext context,
    ScopeInitContext ctx,
  ) init;
  final void Function(_Database data)? dispose;

  const _Host({required this.init, this.dispose});

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: AsyncDataScope<_Database>(
          initData: init,
          disposeData: (data) => dispose?.call(data),
          progressBuilder: (context, progress) =>
              Text('initializing: $progress'),
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
  final Future<String?> Function(
    BuildContext context,
    ScopeInitContext ctx,
  ) init;
  final void Function(Object? data)? onInitializing;
  final void Function(Object? data)? onReady;
  final void Function(bool hasData)? onInitializingHasData;
  final void Function(bool hasData)? onReadyHasData;

  const _NullableHost({
    required this.init,
    this.onInitializing,
    this.onReady,
    this.onInitializingHasData,
    this.onReadyHasData,
  });

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: AsyncDataScope<String?>(
          initData: init,
          disposeData: (data) {},
          progressBuilder: (context, progress) =>
              _NullableReader(onInitializing, onInitializingHasData),
          errorBuilder: (context, error, stackTrace, progress) =>
              const SizedBox.shrink(),
          builder: (context, data) => _NullableReader(onReady, onReadyHasData),
        ),
      );
}

/// Reports what `data` gave it: the value, or whatever it threw. And what
/// `hasData` said, which for a nullable value is the only way to tell the two
/// `null`s apart.
final class _NullableReader extends StatelessWidget {
  final void Function(Object? data)? report;
  final void Function(bool hasData)? reportHasData;

  const _NullableReader(this.report, [this.reportHasData]);

  @override
  Widget build(BuildContext context) {
    final scope = AsyncDataScope.of<String?>(context, listen: false);
    reportHasData?.call(scope.hasData);

    try {
      report?.call(scope.data);
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
