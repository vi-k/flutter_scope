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

  @override
  bool get disposalRequired =>
      state is ScopeDependencyInitialized && _helper?.dispose != null;

  @override
  Stream<String> init() async* {
    final helper = _helper = DepHelper._(this);
    final result = _init(helper);
    if (result is Future<void>) {
      await result;
    }
    yield name;
  }

  @override
  void unmount() {
    _helper?.unmount?.call();
  }

  @override
  Stream<String> dispose() async* {
    if (_state is! ScopeDependencyInitialized) {
      return;
    }

    try {
      final result = _helper?.dispose?.call();
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

  /// Called synchronously when the scope leaves the tree.
  ///
  /// Assign it from the initializer for whatever cannot wait for the
  /// asynchronous teardown — unsubscribing, for instance.
  void Function()? unmount;

  /// Releases what this dependency acquired; awaited during the disposal.
  ///
  /// Leave it unset when the dependency owns nothing.
  FutureOr<void> Function()? dispose;
}
