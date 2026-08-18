import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scopo/scopo.dart';

import 'utils/settle.dart';

void main() {
  tearDown(ScopeConfig.reset);

  group('the waiting branch', () {
    testWidgets('is what a scope queued behind a scopeKey shows', (
      tester,
    ) async {
      final gate = Completer<void>();

      Widget build({required bool holder, required bool successor}) =>
          Directionality(
            textDirection: TextDirection.ltr,
            child: AsyncScopeCoordinator(
              child: Column(
                children: [
                  if (holder)
                    AsyncScope(
                      key: const ValueKey('holder'),
                      scopeKey: 'k',
                      initScope: (context) => Stream.value(AsyncScopeReady()),
                      disposeScope: () => gate.future,
                      progressBuilder: (context, progress) =>
                          const Text('holder: init'),
                      errorBuilder: (context, error, stackTrace, progress) =>
                          Text('holder: $error'),
                      builder: (context) => const Text('holder: ready'),
                    ),
                  if (successor)
                    AsyncScope(
                      key: const ValueKey('successor'),
                      scopeKey: 'k',
                      initScope: (context) => Stream.value(AsyncScopeReady()),
                      disposeScope: () {},
                      waitingBuilder: (context) => const Text('waiting'),
                      progressBuilder: (context, progress) =>
                          const Text('initializing'),
                      errorBuilder: (context, error, stackTrace, progress) =>
                          Text('error: $error'),
                      builder: (context) => const Text('ready'),
                    ),
                ],
              ),
            ),
          );

      await tester.pumpWidget(build(holder: true, successor: false));
      await tester.pumpAndSettle();

      await tester.pumpWidget(build(holder: false, successor: true));
      await settle(
        tester,
        until: () => find.text('ready').evaluate().isNotEmpty,
      );

      expect(
        find.text('waiting'),
        findsOneWidget,
        reason: 'the key is still held, so the scope has not started yet',
      );

      gate.complete();
      await settle(
        tester,
        until: () => find.text('ready').evaluate().isNotEmpty,
      );

      expect(find.text('ready'), findsOneWidget);
    });

    testWidgets('falls back to the initializing branch when it is not given', (
      tester,
    ) async {
      final gate = Completer<void>();

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: AsyncScopeCoordinator(
            child: Column(
              children: [
                AsyncScope(
                  key: const ValueKey('holder'),
                  scopeKey: 'k',
                  initScope: (context) => Stream.value(AsyncScopeReady()),
                  disposeScope: () => gate.future,
                  progressBuilder: (context, progress) =>
                      const Text('holder: init'),
                  errorBuilder: (context, error, stackTrace, progress) =>
                      Text('holder: $error'),
                  builder: (context) => const Text('holder: ready'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: AsyncScopeCoordinator(
            child: Column(
              children: [
                AsyncScope(
                  key: const ValueKey('successor'),
                  scopeKey: 'k',
                  initScope: (context) => Stream.value(AsyncScopeReady()),
                  disposeScope: () {},
                  // No waitingBuilder: `buildOnWaiting()` answers null and the
                  // initializing branch is built with a null progress instead.
                  progressBuilder: (context, progress) =>
                      const Text('initializing'),
                  errorBuilder: (context, error, stackTrace, progress) =>
                      Text('error: $error'),
                  builder: (context) => const Text('ready'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('initializing'), findsOneWidget);

      gate.complete();
      await settle(
        tester,
        until: () => find.text('ready').evaluate().isNotEmpty,
      );
      expect(find.text('ready'), findsOneWidget);
    });
  });

  group('pauseAfterInitialization', () {
    testWidgets('holds the ready state back for the duration it names', (
      tester,
    ) async {
      await tester.pumpWidget(const _PausedHost(pause: Duration(seconds: 1)));
      await tester.pump();
      await tester.pump();

      final scope =
          tester.element<_PausedScopeElement>(find.byType(_PausedScope));

      expect(
        scope.state,
        isA<AsyncScopeProgress>(),
        reason: 'the pause keeps the last progress on screen',
      );

      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(scope.state, isA<AsyncScopeReady>());
    });

    testWidgets('is skipped entirely when the config disables it', (
      tester,
    ) async {
      ScopeConfig.pauseAfterInitializationEnabled = false;

      await tester.pumpWidget(const _PausedHost(pause: Duration(seconds: 1)));
      await tester.pump();
      await tester.pump();

      final scope =
          tester.element<_PausedScopeElement>(find.byType(_PausedScope));

      expect(
        scope.state,
        isA<AsyncScopeReady>(),
        reason: 'no delay is scheduled at all, so the ready state applies at '
            'the next frame',
      );
    });
  });

  group('tag', () {
    test('names a scope in diagnostics instead of its hash', () {
      const tagged = _PausedScope(pause: Duration.zero, tag: 'auth');
      const plain = _PausedScope(pause: Duration.zero);

      expect(tagged.toStringShort(), '_PausedScope(auth)');
      expect(plain.toStringShort(), '_PausedScope');
      expect(
        plain.toStringShort(showHashCode: true),
        matches(RegExp(r'^_PausedScope\(#[0-9a-f]{5}\)$')),
      );
      expect(
        tagged.toStringShort(showHashCode: true),
        '_PausedScope(auth)',
        reason: 'a tag is more use than a hash, so it wins',
      );
    });
  });
}

final class _PausedHost extends StatelessWidget {
  final Duration pause;

  const _PausedHost({required this.pause});

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: _PausedScope(pause: pause),
      );
}

final class _PausedScope
    extends AsyncScopeCore<_PausedScope, _PausedScopeElement> {
  final Duration pause;

  const _PausedScope({required this.pause, super.tag});

  @override
  _PausedScopeElement createScopeElement() => _PausedScopeElement(this);
}

final class _PausedScopeElement
    extends AsyncScopeElementBase<_PausedScope, _PausedScopeElement> {
  _PausedScopeElement(super.widget);

  @override
  Duration? get pauseAfterInitialization => widget.pause;

  @override
  Stream<AsyncScopeInitState> initScope() async* {
    yield AsyncScopeProgress('almost');
    yield AsyncScopeReady();
  }

  @override
  Widget buildOnState(AsyncScopeState state) => const SizedBox.shrink();
}
