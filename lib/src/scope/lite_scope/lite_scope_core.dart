part of '../scope.dart';

/// A core abstract class for lite scopes, providing minimal dependency
/// injection and state management.
///
/// {@category LiteScope}
abstract base class LiteScopeCore<
    W extends LiteScopeCore<W, E, S>,
    E extends LiteScopeElementBase<W, E, S>,
    S extends LiteScopeCoreState<W, E, S>> extends AsyncScopeCore<W, E> {
  /// Creates the widget half of a lite scope.
  const LiteScopeCore({
    super.key,
    super.tag,
    super.child, // Not used by default. You can use it at your own discretion.
  });

  /// Creates the scope element for this lite scope.
  @override
  E createScopeElement();

  /// Looks up and returns the parameters of the scope [W].
  ///
  /// If [listen] is true, the widget will be rebuilt when the scope changes.
  static W paramsOf<
          W extends LiteScopeCore<W, E, S>,
          E extends LiteScopeElementBase<W, E, S>,
          S extends LiteScopeCoreState<W, E, S>>(
    BuildContext context, {
    required bool listen,
  }) =>
      listen
          ? ScopeContext.select<W, LiteScopeElementBase<W, E, S>, W>(
              context,
              (element) => element.widget,
            )
          : ScopeContext.of<W, LiteScopeElementBase<W, E, S>>(
              context,
              listen: false,
            ).widget;

  /// Selects and returns a specific parameter of the scope [W] using the
  /// [selector] and becomes **dependent** on it.
  static V selectParam<
          W extends LiteScopeCore<W, E, S>,
          E extends LiteScopeElementBase<W, E, S>,
          S extends LiteScopeCoreState<W, E, S>,
          V extends Object?>(
    BuildContext context,
    V Function(W widget) selector,
  ) =>
      ScopeContext.select<W, LiteScopeElementBase<W, E, S>, V>(
        context,
        (element) => selector(element.widget),
      );

  /// Tries to find and return the state [S] of the scope [W] from the given
  /// [context].
  ///
  /// Answers `null` on two conditions, not one: there is no such scope above
  /// [context], or there is one whose state does not exist yet. The state is
  /// created in the ready branch, so a scope still waiting for its `scopeKey`,
  /// still initializing, failed, or taken down by `close()` answers `null`
  /// exactly as an absent scope does. [of] tells the two apart; this does
  /// not.
  static S? maybeOf<
          W extends LiteScopeCore<W, E, S>,
          E extends LiteScopeElementBase<W, E, S>,
          S extends LiteScopeCoreState<W, E, S>>(
    BuildContext context,
  ) =>
      ScopeContext.maybeOf<W, LiteScopeElementBase<W, E, S>>(
        context,
        listen: false,
      )?._globalStateKey.currentState;

  /// Finds and returns the state [S] of the scope [W] from the given
  /// [context].
  ///
  /// Throws on two conditions, not one: there is no such scope above
  /// [context], or there is one whose state does not exist yet. The state is
  /// created in the ready branch, so a scope still waiting for its `scopeKey`,
  /// still initializing, failed, or taken down by `close()` has none to give.
  /// The message says which of the two it was, and what state the scope was
  /// in — read it from below `buildOnReady()`, or check `isInitialized`
  /// first.
  static S of<
          W extends LiteScopeCore<W, E, S>,
          E extends LiteScopeElementBase<W, E, S>,
          S extends LiteScopeCoreState<W, E, S>>(
    BuildContext context,
  ) =>
      ScopeContext.of<W, LiteScopeElementBase<W, E, S>>(
        context,
        listen: false,
      )._stateOrThrow;

  /// Selects and returns a specific value from the state [S] of the scope [W]
  /// using the [selector] and becomes **dependent** on it.
  ///
  /// Reaches the state through the same door as [of], and throws on the same
  /// two conditions.
  static V select<
          W extends LiteScopeCore<W, E, S>,
          E extends LiteScopeElementBase<W, E, S>,
          S extends LiteScopeCoreState<W, E, S>,
          V extends Object?>(
    BuildContext context,
    V Function(S scope) selector,
  ) =>
      ScopeContext.select<W, LiteScopeElementBase<W, E, S>, V>(
        context,
        (element) => selector(element._stateOrThrow),
      );
}

