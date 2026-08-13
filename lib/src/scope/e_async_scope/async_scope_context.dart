part of '../scope.dart';

/// {@category AsyncScope}
abstract interface class AsyncScopeContext<W extends ScopeInheritedWidget>
    implements ScopeContext<W> {
  /// The current state of the scope.
  AsyncScopeState get state;

  /// Whether the scope has reached [AsyncScopeReady].
  bool get isInitialized;

  /// Whether the initialization failed.
  bool get hasError;

  /// The error of a failed initialization.
  ///
  /// Throws a [StateError] when there is none.
  Object get error;

  /// The stack trace of [error].
  ///
  /// Throws a [StateError] when there is no error.
  StackTrace get stackTrace;
}
