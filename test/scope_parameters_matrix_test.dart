import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scopo/scopo.dart';

import 'utils/settle.dart';

/// Eleven settings, five families, and one forwarding line per pair.
///
/// Every family reaches the element behind it the same way: the widget holds
/// the setting, the element overrides a getter that reads it back. That line
/// reads exactly like its neighbours, which is why a wrong one — or a missing
/// one — is invisible to review, and why nine of them stayed unforwarded
/// through a release. The suite used to try a handful of the 55 pairs, all of
/// them on `AsyncScope`.
///
/// So the cases here are written once and run against every family. What each
/// one asserts is an effect the setting has on the tree, never the value of
/// the setting: a getter that returns the right number and is never consulted
/// would pass a test written the other way.
void main() {
  late final bool pauseEnabled;

  setUpAll(() {
    pauseEnabled = ScopeConfig.pauseAfterInitializationEnabled;
  });

  tearDown(() {
    ScopeConfig.pauseAfterInitializationEnabled = pauseEnabled;
  });

  for (final family in _families) {
    group(family.name, () {
      // The queue of a `scopeKey` is the one effect visible from outside the
      // scope entirely: a second scope on the same key cannot start until the
      // first has finished disposing of itself. A key that never reaches the
      // element makes the two strangers, and the second one is ready at once.
      testWidgets('scopeKey holds the next scope on the same key back',
          (tester) async {
        final held = Completer<void>();
        final log = <String>[];

        Widget build({required bool first, required bool second}) => _wrap(
              Column(
                children: [
                  if (first)
                    family.build(
                      _Case(
                        label: 'first',
                        log: log,
                        scopeKey: 'shared',
                        disposeGate: held,
                      ),
                    ),
                  if (second)
                    family.build(
                      _Case(
                        label: 'second',
                        log: log,
                        scopeKey: 'shared',
                        // Beyond anything this test advances, so an expiry
                        // cannot be what lets the second scope in.
                        scopeKeyTimeout: const Duration(days: 1),
                      ),
                    ),
                ],
              ),
            );

        await tester.pumpWidget(build(first: true, second: false));
        await tester.pumpAndSettle();
        expect(log, ['ready: first']);

        // Taken off the tree on its own, and only then replaced: both scopes
        // are widgets of the same type, so putting the second one where the
        // first was would have the framework update that element instead of
        // unmounting it -- one scope with new parameters, and no queue in
        // sight.
        await tester.pumpWidget(build(first: false, second: false));
        await settle(tester, until: () => false, rounds: 2);

        // The first scope is parked in its own teardown, still holding the
        // key; the second arrives and queues behind it.
        await tester.pumpWidget(build(first: false, second: true));
        await settle(tester, until: () => false, rounds: 5);

        expect(
          log,
          ['ready: first'],
          reason: 'the second scope is waiting for a key the first has not '
              'given back',
        );

        held.complete();
        await settle(tester, until: () => log.length > 1);

        expect(log, ['ready: first', 'ready: second']);

        await tester.pumpWidget(_wrap(const SizedBox.shrink()));
        await settle(tester, until: () => false, rounds: 5);
      });

      // The wait for a key is bounded, and the bound is this parameter. With
      // the forwarder gone the element takes `ScopeConfig`'s three seconds,
      // which no round of this test reaches.
      testWidgets('scopeKeyTimeout bounds that wait, and reports the expiry',
          (tester) async {
        final held = Completer<void>();
        final log = <String>[];
        var expired = false;

        Widget build({required bool first, required bool second}) => _wrap(
              Column(
                children: [
                  if (first)
                    family.build(
                      _Case(
                        label: 'first',
                        log: log,
                        scopeKey: 'shared',
                        disposeGate: held,
                      ),
                    ),
                  if (second)
                    family.build(
                      _Case(
                        label: 'second',
                        log: log,
                        scopeKey: 'shared',
                        scopeKeyTimeout: const Duration(milliseconds: 50),
                        onScopeKeyTimeout: () => expired = true,
                      ),
                    ),
                ],
              ),
            );

        await tester.pumpWidget(build(first: true, second: false));
        await tester.pumpAndSettle();

        // See the test above on why the tree goes empty in between.
        await tester.pumpWidget(build(first: false, second: false));
        await settle(tester, until: () => false, rounds: 2);

        await tester.pumpWidget(build(first: false, second: true));
        await settle(tester, until: () => expired);

        expect(
          expired,
          isTrue,
          reason: 'the wait was given the 50 ms of this scope, not the three '
              'seconds of the global default',
        );
        expect(
          tester.takeException(),
          isA<TimeoutException>(),
          reason: 'and the expiry is reported before the callback runs',
        );

        held.complete();
        await tester.pumpWidget(_wrap(const SizedBox.shrink()));
        await settle(tester, until: () => false, rounds: 5);
      });

      // An initialization parked on a future that never completes cannot be
      // cancelled: cancelling an `async*` means resuming its body, and a body
      // suspended for good is never resumed. The teardown gives up after this
      // parameter's duration.
      testWidgets('initCancellationTimeout bounds the cancellation',
          (tester) async {
        final never = Completer<void>();
        final log = <String>[];
        var expired = false;

        await tester.pumpWidget(
          _wrap(
            family.build(
              _Case(
                label: 'stuck',
                log: log,
                initGate: never,
                initCancellationTimeout: const Duration(milliseconds: 50),
                onInitCancellationTimeout: () => expired = true,
              ),
            ),
          ),
        );
        await tester.pump();

        await tester.pumpWidget(_wrap(const SizedBox.shrink()));
        await settle(tester, until: () => expired);

        expect(
          expired,
          isTrue,
          reason: 'the teardown stopped waiting after the 50 ms of this '
              'scope, not after the global default',
        );
        expect(
          tester.takeException(),
          isA<TimeoutException>(),
          reason: 'an expiry is reported before the callback is called, and '
              'never passed over in silence',
        );

        // The gate is deliberately left open: an initialization woken up
        // after the teardown is over is a path of its own, and one this test
        // is not about.
      });

      // The scope's own teardown is user code, and a teardown that never
      // finishes must not hold the scope's registration and key for ever.
      testWidgets("disposeScopeTimeout bounds the scope's own teardown",
          (tester) async {
        final never = Completer<void>();
        final log = <String>[];
        var expired = false;

        await tester.pumpWidget(
          _wrap(
            family.build(
              _Case(
                label: 'stuck',
                log: log,
                disposeGate: never,
                disposeScopeTimeout: const Duration(milliseconds: 50),
                onDisposeScopeTimeout: () => expired = true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.pumpWidget(_wrap(const SizedBox.shrink()));
        await settle(tester, until: () => expired);

        expect(expired, isTrue);
        expect(tester.takeException(), isA<TimeoutException>());

        never.complete();
        await settle(tester, until: () => false, rounds: 5);
      });

      // A parent waits for the scopes registered with it before it disposes
      // of itself, and that wait is bounded by this parameter.
      testWidgets('waitForChildrenTimeout bounds the wait for the children',
          (tester) async {
        final never = Completer<void>();
        final log = <String>[];
        var expired = false;

        await tester.pumpWidget(
          _wrap(
            family.build(
              _Case(
                label: 'parent',
                log: log,
                waitForChildrenTimeout: const Duration(milliseconds: 50),
                onWaitForChildrenTimeout: () => expired = true,
                child: family.build(
                  _Case(label: 'child', log: log, disposeGate: never),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(log, containsAll(['ready: parent', 'ready: child']));

        await tester.pumpWidget(_wrap(const SizedBox.shrink()));
        await settle(tester, until: () => expired);

        expect(expired, isTrue);
        expect(tester.takeException(), isA<TimeoutException>());

        never.complete();
        await settle(tester, until: () => false, rounds: 5);
      });

      // The ready branch is held back for this long, so a spinner that has
      // just appeared is not replaced in the very next frame.
      testWidgets('pauseAfterInitialization holds the ready branch back',
          (tester) async {
        final log = <String>[];

        await tester.pumpWidget(
          _wrap(
            family.build(
              _Case(
                label: 'paused',
                log: log,
                pauseAfterInitialization: const Duration(seconds: 1),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(
          log,
          isEmpty,
          reason: 'the ready branch has not been built yet: the pause is what '
              'keeps the initializing one on screen',
        );

        await tester.pump(const Duration(seconds: 1));
        await tester.pump();

        expect(log, ['ready: paused']);

        await tester.pumpWidget(_wrap(const SizedBox.shrink()));
        await settle(tester, until: () => false, rounds: 5);
      });

      // `close()` runs the teardown while the scope is still on screen, and
      // this is the branch shown on top of the frozen screenshot of the ready
      // one. A forwarder that answers `null` shows the screenshot alone --
      // a screen that looks alive and is not.
      if (family.closes) {
        testWidgets('buildOnClosing is shown while close() runs',
            (tester) async {
          final held = Completer<void>();
          final log = <String>[];
          // `close()` captures a screenshot of the subtree, which needs a size
          // to capture: a `SizedBox.shrink()` there has nothing to draw.
          final params = _Case(
            label: 'closing',
            log: log,
            disposeGate: held,
            child: const SizedBox(width: 10, height: 10),
          );

          await tester.pumpWidget(_wrap(family.build(params)));
          await tester.pumpAndSettle();
          expect(log, ['ready: closing']);

          unawaited(params.closeScope!());
          await tester.pumpAndSettle();

          expect(
            find.text('closing'),
            findsOneWidget,
            reason: 'the closing branch belongs to the widget, and the '
                'element only asks for it',
          );

          held.complete();
          await settle(tester, until: () => false, rounds: 5);

          await tester.pumpWidget(_wrap(const SizedBox.shrink()));
          await settle(tester, until: () => false, rounds: 5);
        });
      }
    });
  }
}

Widget _wrap(Widget child) => Directionality(
      textDirection: TextDirection.ltr,
      child: AsyncScopeCoordinator(child: child),
    );

/// One row of the matrix: a family, and the way its widget is built.
final class _Family {
  final String name;
  final Widget Function(_Case params) build;

  /// Whether the family has a `close()` and a `buildOnClosing` to go with it.
  /// The three closure forms have neither.
  final bool closes;

  const _Family(this.name, this.build, {this.closes = false});
}

/// The settings a case gives the scope, plus the two gates that make an
/// initialization or a teardown hang where a test needs it to.
final class _Case {
  final String label;
  final List<String> log;
  final Object? scopeKey;
  final Duration? scopeKeyTimeout;
  final void Function()? onScopeKeyTimeout;
  final Duration? initCancellationTimeout;
  final void Function()? onInitCancellationTimeout;
  final Duration? disposeScopeTimeout;
  final void Function()? onDisposeScopeTimeout;
  final Duration? waitForChildrenTimeout;
  final void Function()? onWaitForChildrenTimeout;
  final Duration? pauseAfterInitialization;
  final Completer<void>? initGate;
  final Completer<void>? disposeGate;
  final Widget? child;

  /// Filled in by the families that have one, so a test can run the closing
  /// path without reaching for a private element.
  Future<void> Function()? closeScope;

  _Case({
    required this.label,
    required this.log,
    this.scopeKey,
    this.scopeKeyTimeout,
    this.onScopeKeyTimeout,
    this.initCancellationTimeout,
    this.onInitCancellationTimeout,
    this.disposeScopeTimeout,
    this.onDisposeScopeTimeout,
    this.waitForChildrenTimeout,
    this.onWaitForChildrenTimeout,
    this.pauseAfterInitialization,
    this.initGate,
    this.disposeGate,
    this.child,
  });

  /// What the ready branch of every family records, so that "is it ready" is
  /// one question with one answer across the matrix.
  Widget get ready {
    log.add('ready: $label');

    return child ?? const SizedBox.shrink();
  }
}

const _families = [
  _Family('AsyncScope', _asyncScope),
  _Family('AsyncDataScope', _asyncDataScope),
  _Family('AsyncControllerScope', _asyncControllerScope),
  _Family('LiteScope', _liteScope, closes: true),
  _Family('Scope', _scope, closes: true),
];

Widget _asyncScope(_Case c) => AsyncScope(
      scopeKey: c.scopeKey,
      scopeKeyTimeout: c.scopeKeyTimeout,
      onScopeKeyTimeout: c.onScopeKeyTimeout,
      initCancellationTimeout: c.initCancellationTimeout,
      onInitCancellationTimeout: c.onInitCancellationTimeout,
      disposeScopeTimeout: c.disposeScopeTimeout,
      onDisposeScopeTimeout: c.onDisposeScopeTimeout,
      waitForChildrenTimeout: c.waitForChildrenTimeout,
      onWaitForChildrenTimeout: c.onWaitForChildrenTimeout,
      pauseAfterInitialization: c.pauseAfterInitialization,
      initScope: (context, ctx) async {
        if (c.initGate case final gate?) {
          await gate.future;
        }
      },
      disposeScope: () async {
        if (c.disposeGate case final gate?) {
          await gate.future;
        }
      },
      progressBuilder: (context, progress) => const SizedBox.shrink(),
      errorBuilder: (context, error, stackTrace, progress) => Text('$error'),
      builder: (context) => c.ready,
    );

Widget _asyncDataScope(_Case c) => AsyncDataScope<String>(
      scopeKey: c.scopeKey,
      scopeKeyTimeout: c.scopeKeyTimeout,
      onScopeKeyTimeout: c.onScopeKeyTimeout,
      initCancellationTimeout: c.initCancellationTimeout,
      onInitCancellationTimeout: c.onInitCancellationTimeout,
      disposeScopeTimeout: c.disposeScopeTimeout,
      onDisposeScopeTimeout: c.onDisposeScopeTimeout,
      waitForChildrenTimeout: c.waitForChildrenTimeout,
      onWaitForChildrenTimeout: c.onWaitForChildrenTimeout,
      pauseAfterInitialization: c.pauseAfterInitialization,
      initData: (context, ctx) async {
        if (c.initGate case final gate?) {
          await gate.future;
        }
        return c.label;
      },
      disposeData: (data) async {
        if (c.disposeGate case final gate?) {
          await gate.future;
        }
      },
      progressBuilder: (context, progress) => const SizedBox.shrink(),
      errorBuilder: (context, error, stackTrace, progress) => Text('$error'),
      builder: (context, data) => c.ready,
    );

Widget _asyncControllerScope(_Case c) => AsyncControllerScope<_Controller>(
      scopeKey: c.scopeKey,
      scopeKeyTimeout: c.scopeKeyTimeout,
      onScopeKeyTimeout: c.onScopeKeyTimeout,
      initCancellationTimeout: c.initCancellationTimeout,
      onInitCancellationTimeout: c.onInitCancellationTimeout,
      disposeScopeTimeout: c.disposeScopeTimeout,
      onDisposeScopeTimeout: c.onDisposeScopeTimeout,
      waitForChildrenTimeout: c.waitForChildrenTimeout,
      onWaitForChildrenTimeout: c.onWaitForChildrenTimeout,
      pauseAfterInitialization: c.pauseAfterInitialization,
      createController: (context) => _Controller(c),
      progressBuilder: (context) => const SizedBox.shrink(),
      errorBuilder: (context, error, stackTrace) => Text('$error'),
      builder: (context, controller) => c.ready,
    );

Widget _liteScope(_Case c) => _LiteFixture(c);

Widget _scope(_Case c) => _ScopeFixture(c);

final class _Controller extends ScopeController {
  final _Case c;

  _Controller(this.c);

  @override
  Future<void> init() async {
    if (c.initGate case final gate?) {
      await gate.future;
    }
  }

  @override
  FutureOr<void> dispose() async {
    if (c.disposeGate case final gate?) {
      await gate.future;
    }
  }
}

final class _LiteFixture extends LiteScope<_LiteFixture, _LiteFixtureState> {
  final _Case c;

  _LiteFixture(this.c)
      : super(
          scopeKey: c.scopeKey,
          scopeKeyTimeout: c.scopeKeyTimeout,
          onScopeKeyTimeout: c.onScopeKeyTimeout,
          initCancellationTimeout: c.initCancellationTimeout,
          onInitCancellationTimeout: c.onInitCancellationTimeout,
          disposeScopeTimeout: c.disposeScopeTimeout,
          onDisposeScopeTimeout: c.onDisposeScopeTimeout,
          waitForChildrenTimeout: c.waitForChildrenTimeout,
          onWaitForChildrenTimeout: c.onWaitForChildrenTimeout,
          pauseAfterInitialization: c.pauseAfterInitialization,
        );

  @override
  Future<void> initScope(ScopeInitContext ctx) async {
    if (c.initGate case final gate?) {
      await gate.future;
    }
  }

  @override
  Widget? buildOnWaiting(BuildContext context) => const SizedBox.shrink();

  @override
  Widget buildOnProgress(BuildContext context, Object? progress) =>
      const SizedBox.shrink();

  @override
  Widget buildOnError(
    BuildContext context,
    Object error,
    StackTrace stackTrace,
    Object? progress,
  ) =>
      Text('$error');

  @override
  Widget? buildOnClosing(BuildContext context) => const Text('closing');

  @override
  _LiteFixtureState createState() => _LiteFixtureState();
}

final class _LiteFixtureState
    extends LiteScopeState<_LiteFixture, _LiteFixtureState> {
  @override
  void initState() {
    super.initState();
    params.c.closeScope = close;
  }

  @override
  Future<void> disposeStateAsync() async {
    if (params.c.disposeGate case final gate?) {
      await gate.future;
    }
  }

  @override
  Widget build(BuildContext context) => params.c.ready;
}

final class _ScopeFixture
    extends Scope<_ScopeFixture, _Deps, _ScopeFixtureState> {
  final _Case c;

  _ScopeFixture(this.c)
      : super(
          scopeKey: c.scopeKey,
          scopeKeyTimeout: c.scopeKeyTimeout,
          onScopeKeyTimeout: c.onScopeKeyTimeout,
          initCancellationTimeout: c.initCancellationTimeout,
          onInitCancellationTimeout: c.onInitCancellationTimeout,
          disposeScopeTimeout: c.disposeScopeTimeout,
          onDisposeScopeTimeout: c.onDisposeScopeTimeout,
          waitForChildrenTimeout: c.waitForChildrenTimeout,
          onWaitForChildrenTimeout: c.onWaitForChildrenTimeout,
          pauseAfterInitialization: c.pauseAfterInitialization,
        );

  @override
  Stream<ScopeInitState<Object, _Deps>> initDependencies(
    BuildContext context,
  ) async* {
    if (c.initGate case final gate?) {
      await gate.future;
    }
    yield ScopeReady(_Deps());
  }

  @override
  Widget buildOnProgress(BuildContext context, Object? progress) =>
      const SizedBox.shrink();

  @override
  Widget buildOnError(
    BuildContext context,
    Object error,
    StackTrace stackTrace,
    Object? progress,
  ) =>
      Text('$error');

  @override
  Widget? buildOnClosing(BuildContext context) => const Text('closing');

  @override
  _ScopeFixtureState createState() => _ScopeFixtureState();
}

final class _Deps implements ScopeDependencies {
  @override
  void onUnmount() {}

  @override
  FutureOr<void> dispose() {}
}

final class _ScopeFixtureState
    extends ScopeState<_ScopeFixture, _Deps, _ScopeFixtureState> {
  @override
  void initState() {
    super.initState();
    params.c.closeScope = close;
  }

  @override
  Future<void> disposeStateAsync() async {
    if (params.c.disposeGate case final gate?) {
      await gate.future;
    }
  }

  @override
  Widget build(BuildContext context) => params.c.ready;
}
