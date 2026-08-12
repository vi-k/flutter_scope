import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scopo/scopo.dart';

void main() {
  setUp(() {
    _NameText.buildCount = 0;
    _AgeText.buildCount = 0;
  });

  group('ScopeModel', () {
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

final class _Model {
  String name;
  final int age;
  int disposeCount = 0;

  _Model(this.name, {this.age = 30});

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
