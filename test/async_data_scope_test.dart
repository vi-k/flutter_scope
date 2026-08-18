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

    // The value is caught in the `map` the family wraps the initialization
    // in, one step ahead of the "already initialized" check in the layer
    // above: `map` runs as the event goes past, `asyncMap` only after. A
    // second `ready` therefore replaced the value before anything could refuse
    // it -- the model stayed as it was, the dependents heard nothing, and the
    // first value was left with nobody to release it.
    testWidgets('a second ready neither replaces the value nor strands it',
        (tester) async {
      final gate = Completer<void>();
      final disposed = <_Database>[];
      final first = _Database('first');
      final second = _Database('second');

      await tester.pumpWidget(
        _Host(
          init: (context) async* {
            yield AsyncDataScopeReady(first);
            await gate.future;

            yield AsyncDataScopeReady(second);
          },
          dispose: disposed.add,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ready: first'), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isA<StateError>(),
        reason: 'a second ready is a mistake in the initialization, and the '
            'scope says so instead of quietly acting on it',
      );
      expect(find.text('ready: first'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester, until: () => disposed.isNotEmpty);

      expect(
        disposed,
        [same(first)],
        reason: 'what is released is what the scope was given and handed on',
      );
    });

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

    // `dataOrNull` cannot answer this one: it is `null` on both sides of the
    // moment the value arrives. `_hasData` was kept for exactly this and was
    // only ever consulted by `data`.
    testWidgets('hasData tells "nothing yet" from "the value is null"',
        (tester) async {
      final gate = Completer<void>();
      final seen = <bool>[];

      await tester.pumpWidget(
        _NullableHost(
          init: (context) async* {
            await gate.future;

            yield AsyncDataScopeReady(null);
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
  final Stream<AsyncDataScopeInitState<Object, String?>> Function(
    BuildContext context,
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
          init: init,
          dispose: (data) {},
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
