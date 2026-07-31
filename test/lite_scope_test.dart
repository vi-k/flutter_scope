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
    for (final (state, init, body)
        in <(String, Stream<AsyncScopeInitState> Function(), String)>[
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

    testWidgets(
      'completes both futures when close() is called twice',
      (tester) async {
        await tester.pumpWidget(_app(const _CloseScope(init: _becomesReady)));
        await tester.pumpAndSettle();
        expect(find.text('ready'), findsOneWidget);

        final element =
            tester.element<_CloseScopeElement>(find.byType(_CloseScope));

        var isFirstClosed = false;
        var isSecondClosed = false;
        unawaited(element.close().whenComplete(() => isFirstClosed = true));

        // Build the closing frame *without* drawing it, so the
        // `ScreenshotReplacer` that is going to release the barrier is mounted
        // while its capture is still pending: drawing the frame here would run
        // the capture to completion before the second `close()` arrives.
        tester.binding.buildOwner!.buildScope(tester.binding.rootElement!);
        expect(find.byType(ScreenshotReplacer), findsOneWidget);

        // A second `close()` must not swap the barrier out from under the
        // first one: the barrier the first `close()` is waiting for is the one
        // the replacer releases.
        unawaited(element.close().whenComplete(() => isSecondClosed = true));

        await _settle(tester, until: () => isFirstClosed && isSecondClosed);

        expect(
          isFirstClosed,
          isTrue,
          reason: 'the first close() must not be orphaned by the second one',
        );
        expect(
          isSecondClosed,
          isTrue,
          reason: 'the second close() must join the first one',
        );
      },
    );

    testWidgets(
      'completes in the ready state even when the screenshot can never '
      'be taken',
      (tester) async {
        // An offstage subtree is built and laid out but never painted, so the
        // repaint boundary can never be captured.
        await tester.pumpWidget(
          _app(const Offstage(child: _CloseScope(init: _becomesReady))),
        );
        await _settle(
          tester,
          until: () => _scopeOf(tester).state is AsyncScopeReady,
        );
        expect(_scopeOf(tester).state, isA<AsyncScopeReady>());

        var isClosed = false;
        unawaited(_scopeOf(tester).close().whenComplete(() => isClosed = true));

        await _settle(tester, until: () => isClosed);

        expect(
          isClosed,
          isTrue,
          reason: 'the capture must give up after a bounded number of retries '
              'instead of keeping close() waiting forever',
        );
        expect(find.byType(RawImage, skipOffstage: false), findsNothing);
      },
    );

    testWidgets(
      'does not touch the disposed model when close() wins the race with the '
      'post-frame callback that applies the ready state',
      (tester) async {
        final binding = tester.binding;

        // Mount by driving the build phase directly, so the post-frame
        // callback that `_performAsyncInit` schedules for `AsyncScopeReady`
        // stays pending -- `pumpWidget` would drain it within the very frame
        // that schedules it (the same technique as in `async_scope_test.dart`).
        binding.attachRootWidget(
          binding.wrapWithDefaultView(
            const Directionality(
              textDirection: TextDirection.ltr,
              child: _CloseScope(init: _becomesReady),
            ),
          ),
        );
        binding.buildOwner!.buildScope(binding.rootElement!);

        // Lets `initAsync()` deliver `AsyncScopeReady` -- so `_initSucceeded`
        // is set and the post-frame callback is scheduled -- without drawing a
        // frame.
        await binding.idle();

        final element = _scopeOf(tester);
        expect(
          element.state,
          isA<AsyncScopeWaiting>(),
          reason: 'the ready state must still be pending for this race',
        );

        var isClosed = false;
        unawaited(element.close().whenComplete(() => isClosed = true));

        // The disposal chain runs to `_model.dispose()`, and only then is the
        // stale post-frame callback drained by a real frame.
        await _settle(tester, until: () => isClosed);

        expect(isClosed, isTrue);
        expect(
          tester.takeException(),
          isNull,
          reason: 'the pending ready callback must not use the disposed model',
        );
        // The ready state was never applied, but `initAsync()` did succeed, so
        // `disposeAsync()` still has to run exactly once (see task 7).
        expect(element.disposeAsyncCount, 1);
        expect(element.state, isA<AsyncScopeWaiting>());
      },
    );

    // The same shape as the `AsyncScopeElementBase` deadlock covered in
    // `async_scope_test.dart`, one layer down: `LiteScopeCoreState`
    // synchronizes its disposal with its own initialization through a
    // completer, and `_performAsyncInit()` runs on a future discarded by
    // `initState()`. A failed `initAsync()` used to leave that completer
    // unsettled, so `close()` -- which reaches it through
    // `LiteScopeElementBase.disposeAsync()` -- never came back.
    for (final (kind, isAsync) in [('synchronously', false), ('async', true)]) {
      testWidgets(
        'completes when the state initAsync throws $kind',
        (tester) async {
          // The failure surfaces as an uncaught error of the zone the build
          // ran in, exactly as for the scope-level initialization; a guarded
          // child zone catches it before `flutter_test` ends the test on it.
          // Nothing inside that zone may throw -- an assertion that fails
          // there is swallowed by the zone's error handler and the test hangs
          // instead of failing -- so every `expect` is made once it is gone.
          final errors = <Object>[];
          var isClosed = false;
          late _CloseScopeElement element;

          await runZonedGuarded(
            () async {
              await tester.pumpWidget(
                _app(
                  _CloseScope(
                    init: _becomesReady,
                    failStateInit: true,
                    failStateInitAsync: isAsync,
                  ),
                ),
              );
              element = _scopeOf(tester);
              // The state only exists once the scope is ready: it is created
              // by the widget `buildOnReady()` mounts.
              await _settle(tester, until: () => element.createdState != null);

              unawaited(element.close().whenComplete(() => isClosed = true));
              await _settle(tester, until: () => isClosed);
            },
            (error, stackTrace) => errors.add(error),
          );

          expect(
            element.createdState,
            isNotNull,
            reason: 'the state must have been created and initialized',
          );
          expect(
            isClosed,
            isTrue,
            reason: 'close() must not wait for an initialization that failed',
          );
          expect(
            element.createdState!.disposeAsyncCount,
            0,
            reason: 'an initialization that never happened is not disposed of',
          );
          expect(
            errors.single,
            isA<StateError>(),
            reason: 'the failure is still reported, not swallowed',
          );
        },
      );
    }
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

    testWidgets(
      'retries without reporting completion, then gives up after the retry cap',
      (tester) async {
        var completedCount = 0;

        // An offstage subtree is never painted, so `debugNeedsPaint` stays true
        // and every attempt takes the retry path.
        await tester.pumpWidget(
          _app(
            Offstage(
              child: ScreenshotReplacer(
                onCompleted: () => completedCount++,
                child: const SizedBox(width: 20, height: 20),
              ),
            ),
          ),
        );

        // The first attempt already ran, in the post-frame callback of the
        // frame above.
        expect(
          completedCount,
          0,
          reason: 'the first attempt must not report completion',
        );

        // A retry must never release the barrier: there is no screenshot yet.
        for (var i = 1; i <= 3; i++) {
          await tester.pump();
          expect(
            completedCount,
            0,
            reason: 'retry $i must not report completion',
          );
        }

        // The retries are capped, though, and giving up must release the
        // barrier -- otherwise `close()` would wait forever.
        for (var i = 0; i < 20 && completedCount == 0; i++) {
          await tester.pump();
        }

        expect(
          completedCount,
          1,
          reason: 'giving up must report completion exactly once',
        );
        expect(find.byType(RawImage, skipOffstage: false), findsNothing);

        // Retrying must have stopped: no further frame reports again.
        for (var i = 0; i < 3; i++) {
          await tester.pump();
        }
        expect(completedCount, 1);
      },
    );
  });
}

