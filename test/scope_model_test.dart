import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scopo/scopo.dart';

void main() {
  setUp(() {
    _NameText.buildCount = 0;
    _AgeText.buildCount = 0;
  });

  group('ScopeModel', () {
    testWidgets('retries a synchronous create failure on the next build', (
      tester,
    ) async {
      final scopeKey = GlobalKey();
      var createAttempts = 0;

      Widget buildTree() => Directionality(
            textDirection: TextDirection.ltr,
            child: ScopeModel<_Model>(
              key: scopeKey,
              create: (context) {
                createAttempts++;
                if (createAttempts == 1) {
                  throw StateError('controlled create failure');
                }

                return _Model('recovered');
              },
              dispose: (model) {},
              builder: (context) {
                final model = ScopeModel.of<_Model>(context, listen: false);

                return Text('name: ${model.name}');
              },
            ),
          );

      await tester.pumpWidget(buildTree());

      expect(createAttempts, 1);
      expect(
        tester.takeException(),
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'controlled create failure',
        ),
      );

      await tester.pumpWidget(buildTree());

      expect(
        tester.takeException(),
        isNull,
        reason: 'the keyed scope remains a real child and can be rebuilt',
      );
      expect(createAttempts, 2);
      expect(find.text('name: recovered'), findsOneWidget);
    });

    testWidgets(
      'removes a failed initialization before reusing its key successfully',
      (tester) async {
        final scopeKey = GlobalKey();
        final disposed = <_Model>[];
        var createAttempts = 0;
        var failCreate = true;

        Widget buildTree() => Directionality(
              textDirection: TextDirection.ltr,
              child: ScopeModel<_Model>(
                key: scopeKey,
                create: (context) {
                  createAttempts++;
                  if (failCreate) {
                    throw StateError('controlled create failure');
                  }

                  return _Model('recovered after removal');
                },
                dispose: disposed.add,
                builder: (context) {
                  final model = ScopeModel.of<_Model>(context, listen: false);

                  return Text('name: ${model.name}');
                },
              ),
            );

        await tester.pumpWidget(buildTree());

        expect(createAttempts, 1);
        expect(
          tester.takeException(),
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'controlled create failure',
          ),
        );

        await tester.pumpWidget(const SizedBox.shrink());
        final removalException = tester.takeException();

        failCreate = false;
        await tester.pumpWidget(buildTree());
        final retryException = tester.takeException();

        expect(
          removalException,
          isNull,
          reason: 'failed initialization has no model to dispose',
        );
        expect(
          retryException,
          isNull,
          reason: 'unmount released the GlobalKey for a fresh scope',
        );
        expect(createAttempts, 2);
        expect(find.text('name: recovered after removal'), findsOneWidget);
        expect(disposed, isEmpty);

        await tester.pumpWidget(const SizedBox.shrink());

        expect(disposed, hasLength(1));
        expect(disposed.single.name, 'recovered after removal');
      },
    );

    testWidgets('create can read an ancestor scope before the first build', (
      tester,
    ) async {
      const session = _Session('alice');

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ScopeModel<_Session>.value(
            value: session,
            builder: (context) => ScopeModel<_Repository>(
              create: (context) => _Repository(
                ScopeModel.of<_Session>(context, listen: false),
              ),
              dispose: (repository) {},
              builder: (context) {
                final repository =
                    ScopeModel.of<_Repository>(context, listen: false);

                return Text('session: ${repository.session.name}');
              },
            ),
          ),
        ),
      );

      expect(find.text('session: alice'), findsOneWidget);
    });

    testWidgets('creates the model once and provides it to the subtree', (
      tester,
    ) async {
      var created = 0;

      await tester.pumpWidget(
        _Host(
          create: (context) {
            created++;

            return _Model('alice');
          },
          revision: 1,
        ),
      );

      expect(created, 1);
      expect(find.text('name: alice'), findsOneWidget);

      // A rebuild from above hands the element a new widget, but the model
      // belongs to the element: it is created in `init()`, which runs once.
      await tester.pumpWidget(
        _Host(
          create: (context) {
            created++;

            return _Model('bob');
          },
          revision: 2,
        ),
      );

      expect(
        created,
        1,
        reason: 'the model outlives the widget that described it',
      );
      expect(find.text('name: alice'), findsOneWidget);
    });

    testWidgets('disposes of the model it created, and only then', (
      tester,
    ) async {
      final disposed = <_Model>[];
      final model = _Model('alice');

      await tester.pumpWidget(
        _Host(create: (context) => model, dispose: disposed.add, revision: 1),
      );

      expect(disposed, isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());

      expect(
        disposed,
        [same(model)],
        reason: 'the model the scope created is the one handed to dispose',
      );
    });

    testWidgets('a model passed by value is left to its owner', (tester) async {
      final model = _Model('alice');

      await tester.pumpWidget(_ValueHost(model: model));

      expect(find.text('name: alice'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());

      expect(
        model.disposeCount,
        0,
        reason: 'a scope that did not create the model does not release it',
      );
    });

    testWidgets('a selector rebuilds only the dependents of what changed', (
      tester,
    ) async {
      final model = _Model('alice');

      await tester.pumpWidget(
        _Host(create: (context) => model, revision: 1),
      );
      await tester.pumpAndSettle();

      final nameBuilds = _NameText.buildCount;
      final ageBuilds = _AgeText.buildCount;

      // The model is not observable, so the dependents are notified when the
      // `ScopeModel` widget itself is rebuilt, and the selector is what keeps
      // the unchanged ones out of that.
      model.name = 'bob';
      await tester.pumpWidget(
        _Host(create: (context) => model, revision: 2),
      );

      expect(find.text('name: bob'), findsOneWidget);
      expect(
        _NameText.buildCount,
        nameBuilds + 1,
        reason: 'the dependent on the changed value was rebuilt',
      );
      expect(
        _AgeText.buildCount,
        ageBuilds,
        reason: 'the dependent on the unchanged value was not',
      );
    });

    testWidgets('of(listen: false) does not subscribe', (tester) async {
      final model = _Model('alice');
      var readerBuilds = 0;

      await tester.pumpWidget(
        _Host(
          create: (context) => model,
          revision: 1,
          child: Builder(
            builder: (context) {
              readerBuilds++;
              final name = ScopeModel.of<_Model>(context, listen: false).name;

              return Text('reader: $name');
            },
          ),
        ),
      );

      final builds = readerBuilds;
      model.name = 'bob';
      await tester.pumpWidget(
        _Host(
          create: (context) => model,
          revision: 2,
          child: Builder(
            builder: (context) {
              readerBuilds++;
              final name = ScopeModel.of<_Model>(context, listen: false).name;

              return Text('reader: $name');
            },
          ),
        ),
      );

      expect(
        readerBuilds,
        builds + 1,
        reason: 'rebuilt by its own parent, not by a subscription',
      );
      expect(find.text('reader: bob'), findsOneWidget);
    });
  });
}

