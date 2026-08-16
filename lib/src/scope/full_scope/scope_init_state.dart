part of '../scope.dart';

/// Represents the initialization state of a [Scope].
///
/// This is a sealed class extended by state classes [ScopeProgress] and
/// [ScopeReady] to indicate the current phase of initialization.
///
/// {@category Scope}
sealed class ScopeInitState<P extends Object, D extends ScopeDependencies> {
  ScopeInitState();
}

/// Represents the progress state during the initialization of a [Scope].
///
/// Contains optional [progress] data to track the initialization state.
///
/// {@category Scope}
final class ScopeProgress<P extends Object, D extends ScopeDependencies>
    extends ScopeInitState<P, D> {
  /// Optional progress data representing the current initialization stage.
  final P? progress;

  /// Creates a [ScopeProgress] with the given [progress].
  ScopeProgress([this.progress]);
}

/// Represents the ready state of a [Scope] when initialization is complete.
///
/// Contains the instantiated [dependencies] that are now available to the application.
///
/// {@category Scope}
final class ScopeReady<P extends Object, D extends ScopeDependencies>
    extends ScopeInitState<P, D> {
  /// The initialized scope dependencies.
  final D dependencies;

  /// Creates a [ScopeReady] with the initialized [dependencies].
  ScopeReady(this.dependencies);
}
