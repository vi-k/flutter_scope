part of '../../../scope.dart';

final class ScopeDependencyException implements Exception {
  /// Путь к зависимости, вызвавшей ошибку, без ведущего слэша.
  ///
  /// Пустая строка означает ошибку самой безымянной корневой зависимости.
  final String name;
  final Object error;
  final StackTrace stackTrace;

  const ScopeDependencyException(this.name, this.error, this.stackTrace);

  @override
  String toString() => '$name: $error';
}
