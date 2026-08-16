part of '../scope.dart';

/// An object with a lifecycle of its own, owned by a scope.
///
/// The three methods the scope calls are sealed, so a controller never has to
/// remember to chain to `super`: [performInit] runs [init], [performUnmount]
/// runs [onUnmount] once, and [performDispose] runs what is left of the
/// teardown and then [dispose]. Everything a controller has to write is in the
/// three hooks below them.
///
/// A controller can also be driven by hand -- in a test, say -- by calling the
/// same three methods in that order.
///
/// {@category AsyncControllerScope}
abstract base class ScopeController {
  bool _mounted = false;
  bool _initStarted = false;

  /// The one teardown run, installed by the first [performDispose].
  ///
  /// Its presence is also what says the controller has been let go of, so
  /// there is nothing else to keep in step with it.
  Completer<void>? _disposeCompleter;

  /// Whether the controller is between the start of its initialization and
  /// the moment it was let go of.
  ///
  /// What to check after every `await` inside [init]: the scope may have gone
  /// while the initialization was suspended.
  bool get mounted => _mounted;

  /// Runs [init], once. Called by the scope.
  ///
  /// A second call does nothing, and neither does one after [performDispose]:
  /// the three methods are a one-way sequence, and a controller that has been
  /// let go of is not brought back — [init] would run against whatever
  /// [dispose] has already released.
  @nonVirtual
  Future<void> performInit() async {
    if (_initStarted || _disposeCompleter != null) {
      return;
    }

    _initStarted = true;
    _mounted = true;
    await init();
  }

  /// Runs [onUnmount], once. Called by the scope.
  @nonVirtual
  void performUnmount() {
    if (!_mounted) {
      return;
    }

    _mounted = false;
    onUnmount();
  }

  /// Runs what is left of the teardown and then [dispose], once.
  ///
  /// Called by the scope. [onUnmount] runs first when it has not run yet, so
  /// the two always arrive in that order.
  ///
  /// There is one teardown run per controller, and every caller observes its
  /// outcome: a second call joins the run that is already going rather than
  /// returning at once and reporting a teardown that is still running as one
  /// that is over. A failure the first caller sees is a failure the second one
  /// sees too.
  @nonVirtual
  Future<void> performDispose() {
    if (_disposeCompleter case final completer?) {
      return completer.future;
    }

    // Installed before the run starts, so a caller arriving while the run is
    // still synchronous joins it instead of starting a second one.
    final completer = Completer<void>();
    _disposeCompleter = completer;
    completer.complete(_runDispose());

    return completer.future;
  }

  Future<void> _runDispose() async {
    performUnmount();
    await dispose();
  }

  /// Acquires whatever the controller needs; awaited.
  ///
  /// A failure here is terminal: the scope shows its error branch, and the
  /// controller is unmounted and disposed of anyway.
  Future<void> init() async {}

  /// Lets go of whatever cannot wait for [dispose].
  ///
  /// Synchronous, and always before [dispose]. Cancel subscriptions and detach
  /// listeners here.
  void onUnmount() {}

  /// Releases what [init] acquired; awaited.
  ///
  /// Runs on every path, including the one where [init] failed halfway, so it
  /// has to expect a partially initialized controller.
  FutureOr<void> dispose() {}
}
