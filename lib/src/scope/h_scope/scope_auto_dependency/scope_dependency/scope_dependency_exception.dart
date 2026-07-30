part of '../../../scope.dart';

final class ScopeDependencyException implements Exception {
  /// The path of the dependency that raised the error, without a leading
  /// slash.
  ///
  /// An empty string means the anonymous root dependency itself failed.
  final String name;
  final Object error;
  final StackTrace stackTrace;

  const ScopeDependencyException(this.name, this.error, this.stackTrace);

  @override
  String toString() => '$name: $error';
}
