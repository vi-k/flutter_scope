part of '../scope.dart';

/// A core abstract class for lite scopes, providing minimal dependency
/// injection and state management.
///
/// {@category LiteScope}
abstract base class LiteScopeCore<
    W extends LiteScopeCore<W, E, S>,
    E extends LiteScopeElementBase<W, E, S>,
    S extends LiteScopeCoreState<W, E, S>> extends AsyncScopeCore<W, E> {
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
  /// Returns `null` if the scope is not found.
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
  /// Throws an error if the scope is not found.
  static S of<
          W extends LiteScopeCore<W, E, S>,
          E extends LiteScopeElementBase<W, E, S>,
          S extends LiteScopeCoreState<W, E, S>>(
    BuildContext context,
  ) =>
      ScopeContext.of<W, LiteScopeElementBase<W, E, S>>(
        context,
        listen: false,
      )._globalStateKey.currentState!;

  /// Selects and returns a specific value from the state [S] of the scope [W]
  /// using the [selector] and becomes **dependent** on it.
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
        (element) => selector(element._globalStateKey.currentState!),
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

  LiteScopeElementBase(super.widget);

  //
  // Overriding block
  //

  @override
  Stream<AsyncScopeInitState> initAsync();

  /// Builds a widget to display while waiting.
  Widget? buildOnWaiting();

  /// Builds a widget to display while the scope is initializing.
  Widget buildOnInitializing(Object? progress);

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
  Future<void> disposeAsync() async {
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

  @override
  bool get autoSelfDependence => _autoSelfDependence;

  @override
  Widget buildOnState(AsyncScopeState state) => switch (state) {
        AsyncScopeWaiting() => buildOnWaiting() ?? buildOnInitializing(null),
        AsyncScopeProgress() => buildOnInitializing(state.progress),
        AsyncScopeReady() => buildOnReady(),
        AsyncScopeError() =>
          buildOnError(state.error, state.stackTrace, state.progress),
      };

  @mustCallSuper
  Widget buildOnReady() {
    _autoSelfDependence = false;

    final child = wrapState(
      _LiteScopeCoreWidget<W, E, S>(
        key: _globalStateKey,
        createState: _createState,
      ),
    );

    return switch (_screenshotCompleter) {
      null => child,
      _ => Stack(
          children: [
            ScreenshotReplacer(
              onCompleted: _completeScreenshot,
              child: child,
            ),
            Positioned.fill(
              child: buildOnClosing() ??
                  ColoredBox(
                    color: Theme.of(this)
                        .colorScheme
                        .surface
                        .withValues(alpha: 0.8),
                    child: const Center(
                      child: CircularProgressIndicator.adaptive(),
                    ),
                  ),
            ),
          ],
        ),
    };
  }

  S _createState() => _state = createState().._scopeElement = this as E;

  @override
  Future<void> _performAsyncDispose() async {
    if (_closeCompleter case final closeCompleter?) {
      return closeCompleter.future;
    }

    final closeCompleter = Completer<void>();
    _closeCompleter = closeCompleter;

    markNeedsBuild();

    if (_screenshotCompleter case final screenshotCompleter?) {
      await screenshotCompleter.future;
    }

    try {
      await super._performAsyncDispose();
    } finally {
      closeCompleter.complete();
    }
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
    if (mounted && state is AsyncScopeReady) {
      _screenshotCompleter = Completer<void>();
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
abstract base class LiteScopeCoreState<
        W extends LiteScopeCore<W, E, S>,
        E extends LiteScopeElementBase<W, E, S>,
        S extends LiteScopeCoreState<W, E, S>>
    extends State<_LiteScopeCoreWidget<W, E, S>> {
  //
  // Overriding block
  //

  /// Initializes the scope asynchronously.
  FutureOr<void> initAsync() {}

  /// Disposes of the scope asynchronously.
  FutureOr<void> disposeAsync() {}

  @override
  Widget build(BuildContext context);

  //
  // End of overriding block
  //

  final _initCompleter = Completer<void>();
  late final E _scopeElement;

  @override
  @visibleForTesting
  Never get widget => throw UnimplementedError();

  /// The parameters defined in the associated scope widget.
  W get params => _scopeElement.widget;

  /// Whether the scope initialization is fully completed.
  bool get isInitialized => _initCompleter.isCompleted;

  @override
  @mustCallSuper
  void initState() {
    super.initState();
    _performAsyncInit(); // ignore: discarded_futures
  }

  Future<void> _performAsyncInit() async {
    final result = initAsync();
    if (result is Future<void>) {
      await result;
      _initCompleter.complete();
      if (mounted) {
        onInitialized();
        notifyDependents();
      }
    } else {
      SchedulerBinding.instance.runOutsideFrame(() {
        _initCompleter.complete();
        if (mounted) {
          onInitialized();
          notifyDependents();
        }
      });
    }
  }

  Future<void> _performAsyncDispose() async {
    if (!_initCompleter.isCompleted) {
      await _initCompleter.future;
    }

    final result = disposeAsync();
    if (result is Future<void>) {
      await result;
    }
  }

  /// Called after the state has been successfully initialized.
  void onInitialized() {}

  @mustCallSuper
  void notifyDependents() {
    _scopeElement.notifyDependents();
  }

  /// Closes the scope gracefully.
  Future<void> close() => ScopeContext.of<W, E>(context, listen: false).close();
}
