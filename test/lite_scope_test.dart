import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scopo/scopo.dart';

void main() {
  group('LiteScope.close()', () {
    // `close()` installs a screenshot barrier and waits for it. The barrier is
    // only ever released by the `ScreenshotReplacer` that `buildOnReady()`
    // mounts, and `buildOnReady()` is the `AsyncScopeReady` branch of
    // `buildOnState()` -- so in any other state nothing can release it and
    // `close()` waits forever.
    for (final (state, init, body) in <(
      String,
      Stream<AsyncScopeInitState> Function(),
      String
    )>[
      ('waiting', _neverEmits, 'waiting'),
      ('initializing', _emitsProgressOnly, 'initializing'),
      ('error', _failsImmediately, 'error'),
    ]) {
      testWidgets(
        'completes while the scope is in the $state state',
        (tester) async {
          await tester.pumpWidget(_app(_CloseScope(init: init)));
          // A few extra frames, so the init stream event (or error) is
          // delivered and applied to the model before `close()` is called.
          for (var i = 0; i < 3; i++) {
            await tester.pump();
          }
          expect(find.text(body), findsOneWidget);

          final element =
              tester.element<_CloseScopeElement>(find.byType(_CloseScope));

          // Deliberately not awaited: before the fix this future never
          // completes, so awaiting it would hang the whole test run instead of
          // failing this test.
          var isClosed = false;
          unawaited(element.close().whenComplete(() => isClosed = true));

          await _settle(tester, until: () => isClosed);

          expect(
            isClosed,
            isTrue,
            reason: 'close() must not wait for a screenshot that '
                'buildOnReady() never takes in the $state state',
          );
        },
      );
    }

    testWidgets(
      'completes in the ready state once the screenshot has been captured',
      (tester) async {
        await tester.pumpWidget(_app(const _CloseScope(init: _becomesReady)));
        await tester.pumpAndSettle();
        expect(find.text('ready'), findsOneWidget);

        final element =
            tester.element<_CloseScopeElement>(find.byType(_CloseScope));

        var isClosed = false;
        unawaited(element.close().whenComplete(() => isClosed = true));

        // The closing frame: `buildOnReady()` now wraps the child into a
        // `ScreenshotReplacer` (plus the closing overlay), and the replacer's
        // post-frame callback starts the capture.
        await tester.pump();
        expect(find.byType(ScreenshotReplacer), findsOneWidget);

        await _settle(tester, until: () => isClosed);

        expect(
          isClosed,
          isTrue,
          reason: 'in the ready state the barrier must still be installed and '
              'released by the ScreenshotReplacer',
        );
      },
    );

    testWidgets(
      'completes when the element leaves the tree before the closing frame '
      'is built',
      (tester) async {
        await tester.pumpWidget(_app(const _CloseScope(init: _becomesReady)));
        await tester.pumpAndSettle();
        expect(find.text('ready'), findsOneWidget);

        final element =
            tester.element<_CloseScopeElement>(find.byType(_CloseScope));

        var isClosed = false;
        unawaited(element.close().whenComplete(() => isClosed = true));

        // `close()` has installed the barrier and marked the element dirty, but
        // the element is deactivated before it gets a chance to rebuild: the
        // `ScreenshotReplacer` that would release the barrier is never mounted
        // at all.
        await tester.pumpWidget(_app(const SizedBox.shrink()));

        await _settle(tester, until: () => isClosed);

        expect(
          isClosed,
          isTrue,
          reason: 'a scope removed from the tree while closing must not keep '
              'close() waiting for a screenshot that can no longer be taken',
        );
      },
    );
  });

  group('ScreenshotReplacer', () {
    testWidgets(
      'reports completion exactly once and releases the captured image',
      (tester) async {
        var completedCount = 0;

        await tester.pumpWidget(
          _app(
            ScreenshotReplacer(
              onCompleted: () => completedCount++,
              child: const SizedBox(
                width: 20,
                height: 20,
                child: ColoredBox(color: Color(0xFF00FF00)),
              ),
            ),
          ),
        );

        ui.Image? captured;
        await _settle(
          tester,
          until: () {
            final images = find.byType(RawImage);
            if (images.evaluate().isEmpty) return false;
            captured = tester.widget<RawImage>(images).image;
            return captured != null;
          },
        );

        expect(
          captured,
          isNotNull,
          reason: 'the repaint boundary was never captured',
        );
        expect(
          completedCount,
          1,
          reason: 'completion is reported once, on the success path',
        );
        expect(captured!.debugDisposed, isFalse);

        // Removing the widget must not report completion a second time, and
        // must release the `ui.Image` handle owned by the state.
        await tester.pumpWidget(_app(const SizedBox.shrink()));

        expect(
          completedCount,
          1,
          reason: 'disposal must not report completion again',
        );
        expect(
          captured!.debugDisposed,
          isTrue,
          reason: 'the captured ui.Image must be disposed of with the state',
        );
      },
    );
  });
}

