import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scopo/scopo.dart';
import 'package:scopo/src/environment/scope_config.dart' show notifyObserver;

import 'utils/observer.dart';
import 'utils/settle.dart';

void main() {
  late RecordingObserver observer;

  setUp(() {
    observer = RecordingObserver();
    ScopeConfig.observer = observer;
  });

  tearDown(() {
    ScopeConfig.observer = null;
  });

  testWidgets('a scope reports that it was initialized and disposed of',
      (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: _CounterScope(child: SizedBox()),
      ),
    );

    expect(observer.events, ['init _CounterScope']);

    await tester.pumpWidget(const SizedBox());

    expect(observer.events, ['init _CounterScope', 'disposed _CounterScope']);

    // `onDisposed` already fired above, synchronously, when the element left
    // the tree. What is left is the scope's own asynchronous teardown, which
    // runs on the real event loop rather than the fake clock `pump` advances
    // -- `settle()` is what lets it finish before the leak tracker looks for
    // what it releases.
    await settle(tester, until: () => false);
  });

  testWidgets('a throwing observer does not reach the scope', (tester) async {
    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = previous);

    ScopeConfig.observer = _ThrowingObserver();

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: _CounterScope(child: Text('built')),
      ),
    );

    expect(
      find.text('built'),
      findsOneWidget,
      reason: 'the scope builds its subtree even though the observer threw',
    );
    expect(errors, hasLength(1));
    expect(errors.single.library, 'scopo');

    // See the first test: lets the scope's own asynchronous teardown finish
    // before the leak tracker looks for what it releases.
    await tester.pumpWidget(const SizedBox());
    await settle(tester, until: () => false);
  });

  test(
      'an observer that produces a scope event of its own is stopped after '
      'the first', () {
    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = previous);

    ScopeConfig.observer = _NestingObserver();

    notifyObserver((observer) => observer.onInit(const _FakeObservable()));

    expect(
      errors,
      hasLength(1),
      reason: 'the nested notification is refused rather than attempted, so '
          'exactly one failure is reported and the call returns normally',
    );
  });

  test('reset() leaves the observer alone', () {
    final observer = RecordingObserver();
    ScopeConfig.observer = observer;

    ScopeConfig.reset();

    expect(ScopeConfig.observer, same(observer));
  });
}

/// A minimal [LiteScope]: nothing to initialize asynchronously, and [child]
/// is shown right away rather than after a ready state is reached.
final class _CounterScope extends LiteScope<_CounterScope, _CounterScopeState> {
  const _CounterScope({super.child});

  @override
  Widget? buildOnWaiting(BuildContext context) => child;

  @override
  _CounterScopeState createState() => _CounterScopeState();
}

final class _CounterScopeState
    extends LiteScopeState<_CounterScope, _CounterScopeState> {
  @override
  Widget build(BuildContext context) => params.child;
}

/// Fails every hook it is asked for.
final class _ThrowingObserver extends ScopeObserver {
  @override
  void onInit(ScopeObservable target) => throw StateError('observer failed');
}

/// Produces a second scope event from [onInit] -- the shape [notifyObserver]
/// itself refuses to recurse into, rather than one that reaches it through a
/// second build. A build reentrant enough to test that path would have to
/// fight the framework's own build-scope lock first, and that lock -- not
/// [notifyObserver]'s -- is what a widget-tree version of this test would
/// actually be exercising.
final class _NestingObserver extends ScopeObserver {
  @override
  void onInit(ScopeObservable target) =>
      notifyObserver((observer) => observer.onDisposed(target));
}

/// A [ScopeObservable] with no scope behind it, for a test that calls
/// [notifyObserver] directly rather than through a widget tree.
final class _FakeObservable implements ScopeObservable {
  const _FakeObservable();

  @override
  String get debugLabel => '_FakeObservable';
}