Widget _app(Widget child) => MaterialApp(home: Center(child: child));

/// The scope element currently in the tree, offstage or not.
_CloseScopeElement _scopeOf(WidgetTester tester) =>
    tester.element<_CloseScopeElement>(
      find.byType(_CloseScope, skipOffstage: false),
    );

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

  /// Makes [_CloseScopeState.initAsync] fail, the way a plain user error in a
  /// state initializer does.
  final bool failStateInit;

  /// Whether that failure is raised from a future ([_CloseScopeState.initAsync]
  /// returns a `FutureOr<void>`, so both are ordinary user code).
  final bool failStateInitAsync;

  const _CloseScope({
    required this.init,
    this.failStateInit = false,
    this.failStateInitAsync = false,
  });

  @override
  _CloseScopeElement createScopeElement() => _CloseScopeElement(this);
}

final class _CloseScopeElement extends LiteScopeElementBase<_CloseScope,
    _CloseScopeElement, _CloseScopeState> {
  /// How many times [disposeAsync] ran, to prove that a disposal racing the
  /// ready state still releases what `initAsync()` acquired.
  int disposeAsyncCount = 0;

  /// The state built by `buildOnReady()`, kept here because the widget that
  /// owns it is private to the package and cannot be found by type.
  _CloseScopeState? createdState;

  _CloseScopeElement(super.widget);

  @override
  Stream<AsyncScopeInitState> initAsync() => widget.init();

  @override
  Future<void> disposeAsync() async {
    disposeAsyncCount++;
    await super.disposeAsync();
  }

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
  _CloseScopeState createState() => createdState = _CloseScopeState();
}

final class _CloseScopeState extends LiteScopeCoreState<_CloseScope,
    _CloseScopeElement, _CloseScopeState> {
  /// How many times [disposeAsync] ran, to prove that a state whose
  /// initialization failed is not disposed of.
  int disposeAsyncCount = 0;

  @override
  FutureOr<void> initAsync() {
    if (!params.failStateInit) return null;
    if (params.failStateInitAsync) {
      return Future<void>.error(StateError('state initAsync failed'));
    }

    throw StateError('state initAsync failed');
  }

  @override
  FutureOr<void> disposeAsync() {
    disposeAsyncCount++;
  }

  @override
  Widget build(BuildContext context) => const Text('ready');
}
