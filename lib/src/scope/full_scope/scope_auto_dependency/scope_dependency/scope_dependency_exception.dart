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

  /// Wraps [error] as the failure of the dependency called [name].
  const ScopeDependencyException(this.name, this.error, this.stackTrace);

  @override
  String toString() => '$name: $error';
}