/// The core element base class for [LiteScopeCore].
///
/// Extends [AsyncScopeElementBase] to provide dependency initialization
/// management without strict payload rules.
///
/// {@category LiteScope}
abstract base class LiteScopeElementBase<
    W extends LiteScopeCore<W, E, S>,
    E extends LiteScopeElementBase<W, E, S>,
    S extends LiteScopeCoreState<W, E, S>> extends AsyncScopeElementBase<W, E> {
  var _autoSelfDependence = true;
  final _globalStateKey = GlobalKey<S>();
  S? _state;
  Completer<void>? _closeCompleter;
  Completer<void>? _screenshotCompleter;

  /// Creates the element of a lite scope.
  LiteScopeElementBase(super.widget);

  //
  // Overriding block
  //

  @override
  Stream<AsyncScopeInitState> initScope();

  /// Builds a widget to display while waiting.
  Widget? buildOnWaiting();

  /// Builds a widget to display while the scope is initializing.
  Widget buildOnProgress(Object? progress);

  /// Builds a widget to display if an error occurs during initialization.
  Widget buildOnError(
    Object error,
    StackTrace stackTrace,
    Object? progress,
  );

  /// Creates the state for this scope.
  S createState();

  /// Wraps the state builder with additional widgets, if needed.
  Widget wrapState(Widget child) => child;

  /// Builds a widget to display while the scope is closing.
  Widget? buildOnClosing() => null;

  //
  // End of overriding block
  //

  @override
  @mustCallSuper
  void onUnmount() {
    super.onUnmount();
    _state?.onUnmount();
  }

  @override
  @mustCallSuper
  Future<void> disposeScope() async {
    if (_state case final state?) {
      await state._performAsyncDispose();
    }
  }

  @override
  @mustCallSuper
  void dispose() {
    // The element is leaving the tree, so [buildOnReady] will never run again
    // and the [ScreenshotReplacer] that releases the screenshot barrier will
    // never be mounted (or is being unmounted right now). Release the barrier
    // here, otherwise an in-flight [close] would wait for it forever.
    _completeScreenshot();
    super.dispose();
  }

  /// Releases the screenshot barrier awaited by [_performAsyncDispose].
  void _completeScreenshot() {
    if (_screenshotCompleter case final screenshotCompleter?
        when !screenshotCompleter.isCompleted) {
      screenshotCompleter.complete();
    }
  }

  /// The state this scope built, or a failure that says why there is none.
  ///
  /// The state lives in the widget `buildOnReady()` mounts, so it exists only
  /// while the scope is [AsyncScopeReady] -- not while it waits for a
  /// `scopeKey`, not while it initializes, not after that failed, and not
  /// once a `close()` has taken the subtree down. A bare `!` answered all of
  /// those with `Null check operator used on a null value`, which names
  /// neither the scope nor the phase it was in.
  S get _stateOrThrow =>
      _globalStateKey.currentState ??
      (throw StateError(
        '${widget.toStringShort()} was found, but it has no state: the state '
        'is created in the ready branch, and this scope is ${model.state}. '
        'Read it from below `buildOnReady()`, or check `isInitialized` first. '
        '`maybeOf` answers `null` here too, the same as when there is no such '
        'scope at all.',
      ));

  @override
  bool get autoSelfDependence => _autoSelfDependence;

  @override
  Widget buildOnState(AsyncScopeState state) => switch (state) {
        AsyncScopeWaiting() => buildOnWaiting() ?? buildOnProgress(null),
        AsyncScopeProgress() => buildOnProgress(state.progress),
        AsyncScopeReady() => buildOnReady(),
        AsyncScopeError() =>
          buildOnError(state.error, state.stackTrace, state.progress),
      };

  /// Builds the ready branch, the state and its wrapper.
  ///
  /// From here on a notification no longer rebuilds the subtree.
  ///
  /// While a [close] is running this branch also carries the closing screen,
  /// and the whole of it is guarded: the barrier [close] waits on is released
  /// by the [ScreenshotReplacer] this build mounts, so a build that does not
  /// finish is a teardown that never begins — not four stages skipped, but
  /// the whole of it, the `scopeKey` and the registration with the parent
  /// included. The failure still surfaces, as the [ErrorWidget] any failing
  /// build turns into; what it no longer takes with it is the teardown behind
  /// it.
  @mustCallSuper
  Widget buildOnReady() {
    _autoSelfDependence = false;

    Widget buildState() => wrapState(
          _LiteScopeCoreWidget<W, E, S>(
            key: _globalStateKey,
            createState: _createState,
          ),
        );

    if (_screenshotCompleter == null) {
      return buildState();
    }

    try {
      return Stack(
        // Not the default `AlignmentDirectional.topStart`, which a bare
        // `Stack` resolves through a `Directionality` *above* itself. A scope
        // at the root of the application builds the app inside each of its
        // branches -- the shape the topic and `example/minimal` teach -- so
        // every `Directionality` in the tree is below this point and there is
        // nothing here to resolve against: the first rebuild after `close()`
        // threw while this `Stack` was being mounted. Nothing is aligned
        // either way, the one child that is not positioned being what the
        // stack takes its size from.
        alignment: Alignment.topLeft,
        children: [
          ScreenshotReplacer(
            onCompleted: _completeScreenshot,
            child: buildState(),
          ),
          Positioned.fill(
            child: buildOnClosing() ??
                ColoredBox(
                  color:
                      Theme.of(this).colorScheme.surface.withValues(alpha: 0.8),
                  child: const Center(
                    child: CircularProgressIndicator.adaptive(),
                  ),
                ),
          ),
        ],
      );
      // ignore: avoid_catching_errors
    } on Object {
      _completeScreenshot();

      rethrow;
    }
  }

  S _createState() => _state = createState().._scopeElement = this as E;

  @override
  Future<void> _performAsyncDispose() {
    // There is one disposal run per element, and every caller -- an explicit
    // [close], a concurrent one, the implicit disposal on unmount -- must
    // observe its outcome. Completing the shared completer *with the run
    // itself* hands the same value, or the same error and stack trace, to all
    // of them alike: a failure the first caller sees is never reported as a
    // success to the next one.
    if (_closeCompleter case final closeCompleter?) {
      return closeCompleter.future;
    }

    // Installed before the run starts, so a caller arriving while the run is
    // still synchronous joins it instead of starting a second one.
    final closeCompleter = Completer<void>();
    _closeCompleter = closeCompleter;
    closeCompleter.complete(_runAsyncDispose());

    return closeCompleter.future;
  }

  Future<void> _runAsyncDispose() async {
    if (_screenshotCompleter case final screenshotCompleter?) {
      // The barrier is released by the [ScreenshotReplacer] that
      // [buildOnReady] mounts, and this is the rebuild that has to mount it.
      // A [notifyDependents] left pending by the scope asks the next rebuild
      // to skip the subtree, so `updateChild` would return the old child and
      // throw away the widget [buildOnReady] just built -- the replacer would
      // never be mounted, nothing would release the barrier, and a scope
      // closed in place stays mounted, so the [dispose] fallback would not run
      // either. `_forceRebuild` is what says the subtree has to be rebuilt
      // anyway; `notifyClients` still runs, so the pending notification is not
      // lost.
      _forceRebuild = true;
      markNeedsBuild();

      await screenshotCompleter.future;
    } else {
      markNeedsBuild();
    }

    await super._performAsyncDispose();
  }

  /// Closes the scope before the disposal occurs.
  ///
  /// Allows displaying a scope closing screen, optionally replacing the
  /// internal widget with a screenshot.
  Future<void> close() async {
    // The screenshot barrier is released by the [ScreenshotReplacer] that
    // [buildOnReady] mounts, and [buildOnState] only calls [buildOnReady] for
    // [AsyncScopeReady]. In any other state -- or when the element is no
    // longer in the tree -- nothing would ever release the barrier, so
    // installing it would make this future hang forever.
    //
    // The barrier is installed at most once per element: a repeated [close]
    // must not replace the barrier that the already running
    // [_performAsyncDispose] is waiting for, otherwise [_completeScreenshot]
    // would release the new one and orphan the old one.
    if (mounted && state is AsyncScopeReady) {
      _screenshotCompleter ??= Completer<void>();
    }

    await _performAsyncDispose();
  }
}