final class _Session {
  final String name;

  const _Session(this.name);
}

final class _Repository {
  final _Session session;

  const _Repository(this.session);
}

final class _Model {
  String name;

  /// Never changes: a selector on it must keep its dependent out of every
  /// notification.
  final int age = 30;

  int disposeCount = 0;

  _Model(this.name);

  void dispose() => disposeCount++;
}

/// A scope that creates its model, with a [revision] the tests change to force
/// a rebuild from above.
final class _Host extends StatelessWidget {
  final _Model Function(BuildContext context) create;
  final void Function(_Model model)? dispose;
  final int revision;
  final Widget? child;

  const _Host({
    required this.create,
    required this.revision,
    this.dispose,
    this.child,
  });

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: ScopeModel<_Model>(
          create: create,
          dispose: dispose ?? (model) {},
          builder: (context) =>
              child ??
              Column(
                children: [
                  const _NameText(),
                  const _AgeText(),
                  Text('revision: $revision'),
                ],
              ),
        ),
      );
}

/// A scope handed a model it does not own.
final class _ValueHost extends StatelessWidget {
  final _Model model;

  const _ValueHost({required this.model});

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: ScopeModel<_Model>.value(
          value: model,
          builder: (context) => const _NameText(),
        ),
      );
}

final class _NameText extends StatelessWidget {
  static int buildCount = 0;

  const _NameText();

  @override
  Widget build(BuildContext context) {
    buildCount++;
    final name = ScopeModel.select<_Model, String>(
      context,
      (model) => model.name,
    );

    return Text('name: $name');
  }
}

final class _AgeText extends StatelessWidget {
  static int buildCount = 0;

  const _AgeText();

  @override
  Widget build(BuildContext context) {
    buildCount++;
    final age = ScopeModel.select<_Model, int>(context, (model) => model.age);

    return Text('age: $age');
  }
}
