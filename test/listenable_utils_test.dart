import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scopo/scopo.dart';

void main() {
  group('listen', () {
    test('calls the listener until the subscription is cancelled', () {
      final notifier = ChangeNotifier();
      addTearDown(notifier.dispose);
      var calls = 0;

      final subscription = notifier.listen(() => calls++);

      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      notifier.notifyListeners();
      expect(calls, 1);

      subscription.cancel();
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      notifier.notifyListeners();
      expect(calls, 1, reason: 'the listener was removed from the listenable');
    });

    test('cancelling twice is a mistake in the caller', () {
      final notifier = ChangeNotifier();
      addTearDown(notifier.dispose);

      final subscription = notifier.listen(() {})..cancel();

      expect(
        subscription.cancel,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('after being disposed'),
          ),
        ),
      );
    });
  });

  group('CompositeListenableSubscription', () {
    test('cancels everything it holds at once', () {
      final first = ChangeNotifier();
      final second = ChangeNotifier();
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      var firstCalls = 0;
      var secondCalls = 0;

      final composite = CompositeListenableSubscription();
      first.listen(() => firstCalls++).addTo(composite);
      composite.add(second.listen(() => secondCalls++));

      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      first.notifyListeners();
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      second.notifyListeners();
      expect((firstCalls, secondCalls), (1, 1));

      composite.cancel();
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      first.notifyListeners();
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      second.notifyListeners();
      expect((firstCalls, secondCalls), (1, 1));
    });

    test('refuses a subscription once it has been cancelled', () {
      final notifier = ChangeNotifier();
      addTearDown(notifier.dispose);
      final composite = CompositeListenableSubscription()..cancel();

      expect(
        () => composite.add(notifier.listen(() {})),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('select', () {
    test('calls the listener only when the selected value changes', () {
      final notifier = _Model();
      addTearDown(notifier.dispose);
      final seen = <int>[];

      final subscription = notifier.select(
        (model) => model.value,
        (model, value) => seen.add(value),
      );

      expect(subscription.value, 0, reason: 'the value is read on subscribe');

      notifier.touch();
      expect(seen, isEmpty, reason: 'the selected value did not change');

      notifier.value = 1;
      expect(seen, [1]);
      expect(subscription.value, 1);

      notifier.value = 1;
      expect(seen, [1], reason: 'the same value again is not a change');

      subscription.cancel();
      notifier.value = 2;
      expect(seen, [1]);
    });

    test('compare decides what counts as a change', () {
      final notifier = _Model();
      addTearDown(notifier.dispose);
      var calls = 0;

      notifier.select(
        (model) => model.value,
        (model, value) => calls++,
        // Inverted on purpose: reports only while the value stays the same.
        compare: (previous, current) => previous == current,
      );

      notifier.touch();
      expect(calls, 1, reason: 'unchanged, and that is what compare reports');

      notifier.value = 5;
      expect(calls, 1, reason: 'changed, so this compare stays silent');
    });
  });

  group('ListenableView', () {
    test('passes subscriptions through to the listenable it wraps', () {
      final notifier = ChangeNotifier();
      addTearDown(notifier.dispose);
      var calls = 0;

      final view = ListenableView(notifier);
      void listener() => calls++;

      view.addListener(listener);
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      notifier.notifyListeners();
      expect(calls, 1);

      view.removeListener(listener);
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      notifier.notifyListeners();
      expect(calls, 1);
    });
  });

  group('ListenableSelector', () {
    testWidgets('rebuilds only when the selected value changes', (
      tester,
    ) async {
      final model = _Model();
      addTearDown(model.dispose);
      var builds = 0;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ListenableSelector<_Model, int>(
            listenable: model,
            selector: (model) => model.value,
            child: const Text('child'),
            builder: (context, listenable, value, child) {
              builds++;

              return Column(children: [Text('value: $value'), child!]);
            },
          ),
        ),
      );

      expect(builds, 1);
      expect(find.text('value: 0'), findsOneWidget);
      expect(
        find.text('child'),
        findsOneWidget,
        reason: 'the child is handed to the builder untouched',
      );

      model.touch();
      await tester.pump();
      expect(builds, 1, reason: 'the selected value did not change');

      model.value = 7;
      await tester.pump();
      expect(builds, 2);
      expect(find.text('value: 7'), findsOneWidget);
    });

    testWidgets('follows the listenable when it is swapped', (tester) async {
      final first = _Model();
      final second = _Model()..value = 100;
      addTearDown(first.dispose);
      addTearDown(second.dispose);

      Widget build(_Model model) => Directionality(
            textDirection: TextDirection.ltr,
            child: ListenableSelector<_Model, int>(
              listenable: model,
              selector: (model) => model.value,
              builder: (context, listenable, value, child) =>
                  Text('value: $value'),
            ),
          );

      await tester.pumpWidget(build(first));
      expect(find.text('value: 0'), findsOneWidget);

      await tester.pumpWidget(build(second));
      expect(find.text('value: 100'), findsOneWidget);

      first.value = 1;
      await tester.pump();
      expect(
        find.text('value: 100'),
        findsOneWidget,
        reason: 'the old listenable no longer drives the widget',
      );

      second.value = 101;
      await tester.pump();
      expect(find.text('value: 101'), findsOneWidget);
    });
  });

  group('StateAsNotifier', () {
    testWidgets('lets a State be listened to like any Listenable', (
      tester,
    ) async {
      var calls = 0;

      await tester.pumpWidget(const _NotifyingHost());

      final state = tester.state<_NotifyingState>(find.byType(_Notifying));
      void listener() => calls++;
      state.addListener(listener);

      state.bump();
      expect(calls, 1);

      state.removeListener(listener);
      state.bump();
      expect(calls, 1);

      // The mixin disposes of the notifier it created; a listener left behind
      // would be used after disposal.
      state.addListener(listener);
      await tester.pumpWidget(const SizedBox.shrink());

      expect(tester.takeException(), isNull);
    });
  });
}

final class _Model extends ChangeNotifier {
  int _value = 0;

  int get value => _value;

  set value(int value) {
    _value = value;
    notifyListeners();
  }

  /// Notifies without changing anything a selector would look at.
  void touch() => notifyListeners();
}

final class _NotifyingHost extends StatelessWidget {
  const _NotifyingHost();

  @override
  Widget build(BuildContext context) => const Directionality(
        textDirection: TextDirection.ltr,
        child: _Notifying(),
      );
}

final class _Notifying extends StatefulWidget {
  const _Notifying();

  @override
  State<_Notifying> createState() => _NotifyingState();
}

final class _NotifyingState extends State<_Notifying>
    with StateAsNotifier<_Notifying> {
  void bump() => notifyListeners();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
