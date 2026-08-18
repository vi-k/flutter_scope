part of '../../../scope.dart';

/// {@category Scope}
final class ScopeDependencyHandle {
  _ScopeDependencyImpl? _dep;

  ScopeDependencyHandle._(this._dep);

  /// The name of the dependency being initialized.
  String get name =>
      _dep?.name ?? (throw StateError('helper already disposed'));

  /// Lets go of whatever cannot wait for [dispose].
  ///
  /// Assign it from the initializer for whatever the asynchronous teardown
  /// cannot wait for — unsubscribing, for instance. It runs exactly once,
  /// always before [dispose], whether the scope was removed from the tree or
  /// closed with `close()`.
  ///
  /// Within a group the hooks run in reverse declaration order, the same way
  /// the disposal does: a later dependency is built on top of an earlier one,
  /// so it stops reaching the world before that one lets go of anything.
  void Function()? unmount;

  /// Releases what this dependency acquired; awaited during the disposal.
  ///
  /// Leave it unset when the dependency owns nothing.
  FutureOr<void> Function()? dispose;
}
