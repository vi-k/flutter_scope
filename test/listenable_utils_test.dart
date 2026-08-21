// The fixtures below carry equality on purpose: `_Box` to stand for a value
// that is replaced rather than mutated, and the notifiers to show that a
// subscription belongs to an object and not to whatever compares equal to it.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scopo/scopo.dart';

import 'utils/leaks.dart';

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
    // A member may be given up on its own -- a conditional subscription, an
    // early return -- while the composite still holds it. Cancelling the
    // composite then walked into a subscription that raises on a second
    // cancel, and everything after it in the list stayed attached to its
    // listenable: a leak, in debug only, where release worked.
    test('cancels the rest when one of them is already cancelled', () {
      final first = ChangeNotifier();
      final second = ChangeNotifier();
      final third = ChangeNotifier();
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      addTearDown(third.dispose);
      var firstCalls = 0;
      var secondCalls = 0;
      var thirdCalls = 0;

      final composite = CompositeListenableSubscription();
      first.listen(() => firstCalls++).addTo(composite);
      final middle = second.listen(() => secondCalls++)..addTo(composite);
      third.listen(() => thirdCalls++).addTo(composite);

      middle.cancel();
      composite.cancel();

      for (final notifier in [first, second, third]) {
        // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
        notifier.notifyListeners();
      }

      expect(
        [firstCalls, secondCalls, thirdCalls],
        [0, 0, 0],
        reason: 'one member that was already gone is no reason to leave the '
            'ones after it listening',
      );
    });

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

    // The composite exists so that nothing is left listening. Adding to one
    // that has already been cancelled used to raise a `StateError` -- and the
    // subscription had been made on the line before the `add`, so the raise
    // was what kept it: attached to its listenable, held by nobody, and
    // reported as a mistake in the caller rather than as the leak it was. It
    // is still a mistake and still says so, with an assertion, the way `cancel`
    // beside it does; what it no longer does is keep the thing it complains
    // about.
    test('adding to a cancelled composite cancels rather than leaks', () {
      final notifier = ChangeNotifier();
      addTearDown(notifier.dispose);
      var calls = 0;

      final composite = CompositeListenableSubscription()..cancel();

      expect(
        () => notifier.listen(() => calls++).addTo(composite),
        // A `StateError`, not an `AssertionError`: `debugAssertNotDisposed`
        // raises through `throwIfDisposed`, so what an assert of this package
        // carries is the message, not the type.
        throwsA(isA<StateError>()),
        reason: 'adding to a composite that is over is a mistake in the '
            'caller, and it says so',
      );

      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      notifier.notifyListeners();

      expect(
        calls,
        0,
        reason: 'and the subscription it was handed was cancelled before it '
            'complained, so nothing is left on the listenable',
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

      // ignore: cascade_invocations
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

      // ignore: cascade_invocations
      notifier.touch();
      expect(calls, 1, reason: 'unchanged, and that is what compare reports');

      notifier.value = 5;
      expect(calls, 1, reason: 'changed, so this compare stays silent');
    });

    // The first value used to be read after the listener was registered. A
    // selector that failed there left the listener on the notifier with no
    // subscription to take it back, and the next notification reached a
    // `late` field nobody had assigned.
    test('a selector that fails on the first read leaves nothing behind', () {
      final notifier = _Model();
      addTearDown(notifier.dispose);

      final reported = <FlutterErrorDetails>[];
      final previousOnError = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = previousOnError);

      expect(
        () => notifier.select<int>(
          (model) => throw StateError('the selector failed'),
          (model, value) {},
        ),
        throwsA(isA<StateError>()),
      );

      expect(
        notifier.isListened,
        isFalse,
        reason: 'the caller never got a subscription, so nothing else could '
            'ever take the listener back',
      );

      notifier.value = 1;

      expect(
        reported,
        isEmpty,
        reason: 'and nothing is left to fail on the next notification',
      );
    });

    // `compare` answers "did it change?", so the comparison for a value that
    // is replaced rather than mutated is `notIdentical` -- `identical` reports
    // the opposite of what it is asked.
    test('notIdentical is the compare for a value that is replaced', () {
      final notifier = _Model();
      addTearDown(notifier.dispose);
      final seen = <_Box>[];

      notifier.select(
        (model) => model.box,
        (model, box) => seen.add(box),
        compare: CompareUtils.notIdentical,
      );

      // ignore: cascade_invocations
      notifier.box = _Box(1);
      expect(
        seen,
        hasLength(1),
        reason: 'a different object, equal or not, is a replacement',
      );

      notifier.touch();
      expect(seen, hasLength(1), reason: 'the same object is not');
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

    // The callbacks used to be replaced only together with the listenable, so
    // a parent that passed a new selector over the same source kept getting
    // the previous one.
    testWidgets('follows a new selector on the same listenable',
        (tester) async {
      final model = _Model()..value = 2;
      addTearDown(model.dispose);

      Widget build(int Function(_Model model) selector) => Directionality(
            textDirection: TextDirection.ltr,
            child: ListenableSelector<_Model, int>(
              listenable: model,
              selector: selector,
              builder: (context, listenable, value, child) =>
                  Text('value: $value'),
            ),
          );

      await tester.pumpWidget(build((model) => model.value));
      expect(find.text('value: 2'), findsOneWidget);

      await tester.pumpWidget(build((model) => model.value * 10));
      expect(
        find.text('value: 20'),
        findsOneWidget,
        reason: 'the selector the widget carries now is the one that runs',
      );

      model.value = 3;
      await tester.pump();
      expect(find.text('value: 30'), findsOneWidget);
    });

    // A selector that raises on its first read takes the update down with it,
    // and that part is Flutter's doing rather than this widget's: the element
    // above catches the failure of the update, puts an error widget in place of
    // the subtree and abandons what was there. Nothing asks the state that
    // raised anything ever again -- no second `didUpdateWidget`, no `dispose` --
    // which is why the cancelled subscription its field still points at is
    // never touched a second time. What is worth holding down is the recovery:
    // the next configuration builds a fresh state, which subscribes once and
    // listens.
    testWidgets(
      'a selector that raised once does not outlive itself',
      (tester) async {
        final model = _Model()..value = 2;
        addTearDown(model.dispose);

        Widget build(int Function(_Model model) selector) => Directionality(
              textDirection: TextDirection.ltr,
              child: ListenableSelector<_Model, int>(
                listenable: model,
                selector: selector,
                builder: (context, listenable, value, child) =>
                    Text('value: $value'),
              ),
            );

        await tester.pumpWidget(build((model) => model.value));
        expect(find.text('value: 2'), findsOneWidget);

        await tester.pumpWidget(
          build((model) => throw StateError('not this time')),
        );
        expect(tester.takeException(), isA<StateError>());

        // The same parent, asking again with a selector that works. Nothing about
        // the failure above is meant to outlive it.
        await tester.pumpWidget(build((model) => model.value * 10));

        expect(
          tester.takeException(),
          isNull,
          reason: 'asking again is not the failure of the last attempt',
        );
        expect(find.text('value: 20'), findsOneWidget);

        model.value = 3;
        await tester.pump();
        expect(
          find.text('value: 30'),
          findsOneWidget,
          reason: 'and it is listening: a cancelled subscription hears nothing',
        );
      },
      // The raise happens while the element is being updated, and the subtree
      // it breaks stays unmounted -- see [unmountableTree].
      experimentalLeakTesting: unmountableTree,
    );

    testWidgets('follows a new compare on the same listenable', (tester) async {
      final model = _Model();
      addTearDown(model.dispose);

      Widget build(bool Function(int previous, int current)? compare) =>
          Directionality(
            textDirection: TextDirection.ltr,
            child: ListenableSelector<_Model, int>(
              listenable: model,
              selector: (model) => model.value,
              compare: compare,
              builder: (context, listenable, value, child) =>
                  Text('value: $value'),
            ),
          );

      await tester.pumpWidget(build((previous, current) => false));
      model.value = 1;
      await tester.pump();
      expect(
        find.text('value: 0'),
        findsOneWidget,
        reason: 'this compare says nothing ever changes',
      );

      await tester.pumpWidget(build(null));
      expect(
        find.text('value: 1'),
        findsOneWidget,
        reason: 'the default compare took over and read the value afresh',
      );

      model.value = 2;
      await tester.pump();
      expect(find.text('value: 2'), findsOneWidget);
    });

    // The order of the two lines in `didUpdateWidget` -- cancel the old
    // subscription, then take the new one -- was checked by a probe when it
    // was written and left to a comment. `select` reads the value at once, so
    // a selector that raises there does it while the state is being updated:
    // with the order reversed the old listener stays on a listenable this
    // widget no longer watches, pointing into an element the framework
    // abandons as it puts an error widget in the subtree's place.
    testWidgets(
      'a selector that raises on a new configuration leaves nothing '
      'on the listenable',
      (tester) async {
        final model = _Model();
        addTearDown(model.dispose);

        Widget build(int Function(_Model) selector) => Directionality(
              textDirection: TextDirection.ltr,
              child: ListenableSelector<_Model, int>(
                listenable: model,
                selector: selector,
                builder: (context, listenable, value, child) =>
                    const SizedBox.shrink(),
              ),
            );

        await tester.pumpWidget(build((model) => model.value));
        expect(model.isListened, isTrue, reason: 'control: it is watching');

        await tester.pumpWidget(
          build((model) => throw StateError('the selector failed')),
        );

        expect(tester.takeException(), isA<StateError>());
        expect(
          model.isListened,
          isFalse,
          reason: 'the old subscription went first, so a selector that cannot '
              'answer leaves nobody behind on the source',
        );
      },
      // The raise this test is written for happens while the state is being
      // updated, and the subtree it breaks stays unmounted -- see
      // [unmountableTree].
      experimentalLeakTesting: unmountableTree,
    );
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

      // ignore: cascade_invocations
      state.bump();
      expect(calls, 1);

      state
        ..removeListener(listener)
        ..bump();
      expect(calls, 1);

      // The mixin disposes of the notifier it created; a listener left behind
      // would be used after disposal.
      state.addListener(listener);
      await tester.pumpWidget(const SizedBox.shrink());

      expect(tester.takeException(), isNull);
    });

    testWidgets('nothing reaches the notifier once the state is gone', (
      tester,
    ) async {
      await tester.pumpWidget(const _NotifyingHost());
      final state = tester.state<_NotifyingState>(find.byType(_Notifying));

      await tester.pumpWidget(const SizedBox.shrink());

      var calls = 0;
      void listener() => calls++;

      // A callback that outlived the state -- a stream event, a timer -- lands
      // here. The disposed notifier used to answer both of these with
      // "A ChangeNotifier was used after being disposed" in debug, and in
      // release it remembered the listener for good.
      state
        ..addListener(listener)
        ..bump();

      expect(tester.takeException(), isNull);
      expect(
        calls,
        0,
        reason: 'a listener taken after the state is gone is never called',
      );
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

  /// A value that is replaced rather than mutated, and compares equal to the
  /// one it replaces.
  _Box _box = _Box(1);

  _Box get box => _box;

  set box(_Box box) {
    _box = box;
    notifyListeners();
  }

  /// Notifies without changing anything a selector would look at.
  void touch() => notifyListeners();

  /// Whether anything is subscribed; [ChangeNotifier.hasListeners] is
  /// `@protected`, and a test is not a subclass.
  bool get isListened => hasListeners;
}

/// A value type: two boxes holding the same number are equal, and a new one is
/// still a different object.
///
/// The constructor is deliberately not `const`: two
/// `const _Box(1)` would be canonicalized into one object, and then there is no
/// replacement left to tell apart from a mutation.
final class _Box {
  final int value;

  _Box(this.value);

  @override
  bool operator ==(Object other) => other is _Box && other.value == value;

  @override
  int get hashCode => value.hashCode;
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
