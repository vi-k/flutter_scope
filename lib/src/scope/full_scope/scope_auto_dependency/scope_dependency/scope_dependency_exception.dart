part of '../../../scope.dart';

/// {@category Scope}
final class ScopeDependencyException implements Exception {
  /// The path of the dependency that raised the error, without a leading
  /// slash.
  ///
  /// An empty string means the anonymous root dependency itself failed.
  final String name;

  /// What the dependency failed with.
  final Object error;

  /// The stack trace of [error].
  final StackTrace stackTrace;

  /// Something the package knows about this failure that [error] does not say,
  /// or `null` when it knows nothing to add.
  ///
  /// A dependency reports what its initializer threw, and that is usually the
  /// whole story. It is not when the throw is a consequence of how the
  /// container is being driven rather than of what the initializer did: the
  /// container knows that, the error does not, and the reader is left with a
  /// message that reads as a mistake in their own code. Set for exactly one
  /// such case today — see `ScopeAutoDependencies`.
  ///
  /// Printed by [toString] on a line of its own, in parentheses.
  final String? hint;

  /// Wraps [error] as the failure of the dependency called [name].
  const ScopeDependencyException(
    this.name,
    this.error,
    this.stackTrace, {
    this.hint,
  });

  @override
  String toString() =>
      hint == null ? '$name: $error' : '$name: $error\n($hint)';
}
