import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scopo/scopo.dart';

import 'utils/settle.dart';

/// The constructor of a closure form *is* its public surface.
///
/// A subclass of `AsyncScopeBase` reaches every setting by overriding a
/// getter, and that is how the rest of the suite reaches them — through
/// hand-written fixtures. A user of `AsyncScope` or `AsyncDataScope` has no
/// such door: a parameter the constructor does not forward is a setting they
/// cannot reach at all, only the process-wide `ScopeConfig` default. Nothing
/// tested the widgets from the constructor side, which is how nine parameters
/// stayed unforwarded through a release while every one of them was honoured
/// by the element behind it.
void main() {
  late final bool pauseEnabled;

  setUpAll(() {
    pauseEnabled = ScopeConfig.pauseAfterInitializationEnabled;
  });

  tearDown(() {
    ScopeConfig.pauseAfterInitializationEnabled = pauseEnabled;
  });

  group('AsyncScope', () {
    testWidgets('holds the ready branch back for pauseAfterInitialization', (
      tester,
    ) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: AsyncScope(
            pauseAfterInitialization: const Duration(seconds: 1),
            initScope: (context, ctx) async {},
            disposeScope: () {},
            progressBuilder: (context, progress) => const Text('init'),
            errorBuilder: (context, error, stackTrace, progress) =>
                Text('$error'),
            builder: (context) => const Text('ready'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.text('init'),
        findsOneWidget,
        reason: 'the pause keeps the initializing branch on screen',
      );

      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(find.text('ready'), findsOneWidget);
    });

    // The pause is a timer of the zone the scope was built in, and a scope
    // taken off the tree in the middle of one used to leave it running. What
    // asserts it is the binding: `flutter_test` ends a test on a timer that is
    // still pending after the tree is gone, so a test that leaves one behind
    // fails with `A Timer is still pending`. For a consumer of the package
    // that is a widget test of their own failing for no reason of theirs; in
    // production it is an unmounted element held for the length of the pause.
    testWidgets('a pause interrupted by the tree going away leaves no timer', (
      tester,
    ) async {
      Widget build({required bool present}) => Directionality(
            textDirection: TextDirection.ltr,
            child: present
                ? AsyncScope(
                    pauseAfterInitialization: const Duration(seconds: 5),
                    initScope: (context, ctx) async {},
                    disposeScope: () {},
                    progressBuilder: (context, progress) => const Text('init'),
                    errorBuilder: (context, error, stackTrace, progress) =>
                        Text('$error'),
                    builder: (context) => const Text('ready'),
                  )
                : const SizedBox.shrink(),
          );

      await tester.pumpWidget(build(present: true));
      await tester.pump();
      await tester.pump();
      expect(
        find.text('init'),
        findsOneWidget,
        reason: 'the pause is running, which is the state this is about',
      );

      await tester.pumpWidget(build(present: false));
      await settle(tester, until: () => false);
    });

    // Passes all nine parameters at once, so the whole surface is pinned by
    // compilation, and asserts the two that this scenario can observe.
    testWidgets('gives up on a hanging dispose after disposeScopeTimeout', (
      tester,
    ) async {
      final hang = Completer<void>();
      var expired = false;

      Widget build({required bool present}) => Directionality(
            textDirection: TextDirection.ltr,
            child: AsyncScopeCoordinator(
              child: present
                  ? AsyncScope(
                      scopeKey: 'k',
                      scopeKeyTimeout: const Duration(days: 1),
                      onScopeKeyTimeout: () {},
                      initCancellationTimeout: const Duration(days: 1),
                      onInitCancellationTimeout: () {},
                      disposeScopeTimeout: const Duration(milliseconds: 50),
                      onDisposeScopeTimeout: () => expired = true,
                      waitForChildrenTimeout: const Duration(days: 1),
                      onWaitForChildrenTimeout: () {},
                      pauseAfterInitialization: const Duration(milliseconds: 1),
                      initScope: (context, ctx) async {},
                      disposeScope: () => hang.future,
                      progressBuilder: (context, progress) =>
                          const Text('init'),
                      errorBuilder: (context, error, stackTrace, progress) =>
                          Text('$error'),
                      builder: (context) => const Text('ready'),
                    )
                  : const SizedBox.shrink(),
            ),
          );

      await tester.pumpWidget(build(present: true));
      await tester.pumpAndSettle();

      expect(find.text('ready'), findsOneWidget);

      await tester.pumpWidget(build(present: false));
      await settle(tester, until: () => expired);

      expect(
        expired,
        isTrue,
        reason: 'the callback the constructor was given is the one called',
      );
      expect(
        tester.takeException(),
        isA<TimeoutException>(),
        reason: 'and the expiry itself is reported',
      );
    });
  });

  group('AsyncDataScope', () {
    testWidgets('holds the ready branch back for pauseAfterInitialization', (
      tester,
    ) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: AsyncDataScope<String>(
            pauseAfterInitialization: const Duration(seconds: 1),
            initData: (context) =>
                Stream.value(AsyncDataScopeReady<Object, String>('value')),
            disposeData: (data) {},
            progressBuilder: (context, progress) => const Text('init'),
            errorBuilder: (context, error, stackTrace, progress) =>
                Text('$error'),
            builder: (context, data) => Text('ready: $data'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.text('init'),
        findsOneWidget,
        reason: 'the pause keeps the initializing branch on screen',
      );

      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(find.text('ready: value'), findsOneWidget);
    });

    testWidgets('gives up on a hanging dispose after disposeScopeTimeout', (
      tester,
    ) async {
      final hang = Completer<void>();
      var expired = false;

      Widget build({required bool present}) => Directionality(
            textDirection: TextDirection.ltr,
            child: AsyncScopeCoordinator(
              child: present
                  ? AsyncDataScope<String>(
                      scopeKey: 'k',
                      scopeKeyTimeout: const Duration(days: 1),
                      onScopeKeyTimeout: () {},
                      initCancellationTimeout: const Duration(days: 1),
                      onInitCancellationTimeout: () {},
                      disposeScopeTimeout: const Duration(milliseconds: 50),
                      onDisposeScopeTimeout: () => expired = true,
                      waitForChildrenTimeout: const Duration(days: 1),
                      onWaitForChildrenTimeout: () {},
                      pauseAfterInitialization: const Duration(milliseconds: 1),
                      initData: (context) => Stream.value(
                        AsyncDataScopeReady<Object, String>('value'),
                      ),
                      disposeData: (data) => hang.future,
                      progressBuilder: (context, progress) =>
                          const Text('init'),
                      errorBuilder: (context, error, stackTrace, progress) =>
                          Text('$error'),
                      builder: (context, data) => Text('ready: $data'),
                    )
                  : const SizedBox.shrink(),
            ),
          );

      await tester.pumpWidget(build(present: true));
      await tester.pumpAndSettle();

      expect(find.text('ready: value'), findsOneWidget);

      await tester.pumpWidget(build(present: false));
      await settle(tester, until: () => expired);

      expect(
        expired,
        isTrue,
        reason: 'the callback the constructor was given is the one called',
      );
      expect(
        tester.takeException(),
        isA<TimeoutException>(),
        reason: 'and the expiry itself is reported',
      );
    });
  });
}