Widget _app(Widget child) => MaterialApp(home: Center(child: child));

/// Pumps frames interleaved with slices of *real* time, until [until] holds or
/// the budget runs out.
///
/// Some of the futures involved here are only completed outside the test's
/// fake-async zone -- the engine rasterization behind
/// `RenderRepaintBoundary.toImage()`, and the `StreamSubscription.cancel()`
/// chain of `AsyncScopeElementBase._performAsyncDispose` (the same `runAsync`
/// workaround is documented in `async_scope_test.dart`) -- so plain `pump()`
/// and `idle()` are not enough to let them make progress.
Future<void> _settle(
  WidgetTester tester, {
  required bool Function() until,
}) async {
  for (var i = 0; i < 20 && !until(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
}

/// Keeps the scope in [AsyncScopeWaiting]: nothing is ever emitted, and the
/// stream stays open until the scope cancels it.
Stream<AsyncScopeInitState> _neverEmits() =>
    Stream<AsyncScopeInitState>.multi((_) {});

/// Moves the scope into [AsyncScopeProgress] and keeps it there.
Stream<AsyncScopeInitState> _emitsProgressOnly() =>
    Stream<AsyncScopeInitState>.multi(
      (controller) => controller.add(AsyncScopeProgress(1)),
    );

/// Moves the scope into [AsyncScopeError].
Stream<AsyncScopeInitState> _failsImmediately() async* {
  throw Exception('init failed');
}

/// Moves the scope into [AsyncScopeReady].
Stream<AsyncScopeInitState> _becomesReady() =>
    Stream<AsyncScopeInitState>.value(AsyncScopeReady());

/// A minimal [LiteScopeCore] with an element type visible to the test, so
/// [LiteScopeElementBase.close] can be called in any state -- including the
/// states in which no [LiteScopeCoreState] exists yet.
final class _CloseScope
    extends LiteScopeCore<_CloseScope, _CloseScopeElement, _CloseScopeState> {
  final Stream<AsyncScopeInitState> Function() init;

  const _CloseScope({required this.init});

  @override
  _CloseScopeElement createScopeElement() => _CloseScopeElement(this);
}

final class _CloseScopeElement extends LiteScopeElementBase<_CloseScope,
    _CloseScopeElement, _CloseScopeState> {
  _CloseScopeElement(super.widget);

  @override
  Stream<AsyncScopeInitState> initAsync() => widget.init();

  @override
  Widget? buildOnWaiting() => const Text('waiting');

  @override
  Widget buildOnInitializing(Object? progress) => const Text('initializing');

  @override
  Widget buildOnError(
    Object error,
    StackTrace stackTrace,
    Object? progress,
  ) =>
      const Text('error');

  @override
  _CloseScopeState createState() => _CloseScopeState();
}

final class _CloseScopeState extends LiteScopeCoreState<_CloseScope,
    _CloseScopeElement, _CloseScopeState> {
  @override
  Widget build(BuildContext context) => const Text('ready');
}
