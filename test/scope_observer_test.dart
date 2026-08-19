import 'dart:async';

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

  testWidgets(
      'a scope built on the asynchronous element reports its own phase, not '
      'the bare pair', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: _CounterScope(child: SizedBox()),
      ),
    );

    // `LiteScope` -- `_CounterScope`'s family -- is built on
    // `AsyncScopeElementBase`: its `initScope()` defaults to an immediate
    // `AsyncScopeReady()`, same as a bare `AsyncScope`. `reportsOwnLifecycle`
    // is therefore `true`, so the single `onInit` below is the asynchronous
    // phase's own -- the structural pair `ScopeWidgetElementBase` fires for
    // every other family is suppressed here, not doubled with it.
    expect(observer.events, ['init _CounterScope', 'ready _CounterScope']);

    await tester.pumpWidget(const SizedBox());

    // The asynchronous teardown -- `dispose`/`disposed` below -- runs on the
    // real event loop rather than the fake clock `pump` advances, so it is
    // not necessarily done the instant the widget leaves the tree. `settle()`
    // gives it the chance `pump`/`pumpAndSettle` cannot.
    await settle(
      tester,
      until: () => observer.events.contains('disposed _CounterScope'),
    );

    expect(observer.events, [
      'init _CounterScope',
      'ready _CounterScope',
      'dispose _CounterScope',
      'disposed _CounterScope',
    ]);
  });

  testWidgets(
      'a scope with no phase of its own reports exactly the structural pair',
      (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: _PlainScope(child: SizedBox()),
      ),
    );

    // `ScopeWidgetBase` -- `_PlainScope`'s family -- goes no further than
    // `ScopeWidgetElementBase` itself: it runs no initialization of its own,
    // so `reportsOwnLifecycle` keeps its default `false` and this is the bare
    // pair from `ScopeWidgetElementBase`, nothing more.
    expect(observer.events, ['init _PlainScope']);

    await tester.pumpWidget(const SizedBox());

    expect(observer.events, ['init _PlainScope', 'disposed _PlainScope']);
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

  testWidgets(
    'an asynchronous scope reports initialization, progress and disposal',
    (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: _AsyncScope(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox());
      await settle(
        tester,
        until: () => observer.events.contains('disposed _AsyncScope'),
      );

      expect(observer.events, [
        'init _AsyncScope',
        'progress _AsyncScope 1/2',
        'progress _AsyncScope 2/2',
        'ready _AsyncScope',
        'dispose _AsyncScope',
        'disposed _AsyncScope',
      ]);
    },
  );

  testWidgets(
    'an initialization that throws reports onError for the initialization '
    'phase',
    (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: AsyncScope(
            initScope: (context) async* {
              yield AsyncScopeProgress('step');
              throw StateError('init failed');
            },
            disposeScope: () {},
            progressBuilder: (context, progress) => const Text('init'),
            errorBuilder: (context, error, stackTrace, progress) =>
                Text('$error'),
            builder: (context) => const Text('ready'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(observer.events, [
        'init AsyncScope',
        'progress AsyncScope step',
        'error AsyncScope initialization Bad state: init failed',
      ]);
    },
  );

  testWidgets(
    'a teardown that throws reports onError for the disposal phase',
    (tester) async {
      // `_performAsyncDispose()` runs from a future `dispose()` discards, so
      // a failure it re-throws at the end reaches only the zone, not
      // `tester.takeException()` -- the same reason
      // `async_scope_test.dart`'s equivalent scenario for `initScope` is
      // guarded. `docs/handoff.md`'s "Грабли" section names this one for
      // `_performAsyncDispose()` specifically.
      final errors = <Object>[];
      await runZonedGuarded(
        () async {
          Widget build({required bool present}) => Directionality(
                textDirection: TextDirection.ltr,
                child: present
                    ? AsyncScope(
                        initScope: (context) => Stream.value(AsyncScopeReady()),
                        disposeScope: () => throw StateError('dispose failed'),
                        progressBuilder: (context, progress) =>
                            const Text('init'),
                        errorBuilder: (context, error, stackTrace, progress) =>
                            Text('$error'),
                        builder: (context) => const Text('ready'),
                      )
                    : const SizedBox.shrink(),
              );

          await tester.pumpWidget(build(present: true));
          await tester.pumpAndSettle();

          await tester.pumpWidget(build(present: false));
          await settle(
            tester,
            until: () => observer.events.any((e) => e.startsWith('error')),
          );
        },
        (error, stackTrace) => errors.add(error),
      );

      expect(observer.events, [
        'init AsyncScope',
        'ready AsyncScope',
        'dispose AsyncScope',
        'error AsyncScope disposal Bad state: dispose failed',
      ]);
      expect(
        errors.single,
        isA<StateError>(),
        reason: 'the failure still reaches the zone, not just the observer',
      );
    },
  );

  testWidgets(
    'a hanging teardown reports onTimeout after disposeScopeTimeout',
    (tester) async {
      final hang = Completer<void>();

      Widget build({required bool present}) => Directionality(
            textDirection: TextDirection.ltr,
            child: present
                ? AsyncScope(
                    disposeScopeTimeout: const Duration(milliseconds: 50),
                    initScope: (context) => Stream.value(AsyncScopeReady()),
                    disposeScope: () => hang.future,
                    progressBuilder: (context, progress) => const Text(
                      'init',
                    ),
                    errorBuilder: (context, error, stackTrace, progress) =>
                        Text('$error'),
                    builder: (context) => const Text('ready'),
                  )
                : const SizedBox.shrink(),
          );

      await tester.pumpWidget(build(present: true));
      await tester.pumpAndSettle();

      await tester.pumpWidget(build(present: false));
      // The abandoned `disposeScope()` is left running in the background --
      // giving up on waiting for it does not stop the teardown, which goes
      // on to report `disposed` right after the expiry, in the same
      // continuation. Settling for `timeout` alone would race that.
      await settle(
        tester,
        until: () => observer.events.contains('disposed AsyncScope'),
      );

      expect(observer.events, [
        'init AsyncScope',
        'ready AsyncScope',
        'dispose AsyncScope',
        'timeout AsyncScope its own teardown',
        'disposed AsyncScope',
      ]);
      expect(tester.takeException(), isA<TimeoutException>());
    },
  );
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

/// A scope with no phase of its own: [ScopeWidgetBase] goes no further than
/// [ScopeWidgetElementBase] itself, so it never overrides
/// [ScopeWidgetElementBase.reportsOwnLifecycle].
final class _PlainScope extends ScopeWidgetBase<_PlainScope> {
  const _PlainScope({super.child});

  @override
  Widget build(BuildContext context) => child;
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

/// A minimal [AsyncScopeCore] with two progress steps before it is ready.
final class _AsyncScope
    extends AsyncScopeCore<_AsyncScope, _AsyncScopeElement> {
  const _AsyncScope();

  @override
  _AsyncScopeElement createScopeElement() => _AsyncScopeElement(this);
}

final class _AsyncScopeElement
    extends AsyncScopeElementBase<_AsyncScope, _AsyncScopeElement> {
  _AsyncScopeElement(super.widget);

  @override
  Stream<AsyncScopeInitState> initScope() async* {
    yield AsyncScopeProgress('1/2');
    yield AsyncScopeProgress('2/2');
    yield AsyncScopeReady();
  }

  @override
  Widget buildOnState(AsyncScopeState state) => const SizedBox.shrink();
}
