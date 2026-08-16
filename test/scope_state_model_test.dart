import 'package:flutter_test/flutter_test.dart';
import 'package:scopo/scopo.dart';

/// The two notifiers a scope keeps its state in, and the read-only views of
/// them.
///
/// Nothing in the suite named them: it reaches them through the scopes that own
/// one, where only the paths those scopes happen to walk are tried. What a user
/// gets by building one directly — which is what they are exported for — went
/// untried, and so did the one decision either of them makes on its own:
/// whether an update is worth telling the listeners about.
void main() {
  group('ScopeStateNotifier', () {
    test('tells the listeners about every update by default', () {
      final notifier = ScopeStateNotifier<String>('a');
      addTearDown(notifier.dispose);
      var notifications = 0;

      notifier
        ..addListener(() => notifications++)
        ..update('b')
        ..update('b');

      expect(notifier.state, 'b');
      expect(
        notifications,
        2,
        reason: 'the default `equals` answers false, so even a value equal to '
            'the current one counts as a change: a state that is not a value '
            'type is the common case, and silence would be the wrong default '
            'for it',
      );
    });

    test('an equals that recognises the value keeps both quiet', () {
      final notifier = _Deduplicating('a');
      addTearDown(notifier.dispose);
      final first = notifier.state;
      var notifications = 0;

      notifier
        ..addListener(() => notifications++)
        ..update('a');

      expect(notifications, 0);
      expect(
        identical(notifier.state, first),
        isTrue,
        reason: 'an update that is not passed on is not applied either: the '
            'listeners and the state would otherwise disagree about which '
            'object is current',
      );

      notifier.update('b');

      expect(notifications, 1);
      expect(notifier.state, 'b');
    });

    test('the unmodifiable view reads through and forwards its listeners', () {
      final notifier = ScopeStateNotifier<String>('a');
      addTearDown(notifier.dispose);
      final view = notifier.asUnmodifiable();
      var notifications = 0;
      void listener() => notifications++;

      view.addListener(listener);
      notifier.update('b');

      expect(view.state, 'b', reason: 'the view holds no state of its own');
      expect(notifications, 1);

      view.removeListener(listener);
      notifier.update('c');

      expect(
        notifications,
        1,
        reason: 'and it removes from the notifier the listener it added to it',
      );
      expect(view.state, 'c');
    });
  });

  group('ScopeStateWithErrorNotifier', () {
    test('has no error until it is given one', () {
      final notifier = ScopeStateWithErrorNotifier<String>('a');
      addTearDown(notifier.dispose);

      expect(notifier.hasError, isFalse);
      expect(notifier.state, 'a');
      expect(() => notifier.error, throwsStateError);
      expect(() => notifier.stackTrace, throwsStateError);
    });

    test('reading the state after a failure raises it, trace and all', () {
      final notifier = ScopeStateWithErrorNotifier<String>('a');
      addTearDown(notifier.dispose);
      final failure = Exception('boom');
      final trace = StackTrace.current;
      var notifications = 0;

      notifier
        ..addListener(() => notifications++)
        ..setError(failure, trace);

      expect(notifier.hasError, isTrue);
      expect(notifications, 1, reason: 'a failure is a change like any other');
      expect(notifier.error, same(failure));
      expect(notifier.stackTrace, same(trace));

      Object? caught;
      StackTrace? caughtTrace;
      try {
        notifier.state;
      } on Object catch (error, stackTrace) {
        caught = error;
        caughtTrace = stackTrace;
      }

      expect(caught, same(failure));
      expect(
        caughtTrace,
        same(trace),
        reason: 'the trace of where it actually failed, not of where it was '
            'read: a reporter handed the reading site has nothing to work from',
      );
    });

    test('the view of it answers for the error too', () {
      final notifier = ScopeStateWithErrorNotifier<String>('a');
      addTearDown(notifier.dispose);
      final view = notifier.asUnmodifiable();
      final failure = Exception('boom');
      final trace = StackTrace.current;

      expect(view.hasError, isFalse);

      notifier.setError(failure, trace);

      expect(view.hasError, isTrue);
      expect(view.error, same(failure));
      expect(view.stackTrace, same(trace));
      expect(() => view.state, throwsA(same(failure)));
    });
  });
}

/// A notifier that treats equal values as no change, the way the documentation
/// says a value type should.
final class _Deduplicating extends ScopeStateNotifier<String> {
  _Deduplicating(super.initialState);

  @override
  bool equals(String previous, String current) => previous == current;
}
