part of '../scope.dart';

/// A container for dependencies (e.g., repositories, services).
///
/// {@category Scope}
// ignore: one_member_abstracts
abstract interface class ScopeDependencies {
  /// Called when the scope is unmounted from the widget tree.
  void unmount();

  /// Disposes of the dependencies, releasing any resources they hold.
  FutureOr<void> dispose();
}

/// Extension on [ScopeDependencies] to provide streaming capabilities.
///
/// {@category Scope}
extension ScopeDependenciesExtension on ScopeDependencies {
  /// Converts the dependencies into a stream emitting a [ScopeReady] state.
  Stream<ScopeInitState<P, T>>
      asStream<P extends Object, T extends ScopeDependencies>() =>
          Stream.value(ScopeReady(this as T));
}
