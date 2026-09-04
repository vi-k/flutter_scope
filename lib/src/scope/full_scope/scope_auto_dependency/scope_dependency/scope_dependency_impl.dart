part of '../../../scope.dart';

/// {@category Scope}
final class _ScopeDependencyImpl with ScopeDependencyMixin {
  @override
  final String name;

  @override
  final int count = 1;

  final FutureOr<void> Function(ScopeDependencyHandle dep) _init;
  ScopeDependencyHandle? _helper;

  _ScopeDependencyImpl(this.name, this._init)
      : assert(name.isNotEmpty, 'The dependency name cannot be empty');

  /// Whether this dependency is holding something that has to be given back.
  ///
  /// The question is what the initializer took, not how it ended. An
  /// initializer that acquired a resource and registered its disposer keeps
  /// that resource whether it then succeeded, failed or was cancelled — and the
  /// promise is to release everything that was created. Asking the state
  /// instead let a failure keep whatever it had already taken.
  ///
  /// [ScopeDependencyHandle.unmount] counts as much as `dispose`: it is the
  /// other documented way of holding something — a subscription, usually — and
  /// a hook that still has to run is a thing to hold on to. Asked about
  /// `dispose` alone, a bare leaf standing as the root of a container said it
  /// held nothing, and the next `init()` replaced it in silence: the `unmount`
  /// of the first run was never called at all.
  @override
  bool get disposalRequired =>
      !_isDisposalDone &&
      (_helper?.dispose != null || _helper?.unmount != null);

  @override
  Future<void> _runInit(
    ScopeInitContext ctx,
    void Function(String path) onStep,
  ) async {
    // First of all, before the handle and before the initializer: the promise
    // is that this is out before the step awaits anything, so that a step
    // which never comes back is still the last one announced. Nothing between
    // here and the initializer waits for anything.
    _onStepStarted?.call(name);
    final helper = _helper = ScopeDependencyHandle._(this);
    final result = _init(helper);
    if (result is Future<void>) {
      await result;
    }
    onStep(name);
  }

  /// Runs the registered `unmount` hook, and only ever the first time.
  ///
  /// The hook is taken off the helper before it is called, so "exactly once"
  /// holds by construction rather than by which paths happen to reach here.
  /// There is more than one: a scope removed from the tree unmounts its
  /// container through the element, a scope whose initialization failed never
  /// gets that far and is unmounted from inside `ScopeAutoDependencies.init`,
  /// and a container held by hand can be unmounted by its owner. Clearing the
  /// hook after `dispose` would not be enough either — a dependency that
  /// registered `unmount` and no `dispose` keeps its helper through the
  /// disposal.
  @override
  void onUnmount() {
    final unmount = _helper?.unmount;
    _helper?.unmount = null;
    unmount?.call();
  }

  @override
  Future<void> _runDispose(void Function(String path) onStep) async {
    final helper = _helper;
    final disposer = helper?.dispose;
    if (helper == null || disposer == null) {
      return;
    }

    // Taken off before it is called, the way [onUnmount] above takes its own
    // hook off, and for the same reason: "exactly once" then holds by
    // construction rather than by which caller happens to arrive first. Left
    // in place until the `finally`, as it was, the clearing came *after* the
    // `await`, so a second `dispose()` arriving while the first was parked on
    // the disposer read the same hook and ran it a second time — a second
    // rollback, a second close, a second write.
    //
    // The hook alone: the handle itself is what answers `dep.name`, which the
    // disposer may well read, and it is let go of below.
    helper.dispose = null;

    // After the early return above, not before it: a dependency that
    // registered only an `unmount` is still walked -- `disposalRequired`
    // counts that hook as much as a disposer, and it is right to -- but it
    // has no release to run and yields nothing. Announced from the top of
    // this method it would have been an entry with no exit behind it, which
    // is precisely the shape a reader takes for a release that hung.
    _onDisposalStepStarted?.call(name);

    try {
      final result = disposer();
      if (result is Future<void>) {
        await result;
      }

      // The exit before the step is reported onwards, which is the order the
      // pair is read in: an entry with no exit means a release that hung, and
      // a disposer that finished must never look like one.
      _onDisposalStepEnded?.call(name);
      onStep(name);
      // ignore: avoid_catching_errors
    } on Object catch (error, stackTrace) {
      // The third thing an entry can end with, and now the only other one: a
      // teardown is not cancelled, so a throw is all that is left.
      _onDisposalStepFailed?.call(name, error, stackTrace);
      rethrow;
    } finally {
      _helper?._dep = null;
      _helper = null;
    }
  }

  @override
  String get wrappedName => '"$name"';

  @override
  String stateToString() => '$state';
}
