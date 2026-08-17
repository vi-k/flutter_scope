part of '../../../scope.dart';

/// {@category Scope}
final class _ScopeDependencyImpl with ScopeDependencyMixin {
  @override
  final String name;

  @override
  final int count = 1;

  final FutureOr<void> Function(DepHelper dep) _init;
  DepHelper? _helper;

  _ScopeDependencyImpl(this.name, this._init)
      : assert(name.isNotEmpty, 'The dependency name cannot be empty');

  /// Whether this dependency is holding something that has to be given back.
  ///
  /// The question is what the initializer took, not how it ended. An
  /// initializer that acquired a resource and registered its disposer keeps
  /// that resource whether it then succeeded, failed or was cancelled — and the
  /// promise is to release everything that was created. Asking the state
  /// instead let a failure keep whatever it had already taken.
  @override
  bool get disposalRequired => !_isDisposalDone && _helper?.dispose != null;

  @override
  Stream<String> init() async* {
    final helper = _helper = DepHelper._(this);
    final result = _init(helper);
    if (result is Future<void>) {
      await result;
    }
    yield name;
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
  Stream<String> dispose() async* {
    final disposer = _helper?.dispose;
    if (disposer == null) {
      return;
    }

    try {
      final result = disposer();
      if (result is Future<void>) {
        await result;
      }
      yield name;
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

/// {@category Scope}
final class DepHelper {
  _ScopeDependencyImpl? _dep;

  DepHelper._(this._dep);

  /// The name of the dependency being initialized.
  String get name =>
      _dep?.name ?? (throw StateError('helper already disposed'));

  /// Lets go of whatever cannot wait for [dispose].
  ///
  /// Assign it from the initializer for whatever the asynchronous teardown
  /// cannot wait for — unsubscribing, for instance. It runs exactly once,
  /// always before [dispose], whether the scope was removed from the tree or
  /// closed with `close()`.
  void Function()? unmount;

  /// Releases what this dependency acquired; awaited during the disposal.
  ///
  /// Leave it unset when the dependency owns nothing.
  FutureOr<void> Function()? dispose;
}
