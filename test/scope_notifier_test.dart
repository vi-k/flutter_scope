import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scopo/scopo.dart';

void main() {
  setUp(() {
    _CounterValueView.buildCount = 0;
    _ConstantView.buildCount = 0;
  });

  group('ScopeNotifier', () {
    testWidgets('a failed create leaves nothing to unsubscribe from', (
      tester,
    ) async {
      // The disposal runs for a scope whose initialization failed too, and
      // this family's disposer reaches for the model to take its listener
      // back — a model a `create` that threw never produced.
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ScopeNotifier<_Counter>(
            create: (context) => throw StateError('controlled create failure'),
            dispose: (counter) => counter.dispose(),
            builder: (context) => const SizedBox.shrink(),
          ),
        ),
      );

      expect(
        tester.takeException(),
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'controlled create failure',
        ),
      );

      await tester.pumpWidget(const SizedBox.shrink());

      expect(tester.takeException(), isNull);
    });

    testWidgets('rebuilds only the dependents whose selected value changed', (
      tester,
    ) async {
      final counter = _Counter();
      addTearDown(counter.dispose);

      await tester.pumpWidget(_Host(counter: counter));
      await tester.pumpAndSettle();

      final valueBuilds = _CounterValueView.buildCount;
      final constantBuilds = _ConstantView.buildCount;

      counter.increment();
      await tester.pump();

      expect(find.text('value: 1'), findsOneWidget);
      expect(
        _CounterValueView.buildCount,
        valueBuilds + 1,
        reason: 'the scope listens to the model and notified this dependent',
      );
      expect(
        _ConstantView.buildCount,
        constantBuilds,
        reason: 'the value this one selects did not change',
      );
    });

    testWidgets('of(listen: false) does not subscribe', (tester) async {
      final counter = _Counter();
      addTearDown(counter.dispose);
      var readerBuilds = 0;

      await tester.pumpWidget(
        _Host(
          counter: counter,
          child: Builder(
            builder: (context) {
              readerBuilds++;
              ScopeNotifier.of<_Counter>(context, listen: false);

              return const Text('reader');
            },
          ),
        ),
      );

      final builds = readerBuilds;
      counter.increment();
      await tester.pump();

      expect(readerBuilds, builds);
    });

    testWidgets('disposes of the model it created', (tester) async {
      late _Counter created;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ScopeNotifier<_Counter>(
            create: (context) => created = _Counter(),
            dispose: (counter) => counter.dispose(),
            builder: (context) => const _CounterValueView(),
          ),
        ),
      );

      expect(created.disposeCount, 0);

      await tester.pumpWidget(const SizedBox.shrink());

      expect(created.disposeCount, 1);
    });

    testWidgets(
      'stops listening to a model it was given once it leaves the tree',
      (tester) async {
        final counter = _Counter();
        addTearDown(counter.dispose);

        await tester.pumpWidget(_Host(counter: counter));
        await tester.pumpAndSettle();

        await tester.pumpWidget(const SizedBox.shrink());

        // The scope removed its listener on the way out, so nothing is left
        // to mark a defunct element dirty.
        counter.increment();
        await tester.pump();

        expect(tester.takeException(), isNull);
      },
    );
  });

  testWidgets(
    'ScopeNotifier.value re-subscribes to the new listenable on swap',
    (tester) async {
      final first = ValueNotifier<int>(0);
      final second = ValueNotifier<int>(100);
      addTearDown(first.dispose);
      addTearDown(second.dispose);

      Widget app(ValueNotifier<int> value) => MaterialApp(
            home: ScopeNotifier<ValueNotifier<int>>.value(
              value: value,
              builder: (context) => const _ValueView(),
            ),
          );

      await tester.pumpWidget(app(first));
      expect(find.text('0'), findsOneWidget);

      // Sanity check: before the swap, mutating the original listenable
      // still triggers a rebuild.
      first.value = 1;
      await tester.pump();
      expect(find.text('1'), findsOneWidget);

      // Swap the listenable at the same widget position (same type, no
      // key), so the element is updated in place instead of recreated.
      await tester.pumpWidget(app(second));
      expect(find.text('100'), findsOneWidget);

      // The old listenable must no longer trigger rebuilds: its listener
      // was removed on swap.
      first.value = 2;
      await tester.pump();
      expect(find.text('100'), findsOneWidget);
      expect(find.text('2'), findsNothing);

      // The new listenable must trigger rebuilds: this is the regression
      // under test. `update` must call `addListener` on the new value, not
      // `removeListener`.
      second.value = 101;
      await tester.pump();
      expect(find.text('101'), findsOneWidget);
    },
  );
}

class _ValueView extends StatelessWidget {
  const _ValueView();

  @override
  Widget build(BuildContext context) {
    final value = ScopeNotifier.select<ValueNotifier<int>, int>(
      context,
      (model) => model.value,
    );

    return Text('$value');
  }
}

/// A model with one value that changes and one that never does.
final class _Counter extends ChangeNotifier {
  int _value = 0;
  int get value => _value;

  int get constant => 42;

  int disposeCount = 0;

  void increment() {
    _value++;
    notifyListeners();
  }

  @override
  void dispose() {
    disposeCount++;
    super.dispose();
  }
}

final class _Host extends StatelessWidget {
  final _Counter counter;
  final Widget? child;

  const _Host({required this.counter, this.child});

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: ScopeNotifier<_Counter>.value(
          value: counter,
          builder: (context) =>
              child ??
              const Column(children: [_CounterValueView(), _ConstantView()]),
        ),
      );
}

final class _CounterValueView extends StatelessWidget {
  static int buildCount = 0;

  const _CounterValueView();

  @override
  Widget build(BuildContext context) {
    buildCount++;
    final value = ScopeNotifier.select<_Counter, int>(
      context,
      (counter) => counter.value,
    );

    return Text('value: $value');
  }
}

final class _ConstantView extends StatelessWidget {
  static int buildCount = 0;

  const _ConstantView();

  @override
  Widget build(BuildContext context) {
    buildCount++;
    final value = ScopeNotifier.select<_Counter, int>(
      context,
      (counter) => counter.constant,
    );

    return Text('constant: $value');
  }
}