/// The state implementation for [LiteScopeCore].
final class _LiteScopeCoreWidget<
    W extends LiteScopeCore<W, E, S>,
    E extends LiteScopeElementBase<W, E, S>,
    S extends LiteScopeCoreState<W, E, S>> extends StatefulWidget {
  final S Function() _createState;

  const _LiteScopeCoreWidget({
    required GlobalKey<S> super.key,
    required S Function() createState,
  }) : _createState = createState;

  @override
  S createState() => _createState();

  @override
  String toStringShort() => '$S';
}

/// The core state base class for [LiteScopeCore].
///
/// {@category LiteScope}
abstract base class LiteScopeCoreState<
        W extends LiteScopeCore<W, E, S>,
        E extends LiteScopeElementBase<W, E, S>,
        S extends LiteScopeCoreState<W, E, S>>
    extends State<_LiteScopeCoreWidget<W, E, S>> {
  //
  // Overriding block
  //

  /// Initializes the scope asynchronously.
  FutureOr<void> initStateAsync() {}

  /// Lets go of whatever cannot wait for [disposeStateAsync].
  ///
  /// Cancel subscriptions and detach listeners here — everything that must
  /// stop reaching a scope on its way out. It runs exactly once, always before
  /// [disposeStateAsync], whether the scope was removed from the tree or closed
  /// with [close].
  ///
  /// **[State.dispose] is not part of that order.** It belongs to Flutter, not
  /// to the scope: on removal the framework calls it before the scope's
  /// teardown even begins, and after a [close] it does not run until the tree
  /// comes down — which may be much later, or never, while the closing screen
  /// is on show. The synchronous half of a scope's teardown therefore goes
  /// here, not there.
  ///
  /// The [BuildContext] is gone by the time this runs on a removed scope, so
  /// it may only touch what the state holds in its own fields.
  @mustCallSuper
  void onUnmount() {}

  /// Disposes of the scope asynchronously.
  FutureOr<void> disposeStateAsync() {}

  /// Sealed on purpose: put the teardown in [onUnmount] and [disposeStateAsync].
  ///
  /// [State.dispose] belongs to Flutter and lands on either side of a scope's
  /// teardown depending on how the scope went — before all of it when the tree
  /// took the scope down, and not until the tree comes down after a [close],
  /// which may be much later or never while the closing screen is on show.
  /// Nothing a scope has to let go of can be released on a schedule like that,
  /// so this is not a hook to write in.
  @nonVirtual
  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context);

  //
  // End of overriding block
  //

  /// Disposal may begin before the end of asynchronous initialization.
  /// Therefore, we use [_initCompleter] for synchronization.
  ///
  /// It is settled when the initialization *ends*, successfully or not:
  /// [_performAsyncDispose] waits for it, and a failure that left it unsettled
  /// would keep the scope from ever being disposed of. Whether the
  /// initialization actually worked is [_initSucceeded].
  final _initCompleter = Completer<void>();

  /// Whether [initStateAsync] has completed successfully.
  bool _initSucceeded = false;

  late final E _scopeElement;

  /// Not the widget of this state, and there is none to hand back.
  ///
  /// A scope state is not driven by a `StatefulWidget` of its own: the widget
  /// this state belongs to is the scope, its parameters are on that scope, and
  /// [params] is how to read them. `State.widget` is part of the contract this
  /// class has to satisfy all the same, so it is here — and it refuses out
  /// loud rather than handing back something that only looks right.
  ///
  /// Anything mixed into a scope state that reads `widget` lands here: a
  /// `State` mixin written for ordinary widgets, most likely. Read [params]
  /// instead, or keep what the mixin needs in a field of its own.
  @nonVirtual
  @override
  Never get widget => throw UnsupportedError(
        'A scope state has no widget of its own. The parameters of the scope '
        'are on the scope widget; read them through `params`.',
      );

  /// The parameters defined in the associated scope widget.
  W get params => _scopeElement.widget;

  /// Whether the scope initialization is fully completed.
  bool get isInitialized => _initSucceeded;

  @override
  @mustCallSuper
  void initState() {
    super.initState();
    _performAsyncInit(); // ignore: discarded_futures
  }

  Future<void> _performAsyncInit() async {
    try {
      final result = initStateAsync();
      if (result is Future<void>) {
        await result;
        _completeInit();
      } else {
        SchedulerBinding.instance.runOutsideFrame(_completeInit);
      }
    } on Object {
      // This future is discarded by `initState`, so nothing else ever settles
      // the completer: leaving it unsettled would park [_performAsyncDispose]
      // -- and the `close()` that waits for it -- forever. The error is
      // re-thrown untouched, so it still surfaces as an uncaught error of the
      // zone the build ran in.
      if (!_initCompleter.isCompleted) {
        _initCompleter.complete();
      }
      rethrow;
    }
  }

  void _completeInit() {
    _initSucceeded = true;
    _initCompleter.complete();
    if (mounted) {
      onInitialized();
      notifyDependents();
    }
  }

  Future<void> _performAsyncDispose() async {
    if (!_initCompleter.isCompleted) {
      await _initCompleter.future;
    }

    // Nothing was initialized, so there is nothing to dispose of -- the same
    // rule `AsyncScopeElementBase` applies to its own `disposeStateAsync`.
    if (!_initSucceeded) {
      return;
    }

    final result = disposeStateAsync();
    if (result is Future<void>) {
      await result;
    }
  }

  /// Called after the state has been successfully initialized.
  void onInitialized() {}

  /// Rebuilds the descendants subscribed to a value that changed.
  @mustCallSuper
  void notifyDependents() {
    _scopeElement.notifyDependents();
  }

  /// Closes the scope gracefully.
  ///
  /// The element is the one this state was made for, taken from the field it
  /// was handed at creation rather than looked up through [context]. A lookup
  /// answers the *nearest* scope of this type, which is not necessarily this
  /// one -- a `wrapState` that puts another scope of the same type around the
  /// state is enough to shadow it -- and it answers nothing at all once the
  /// state has been unmounted, where closing a scope that is already gone
  /// should cost nothing.
  Future<void> close() => _scopeElement.close();
}
