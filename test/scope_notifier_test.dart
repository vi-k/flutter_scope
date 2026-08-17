// `_NamedCounter` carries equality on purpose: equality on a mutable class is
// what the lint warns about, and the scope must not read it as "the same
// subscription".
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scopo/scopo.dart';

import 'utils/leaks.dart';

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

    // Owning a subscription is about the object that holds the listener list,
    // and `==` does not answer that: two equal models are still two lists.
    // The listener used to stay on the one the scope had left.
    testWidgets('moves the subscription to an equal but different model',
        (tester) async {
      final first = _NamedCounter('same');
      final second = _NamedCounter('same');
      addTearDown(first.dispose);
      addTearDown(second.dispose);

      Widget build(_NamedCounter model) => Directionality(
            textDirection: TextDirection.ltr,
            child: ScopeNotifier<_NamedCounter>.value(
              value: model,
              builder: (context) => const _NamedCounterView(),
            ),
          );

      await tester.pumpWidget(build(first));
      expect(find.text('named: 0'), findsOneWidget);

      await tester.pumpWidget(build(second));
      second.bump();
      await tester.pump();

      expect(
        find.text('named: 1'),
        findsOneWidget,
        reason: 'the subscription moved to the model the scope now holds',
      );

      first.bump();
      await tester.pump();

      expect(
        find.text('named: 1'),
        findsOneWidget,
        reason: 'and the one it left behind no longer drives the scope',
      );
    });

    // The same rule as for `ScopeModel`, with one more thing to get wrong: the
    // listener. The assert fires before any subscription is moved.
    testWidgets(
      'cannot change between the owning constructor and .value',
      (tester) async {
        final external = _NamedCounter('given');

        Widget build({required bool owning}) => Directionality(
              textDirection: TextDirection.ltr,
              child: owning
                  ? ScopeNotifier<_NamedCounter>(
                      create: (context) => _NamedCounter('owned'),
                      dispose: (model) => model.dispose(),
                      builder: (context) => const _NamedCounterView(),
                    )
                  : ScopeNotifier<_NamedCounter>.value(
                      value: external,
                      builder: (context) => const _NamedCounterView(),
                    ),
            );

        await tester.pumpWidget(build(owning: true));
        await tester.pumpAndSettle();

        await tester.pumpWidget(build(owning: false));

        expect(
          tester.takeException(),
          isA<AssertionError>().having(
            (error) => error.message.toString(),
            'message',
            contains('`Widget.key`'),
          ),
        );
        expect(
          external.hasAnyListener,
          isFalse,
          reason: 'nothing was subscribed to the model the scope refused',
        );
      },
      // The assert fires while the scope is being updated, so the subtree
      // it breaks stays unmounted -- see [unmountableTree].
      experimentalLeakTesting: unmountableTree,
    );

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

    // A scope over somebody else's model needs a name in the log as much as
    // one that owns it: `.value` is exactly where two scopes of the same type
    // stand side by side over two different models.
    test('names a .value scope in diagnostics instead of its hash', () {
      final model = ValueNotifier<int>(0);
      addTearDown(model.dispose);

      final tagged = ScopeNotifier<ValueNotifier<int>>.value(
        tag: 'auth',
        value: model,
        builder: (context) => const SizedBox.shrink(),
      );
      final plain = ScopeNotifier<ValueNotifier<int>>.value(
        value: model,
        builder: (context) => const SizedBox.shrink(),
      );

      expect(tagged.toStringShort(), 'ScopeNotifier<ValueNotifier<int>>(auth)');
      expect(plain.toStringShort(), 'ScopeNotifier<ValueNotifier<int>>');
      expect(
        tagged.toStringShort(showHashCode: true),
        'ScopeNotifier<ValueNotifier<int>>(auth)',
        reason: 'a tag is more use than a hash, so it wins',
      );
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

  // `notifyDependents()` is what the scope's own subscription to the model
  // calls, and it sets a flag that the *next* rebuild reads. Nothing stopped
  // it from being set in the middle of the current one: a `builder` that
  // touches the model synchronously -- a lazy load, a default being filled in
  // -- notifies while the scope is building, `markNeedsBuild()` is swallowed
  // for an element that is already building, and the flag was still up by the
  // time `updateChild` ran. `updateChild` then kept "the child from the last
  // real build", of which there was none.
  //
  // In debug the framework raises two derived assertions that name neither
  // the scope nor the reason. In release there are no assertions at all and
  // the subtree is simply not there.
  testWidgets(
    'a model notified from inside the builder still mounts the subtree',
    (tester) async {
      final counter = _Counter();
      addTearDown(counter.dispose);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ScopeNotifier<_Counter>.value(
            value: counter,
            builder: (context) {
              // The notification happens while this very scope is building.
              counter.increment();

              return const _CounterValueView();
            },
          ),
        ),
      );

      expect(
        tester.takeException(),
        isNull,
        reason: 'a notification made during the build is a thing user code '
            'does; it must not break the frame',
      );
      expect(
        find.byType(_CounterValueView),
        findsOneWidget,
        reason: 'the subtree the builder returned has to be mounted -- the '
            'notify-only path is about *later* rebuilds, and there is no '
            'earlier build whose child could be kept instead',
      );
    },
  );

  // The other half of the same defect. Marking the element dirty from inside
  // its own build does nothing at all: the framework's assertion lets the
  // self case through and `if (dirty) return;` swallows the call. So the
  // notification is not merely late, it is gone -- unless something asks for
  // the rebuild once the build is over.
  //
  // Showing that needs a dependent the subtree walk will *not* rebuild on its
  // own, or the assertion passes whether the notification arrived or not: the
  // child here is a `const` instance, so `updateChild` returns it untouched,
  // and the selector check that runs on `update` happens before the builder
  // increments. Being notified is the only way left for it to learn.
  testWidgets(
    'a model notified from inside the builder does not lose the notification',
    (tester) async {
      final counter = _Counter();
      addTearDown(counter.dispose);
      var notifyOnBuild = false;

      Widget build(String tag) => Directionality(
            textDirection: TextDirection.ltr,
            child: ScopeNotifier<_Counter>.value(
              tag: tag,
              value: counter,
              builder: (context) {
                if (notifyOnBuild) {
                  counter.increment();
                }

                return const _CounterValueView();
              },
            ),
          );

      await tester.pumpWidget(build('first'));
      expect(find.text('value: 0'), findsOneWidget);

      final buildsBefore = _CounterValueView.buildCount;

      notifyOnBuild = true;
      await tester.pumpWidget(build('second'));
      await tester.pumpAndSettle();

      expect(
        _CounterValueView.buildCount,
        greaterThan(buildsBefore),
        reason: 'the dependent has to be rebuilt by the notification: the '
            'walk itself reuses the const child and leaves it alone',
      );
      expect(
        find.text('value: 1'),
        findsOneWidget,
        reason: 'a notification made during a build is deferred, not dropped',
      );
    },
  );
}

/// A model whose equality is by name, so two of them can be equal and still be
/// two objects with two listener lists.
final class _NamedCounter extends ChangeNotifier {
  final String name;

  int _value = 0;

  int get value => _value;

  _NamedCounter(this.name);

  void bump() {
    _value++;
    notifyListeners();
  }

  /// [ChangeNotifier.hasListeners] is `@protected`, and a test is not a
  /// subclass.
  bool get hasAnyListener => hasListeners;

  @override
  bool operator ==(Object other) =>
      other is _NamedCounter && other.name == name;

  @override
  int get hashCode => name.hashCode;
}

final class _NamedCounterView extends StatelessWidget {
  const _NamedCounterView();

  @override
  Widget build(BuildContext context) {
    final value = ScopeNotifier.select<_NamedCounter, int>(
      context,
      (model) => model.value,
    );

    return Text('named: $value');
  }
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
