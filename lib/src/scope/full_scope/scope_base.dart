part of '../scope.dart';

/// A function that initializes scope dependencies and returns them.
///
/// The progress goes through [ScopeInitContext.progress], which is why there
/// is no type argument for it here.
///
/// {@category Scope}
typedef ScopeInitCallback<D extends ScopeDependencies> = Future<D> Function(
  BuildContext context,
  ScopeInitContext ctx,
);

/// A builder function used to display a waiting widget while the [Scope] is
/// waiting for a [Scope.scopeKey] and [Scope.initDependencies] to send their
/// first state.
///
/// {@category Scope}
typedef ScopeWaitingBuilder = Widget? Function(BuildContext context);

/// A builder function used to display a widget while the [Scope] is
/// initializing dependencies.
///
/// Contains optional [progress] data dynamically yielded during
/// initialization.
///
/// {@category Scope}
typedef ScopeProgressBuilder<P extends Object> = Widget Function(
  BuildContext context,
  P? progress,
);

/// A builder function used to display an error widget if scope initialization
/// fails.
///
/// {@category Scope}
typedef ScopeErrorBuilder<P extends Object> = Widget Function(
  BuildContext context,
  Object error,
  StackTrace stackTrace,
  P? progress,
);

/// A base class for creating scopes with dependency injection and state
/// management.
///
/// Extends [ScopeCore] to provide lifecycle, initialization, and configuration
/// handling.
///
/// {@category Scope}
abstract base class Scope<W extends Scope<W, D, S>, D extends ScopeDependencies,
        S extends ScopeState<W, D, S>>
    extends ScopeCore<W, _ScopeElement<W, D, S>, D, S> {
  /// A key used to synchronize the initialization of the scope.
  final Object? scopeKey;

  /// How long to wait for [scopeKey]; `null` takes the default.
  ///
  /// Defaults to [ScopeConfig.defaultScopeKeyTimeout]; [ScopeTimeout.none]
  /// removes the limit for this scope alone.
  final Duration? scopeKeyTimeout;

  /// Called when the wait for [scopeKey] expires.
  ///
  /// The expiry is reported through [FlutterError.reportError] either way,
  /// and the scope proceeds as if the wait had succeeded.
  final void Function()? onScopeKeyTimeout;

  /// How long the teardown waits for the initialization to be cancelled;
  /// `null` takes the default.
  ///
  /// Defaults to [ScopeConfig.defaultInitCancellationTimeout]. This is the one
  /// timeout that refuses [ScopeTimeout.none], with an assert: a cancellation
  /// waits for a generator to run out, and one suspended on a future that
  /// never completes never does. Removing this limit is a decision for the
  /// whole application, and it is made there.
  final Duration? initCancellationTimeout;

  /// Called when the wait for the cancellation expires.
  ///
  /// The expiry is reported through [FlutterError.reportError] either way,
  /// and the teardown goes on without the initialization.
  final void Function()? onInitCancellationTimeout;

  /// How long to wait for each half of the teardown; `null` takes the default.
  ///
  /// Defaults to [ScopeConfig.defaultDisposeScopeTimeout]; [ScopeTimeout.none]
  /// removes the limit for this scope alone. There are two halves behind it —
  /// `disposeStateAsync` of the state, and then the disposal of the dependency
  /// container — and each is bounded by this on its own, so a teardown where
  /// both hang reports two expiries.
  final Duration? disposeScopeTimeout;

  /// Called when the wait for the teardown expires.
  ///
  /// The expiry is reported through [FlutterError.reportError] either way,
  /// and the release goes on without waiting for the step to finish.
  final void Function()? onDisposeScopeTimeout;

  /// How long to wait for the child scopes; `null` takes the default.
  ///
  /// Defaults to [ScopeConfig.defaultWaitForChildrenTimeout];
  /// [ScopeTimeout.none] removes the limit for this scope alone.
  final Duration? waitForChildrenTimeout;

  /// Called when the wait for the child scopes expires.
  ///
  /// The expiry is reported through [FlutterError.reportError] either way,
  /// and the teardown goes on without the children that never finished.
  final void Function()? onWaitForChildrenTimeout;

  /// An optional duration to pause after initialization is successful.
  ///
  /// [ScopeTimeout.none] is refused here, with an assert: a pause is a
  /// stretch of time to hold the ready branch back for rather than a limit
  /// on a wait, and "wait as long as it takes" has nothing to say about one.
  final Duration? pauseAfterInitialization;

  /// Creates a scope.
  const Scope({
    super.key,
    super.tag,
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
    super.child, // Not used by default. You can use it at your own discretion.
  });

  /// Initializes the scope's dependencies and streams the initialization
  /// state.
  Future<D> initDependencies(BuildContext context, ScopeInitContext ctx);

  /// Builds a widget to display while waiting for [scopeKey] and
  /// [initDependencies] to send their first state.
  Widget? buildOnWaiting(BuildContext context) => null;

  /// Builds a widget to display while the scope is initializing dependencies.
  Widget buildOnProgress(BuildContext context, Object? progress);

  /// Builds a widget to display if an error occurs during initialization.
  Widget buildOnError(
    BuildContext context,
    Object error,
    StackTrace stackTrace,
    Object? progress,
  );

  /// Creates the state for this scope.
  S createState();

  /// Wraps the state builder with additional widgets, if needed.
  Widget wrapState(BuildContext context, D dependencies, Widget child) => child;

  /// Builds a widget to display while the scope is closing.
  Widget? buildOnClosing(BuildContext context) => null;

  @override
  // ignore: library_private_types_in_public_api
  _ScopeElement<W, D, S> createScopeElement() => _ScopeElement(this as W);

  /// Looks up and returns the parameters of the scope [W].
  ///
  /// If [listen] is true, the widget will be rebuilt when the scope changes.
  static W paramsOf<W extends Scope<W, D, S>, D extends ScopeDependencies,
          S extends ScopeState<W, D, S>>(
    BuildContext context, {
    required bool listen,
  }) =>
      listen
          ? ScopeContext.select<W, _ScopeElement<W, D, S>, W>(
              context,
              (element) => element.widget,
            )
          : ScopeContext.of<W, _ScopeElement<W, D, S>>(
              context,
              listen: false,
            ).widget;

  /// Selects and returns a specific parameter of the scope [W] using the
  /// [selector] and becomes **dependent** on it.
  static V selectParam<W extends Scope<W, D, S>, D extends ScopeDependencies,
          S extends ScopeState<W, D, S>, V extends Object?>(
    BuildContext context,
    V Function(W widget) selector,
  ) =>
      ScopeContext.select<W, _ScopeElement<W, D, S>, V>(
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
  static S? maybeOf<W extends Scope<W, D, S>, D extends ScopeDependencies,
          S extends ScopeState<W, D, S>>(BuildContext context) =>
      ScopeContext.maybeOf<W, _ScopeElement<W, D, S>>(
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
  static S of<W extends Scope<W, D, S>, D extends ScopeDependencies,
          S extends ScopeState<W, D, S>>(BuildContext context) =>
      ScopeContext.of<W, _ScopeElement<W, D, S>>(
        context,
        listen: false,
      )._stateOrThrow;

  /// Selects and returns a specific value from the state [S] of the scope [W]
  /// using the [selector] and becomes **dependent** on it.
  ///
  /// Reaches the state through the same door as [of], and throws on the same
  /// two conditions.
  static V select<W extends Scope<W, D, S>, D extends ScopeDependencies,
          S extends ScopeState<W, D, S>, V extends Object?>(
    BuildContext context,
    V Function(S scope) selector,
  ) =>
      ScopeContext.select<W, _ScopeElement<W, D, S>, V>(
        context,
        (element) => selector(element._stateOrThrow),
      );
}

/// The default element underlying [Scope].
final class _ScopeElement<W extends Scope<W, D, S>, D extends ScopeDependencies,
        S extends ScopeState<W, D, S>>
    extends ScopeElementBase<W, _ScopeElement<W, D, S>, D, S> {
  _ScopeElement(super.widget);

  @override
  Object? get scopeKey => widget.scopeKey;

  @override
  Duration? get scopeKeyTimeout => widget.scopeKeyTimeout;

  @override
  void onScopeKeyTimeout() => widget.onScopeKeyTimeout?.call();

  @override
  Duration? get initCancellationTimeout => widget.initCancellationTimeout;

  @override
  void onInitCancellationTimeout() => widget.onInitCancellationTimeout?.call();

  @override
  Duration? get disposeScopeTimeout => widget.disposeScopeTimeout;

  @override
  void onDisposeScopeTimeout() => widget.onDisposeScopeTimeout?.call();

  @override
  Duration? get waitForChildrenTimeout => widget.waitForChildrenTimeout;

  @override
  void onWaitForChildrenTimeout() => widget.onWaitForChildrenTimeout?.call();

  @override
  Duration? get pauseAfterInitialization => widget.pauseAfterInitialization;

  @override
  Future<D> initDependencies(ScopeInitContext ctx) =>
      widget.initDependencies(this, ctx);

  @override
  Widget? buildOnWaiting() => widget.buildOnWaiting(this);

  @override
  Widget buildOnProgress(Object? progress) =>
      widget.buildOnProgress(this, progress);

  @override
  Widget buildOnError(
    Object error,
    StackTrace stackTrace,
    Object? progress,
  ) =>
      widget.buildOnError(this, error, stackTrace, progress);

  @override
  S createState() => widget.createState();

  @override
  Widget wrapState(Widget child) => widget.wrapState(this, dependencies, child);

  @override
  Widget? buildOnClosing() => widget.buildOnClosing(this);
}

/// The state implementation for [Scope].
///
/// Extends [ScopeCoreState] to give convenient access to the [dependencies].
///
/// {@category Scope}
abstract base class ScopeState<W extends Scope<W, D, S>,
        D extends ScopeDependencies, S extends ScopeState<W, D, S>>
    extends ScopeCoreState<W, _ScopeElement<W, D, S>, D, S> {
  //
  // Overriding block
  //

  @override
  FutureOr<void> initStateAsync() {}

  @override
  FutureOr<void> disposeStateAsync() {}

  @override
  Widget build(BuildContext context);

  //
  // End of overriding block
  //

  /// The parameters defined in the associated scope widget.
  @override
  W get params;

  /// Whether the scope initialization is fully completed.
  @override
  bool get isInitialized;

  /// Called after the state has been successfully initialized.
  @override
  void onInitialized();

  @override
  void notifyDependents();

  /// Closes the scope gracefully.
  @override
  Future<void> close();
}

/// The five accessors of one [Scope], with its type arguments named once.
///
/// A scope hands its state and its parameters to descendants through five
/// static methods of [Scope], and every one of them wants the whole triple —
/// `Scope.select<App, AppDependencies, AppState, V>(context, selector)`. Written
/// out as static members of the scope, as they were, that is five wrappers of
/// three lines each, and the triple is repeated in every one of them.
///
/// This is the same five, with the triple given once:
///
/// ```dart
/// final class App extends Scope<App, AppDependencies, AppState> {
///   static const access = ScopeAccess<App, AppDependencies, AppState>();
///   …
/// }
///
/// // and from a descendant:
/// final counter = App.access.select(context, (state) => state.counter);
/// ```
///
/// It holds nothing and does nothing of its own: every method below is the
/// static of the same name, called with the arguments this object carries. Use
/// it or write the wrappers by hand — the two are the same thing, and a scope
/// that wants accessors under different names still writes them.
///
/// {@category Scope}
final class ScopeAccess<W extends Scope<W, D, S>, D extends ScopeDependencies,
    S extends ScopeState<W, D, S>> {
  /// Creates an accessor for the scope [W].
  const ScopeAccess();

  /// Finds and returns the state of the scope, or throws.
  ///
  /// See [Scope.of] for what it throws on.
  S of(BuildContext context) => Scope.of<W, D, S>(context);

  /// Tries to find and return the state of the scope.
  ///
  /// See [Scope.maybeOf] for the two conditions it answers `null` on.
  S? maybeOf(BuildContext context) => Scope.maybeOf<W, D, S>(context);

  /// Selects a value from the state and **subscribes** to it.
  V select<V extends Object?>(
    BuildContext context,
    V Function(S state) selector,
  ) =>
      Scope.select<W, D, S, V>(context, selector);

  /// Returns the parameters of the scope — the scope widget itself.
  W paramsOf(BuildContext context, {required bool listen}) =>
      Scope.paramsOf<W, D, S>(context, listen: listen);

  /// Selects a single parameter of the scope and **subscribes** to it.
  V selectParam<V extends Object?>(
    BuildContext context,
    V Function(W widget) selector,
  ) =>
      Scope.selectParam<W, D, S, V>(context, selector);
}
